package io.nurunuru.app.viewmodel

import android.app.Activity
import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.nurunuru.app.data.NostrClient
import io.nurunuru.app.data.NostrKeyUtils
import io.nurunuru.app.data.NostrRepository
import io.nurunuru.app.data.NosskeyManager
import io.nurunuru.app.data.NosskeyManager.NosskeyError
import io.nurunuru.app.data.SecureKeyManager
import io.nurunuru.app.data.models.UserProfile
import io.nurunuru.app.data.models.NostrKind
import io.nurunuru.app.data.prefs.AppPreferences
import io.nurunuru.app.data.signers.NosskeySigner
import io.nurunuru.app.data.*
import javax.crypto.Cipher
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

sealed class AuthState {
    object Checking : AuthState()
    object LoggedOut : AuthState()
    /** 秘密鍵は AuthState に含めない — SecureKeyManager 経由でのみアクセス */
    data class LoggedIn(
        val pubkeyHex: String,
        val isExternal: Boolean = false,
        val hasInternalKey: Boolean = false
    ) : AuthState()
    /** 生体認証が必要な状態 */
    object BiometricRequired : AuthState()
    data class Error(val message: String) : AuthState()
    object ExternalSignerWaiting : AuthState()
}

data class GeneratedAccount(
    val pubkeyHex: String,
    val nsec: String,
    val npub: String
)

data class ReferralInvitePreview(
    val pubkeyHex: String,
    val profile: UserProfile? = null,
    val isLoading: Boolean = false
)

class AuthViewModel(application: Application) : AndroidViewModel(application) {

    val prefs = AppPreferences(application)
    val keyManager = SecureKeyManager(application)
    val nosskeyManager = NosskeyManager()
    private var activeNosskeySigner: NosskeySigner? = null
    @Volatile private var pendingReferralFollowPubkey: String? = null

    private val _authState = MutableStateFlow<AuthState>(AuthState.Checking)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    private val _referralInvitePreview = MutableStateFlow<ReferralInvitePreview?>(null)
    val referralInvitePreview: StateFlow<ReferralInvitePreview?> = _referralInvitePreview.asStateFlow()

    private val _profileNavigationEvents = MutableSharedFlow<String>(extraBufferCapacity = 1)
    val profileNavigationEvents = _profileNavigationEvents.asSharedFlow()

    private val _eventNavigationEvents = MutableSharedFlow<String>(extraBufferCapacity = 1)
    val eventNavigationEvents = _eventNavigationEvents.asSharedFlow()

    init {
        migrateAndCheckLogin()
    }

    /**
     * 旧形式からのマイグレーション + ログイン状態チェック。
     */
    private fun migrateAndCheckLogin() {
        viewModelScope.launch(Dispatchers.IO) {
            // 旧 EncryptedSharedPreferences からの移行
            @Suppress("DEPRECATION")
            if (prefs.privateKeyHex != null && !keyManager.hasStoredKey()) {
                keyManager.migrateFromLegacy(prefs)
            }

            prefs.pendingReferralPubkeyHex?.let { setPendingReferralFollow(it) }
            checkStoredLogin()
        }
    }

    private suspend fun checkStoredLogin() {
        val pubKey = prefs.publicKeyHex
        val isExternal = prefs.isExternalSigner
        val hasSecureKey = keyManager.hasStoredKey()

        // Nosskey path: the secret is never stored locally — only credential metadata.
        // Treat this as logged-in without unlocking SecureKeyManager. Signing/encrypt
        // operations will trigger their own biometric prompt via the CredentialManager.
        if (prefs.loginMethod == "nosskey") {
            val nosskeyInfo = nosskeyManager.loadStoredKeyInfo(getApplication())
            val effectivePubkey = nosskeyInfo?.pubkey ?: pubKey
            if (nosskeyInfo != null && effectivePubkey != null) {
                _authState.value = AuthState.LoggedIn(
                    effectivePubkey,
                    isExternal = false,
                    hasInternalKey = true
                )
                return
            }
        }

        if (pubKey != null && (hasSecureKey || isExternal)) {
            if (isExternal) {
                io.nurunuru.app.data.ExternalSigner.setCurrentUser(pubKey)
                _authState.value = AuthState.LoggedIn(pubKey, isExternal = true)
                viewModelScope.launch(Dispatchers.IO) { syncRelayListOnLogin(pubKey, io.nurunuru.app.data.ExternalSigner) }
            } else if (hasSecureKey) {
                if (keyManager.isBiometricBound()) {
                    // 生体認証が必要 → BiometricRequired 状態にして UI に委譲
                    _authState.value = AuthState.BiometricRequired
                } else {
                    // 生体認証不要 → 直接復号
                    if (keyManager.unlockKeyDirect()) {
                        _authState.value = AuthState.LoggedIn(
                            pubKey,
                            isExternal = false,
                            hasInternalKey = true
                        )
                        viewModelScope.launch(Dispatchers.IO) { syncRelayListOnLogin(pubKey, io.nurunuru.app.data.InternalSigner(keyManager)) }
                    } else {
                        _authState.value = AuthState.Error("秘密鍵の復号に失敗しました")
                    }
                }
            }
        } else {
            _authState.value = AuthState.LoggedOut
        }
    }

