package io.nurunuru.app.data.signers

import android.app.Activity
import android.util.Log
import io.nurunuru.app.data.AppSigner
import io.nurunuru.app.data.NosskeyKeyInfo
import io.nurunuru.app.data.NosskeyManager
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import rust.nostr.sdk.Keys
import rust.nostr.sdk.NostrSigner
import rust.nostr.sdk.PublicKey
import rust.nostr.sdk.UnsignedEvent
import java.io.Closeable

/**
 * Nosskey "PRF Direct Method" signer.
 *
 * Every sign/encrypt call:
 *  1. Returns the cached 32-byte secret if it is younger than [CACHE_TTL_MS].
 *  2. Otherwise runs a PRF assertion via [NosskeyManager.deriveSecretKey],
 *     which triggers the system biometric prompt.
 *
 * The cached secret is zeroized when the TTL expires or [close] is called.
 *
 * NOTE: this signer holds an Activity reference and must therefore be short-lived.
 * Build a fresh instance per user-initiated flow.
 */
class NosskeySigner(
    private val activity: Activity,
    private val nosskeyManager: NosskeyManager,
    private val keyInfo: NosskeyKeyInfo
) : AppSigner, Closeable {

    private val mutex = Mutex()
    private var cachedSecret: ByteArray? = null
    private var cachedAt: Long = 0L

    private var _keys: Keys? = null
    private var _signer: NostrSigner? = null

    override fun getPublicKeyHex(): String = keyInfo.pubkey

    override suspend fun signEvent(eventJson: String, requireManualApproval: Boolean): String? {
        return try {
            val signer = ensureSigner()
            val unsigned = UnsignedEvent.fromJson(eventJson)
            signer.signEvent(unsigned).asJson()
        } catch (e: Exception) {
            Log.e(TAG, "signEvent failed: ${e.message}", e)
            null
        }
    }

    override suspend fun nip04Encrypt(receiverPubkeyHex: String, content: String): String? {
        return try {
            ensureSigner().nip04Encrypt(PublicKey.parse(receiverPubkeyHex), content)
        } catch (e: Exception) {
            Log.e(TAG, "nip04Encrypt failed: ${e.message}", e)
            null
        }
    }

    override suspend fun nip04Decrypt(senderPubkeyHex: String, content: String): String? {
        return try {
            ensureSigner().nip04Decrypt(PublicKey.parse(senderPubkeyHex), content)
        } catch (e: Exception) {
            Log.e(TAG, "nip04Decrypt failed: ${e.message}", e)
            null
        }
    }

    override suspend fun nip44Encrypt(receiverPubkeyHex: String, content: String): String? {
        return try {
            ensureSigner().nip44Encrypt(PublicKey.parse(receiverPubkeyHex), content)
        } catch (e: Exception) {
            Log.e(TAG, "nip44Encrypt failed: ${e.message}", e)
            null
        }
    }

    override suspend fun nip44Decrypt(senderPubkeyHex: String, content: String): String? {
        return try {
            ensureSigner().nip44Decrypt(PublicKey.parse(senderPubkeyHex), content)
        } catch (e: Exception) {
            Log.e(TAG, "nip44Decrypt failed: ${e.message}", e)
            null
        }
    }

    /**
     * Prime signer cache with a freshly derived PRF secret. The input is copied;
     * caller remains responsible for zeroizing its own ByteArray.
     */
    fun primeCache(secret: ByteArray) {
        zeroizeSecret()
        cachedSecret = secret.copyOf()
        cachedAt = System.currentTimeMillis()
        _keys = null
        _signer = null
    }

    /**
     * Drop cached secret and rust-nostr Keys/Signer.
     */
    override fun close() {
        zeroizeSecret()
        _keys = null
        _signer = null
    }

    private suspend fun ensureSigner(): NostrSigner = mutex.withLock {
        val cached = _signer
        if (cached != null && isCacheFresh()) return@withLock cached
        if (cached != null) {
            // expired — drop the prior key material before deriving anew
            zeroizeSecret()
            _keys = null
            _signer = null
        }
        val privHex = ensureSecretHexLocked()
        val keys = Keys.parse(privHex)
        _keys = keys
        val signer = NostrSigner.keys(keys)
        _signer = signer
        signer
    }

    /**
     * Caller must hold [mutex].
     */
    private suspend fun ensureSecretHexLocked(): String {
        val existing = cachedSecret
        if (existing != null && isCacheFresh()) {
            return existing.toHexLower()
        }
        if (existing != null) {
            existing.fill(0)
            cachedSecret = null
        }
        val fresh = nosskeyManager.deriveSecretKey(activity, keyInfo)
        cachedSecret = fresh
        cachedAt = System.currentTimeMillis()
        return fresh.toHexLower()
    }

    private fun isCacheFresh(): Boolean {
        if (cachedSecret == null) return false
        return (System.currentTimeMillis() - cachedAt) < CACHE_TTL_MS
    }

    private fun zeroizeSecret() {
        cachedSecret?.fill(0)
        cachedSecret = null
        cachedAt = 0L
    }

    private fun ByteArray.toHexLower(): String =
        joinToString("") { "%02x".format(it) }

    companion object {
        private const val TAG = "NosskeySigner"
        private const val CACHE_TTL_MS: Long = 5 * 60 * 1000L
    }
}
