package io.nurunuru.app.data

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Base64
import android.util.Log
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.security.SecureRandom

/**
 * Nosskey "PRF Direct Method" manager.
 *
 * Implements WebAuthn Passkey + PRF extension based deterministic Nostr key derivation,
 * following https://github.com/ocknamo/nosskey-sdk .
 *
 * - register: create a Passkey on a platform authenticator (Android Credential Manager).
 * - sign: request PRF assertion with the fixed salt "nostr-pwk" → 32-byte secret →
 *   used DIRECTLY as the secp256k1 Schnorr private key.
 *
 * The private key itself is NEVER persisted. Only `{ credentialId, pubkey, salt }` is.
 * Every sign/encrypt re-derives the key via the system biometric prompt
 * (callers may keep a short in-memory cache; see NosskeySigner).
 */
class NosskeyManager {

    /**
     * @param credentialId base64url-encoded WebAuthn credential id
     * @param pubkey       x-only Schnorr public key (hex)
     * @param salt         hex-encoded PRF salt. Defaults to UTF-8 "nostr-pwk".
     * @param username     optional display username (for UX only)
     */
    @Serializable
    data class NosskeyKeyInfo(
        val credentialId: String,
        val pubkey: String,
        val salt: String = STANDARD_SALT_HEX,
        val username: String? = null
    )

    data class NosskeyCreationResult(
        val keyInfo: NosskeyKeyInfo,
        /** Caller must zeroize after use. */
        val secretKey: ByteArray
    )

    sealed class NosskeyError(message: String) : Exception(message) {
        object Unsupported : NosskeyError("Passkeys not supported on this device")
        object PrfUnsupported : NosskeyError("PRF extension not supported")
        object UserCancelled : NosskeyError("User cancelled passkey operation")
        object PrfMissing : NosskeyError("PRF output missing from response")
        object InvalidPrfOutput : NosskeyError("PRF output is invalid (all zeros)")
        data class RegistrationFailed(val reason: String) :
            NosskeyError("Registration failed: $reason")
        data class AssertionFailed(val reason: String) :
            NosskeyError("Assertion failed: $reason")
    }

    /**
     * Register a new Passkey and derive the Nostr public key from its PRF output.
     *
     * This performs two CredentialManager round-trips:
     *  1. createCredential — creates the platform passkey (Touch ID / Face ID / 指紋認証).
     *  2. getCredential    — fetches the PRF output to derive the Schnorr keypair.
     *
     * The intermediate 32-byte secret is zeroized before return.
     */
    suspend fun createPasskeyWithSecret(
        activity: Activity,
        username: String,
        displayName: String,
        rpId: String = RP_ID
    ): NosskeyCreationResult {
        if (!isPlatformSupported(activity)) throw NosskeyError.Unsupported

        val challenge = randomBytes(32)
        val userHandle = randomBytes(16)

        val createJson = buildJsonObject {
            put("challenge", b64url(challenge))
            put("rp", buildJsonObject {
                put("id", rpId)
                put("name", RP_NAME)
            })
            put("user", buildJsonObject {
                put("id", b64url(userHandle))
                put("name", username)
                put("displayName", displayName)
            })
            put("pubKeyCredParams", buildJsonArray {
                addJsonObject {
                    put("type", "public-key")
                    put("alg", -7)
                }
                addJsonObject {
                    put("type", "public-key")
                    put("alg", -8)
                }
            })
            put("authenticatorSelection", buildJsonObject {
                put("userVerification", "required")
                put("residentKey", "required")
            })
            put("extensions", buildJsonObject {
                put("prf", buildJsonObject {
                    // Ask for PRF evaluation during registration when the provider
                    // supports it. Some Android providers ignore this and only return
                    // `enabled`; in that case we fallback to one assertion below.
                    put("eval", buildJsonObject {
                        put("first", b64url(hexToBytes(STANDARD_SALT_HEX)!!))
                    })
                })
            })
        }.toString()

        val registrationResponseJson: String
        val credentialId: String = try {
            val cm = CredentialManager.create(activity)
            val request = CreatePublicKeyCredentialRequest(requestJson = createJson)
            val response = cm.createCredential(activity, request) as CreatePublicKeyCredentialResponse
            registrationResponseJson = response.registrationResponseJson
            extractCredentialId(registrationResponseJson)
                ?: throw NosskeyError.RegistrationFailed("credential id missing")
        } catch (e: CreateCredentialCancellationException) {
            throw NosskeyError.UserCancelled
        } catch (e: NosskeyError) {
            throw e
        } catch (e: CreateCredentialException) {
            Log.e(TAG, "createCredential failed: ${e.type} - ${e.message}", e)
            throw NosskeyError.RegistrationFailed(e.message ?: e.type)
        } catch (e: Exception) {
            Log.e(TAG, "createCredential threw unexpected", e)
            throw NosskeyError.RegistrationFailed(e.message ?: "unknown")
        }

        // We now have a credentialId, but no public key yet. Derive it by performing a
        // PRF assertion (this triggers the biometric prompt) and computing the Schnorr
        // x-only pubkey from the 32-byte PRF output.
        val seed = NosskeyKeyInfo(
            credentialId = credentialId,
            pubkey = "",
            salt = STANDARD_SALT_HEX,
            username = username
        )
        val secret = extractPrfFirstOrNull(registrationResponseJson)
            ?: deriveSecretKey(activity, seed, rpId)
        try {
            val privHex = secret.toHexLower()
            val pubHex = NostrKeyUtils.derivePublicKey(privHex)
                ?: throw NosskeyError.RegistrationFailed("public key derivation failed")
            val keyInfo = NosskeyKeyInfo(
                credentialId = credentialId,
                pubkey = pubHex,
                salt = STANDARD_SALT_HEX,
                username = username
            )
            return NosskeyCreationResult(keyInfo = keyInfo, secretKey = secret)
        } catch (e: Exception) {
            secret.fill(0)
            throw e
        }
    }