    /**
     * 生体認証成功時に呼ばれる。
     */
    fun onBiometricSuccess(cipher: Cipher) {
        viewModelScope.launch(Dispatchers.IO) {
            val pubKey = prefs.publicKeyHex
            if (pubKey != null && keyManager.unlockKey(cipher)) {
                _authState.value = AuthState.LoggedIn(
                    pubKey,
                    isExternal = false,
                    hasInternalKey = true
                )
                launch { syncRelayListOnLogin(pubKey, io.nurunuru.app.data.InternalSigner(keyManager)) }
            } else {
                _authState.value = AuthState.Error("秘密鍵のアンロックに失敗しました")
            }
        }
    }

    /**
     * 生体認証が利用不可で直接復号に成功した場合のフォールバック。
     */
    fun onBiometricFallbackSuccess() {
        val pubKey = prefs.publicKeyHex ?: return
        viewModelScope.launch(Dispatchers.IO) {
            _authState.value = AuthState.LoggedIn(pubKey, isExternal = false, hasInternalKey = true)
            launch { syncRelayListOnLogin(pubKey, io.nurunuru.app.data.InternalSigner(keyManager)) }
        }
    }

    /**
     * 生体認証失敗/キャンセル時。
     */
    fun onBiometricFailure() {
        _authState.value = AuthState.LoggedOut
    }

    fun generateNewAccount(): GeneratedAccount? {
        return try {
            val keys = NostrKeyUtils.generateKeys()
            val privHex = keys.secretKey().toHex()
            val pubHex = keys.publicKey().toHex()
            val nsec = NostrKeyUtils.encodeNsec(privHex) ?: ""
            val npub = NostrKeyUtils.encodeNpub(pubHex) ?: ""

            // 秘密鍵を SecureKeyManager に安全に保存
            val keyBytes = hexToBytes(privHex)
            if (keyBytes != null) {
                keyManager.generateKeystoreKey(requireBiometric = false)
                keyManager.storeKey(keyBytes, pubHex)
                keyBytes.fill(0)
            }

            GeneratedAccount(
                pubkeyHex = pubHex,
                nsec = nsec,
                npub = npub
            )
        } catch (e: Exception) {
            null
        }
    }


    fun saveInitialOnboardingDraft(
        name: String,
        about: String,
        picture: String = "",
        banner: String = "",
        nip05: String = "",
        lud16: String = "",
        website: String = "",
        birthday: String = "",
        relays: List<Triple<String, Boolean, Boolean>>? = null
    ) {
        val relayList = relays ?: listOf(
            Triple("wss://yabu.me", true, true),
            Triple("wss://relay-jp.nostr.wirednet.jp", true, true),
            Triple("wss://r.kojira.io", true, true)
        )
        prefs.nip65Relays = relayList.map { (url, read, write) ->
            io.nurunuru.app.data.models.Nip65Relay(url, read, write)
        }
        prefs.mainRelay = relayList.firstOrNull { it.second && it.third }?.first
            ?: relayList.firstOrNull()?.first
            ?: "wss://yabu.me"
        val pubkey = prefs.publicKeyHex ?: keyManager.getStoredPublicKeyHex()
        if (!pubkey.isNullOrBlank()) {
            val draft = UserProfile(
                pubkey = pubkey,
                name = name,
                displayName = name,
                about = about,
                picture = picture,
                banner = banner,
                nip05 = nip05,
                lud16 = lud16,
                website = website,
                birthday = birthday
            )
            try {
                io.nurunuru.app.data.cache.NostrCache(getApplication()).setCachedProfile(pubkey, draft, true)
            } catch (e: Exception) {
                android.util.Log.w("AuthViewModel", "saveInitialOnboardingDraft cache failed: ${e.message}")
            }
        }
    }

