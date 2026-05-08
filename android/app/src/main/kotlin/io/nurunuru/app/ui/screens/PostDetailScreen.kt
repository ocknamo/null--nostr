package io.nurunuru.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.nurunuru.app.data.NostrClient
import io.nurunuru.app.data.NostrRepository
import io.nurunuru.app.data.addBookmark
import io.nurunuru.app.data.deleteEvent
import io.nurunuru.app.data.fetchEvent
import io.nurunuru.app.data.fetchEvents
import io.nurunuru.app.data.fetchEventsFromRelays
import io.nurunuru.app.data.fetchNip65WriteRelays
import io.nurunuru.app.data.fetchNip65ReadRelays
import io.nurunuru.app.data.likePost
import io.nurunuru.app.data.repostPost
import io.nurunuru.app.data.models.NostrKind
import io.nurunuru.app.data.models.ScoredPost
import io.nurunuru.app.ui.components.*
import io.nurunuru.app.ui.theme.LineGreen
import io.nurunuru.app.ui.theme.LocalNuruColors
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PostDetailScreen(
    eventId: String,
    initialPost: ScoredPost? = null,
    repository: NostrRepository,
    myPubkey: String,
    onBack: () -> Unit,
    onProfileClick: (String) -> Unit = {}
) {
    val nuruColors = LocalNuruColors.current

    val coroutineScope = rememberCoroutineScope()
    var post by remember(eventId) { mutableStateOf(initialPost?.takeIf { it.event.id == eventId }) }
    var replies by remember { mutableStateOf<List<ScoredPost>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var showReplyModal by remember { mutableStateOf(false) }

    fun updatePostState(eventIdToUpdate: String, transform: (ScoredPost) -> ScoredPost) {
        post = post?.let { if (it.event.id == eventIdToUpdate) transform(it) else it }
        replies = replies.map { if (it.event.id == eventIdToUpdate) transform(it) else it }
    }

    fun likeDetailPost(target: ScoredPost, emoji: String = "+", customTags: List<List<String>> = emptyList()) {
        coroutineScope.launch {
            try {
                if (target.isLiked) {
                    val likeEventId = target.myLikeEventId ?: return@launch
                    if (repository.deleteEvent(likeEventId)) {
                        updatePostState(target.event.id) {
                            it.copy(isLiked = false, likeCount = maxOf(0, it.likeCount - 1), myLikeEventId = null)
                        }
                    }
                    return@launch
                }
                val newEventId = repository.likePost(target.event.id, target.event.pubkey, emoji, customTags)
                if (newEventId != null) {
                    updatePostState(target.event.id) {
                        it.copy(isLiked = true, likeCount = it.likeCount + 1, myLikeEventId = newEventId)
                    }
                }
            } catch (_: Exception) { }
        }
    }

    fun repostDetailPost(target: ScoredPost) {
        coroutineScope.launch {
            try {
                if (target.isReposted) {
                    val repostEventId = target.myRepostEventId ?: return@launch
                    if (repository.deleteEvent(repostEventId)) {
                        updatePostState(target.event.id) {
                            it.copy(isReposted = false, repostCount = maxOf(0, it.repostCount - 1), myRepostEventId = null)
                        }
                    }
                    return@launch
                }
                val eventJson = try {
                    kotlinx.serialization.json.Json { encodeDefaults = true }.encodeToString(
                        io.nurunuru.app.data.models.NostrEvent.serializer(), target.event
                    )
                } catch (_: Exception) { null }
                val newEventId = repository.repostPost(target.event.id, eventJson)
                if (newEventId != null) {
                    updatePostState(target.event.id) {
                        it.copy(isReposted = true, repostCount = it.repostCount + 1, myRepostEventId = newEventId)
                    }
                }
            } catch (_: Exception) { }
        }
    }

    LaunchedEffect(eventId) {
        isLoading = true
        val fetchedPost = repository.fetchEvent(eventId)
        if (fetchedPost != null) post = fetchedPost
        else if (post == null && initialPost?.event?.id == eventId) post = initialPost
        try {
            val replyFilter = NostrClient.Filter(
                kinds = listOf(NostrKind.TEXT_NOTE),
                tags = mapOf("e" to listOf(eventId)),
                limit = 50
            )
            val replyRelays = (post?.event?.pubkey?.let { repository.fetchNip65ReadRelays(it) }.orEmpty() +
                repository.fetchNip65WriteRelays(myPubkey) +
                repository.getSavedRelayUrls()).distinct()
            android.util.Log.d("PostDetailScreen", "PostDetail reply fetch relays=" + replyRelays.size + " event=" + eventId.take(8))
            val replyEvents = if (replyRelays.isNotEmpty()) {
                repository.fetchEventsFromRelays(replyRelays, replyFilter, timeoutMs = 7_000)
            } else {
                repository.fetchEvents(replyFilter, timeoutMs = 5_000)
            }
            android.util.Log.d("PostDetailScreen", "PostDetail reply events=" + replyEvents.size + " event=" + eventId.take(8))
            val enriched = repository.enrichPostsDirect(replyEvents.distinctBy { it.id })
            replies = enriched
                .filter { it.event.id != eventId }
                .sortedBy { it.event.createdAt }
        } catch (_: Exception) {}
        isLoading = false
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        floatingActionButton = {
            if (post != null) {
                Surface(
                    color = LineGreen,
                    contentColor = Color.White,
                    shape = RoundedCornerShape(28.dp),
                    shadowElevation = 8.dp,
                    modifier = Modifier
                        .navigationBarsPadding()
                        .padding(end = 4.dp, bottom = 8.dp)
                        .height(56.dp)
                        .clickable { showReplyModal = true }
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 20.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Outlined.ChatBubbleOutline, contentDescription = null, modifier = Modifier.size(22.dp))
                        Text("返信", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    }
                }
            }
        },
        containerColor = Color.Black
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(Color.Black)
        ) {
            when {
                isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = LineGreen) }
                post == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("投稿が見つかりませんでした", color = nuruColors.textSecondary) }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(top = 104.dp, bottom = 112.dp)
                    ) {
                        item(key = "${post!!.event.id}") {
                            PostItem(
                                post = post!!,
                                onLike = { emoji, tags -> likeDetailPost(post!!, emoji, tags) },
                                onRepost = { repostDetailPost(post!!) },
                                onProfileClick = onProfileClick,
                                repository = repository,
                                onBookmark = { coroutineScope.launch { repository.addBookmark(myPubkey, post!!.event.id) } },
                                myPubkey = myPubkey
                            )
                        }

                        if (replies.isNotEmpty()) {
                            item(key = "replies_header") { HorizontalDivider(color = nuruColors.border, thickness = 0.5.dp) }
                            items(replies, key = { it.event.id }) { reply ->
                                PostItem(
                                    post = reply,
                                    onLike = { emoji, tags -> likeDetailPost(reply, emoji, tags) },
                                    onRepost = { repostDetailPost(reply) },
                                    onProfileClick = onProfileClick,
                                    repository = repository,
                                    onBookmark = { coroutineScope.launch { repository.addBookmark(myPubkey, reply.event.id) } },
                                    myPubkey = myPubkey
                                )
                            }
                        } else {
                            item(key = "empty_replies") {
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = 64.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(14.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Outlined.Forum,
                                        contentDescription = null,
                                        tint = nuruColors.textTertiary,
                                        modifier = Modifier.size(58.dp)
                                    )
                                    Text("まだリプライはありません", color = nuruColors.textTertiary, fontSize = 15.sp)
                                }
                            }
                        }
                    }
                }
            }

            Surface(
                color = nuruColors.bgSecondary.copy(alpha = 0.95f),
                shape = RoundedCornerShape(18.dp),
                modifier = Modifier
                    .statusBarsPadding()
                    .padding(start = 20.dp, top = 12.dp)
                    .height(40.dp)
                    .clickable(onClick = onBack)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = nuruColors.textPrimary, modifier = Modifier.size(18.dp))
                    Text("閉じる", color = nuruColors.textPrimary, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
            }
        }
    }


    if (showReplyModal && post != null) {
        PostModal(
            myPubkey = myPubkey,
            pictureUrl = null,
            displayName = "",
            repository = repository,
            replyToId = post!!.event.id,
            replyToPubkey = post!!.event.pubkey,
            onDismiss = { showReplyModal = false },
            onSuccess = {
                showReplyModal = false
                coroutineScope.launch {
                    val replyFilter = NostrClient.Filter(
                        kinds = listOf(NostrKind.TEXT_NOTE),
                        tags = mapOf("e" to listOf(eventId)),
                        limit = 50
                    )
                    replies = repository.enrichPostsDirect(repository.fetchEvents(replyFilter, timeoutMs = 5_000))
                        .filter { it.event.id != eventId }
                        .sortedBy { it.event.createdAt }
                }
            }
        )
    }

}