    suspend fun createPasskey(
        activity: Activity,
        username: String,
        displayName: String,
        rpId: String = RP_ID
    ): NosskeyKeyInfo {
        val result = createPasskeyWithSecret(activity, username, displayName, rpId)
        try {
            return result.keyInfo
        } finally {
            result.secretKey.fill(0)
        }
    }

    /**
     * Run a PRF assertion and return the raw 32-byte secret.
     * The caller MUST zeroize the returned ByteArray once done.
     */
    suspend fun deriveSecretKey(
        activity: Activity,
        keyInfo: NosskeyKeyInfo,
        rpId: String = RP_ID
    ): ByteArray {
        if (!isPlatformSupported(activity)) throw NosskeyError.Unsupported

        val challenge = randomBytes(32)
        val saltBytes = hexToBytes(keyInfo.salt)
            ?: throw NosskeyError.AssertionFailed("invalid salt hex")

        val getJson = buildJsonObject {
            put("challenge", b64url(challenge))
            put("rpId", rpId)
            put("allowCredentials", buildJsonArray {
                addJsonObject {
                    put("type", "public-key")
                    put("id", keyInfo.credentialId)
                }
            })
            put("userVerification", "required")
            put("extensions", buildJsonObject {
                put("prf", buildJsonObject {
                    put("eval", buildJsonObject {
                        put("first", b64url(saltBytes))
                    })
                })
            })
        }.toString()

        val responseJson: String = try {
            val cm = CredentialManager.create(activity)
            val option = GetPublicKeyCredentialOption(requestJson = getJson)
            val request = GetCredentialRequest(listOf(option))
            val result = cm.getCredential(activity, request)
            val cred = result.credential as? PublicKeyCredential
                ?: throw NosskeyError.AssertionFailed("response is not a PublicKeyCredential")
            cred.authenticationResponseJson
        } catch (e: GetCredentialCancellationException) {
            throw NosskeyError.UserCancelled
        } catch (e: NosskeyError) {
            throw e
        } catch (e: GetCredentialException) {
            Log.e(TAG, "getCredential failed: ${e.type} - ${e.message}", e)
            throw NosskeyError.AssertionFailed(e.message ?: e.type)
        } catch (e: Exception) {
            Log.e(TAG, "getCredential threw unexpected", e)
            throw NosskeyError.AssertionFailed(e.message ?: "unknown")
        }

        return extractPrfFirst(responseJson)
    }

    /**
     * Load persisted key info, or null if no nosskey account is registered.
     */
    fun loadStoredKeyInfo(context: Context): NosskeyKeyInfo? {
        val prefs = prefs(context)
        val raw = prefs.getString(KEY_INFO, null) ?: return null
        return try {
            jsonCodec.decodeFromString<NosskeyKeyInfo>(raw)
        } catch (e: Exception) {
            Log.w(TAG, "loadStoredKeyInfo decode failed: ${e.message}")
            null
        }
    }

