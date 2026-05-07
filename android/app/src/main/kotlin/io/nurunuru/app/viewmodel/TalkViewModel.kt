package io.nurunuru.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.nurunuru.app.data.NostrClient
import io.nurunuru.app.data.NostrRepository
import io.nurunuru.app.data.*
import io.nurunuru.app.data.models.DmConversation
import io.nurunuru.app.data.models.MlsGroup
import io.nurunuru.app.data.models.MlsMessage
import io.nurunuru.app.data.models.UserProfile
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * Android Talk ViewModel for Marmot MLS conversations.
 *
 * Mirrors the iOS TalkViewModel policy:
 * - Lazy group loading so Talk/Marmot relays do not block timeline startup.
 * - Local-first open, relay catch-up in background.
 * - DM duplicate/canonical selection prefers the group that has peer messages.
 * - Before send, replay/catch up the active group so outbound Kind-445 is created from a current epoch.
 * - Failed/timed-out sends remove optimistic bubbles.
 */
data class TalkUiState(
    val groups: List<MlsGroup> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val activeGroupId: String? = null,
    val activeGroup: MlsGroup? = null,
    val messages: List<MlsMessage> = emptyList(),
    val messagesLoading: Boolean = false,
    val sendingMessage: Boolean = false,
    // Legacy (read-only; Talk UI is Marmot MLS only)
    @Suppress("DEPRECATION")
    val legacyConversations: List<DmConversation> = emptyList(),
    val showLegacy: Boolean = false,
    // Group management UI state
    val showGroupInfo: Boolean = false,
    val showCreateGroup: Boolean = false,
    // Following list for member picker (loaded on demand)
    val followingProfiles: List<UserProfile> = emptyList(),
    val followingLoading: Boolean = false
)