    suspend fun publishInitialMetadata(
        signer: io.nurunuru.app.data.AppSigner,
        name: String,
        about: String,
        picture: String = "",
        banner: String = "",
        nip05: String = "",
        lud16: String = "",
        website: String = "",
        birthday: String = "",
        relays: List<Triple<String, Boolean, Boolean>>? = null
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val targetRelays = relays?.map { it.first } ?: listOf("wss://yabu.me", "wss://relay.nostr.wirednet.jp", "wss://r.kojira.io")
            val client = NostrClient(
                context = getApplication(),
                relays = targetRelays,
                signer = signer
            )
            client.connect()

            delay(1500)

            val cache = io.nurunuru.app.data.cache.NostrCache(getApplication())
            val recommendationEngine = io.nurunuru.app.data.RecommendationEngine(getApplication())
            val repository = NostrRepository(client, prefs, cache, recommendationEngine)

            val relayList = relays ?: targetRelays.map { Triple(it, true, true) }
            // Persist the selected relay set before publishing so the just-created
            // account immediately uses the same NIP-65 relays after login.
            prefs.nip65Relays = relayList.map { (url, read, write) ->
                io.nurunuru.app.data.models.Nip65Relay(url, read, write)
            }
            prefs.mainRelay = relayList.firstOrNull { it.second && it.third }?.first
                ?: relayList.firstOrNull()?.first
                ?: "wss://yabu.me"

            val profile = UserProfile(
                pubkey = signer.getPublicKeyHex(),
                name = name,
                displayName = name,
                about = about,
                picture = picture,
                banner = banner,
                nip05 = nip05,
                lud16 = lud16,
                website = website,
                birthday = birthday
            )
            val profilePublished = repository.updateProfile(profile)
            if (!profilePublished) {
                android.util.Log.e("AuthViewModel", "Initial kind0 profile publish failed")
                client.disconnect()
                return@withContext false
            }

            delay(500)
            val relayPublished = repository.updateRelayList(relayList) || run {
                android.util.Log.w("AuthViewModel", "Initial kind10002 relay publish failed; retrying once")
                delay(1000)
                repository.updateRelayList(relayList)
            }
            if (!relayPublished) {
                android.util.Log.e("AuthViewModel", "Initial kind10002 relay publish failed")
                client.disconnect()
                return@withContext false
            }

            delay(1000)
            client.disconnect()
            true
        } catch (e: Exception) {
            android.util.Log.e("AuthViewModel", "publishInitialMetadata failed", e)
            false
        }
    }

    private suspend fun syncRelayListOnLogin(pubKeyHex: String, signer: io.nurunuru.app.data.AppSigner) {
        try {
            val discoveryRelays = (prefs.nip65Relays.map { it.url } + prefs.relays.toList() + OutboxModel.RELAY_LIST_DISCOVERY_RELAYS).distinct()
            val client = NostrClient(
                context = getApplication(),
                relays = discoveryRelays,
                signer = signer
            )
            client.connect()
            delay(1200)
            val cache = io.nurunuru.app.data.cache.NostrCache(getApplication())
            val recommendationEngine = io.nurunuru.app.data.RecommendationEngine(getApplication())
            val repository = NostrRepository(client, prefs, cache, recommendationEngine)
            repository.syncLoggedInUserRelayList(pubKeyHex)
            client.disconnect()
        } catch (e: Exception) {
            android.util.Log.w("AuthViewModel", "syncRelayListOnLogin failed: " + e.message)
        }
    }

    /**
     * 新規作成チュートリアル投稿。
     * オンボーディング最終段階で kind:1 ノートを発行する。
     *
     * - 本文は UI 側 (TutorialStep) で既定として `\n#nostrはじめました` が pre-fill されており、
     *   ユーザーがそのまま投稿すればハッシュタグ付きで送信される。
     * - ユーザーが意図的にハッシュタグ行を削除した場合は、削除した状態のまま送信する。
     *   この関数は本文への自動補完・末尾付与を一切行わない (「勝手に付けられた」を回避する規約)。
     * - 本文中の `#xxx` のみを抽出して `t` タグを生成する (PostModal と同一規約)。
     * - `publishInitialMetadata` と同じ一時 NostrClient を生成して送信する
     *   (この時点では prefs にリレーが入っていても client が起動していない)。
     * - 140 文字超 / 空本文の場合は送信せず `false` を返す。
     *
     * @return 投稿成功時 true。
     */
    suspend fun publishTutorialPost(
        signer: io.nurunuru.app.data.AppSigner,
        content: String,
        relays: List<Triple<String, Boolean, Boolean>>? = null
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            // 本文は UI 側で pre-fill 済み (`\n#nostrはじめました`)。
            // ユーザーが意図的にハッシュタグを消した場合は、消した状態のまま送信する
            // (自動補完・末尾付与は一切行わない。3 プラットフォーム共通の規約)。
            // trim せず原文を送信して、pre-fill 由来の先頭改行を尊重する。
            val finalContent = content

            // 本文中の `#xxx` のみを `t` タグとして抽出 (PostModal.kt と同一規約)。
            // ユーザーがハッシュタグを消していれば t タグも付かない (意図尊重)。
            // Web (SignUpModal.js) / iOS (AuthViewModel.swift) と同じく
            // 「lowercase → distinct」の順で正規化し、`#Foo` と `#foo` を同一視する。
            val hashtagRegex = Regex("#([\\w\\u3040-\\u309F\\u30A0-\\u30FF\\u4E00-\\u9FFF\\uFF00-\\uFFEF]+)")
            val foundTags = hashtagRegex.findAll(finalContent)
                .map { it.groupValues[1].lowercase() }
                .distinct()
                .toList()

            if (finalContent.length > 140) {
                android.util.Log.w("AuthViewModel", "publishTutorialPost: content exceeds 140 chars")
                return@withContext false
            }
            if (finalContent.trim().isEmpty()) {
                android.util.Log.w("AuthViewModel", "publishTutorialPost: content is empty")
                return@withContext false
            }
            val tags = foundTags.map { listOf("t", it) }  // foundTags は既に lowercase 正規化済み

            val targetRelays = relays?.map { it.first }
                ?: prefs.nip65Relays.map { it.url }.ifEmpty {
                    listOf("wss://yabu.me", "wss://relay-jp.nostr.wirednet.jp", "wss://r.kojira.io")
                }

            val client = NostrClient(
                context = getApplication(),
                relays = targetRelays,
                signer = signer
            )
            try {
                client.connect()
                delay(1500)

                val cache = io.nurunuru.app.data.cache.NostrCache(getApplication())
                val recommendationEngine = io.nurunuru.app.data.RecommendationEngine(getApplication())
                val repository = NostrRepository(client, prefs, cache, recommendationEngine)

                val result = repository.publishNote(
                    content = finalContent,
                    customTags = tags
                )
                delay(800)

                if (result == null) {
                    android.util.Log.w("AuthViewModel", "publishTutorialPost: publishNote returned null")
                    false
                } else {
                    android.util.Log.d("AuthViewModel", "publishTutorialPost OK: ${result.id}")
                    true
                }
            } finally {
                // 例外パスでも必ず接続を閉じる (リレー接続リーク防止)。
                try { client.disconnect() } catch (e: Exception) {
                    android.util.Log.w("AuthViewModel", "publishTutorialPost: disconnect failed", e)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("AuthViewModel", "publishTutorialPost failed", e)
            false
        }
    }

    fun setPendingReferralFollow(rawPubkey: String?) {
        val hex = normalizeReferralPubkey(rawPubkey)
        pendingReferralFollowPubkey = hex
        prefs.pendingReferralPubkeyHex = hex
        if (hex != null) loadReferralInvitePreview(hex)
        else _referralInvitePreview.value = null
    }

    fun dismissReferralInvite() {
        pendingReferralFollowPubkey = null
        prefs.pendingReferralPubkeyHex = null
        _referralInvitePreview.value = null
    }

    private fun loadReferralInvitePreview(pubkeyHex: String) {
        _referralInvitePreview.value = ReferralInvitePreview(pubkeyHex, isLoading = true)
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val relays = prefs.relays.toList().ifEmpty { io.nurunuru.app.data.models.DEFAULT_RELAYS }
                val signer = object : io.nurunuru.app.data.AppSigner {
                    override fun getPublicKeyHex(): String = pubkeyHex
                    override suspend fun signEvent(eventJson: String, requireManualApproval: Boolean): String? = null
                    override suspend fun nip04Encrypt(receiverPubkeyHex: String, content: String): String? = null
                    override suspend fun nip04Decrypt(senderPubkeyHex: String, content: String): String? = null
                    override suspend fun nip44Encrypt(receiverPubkeyHex: String, content: String): String? = null
                    override suspend fun nip44Decrypt(senderPubkeyHex: String, content: String): String? = null
                }
                val client = NostrClient(getApplication(), relays, signer)
                val repo = NostrRepository(client, prefs, io.nurunuru.app.data.cache.NostrCache(getApplication()), RecommendationEngine(getApplication()))
                client.connect()
                delay(1_200)
                val profile = repo.fetchProfiles(listOf(pubkeyHex))[pubkeyHex]
                client.disconnect()
                _referralInvitePreview.value = ReferralInvitePreview(pubkeyHex, profile = profile, isLoading = false)
            } catch (e: Exception) {
                android.util.Log.w("AuthViewModel", "Referral preview failed: ${e.message}")
                _referralInvitePreview.value = ReferralInvitePreview(pubkeyHex, isLoading = false)
            }
        }
    }

    fun handleProfileReferralDeepLink(uri: Uri) {
        val raw = uri.getQueryParameter("npub")
            ?: uri.getQueryParameter("pubkey")
            ?: uri.getQueryParameter("ref")
            ?: uri.lastPathSegment?.takeIf { it.startsWith("npub1") || it.length == 64 }
        val hex = normalizeReferralPubkey(raw) ?: return
        val current = _authState.value
        if (current is AuthState.LoggedIn) {
            if (hex != current.pubkeyHex) _profileNavigationEvents.tryEmit(hex)
        } else {
            setPendingReferralFollow(hex)
        }
    }

    fun handleEventDeepLink(uri: Uri) {
        val raw = uri.getQueryParameter("id")
            ?: uri.getQueryParameter("event")
            ?: uri.lastPathSegment?.takeIf { it.length == 64 }
        val eventId = raw?.takeIf { it.matches(Regex("^[0-9a-fA-F]{64}$")) }?.lowercase() ?: return
        if (_authState.value is AuthState.LoggedIn) _eventNavigationEvents.tryEmit(eventId)
    }

    private fun normalizeReferralPubkey(rawPubkey: String?): String? {
        val normalized = rawPubkey?.takeIf { it.isNotBlank() }?.let { NostrKeyUtils.parsePublicKey(it) ?: it }
        return normalized?.takeIf { it.matches(Regex("^[0-9a-fA-F]{64}$")) }?.lowercase()
    }

    fun completeRegistration(pubKeyHex: String, activity: Activity? = null) {
        // 秘密鍵は既に SecureKeyManager（nsec）または Passkey（nosskey）に保存済み。
        // 「はじめる」タップ時はログイン状態を先に反映し、LoginScreen/新規登録画面へ
        // 一瞬戻ることなく MainScreen(ホーム) へ直接切り替える。
        prefs.publicKeyHex = pubKeyHex
        prefs.isExternalSigner = false
        _authState.value = AuthState.LoggedIn(
            pubKeyHex,
            isExternal = false,
            hasInternalKey = prefs.loginMethod != "nosskey"
        )

        // リレー同期は遷移後にバックグラウンドで継続する。
        viewModelScope.launch(Dispatchers.IO) {
            val signer: io.nurunuru.app.data.AppSigner =
                if (prefs.loginMethod == "nosskey") {
                    val keyInfo = nosskeyManager.loadStoredKeyInfo(getApplication())
                    if (keyInfo != null && activity != null) {
                        NosskeySigner(activity, nosskeyManager, keyInfo)
                    } else {
                        android.util.Log.w(
                            "AuthViewModel",
                            "completeRegistration: nosskey selected but activity/keyInfo missing — skipping relay sync"
                        )
                        return@launch
                    }
                } else {
                    io.nurunuru.app.data.InternalSigner(keyManager)
                }
            val referral = pendingReferralFollowPubkey
            if (!referral.isNullOrBlank() && referral != pubKeyHex) {
                // Apply the invite follow before relay-sync. A brand-new account has no
                // remote kind:10002 yet; syncing first may no-op or rewrite relay prefs
                // while the follow publish is preparing. We also seed the local cache
                // synchronously inside followPendingReferral so MainScreen can show the
                // follow immediately even if relay ACKs are slow.
                followPendingReferral(pubKeyHex, referral, signer)
                pendingReferralFollowPubkey = null
                prefs.pendingReferralPubkeyHex = null
                _referralInvitePreview.value = null
            }
            syncRelayListOnLogin(pubKeyHex, signer)
        }
    }

    private suspend fun followPendingReferral(myPubkeyHex: String, targetPubkeyHex: String, signer: io.nurunuru.app.data.AppSigner) {
        val appContext = getApplication<Application>()
        val cache = io.nurunuru.app.data.cache.NostrCache(appContext)
        val optimistic = cache.getCachedFollowList(myPubkeyHex).orEmpty()
            .plus(targetPubkeyHex)
            .distinct()
        // Make the local graph correct immediately. MainScreen uses the same cache
        // file, so this survives relay latency and app restarts during the first run.
        cache.setCachedFollowList(myPubkeyHex, optimistic)

        try {
            val relays = (prefs.nip65Relays.map { it.url } + prefs.relays.toList() +
                listOf("wss://yabu.me", "wss://relay-jp.nostr.wirednet.jp", "wss://r.kojira.io"))
                .distinct()
            val client = NostrClient(appContext, relays, signer)
            val repo = NostrRepository(client, prefs, cache, RecommendationEngine(appContext))
            client.connect()
            delay(1_000)
            val success = repo.publishContactList(myPubkeyHex, optimistic)
            if (!success) {
                android.util.Log.w("AuthViewModel", "Referral follow publish failed; kept local cache target=${targetPubkeyHex.take(8)}")
            }
            delay(500)
            client.disconnect()
            android.util.Log.d("AuthViewModel", "Referral follow applied local=true publish=$success target=${targetPubkeyHex.take(8)} total=${optimistic.size}")
        } catch (e: Exception) {
            android.util.Log.w("AuthViewModel", "Referral follow failed after local cache seed: ${e.message}")
        }
    }

    private suspend fun NostrRepository.publishContactList(myPubkeyHex: String, follows: List<String>): Boolean {
        return try {
            val tags = follows.distinct().map { listOf("p", it) }
            val ok = publishNewEventForOnboarding(NostrKind.CONTACT_LIST, "", tags) != null
            if (ok) {
                io.nurunuru.app.data.cache.NostrCache(getApplication()).setCachedFollowList(myPubkeyHex, follows.distinct())
            }
            ok
        } catch (e: Exception) {
            android.util.Log.w("AuthViewModel", "publishContactList failed: ${e.message}")
            false
        }
    }

    private suspend fun NostrRepository.publishNewEventForOnboarding(
        kind: Int,
        content: String,
        tags: List<List<String>>
    ): String? {
        return try {
            val rustClient = client.getRustClient() ?: return null
            val unsigned = withContext(Dispatchers.IO) {
                rustClient.createUnsignedEvent(kind.toUInt(), content, tags, myPubkeyHex)
            }
            val signedJson = client.getSigner().signEvent(unsigned) ?: return null
            withContext(Dispatchers.IO) { rustClient.publishRawEvent(signedJson) }
        } catch (e: Exception) {
            android.util.Log.w("AuthViewModel", "publishNewEventForOnboarding failed: ${e.message}")
            null
        }
    }

    fun loginWithAmber(pubkey: String) {
        viewModelScope.launch(Dispatchers.IO) {
            // Normalize to hex — Amber may return npub (bech32) or hex format
            val pubkeyHex = io.nurunuru.app.data.NostrKeyUtils.parsePublicKey(pubkey) ?: pubkey
            prefs.publicKeyHex = pubkeyHex
            prefs.isExternalSigner = true
            prefs.loginMethod = "amber"
            io.nurunuru.app.data.ExternalSigner.setCurrentUser(pubkeyHex)
            syncRelayListOnLogin(pubkeyHex, io.nurunuru.app.data.ExternalSigner)
            _authState.value = AuthState.LoggedIn(pubkeyHex, isExternal = true)
        }
    }

    fun login(nsecOrHex: String) {
        viewModelScope.launch(Dispatchers.IO) {
            _authState.value = AuthState.Checking

            val privKeyHex = NostrKeyUtils.parsePrivateKey(nsecOrHex)
            if (privKeyHex == null) {
                _authState.value = AuthState.Error("秘密鍵の形式が正しくありません（nsec1... または64桁の16進数）")
                return@launch
            }

            val pubKeyHex = NostrKeyUtils.derivePublicKey(privKeyHex)
            if (pubKeyHex == null) {
                _authState.value = AuthState.Error("公開鍵の導出に失敗しました")
                return@launch
            }

            try {
                // hex → ByteArray → SecureKeyManager で暗号化保存
                val keyBytes = hexToBytes(privKeyHex)
                if (keyBytes == null || keyBytes.size != 32) {
                    _authState.value = AuthState.Error("秘密鍵のバイト変換に失敗しました")
                    return@launch
                }

                try {
                    keyManager.generateKeystoreKey(requireBiometric = false)
                } catch (e: Exception) {
                    _authState.value = AuthState.Error("キーストア鍵の生成に失敗しました: ${e.message}")
                    return@launch
                }

                try {
                    keyManager.storeKey(keyBytes, pubKeyHex)
                } catch (e: Exception) {
                    _authState.value = AuthState.Error("秘密鍵の暗号化保存に失敗しました: ${e.message}")
                    return@launch
                } finally {
                    keyBytes.fill(0)
                }

                prefs.publicKeyHex = pubKeyHex
                prefs.isExternalSigner = false
                prefs.clearPrivateKey()

                syncRelayListOnLogin(pubKeyHex, io.nurunuru.app.data.InternalSigner(keyManager))
                _authState.value = AuthState.LoggedIn(pubKeyHex, isExternal = false, hasInternalKey = true)
            } catch (e: Exception) {
                _authState.value = AuthState.Error("ログイン処理中にエラーが発生しました: ${e.message}")
            }
        }
    }

    /**
     * Generate a brand new account whose private key is derived from a freshly
     * registered Passkey + PRF assertion (nosskey "PRF Direct Method").
     *
     * - The secret is never persisted; only the credential metadata is.
     * - Pubkey is computed via rust-nostr and stored in [prefs.publicKeyHex] so
     *   the rest of the app can keep using the existing read paths.
     */
    suspend fun generateNewAccountWithPasskey(
        activity: Activity,
        username: String
    ): GeneratedAccount? = withContext(Dispatchers.IO) {
        try {
            val creation = nosskeyManager.createPasskeyWithSecret(
                activity = activity,
                username = username,
                displayName = username
            )
            val keyInfo = creation.keyInfo
            // Reuse the PRF secret returned from registration/fallback assertion.
            // Do not derive it again here; that caused an extra Passkey prompt.
            val secret = creation.secretKey
            try {
                val privHex = secret.joinToString("") { "%02x".format(it) }
                val pubHex = NostrKeyUtils.derivePublicKey(privHex)
                    ?: throw IllegalStateException("derive pubkey failed")
                val nsec = NostrKeyUtils.encodeNsec(privHex) ?: ""
                val npub = NostrKeyUtils.encodeNpub(pubHex) ?: ""
                val finalKeyInfo = if (keyInfo.pubkey == pubHex) keyInfo
                                   else keyInfo.copy(pubkey = pubHex)
                nosskeyManager.saveKeyInfo(getApplication(), finalKeyInfo)
                prefs.loginMethod = "nosskey"
                prefs.publicKeyHex = pubHex
                prefs.isExternalSigner = false

                // Seed a session signer with the same PRF secret so profile,
                // relay-list, tutorial post, and MainScreen startup do not prompt
                // again immediately after registration.
                activeNosskeySigner?.close()
                activeNosskeySigner = NosskeySigner(activity, nosskeyManager, finalKeyInfo).also {
                    it.primeCache(secret)
                }

                GeneratedAccount(pubkeyHex = pubHex, nsec = nsec, npub = npub)
            } finally {
                secret.fill(0)
            }
        } catch (e: NosskeyError.UserCancelled) {
            null
        } catch (e: Exception) {
            android.util.Log.e("AuthViewModel", "generateNewAccountWithPasskey failed", e)
            _authState.value = AuthState.Error("パスキー登録失敗: ${e.message}")
            null
        }
    }

    /**
     * Log in with a previously registered Passkey by performing a PRF assertion
     * to verify the credential still works, then setting the session state.
     */
    fun loginWithPasskey(activity: Activity) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val keyInfo = nosskeyManager.loadStoredKeyInfo(getApplication())
                    ?: run {
                        _authState.value = AuthState.Error(
                            "パスキーが登録されていません。先に新規登録してください"
                        )
                        return@launch
                    }
                // Verify by running a real PRF assertion (biometric prompt), then
                // reuse the same secret for the session signer cache.
                val secret = nosskeyManager.deriveSecretKey(activity, keyInfo)
                try {
                    activeNosskeySigner?.close()
                    activeNosskeySigner = NosskeySigner(activity, nosskeyManager, keyInfo).also {
                        it.primeCache(secret)
                    }
                } finally {
                    secret.fill(0)
                }
                prefs.publicKeyHex = keyInfo.pubkey
                prefs.loginMethod = "nosskey"
                prefs.isExternalSigner = false
                _authState.value = AuthState.LoggedIn(
                    keyInfo.pubkey,
                    isExternal = false,
                    hasInternalKey = false
                )
            } catch (e: NosskeyError.UserCancelled) {
                // explicit user cancel — leave state alone
            } catch (e: Exception) {
                android.util.Log.e("AuthViewModel", "loginWithPasskey failed", e)
                _authState.value = AuthState.Error("パスキーログイン失敗: ${e.message}")
            }
        }
    }

    /**
     * Build the appropriate signer for the current session.
     * NosskeySigner requires an Activity because every signature triggers a
     * biometric prompt via CredentialManager. Internal and external paths
     * keep working as before.
     */
    fun buildSigner(activity: Activity? = null): io.nurunuru.app.data.AppSigner {
        return when (prefs.loginMethod) {
            "nosskey" -> {
                activeNosskeySigner ?: run {
                    val keyInfo = nosskeyManager.loadStoredKeyInfo(getApplication())
                        ?: throw IllegalStateException("nosskey info missing")
                    val act = activity
                        ?: throw IllegalStateException("Activity required for NosskeySigner")
                    NosskeySigner(act, nosskeyManager, keyInfo).also { activeNosskeySigner = it }
                }
            }
            "amber", "external" -> io.nurunuru.app.data.ExternalSigner
            else -> io.nurunuru.app.data.InternalSigner(keyManager)
        }
    }

    /**
     * 生体認証を有効化する (設定画面から呼ばれる)。
     */
    fun enableBiometric() {
        viewModelScope.launch(Dispatchers.IO) {
            val keyBytes = keyManager.getKeyBytes() ?: return@launch
            val pubkey = keyManager.getStoredPublicKeyHex() ?: return@launch

            try {
                keyManager.deleteAll()
                keyManager.generateKeystoreKey(requireBiometric = true)
                keyManager.storeKey(keyBytes, pubkey)
                keyBytes.fill(0)
            } catch (e: Exception) {
                keyManager.generateKeystoreKey(requireBiometric = false)
                keyManager.storeKey(keyBytes, pubkey)
                keyBytes.fill(0)
            }
        }
    }

    fun getNsecTemporary(): String? {
        return keyManager.getKeyHexTemporary()?.let { NostrKeyUtils.encodeNsec(it) }
    }

    suspend fun getNsecForCurrentAccount(activity: Activity? = null): String? = withContext(Dispatchers.IO) {
        if (prefs.loginMethod == "nosskey") {
            val keyInfo = nosskeyManager.loadStoredKeyInfo(getApplication()) ?: return@withContext null
            val act = activity ?: return@withContext null
            val secret = nosskeyManager.deriveSecretKey(act, keyInfo)
            try {
                NostrKeyUtils.encodeNsec(secret.joinToString("") { "%02x".format(it) })
            } catch (e: Exception) {
                android.util.Log.e("AuthViewModel", "getNsecForCurrentAccount(nosskey) failed", e)
                null
            } finally {
                secret.fill(0)
            }
        } else {
            getNsecTemporary()
        }
    }

    fun logout() {
        val app = getApplication<Application>()

        // Issue #181: external-signer MLS DB key is pubkey-scoped, so we
        // wipe it via the current pubkey BEFORE prefs.clear() forgets it.
        // For the internal-signer path the key is derived from nsec via
        // HKDF and not persisted, so deleteAll() / clearLocalRustDatabases()
        // is sufficient.
        try {
            val currentPubkey = prefs.publicKeyHex
            if (currentPubkey != null && currentPubkey.length == 64) {
                io.nurunuru.app.data.MlsDbKeyStore.clearExternalKey(app, currentPubkey)
            } else if (currentPubkey != null) {
                // bech32 form or unexpected — wipe everything in the
                // external keystore to be safe.
                io.nurunuru.app.data.MlsDbKeyStore.clearAllExternalKeys(app)
            }
        } catch (_: Exception) { }

        keyManager.deleteAll()
        // Do NOT clear NosskeyKeyInfo here. It is non-secret metadata
        // (credentialId/pubkey/salt) required for passkey login after logout.
        activeNosskeySigner?.close()
        activeNosskeySigner = null

        // Privacy/account isolation: Talk uses Rust MLS SQLite as its source of truth.
        // If it survives logout, a different account can still see old local groups/messages
        // because the FFI DB is app-global. Clear both app-layer cache and local Rust DB files.
        try { io.nurunuru.app.data.cache.NostrCache(app).clearAll() } catch (_: Exception) { }
        try { clearLocalRustDatabases(app) } catch (_: Exception) { }

        prefs.clear()
        prefs.loginMethod = null
        _authState.value = AuthState.LoggedOut
    }

    private fun clearLocalRustDatabases(context: Context) {
        val base = File(context.filesDir, "nostrdb_ndb")
        // MLS database path is configured in Rust as "${filesDir}/nostrdb_ndb_mls.sqlite3".
        listOf(
            base,
            File(context.filesDir, "nostrdb_ndb_mls.sqlite3"),
            File(context.filesDir, "nostrdb_ndb_mls.sqlite3-shm"),
            File(context.filesDir, "nostrdb_ndb_mls.sqlite3-wal")
        ).forEach { file ->
            if (file.exists()) {
                if (file.isDirectory) file.deleteRecursively() else file.delete()
            }
        }
    }

    fun clearError() {
        if (_authState.value is AuthState.Error) {
            _authState.value = AuthState.LoggedOut
        }
    }

    private fun hexToBytes(hex: String): ByteArray? {
        if (hex.length % 2 != 0) return null
        return try {
            ByteArray(hex.length / 2) { i ->
                hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        } catch (e: NumberFormatException) {
            null
        }
    }
}
