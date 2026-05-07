package io.nurunuru.app.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import io.nurunuru.app.MainActivity
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * NIP-55 / Amber signer bridge.
 *
 * Important rules:
 * - sign_event first tries Amber ContentProvider.  If Amber has a remembered
 *   approval (1m/5m/10m/Always/full trust), this signs silently and Amber UI never opens.
 * - If ContentProvider explicitly says "rejected", there is no remembered
 *   approval, so we open Amber ActivityResult UI.  The user can then choose
 *   Never / 1m / 5m / 10m / Always.
 * - Background NIP-04/44 encrypt/decrypt never opens Amber UI unless the app's
 *   own autoSignEnabled setting allows ContentProvider use.
 */
object ExternalSigner : AppSigner {
    private const val TAG = "ExternalSigner"
    private const val PACKAGE_NAME = "com.greenart7c3.nostrsigner"
    private const val CALLER_PACKAGE = "io.nurunuru.app"

    private var currentUserPubkey: String = ""
    private var pendingRequest: CompletableDeferred<Intent>? = null
    private val mutex = kotlinx.coroutines.sync.Mutex()

    // Try Amber first, then generic package authority.
    private val contentAuthorities = listOf(
        "com.greenart7c3.nostrsigner",
        "com.nostr.signer"
    )
    @Volatile private var workingAuthority: String? = null

    fun setCurrentUser(pubkey: String) { currentUserPubkey = pubkey }