class TalkViewModel(
    private val repository: NostrRepository,
    @Suppress("unused") private val nostrClient: NostrClient,
    private val myPubkeyHex: String
) : ViewModel() {

    private val _uiState = MutableStateFlow(TalkUiState(isLoading = false))
    val uiState: StateFlow<TalkUiState> = _uiState.asStateFlow()

    private var messageStreamJob: Job? = null
    private var didInitialLoad = false
    private var loadGroupsInFlight = false
    private var openingGroupInFlight = false

    /** Called by TalkScreen when the tab is actually shown. */
    fun loadGroupsIfNeeded() {
        if (didInitialLoad) return
        didInitialLoad = true
        loadGroups()
    }

    /**
     * キャッシュクリア後にUIを即時リセットして再取得する。
     * Rust MLS 状態から再構築されるため、退出済みグループは leftIds フィルタで除外される。
     */
    fun clearStateAfterCacheClear() {
        messageStreamJob?.cancel()
        messageStreamJob = null
        _uiState.update {
            it.copy(
                groups = emptyList(),
                messages = emptyList(),
                activeGroupId = null,
                activeGroup = null,
                showGroupInfo = false
            )
        }
        didInitialLoad = false
        loadGroupsIfNeeded()
    }

    fun loadGroups() {
        if (loadGroupsInFlight) return
        loadGroupsInFlight = true
        viewModelScope.launch {
            val cached = repository.getCachedMlsGroups().sortedByDescending { it.lastMessageTime }
            _uiState.update { it.copy(groups = cached, isLoading = true, error = null) }
            try {
                val fetched = repository.fetchMlsGroups().sortedByDescending { it.lastMessageTime }
                _uiState.update { state ->
                    val active = state.activeGroup?.let { current ->
                        fetched.firstOrNull { it.groupIdHex == current.groupIdHex } ?: current
                    }
                    state.copy(groups = fetched, activeGroup = active, isLoading = false)
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = normalizeMlsError(e, "トークの読み込みに失敗しました"), isLoading = false) }
            } finally {
                loadGroupsInFlight = false
            }
        }
    }

    fun openGroup(groupIdHex: String) {
        if (openingGroupInFlight) return
        val requested = _uiState.value.groups.firstOrNull { it.groupIdHex == groupIdHex } ?: return
        openingGroupInFlight = true
        _uiState.update {
            it.copy(
                activeGroupId = requested.groupIdHex,
                activeGroup = requested,
                messagesLoading = true,
                error = null
            )
        }
        startMessageStream(requested.groupIdHex)

        viewModelScope.launch {
            try {
                var finalGroup = requested
                var finalMessages = repository.getLocalMlsMessages(requested.groupIdHex)
                if (finalMessages.isNotEmpty()) {
                    _uiState.update { it.copy(messages = dedupeMessages(finalMessages), messagesLoading = false) }
                }

                // WhiteNoise/Marmot interop: if multiple DM groups with the same partner
                // exist, prefer the group whose local/repair history contains peer messages.
                if (requested.isDm) {
                    val partner = requested.memberPubkeys.firstOrNull { it != myPubkeyHex }
                    val candidates = (_uiState.value.groups.filter { candidate ->
                        candidate.isDm && (partner == null || candidate.memberPubkeys.contains(partner))
                    } + requested)
                        .distinctBy { it.groupIdHex }
                        .sortedWith(compareByDescending<MlsGroup> { it.lastMessageTime }.thenBy { it.groupIdHex })
                        .take(8)

                    val scanned = candidates.map { candidate ->
                        var local = if (candidate.groupIdHex == requested.groupIdHex) {
                            finalMessages
                        } else {
                            repository.getLocalMlsMessages(candidate.groupIdHex)
                        }
                        if (local.none { it.senderPubkey != myPubkeyHex }) {
                            try {
                                local = withTimeout(30_000) {
                                    repository.fetchMlsMessages(candidate.groupIdHex, repairFull = true)
                                }
                            } catch (_: Exception) {
                                local
                            }
                        }
                        candidate to local
                    }

                    scanned.maxWithOrNull(compareBy<Pair<MlsGroup, List<MlsMessage>>> { entry ->
                        entry.second.count { it.senderPubkey != myPubkeyHex }
                    }.thenBy { entry ->
                        entry.second.filter { it.senderPubkey != myPubkeyHex }.maxOfOrNull { it.timestamp } ?: 0L
                    }.thenBy { entry ->
                        entry.second.size
                    }.thenBy { entry ->
                        entry.second.maxOfOrNull { it.timestamp } ?: 0L
                    }.thenBy { entry ->
                        entry.first.lastMessageTime
                    })?.let { best ->
                        finalGroup = best.first
                        finalMessages = best.second
                    }
                }

                _uiState.update {
                    it.copy(
                        activeGroupId = finalGroup.groupIdHex,
                        activeGroup = finalGroup,
                        messages = dedupeMessages(finalMessages),
                        messagesLoading = false,
                        error = null
                    )
                }
                startMessageStream(finalGroup.groupIdHex)
            } catch (e: Exception) {
                _uiState.update { it.copy(messagesLoading = false) }
            } finally {
                openingGroupInFlight = false
            }
        }
    }

    fun closeGroup() {
        messageStreamJob?.cancel()
        messageStreamJob = null
        _uiState.update {
            it.copy(
                activeGroupId = null,
                activeGroup = null,
                messages = emptyList(),
                showGroupInfo = false
            )
        }
    }

    fun sendMessage(groupIdHex: String, content: String) {
        val trimmed = content.trim()
        if (trimmed.isBlank()) return

        viewModelScope.launch {
            var group = _uiState.value.activeGroup ?: _uiState.value.groups.firstOrNull { it.groupIdHex == groupIdHex } ?: return@launch

            // Last-chance DM canonicalization: do not send to a self-only orphan duplicate.
            if (group.isDm && _uiState.value.messages.none { it.senderPubkey != myPubkeyHex } && siblingDmGroupIds(group).size > 1) {
                openGroup(group.groupIdHex)
                delay(300)
                group = _uiState.value.activeGroup ?: group
            }

            // Critical Marmot interop rule: catch up before creating an application message.
            try {
                val caughtUp = withTimeout(30_000) {
                    repository.fetchMlsMessages(group.groupIdHex, repairFull = true)
                }
                if (shouldReplaceMessages(_uiState.value.messages, caughtUp)) {
                    _uiState.update { it.copy(messages = dedupeMessages(caughtUp)) }
                }
            } catch (_: Exception) {
                _uiState.update { it.copy(error = "同期中です。少し待ってから再送してください") }
                return@launch
            }

            val tempId = "local_${System.currentTimeMillis()}"
            val optimistic = MlsMessage(
                id = tempId,
                senderPubkey = myPubkeyHex,
                content = trimmed,
                timestamp = System.currentTimeMillis() / 1000,
                groupIdHex = group.groupIdHex
            )
            _uiState.update { it.copy(sendingMessage = true, messages = dedupeMessages(it.messages + optimistic)) }

            try {
                val success = withTimeout(30_000) { repository.sendMlsMessage(group.groupIdHex, trimmed) }
                if (success) {
                    val latest = repository.getLocalMlsMessages(group.groupIdHex).ifEmpty {
                        repository.fetchMlsMessages(group.groupIdHex)
                    }
                    _uiState.update { it.copy(messages = dedupeMessages(latest), error = null) }
                } else {
                    _uiState.update {
                        it.copy(
                            messages = it.messages.filterNot { msg -> msg.id == tempId },
                            error = "送信保留中です。接続状態を確認して再試行してください"
                        )
                    }
                }
            } catch (e: TimeoutCancellationException) {
                _uiState.update {
                    it.copy(
                        messages = it.messages.filterNot { msg -> msg.id == tempId },
                        error = "送信がタイムアウトしました。通信状態を確認して再試行してください"
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        messages = it.messages.filterNot { msg -> msg.id == tempId },
                        error = normalizeMlsError(e, "送信保留中です。接続状態を確認して再試行してください")
                    )
                }
            } finally {
                _uiState.update { it.copy(sendingMessage = false) }
            }
        }
    }

    fun createDmConversation(partnerPubkey: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                // Interop safety: publish/refresh my KeyPackage and Marmot relay lists first.
                repository.forceRepublishMyKeyPackageIfNeeded()

                val currentGroups = if (_uiState.value.groups.isEmpty()) {
                    val fetched = repository.fetchMlsGroups()
                    _uiState.update { it.copy(groups = fetched) }
                    fetched
                } else {
                    _uiState.value.groups
                }
                val existing = currentGroups.firstOrNull { g -> g.isDm && g.memberPubkeys.contains(partnerPubkey) }
                if (existing != null) {
                    _uiState.update { it.copy(isLoading = false) }
                    openGroup(existing.groupIdHex)
                    return@launch
                }

                val group = repository.createDmGroup(partnerPubkey)
                if (group != null) {
                    _uiState.update { it.copy(groups = (listOf(group) + currentGroups).distinctBy { g -> g.groupIdHex }, isLoading = false) }
                    openGroup(group.groupIdHex)
                } else {
                    _uiState.update { it.copy(isLoading = false, error = "相手のキーパッケージが見つかりません") }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = normalizeMlsError(e, "トークの作成に失敗しました"), isLoading = false) }
            }
        }
    }

    fun createGroupChat(name: String, memberPubkeys: List<String>) {
        if (name.isBlank() || memberPubkeys.isEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null, showCreateGroup = false) }
            try {
                val group = repository.createGroupChat(name, memberPubkeys)
                if (group != null) {
                    val groups = (listOf(group) + _uiState.value.groups).distinctBy { it.groupIdHex }
                    _uiState.update { it.copy(groups = groups, isLoading = false) }
                    openGroup(group.groupIdHex)
                } else {
                    _uiState.update { it.copy(isLoading = false, error = "グループの作成に失敗しました") }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = normalizeMlsError(e, "グループの作成に失敗しました"), isLoading = false) }
            }
        }
    }

    fun leaveGroup() {
        val group = _uiState.value.activeGroup ?: return
        viewModelScope.launch {
            // First hide locally to prevent resurrection if leave publish fails.
            repository.hideMlsGroupLocally(group.groupIdHex)
            if (group.isDm) {
                siblingDmGroupIds(group).filter { it != group.groupIdHex }.forEach { repository.hideMlsGroupLocally(it) }
            }
            try {
                repository.leaveGroup(group.groupIdHex)
            } catch (_: Exception) {
                // Non-fatal: local hide remains authoritative for UI.
            }
            val partner = group.memberPubkeys.firstOrNull { it != myPubkeyHex }
            val groups = if (group.isDm && partner != null) {
                _uiState.value.groups.filterNot { it.isDm && it.memberPubkeys.contains(partner) }
            } else {
                _uiState.value.groups.filter { it.groupIdHex != group.groupIdHex }
            }
            _uiState.update {
                it.copy(
                    groups = groups,
                    activeGroupId = null,
                    activeGroup = null,
                    messages = emptyList(),
                    showGroupInfo = false
                )
            }
        }
    }

    fun addMember(memberPubkey: String) {
        val groupIdHex = _uiState.value.activeGroupId ?: return
        viewModelScope.launch {
            try {
                val success = repository.addMemberToGroup(groupIdHex, memberPubkey)
                if (success) {
                    val groups = repository.fetchMlsGroups()
                    val activeGroup = groups.firstOrNull { it.groupIdHex == groupIdHex }
                    _uiState.update { it.copy(groups = groups, activeGroup = activeGroup) }
                } else {
                    _uiState.update { it.copy(error = "メンバーの追加に失敗しました") }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = normalizeMlsError(e, "メンバーの追加に失敗しました")) }
            }
        }
    }

    fun removeMember(memberPubkey: String) {
        val groupIdHex = _uiState.value.activeGroupId ?: return
        viewModelScope.launch {
            try {
                val success = repository.removeMemberFromGroup(groupIdHex, memberPubkey)
                if (success) {
                    val groups = repository.fetchMlsGroups()
                    val activeGroup = groups.firstOrNull { it.groupIdHex == groupIdHex }
                    _uiState.update { it.copy(groups = groups, activeGroup = activeGroup) }
                } else {
                    _uiState.update { it.copy(error = "メンバーの削除に失敗しました") }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = normalizeMlsError(e, "メンバーの削除に失敗しました")) }
            }
        }
    }

    private fun startMessageStream(groupIdHex: String) {
        messageStreamJob?.cancel()
        messageStreamJob = viewModelScope.launch {
            while (true) {
                delay(3_000)
                if (_uiState.value.activeGroupId != groupIdHex) break
                try {
                    val messages = repository.fetchMlsMessages(groupIdHex)
                    val normalized = dedupeMessages(messages)
                    if (shouldReplaceMessages(_uiState.value.messages, normalized)) {
                        _uiState.update { it.copy(messages = normalized) }
                    }
                } catch (_: Exception) {
                    // Keep polling non-fatal.
                }
            }
        }
    }

    fun repairCurrentGroup() {
        val groupId = _uiState.value.activeGroupId ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(messagesLoading = true) }
            val repaired = repository.repairMlsGroupHistory(groupId)
            _uiState.update { it.copy(messages = dedupeMessages(repaired), messagesLoading = false, error = null) }
        }
    }

    fun ensureKeyPackagePublished() {
        viewModelScope.launch {
            try {
                repository.ensureKeyPackagePublished()
            } catch (_: Exception) {
                // Non-critical.
            }
        }
    }

    fun showGroupInfo() { _uiState.update { it.copy(showGroupInfo = true) } }
    fun hideGroupInfo() { _uiState.update { it.copy(showGroupInfo = false) } }
    fun showCreateGroup() {
        _uiState.update { it.copy(showCreateGroup = true) }
        loadFollowingProfiles()
    }
    fun hideCreateGroup() { _uiState.update { it.copy(showCreateGroup = false) } }

    private fun loadFollowingProfiles() {
        if (_uiState.value.followingLoading || _uiState.value.followingProfiles.isNotEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(followingLoading = true) }
            try {
                val pubkeys = repository.fetchFollowList(myPubkeyHex)
                val profiles = if (pubkeys.isNotEmpty()) repository.fetchProfiles(pubkeys.take(200)) else emptyMap()
                val profileList = pubkeys.take(200).map { pk -> profiles[pk] ?: UserProfile(pubkey = pk) }
                _uiState.update { it.copy(followingProfiles = profileList, followingLoading = false) }
            } catch (e: Exception) {
                _uiState.update { it.copy(followingLoading = false, error = "フォローリストの取得に失敗しました") }
            }
        }
    }

    fun toggleLegacy() { _uiState.update { it.copy(showLegacy = !it.showLegacy) } }
    fun clearError() { _uiState.update { it.copy(error = null) } }

    private fun siblingDmGroupIds(group: MlsGroup): List<String> {
        val partner = group.memberPubkeys.firstOrNull { it != myPubkeyHex } ?: return emptyList()
        return _uiState.value.groups
            .filter { it.isDm && it.memberPubkeys.contains(partner) }
            .map { it.groupIdHex }
    }

    private fun dedupeMessages(input: List<MlsMessage>): List<MlsMessage> =
        input.associateBy { "${it.groupIdHex}|${it.senderPubkey}|${it.timestamp}|${it.content.trim()}" }
            .values
            .sortedWith(compareBy<MlsMessage> { it.timestamp }.thenBy { it.id })

    private fun shouldReplaceMessages(current: List<MlsMessage>, incoming: List<MlsMessage>): Boolean {
        val normalizedIncoming = dedupeMessages(incoming)
        if (current.size != normalizedIncoming.size) return true
        return current.zip(normalizedIncoming).any { (lhs, rhs) ->
            lhs.id != rhs.id ||
                lhs.senderPubkey != rhs.senderPubkey ||
                lhs.timestamp != rhs.timestamp ||
                lhs.content != rhs.content
        }
    }

    private fun normalizeMlsError(error: Throwable, fallback: String): String {
        val raw = (error.message ?: error.toString()).lowercase()
        return when {
            "invalid_base64_content" in raw || "invalid base64" in raw -> "MLSイベント形式が不正です（base64）"
            "malformed_content_too_short" in raw || "too_short" in raw -> "MLSイベント形式が不正です（長さ不足）"
            "missing_h_tag" in raw -> "MLSイベント形式が不正です（hタグ不足）"
            "group_id_mismatch" in raw -> "MLSイベントのグループIDが一致しません"
            "invalid_kind" in raw -> "MLSイベント種別が不正です"
            "pending proposal exists" in raw || "pending commit exists" in raw -> "同期中です。少し待って再試行してください"
            "no ffi client" in raw || "ffi unavailable" in raw || "mls not initialised" in raw -> "MLSエンジンが利用できません"
            "not admin" in raw -> "管理者のみがこの操作を実行できます"
            else -> fallback
        }
    }

    class Factory(
        private val repository: NostrRepository,
        private val nostrClient: NostrClient,
        private val myPubkeyHex: String
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            TalkViewModel(repository, nostrClient, myPubkeyHex) as T
    }
}