    fun saveKeyInfo(context: Context, info: NosskeyKeyInfo) {
        val raw = jsonCodec.encodeToString(info)
        prefs(context).edit().putString(KEY_INFO, raw).apply()
    }

    fun clearStoredKeyInfo(context: Context) {
        prefs(context).edit().remove(KEY_INFO).apply()
    }

    /**
     * Platform capability check. PRF Direct Method requires CredentialManager
     * (officially supported on Android 9 / API 28+) so older devices fall back.
     */
    fun isPlatformSupported(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return try {
            CredentialManager.create(context)
            true
        } catch (e: Throwable) {
            Log.w(TAG, "CredentialManager unavailable: ${e.message}")
            false
        }
    }

    // ─── helpers ─────────────────────────────────────────────────────────────

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun randomBytes(n: Int): ByteArray {
        val out = ByteArray(n)
        SecureRandom().nextBytes(out)
        return out
    }

    private fun b64url(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

    private fun b64urlDecode(s: String): ByteArray {
        // accept padding-less, URL-safe, or standard base64; pad as needed
        val normalized = s.replace('-', '+').replace('_', '/')
        val padded = when (normalized.length % 4) {
            2 -> "$normalized=="
            3 -> "$normalized="
            else -> normalized
        }
        return Base64.decode(padded, Base64.DEFAULT)
    }

    private fun ByteArray.toHexLower(): String =
        joinToString("") { "%02x".format(it) }

    private fun hexToBytes(hex: String): ByteArray? {
        if (hex.length % 2 != 0) return null
        return try {
            ByteArray(hex.length / 2) { i ->
                hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        } catch (_: NumberFormatException) {
            null
        }
    }

    private fun extractCredentialId(registrationResponseJson: String): String? {
        return try {
            val root = jsonCodec.parseToJsonElement(registrationResponseJson).jsonObject
            root["id"]?.jsonPrimitive?.content
        } catch (e: Exception) {
            Log.w(TAG, "extractCredentialId failed: ${e.message}")
            null
        }
    }

    private fun extractPrfFirstOrNull(responseJson: String): ByteArray? {
        return try {
            extractPrfFirst(responseJson)
        } catch (_: NosskeyError.PrfMissing) {
            null
        } catch (_: NosskeyError.PrfUnsupported) {
            null
        } catch (e: Exception) {
            Log.w(TAG, "registration PRF result unavailable: ${e.message}")
            null
        }
    }

    /**
     * Parse the authentication response JSON and pull out
     * `clientExtensionResults.prf.results.first` as a 32-byte secret.
     */
    private fun extractPrfFirst(authenticationResponseJson: String): ByteArray {
        val root = try {
            jsonCodec.parseToJsonElement(authenticationResponseJson).jsonObject
        } catch (e: Exception) {
            throw NosskeyError.AssertionFailed("response JSON parse failed: ${e.message}")
        }

        val cer = root["clientExtensionResults"]?.jsonObject
            ?: throw NosskeyError.PrfMissing
        val prf = cer["prf"]?.jsonObject
            ?: throw NosskeyError.PrfUnsupported
        val results = prf["results"]?.jsonObject
            ?: throw NosskeyError.PrfMissing
        val firstB64 = results["first"]?.jsonPrimitive?.content
            ?: throw NosskeyError.PrfMissing

        val raw = try {
            b64urlDecode(firstB64)
        } catch (e: Exception) {
            throw NosskeyError.AssertionFailed("PRF base64 decode failed: ${e.message}")
        }
        if (raw.size != 32) {
            throw NosskeyError.AssertionFailed("PRF output is ${raw.size} bytes, expected 32")
        }
        if (raw.all { it == 0.toByte() }) {
            throw NosskeyError.InvalidPrfOutput
        }
        return raw
    }

    companion object {
        const val STANDARD_SALT_HEX = "6e6f7374722d70776b" // UTF-8 "nostr-pwk"
        const val RP_ID = "www.nullnull.app"
        const val RP_NAME = "ぬるぬる"

        private const val TAG = "NosskeyManager"
        private const val PREFS_NAME = "nurunuru_nosskey"
        private const val KEY_INFO = "keyinfo"

        private val jsonCodec: Json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }
}

// Convenience type aliases so callers can write `NosskeyKeyInfo` and `NosskeyError`
// without the inner-class qualification (matches the spec API surface).
typealias NosskeyKeyInfo = NosskeyManager.NosskeyKeyInfo
typealias NosskeyError = NosskeyManager.NosskeyError