    fun createGetPublicKeyIntent(context: Context?): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("nostrsigner:")).apply {
            `package` = PACKAGE_NAME
            putExtra("type", "get_public_key")
            // Account selection only. Do not pass permissions here; Amber should let
            // the user set remember policy from each approval screen.
            putExtra("package", CALLER_PACKAGE)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

    private fun createSignEventIntent(eventJson: String, pubkey: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("nostrsigner:$eventJson")).apply {
            `package` = PACKAGE_NAME
            putExtra("type", "sign_event")
            putExtra("event_json", eventJson)
            putExtra("current_user", pubkey)
            putExtra("package", CALLER_PACKAGE)
            putExtra("returnType", "event")
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

    private fun createCryptoIntent(content: String, pubkey: String, currentUser: String, type: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("nostrsigner:$content")).apply {
            `package` = PACKAGE_NAME
            putExtra("type", type)
            putExtra("current_user", currentUser)
            putExtra("pubkey", pubkey)
            putExtra("returnType", "signature")
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

    suspend fun signEvent(context: Context?, eventJson: String, pubkey: String, requireManualApproval: Boolean = false): String? {
        Log.d(TAG, "Requesting sign_event")
        val result = request(context, createSignEventIntent(eventJson, pubkey)) ?: run {
            Log.w(TAG, "Signing request failed or cancelled")
            return null
        }
        return parseSignedResult(result, eventJson, pubkey)
    }

    private fun parseSignedResult(result: Intent, eventJson: String, pubkey: String): String? {
        result.getStringExtra("event")?.takeIf { it.isNotBlank() }?.let { return it }
        val value = result.getStringExtra("signature")
            ?: result.getStringExtra("sig")
            ?: result.getStringExtra("result")
            ?: result.data?.toString()?.removePrefix("nostrsigner:")
        if (value.isNullOrBlank()) {
            Log.w(TAG, "No event or signature found in signer result")
            return null
        }

        if (value.trim().startsWith("{")) {
            try {
                val obj = Json.parseToJsonElement(value).jsonObject
                if (obj.containsKey("sig") || obj.containsKey("signature")) return value
            } catch (_: Exception) {}
        }

        return try {
            val map = Json.parseToJsonElement(eventJson).jsonObject.toMutableMap()
            map["sig"] = kotlinx.serialization.json.JsonPrimitive(value)
            if (!map.containsKey("pubkey")) map["pubkey"] = kotlinx.serialization.json.JsonPrimitive(pubkey)
            if (!map.containsKey("id")) {
                Json.parseToJsonElement(eventJson).jsonObject["id"]?.jsonPrimitive?.content?.let {
                    map["id"] = kotlinx.serialization.json.JsonPrimitive(it)
                }
            }
            Json.encodeToString(JsonObject(map))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reconstruct signed event", e)
            null
        }
    }

    suspend fun decrypt(context: Context?, content: String, pubkey: String, currentUser: String, nip44: Boolean): String? {
        val type = if (nip44) "nip44_decrypt" else "nip04_decrypt"
        return request(context, createCryptoIntent(content, pubkey, currentUser, type))?.extractCryptoResult()
    }

    suspend fun encrypt(context: Context?, content: String, pubkey: String, currentUser: String, nip44: Boolean): String? {
        val type = if (nip44) "nip44_encrypt" else "nip04_encrypt"
        return request(context, createCryptoIntent(content, pubkey, currentUser, type))?.extractCryptoResult()
    }

    private fun Intent.extractCryptoResult(): String? =
        getStringExtra("signature") ?: getStringExtra("sig") ?: getStringExtra("content") ?: getStringExtra("result") ?: data?.toString()?.removePrefix("nostrsigner:")

    private suspend fun request(context: Context?, intent: Intent): Intent? = mutex.withLock {
        val ctx = context ?: MainActivity.instance ?: return null
        val type = intent.getStringExtra("type") ?: return null

        if (type == "sign_event") {
            when (val provider = withContext(Dispatchers.IO) { queryContentProvider(ctx, intent) }) {
                is ProviderResult.Success -> {
                    Log.d(TAG, "Amber remembered approval success via ContentProvider; no UI")
                    return provider.intent
                }
                ProviderResult.Rejected -> {
                    Log.d(TAG, "Amber ContentProvider reports no remembered approval; opening approval UI")
                    return launchForResult(ctx, intent)
                }
                ProviderResult.Unavailable -> {
                    Log.d(TAG, "Amber ContentProvider unavailable; opening approval UI")
                    return launchForResult(ctx, intent)
                }
            }
        }

        val autoSignEnabled = (ctx.applicationContext as? io.nurunuru.app.NuruNuruApp)?.prefs?.autoSignEnabled ?: false
        if (autoSignEnabled) {
            return when (val provider = withContext(Dispatchers.IO) { queryContentProvider(ctx, intent) }) {
                is ProviderResult.Success -> provider.intent
                ProviderResult.Rejected, ProviderResult.Unavailable -> null
            }
        }

        if (type.startsWith("nip04_") || type.startsWith("nip44_")) {
            Log.d(TAG, "Skipping automatic Amber request for background crypto (type=$type)")
            return null
        }

        return launchForResult(ctx, intent)
    }

    private suspend fun launchForResult(ctx: Context, intent: Intent): Intent? {
        val deferred = CompletableDeferred<Intent>()
        pendingRequest = deferred
        val launched = withContext(Dispatchers.Main.immediate) {
            when {
                ctx is MainActivity -> { ctx.launchExternalSigner(intent); true }
                MainActivity.instance != null -> { MainActivity.instance!!.launchExternalSigner(intent); true }
                else -> false
            }
        }
        if (!launched) {
            pendingRequest = null
            return null
        }
        return try {
            deferred.await()
        } catch (e: Exception) {
            Log.w(TAG, "Signer result wait failed: ${e.message}")
            null
        } finally {
            pendingRequest = null
        }
    }

    private sealed class ProviderResult {
        data class Success(val intent: Intent) : ProviderResult()
        object Rejected : ProviderResult()
        object Unavailable : ProviderResult()
    }

    private fun queryContentProvider(context: Context, intent: Intent): ProviderResult {
        val type = intent.getStringExtra("type") ?: return ProviderResult.Unavailable
        val data = intent.getStringExtra("event_json")
            ?: intent.data?.toString()?.removePrefix("nostrsigner:")
            ?: ""
        val currentUser = intent.getStringExtra("current_user") ?: currentUserPubkey
        val counterparty = intent.getStringExtra("pubkey") ?: ""
        val normalizedType = type.uppercase()

        val authorities = buildList {
            workingAuthority?.let { add(it) }
            addAll(contentAuthorities.filter { it != workingAuthority })
        }

        var sawRejected = false
        for (authority in authorities) {
            val uri = Uri.parse("content://$authority.$normalizedType")
            try {
                Log.d(TAG, "Querying Amber provider: $uri")
                val projection = if (normalizedType == "SIGN_EVENT") {
                    // Amber SignerProvider expects projection[0]=json, projection[2]=npub/hex.
                    // NIP-55 / Amber expect sortOrder=null. Amber then uses
                    // ContentProvider.callingPackage for app identity. Passing
                    // "io.nurunuru.app" as sortOrder makes Amber treat it as a
                    // non-hex pubkey and return null, causing UI flicker.
                    arrayOf(data, "", currentUser)
                } else {
                    // Crypto expects projection[0]=content, projection[1]=counterparty, projection[2]=account.
                    arrayOf(data, counterparty, currentUser)
                }
                val cursor = context.contentResolver.query(
                    uri,
                    projection,
                    null,
                    null,
                    null
                )
                if (cursor == null) {
                    Log.d(TAG, "  → null cursor")
                    continue
                }
                cursor.use { c ->
                    if (!c.moveToFirst()) {
                        Log.d(TAG, "  → empty cursor")
                    } else {
                        val rejectedIndex = c.getColumnIndex("rejected")
                        if (rejectedIndex >= 0 && c.getString(rejectedIndex) == "true") {
                            Log.d(TAG, "  → provider rejected (no remembered approval)")
                            sawRejected = true
                        } else {
                            val signature = c.getColumnIndex("signature").takeIf { it >= 0 }?.let { c.getString(it) }
                            val event = c.getColumnIndex("event").takeIf { it >= 0 }?.let { c.getString(it) }
                            val result = c.getColumnIndex("result").takeIf { it >= 0 }?.let { c.getString(it) }
                            if (!signature.isNullOrBlank() || !event.isNullOrBlank() || !result.isNullOrBlank()) {
                                workingAuthority = authority
                                return ProviderResult.Success(Intent().apply {
                                    putExtra("signature", signature)
                                    putExtra("event", event)
                                    putExtra("result", result)
                                })
                            }

                            for (i in 0 until c.columnCount) {
                                val value = c.getString(i)
                                if (!value.isNullOrBlank()) {
                                    workingAuthority = authority
                                    return ProviderResult.Success(Intent().apply { putExtra("signature", value) })
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Provider query failed [$uri]: ${e::class.simpleName}: ${e.message}")
            }
        }
        return if (sawRejected) ProviderResult.Rejected else ProviderResult.Unavailable
    }

    override fun getPublicKeyHex(): String = currentUserPubkey
    override suspend fun signEvent(eventJson: String, requireManualApproval: Boolean): String? = signEvent(null, eventJson, getPublicKeyHex(), requireManualApproval)
    override suspend fun nip04Encrypt(receiverPubkeyHex: String, content: String): String? = encrypt(null, content, receiverPubkeyHex, getPublicKeyHex(), false)
    override suspend fun nip04Decrypt(senderPubkeyHex: String, encryptedContent: String): String? = decrypt(null, encryptedContent, senderPubkeyHex, getPublicKeyHex(), false)
    override suspend fun nip44Encrypt(receiverPubkeyHex: String, content: String): String? = encrypt(null, content, receiverPubkeyHex, getPublicKeyHex(), true)
    override suspend fun nip44Decrypt(senderPubkeyHex: String, encryptedContent: String): String? = decrypt(null, encryptedContent, senderPubkeyHex, getPublicKeyHex(), true)

    fun onResult(intent: Intent?) {
        Log.d(TAG, "onResult called: intent=${if (intent != null) "non-null (extras: ${intent.extras?.keySet()?.joinToString()})" else "null"}")
        if (intent != null) pendingRequest?.takeIf { !it.isCompleted }?.complete(intent)
        else pendingRequest?.takeIf { !it.isCompleted }?.cancel()
        pendingRequest = null
    }
}
