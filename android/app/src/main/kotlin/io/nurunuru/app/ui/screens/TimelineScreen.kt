package io.nurunuru.app.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshContainer
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import io.nurunuru.app.data.prefs.AppPreferences
import io.nurunuru.app.data.models.ScoredPost
import io.nurunuru.app.ui.components.*
import io.nurunuru.app.ui.theme.LineGreen
import io.nurunuru.app.ui.theme.LocalNuruColors
import io.nurunuru.app.viewmodel.FeedType
import io.nurunuru.app.viewmodel.TimelineViewModel
import kotlinx.coroutines.launch
import androidx.compose.foundation.ExperimentalFoundationApi

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun TimelineScreen(
    viewModel: TimelineViewModel,
    repository: io.nurunuru.app.data.NostrRepository,
    prefs: AppPreferences,
    myPubkey: String,
    myPictureUrl: String?,
    myDisplayName: String,
    onStartDM: (String) -> Unit = {},
    onNoteClick: ((String, ScoredPost?) -> Unit)? = null
) {
    val uiState by viewModel.uiState.collectAsState()
    val nuruColors = LocalNuruColors.current

    var showPostModal by remember { mutableStateOf(false) }
    var showSearchModal by remember { mutableStateOf(false) }
    var showNotificationsModal by remember { mutableStateOf(false) }
    var viewingPubkey by remember { mutableStateOf<String?>(null) }

    // ADR-0013: relay-wide feed is removed from primary UI.
    val pagerState = rememberPagerState(
        initialPage = 0
    ) { 1 }

    LaunchedEffect(pagerState.currentPage) {
        if (uiState.feedType != FeedType.FOLLOWING) {
            viewModel.switchFeed(FeedType.FOLLOWING)
        }
    }

    LaunchedEffect(uiState.feedType) {
        if (uiState.feedType != FeedType.FOLLOWING) {
            viewModel.switchFeed(FeedType.FOLLOWING)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            topBar = {
                TimelineHeader(
                    feedType = FeedType.FOLLOWING,
                    onFeedTypeChange = { viewModel.switchFeed(FeedType.FOLLOWING) },
                    showRecommendedDot = false,
                    showFollowingDot = uiState.hasNewFollowing || uiState.pendingFollowingPosts.isNotEmpty(),
                    showNotificationsDot = uiState.hasNewNotifications,
                    onSearchClick = { showSearchModal = true },
                    onNotificationsClick = { viewModel.markNotificationsSeen(); showNotificationsModal = true },
                    savedRelayUrls = emptyList(),
                    selectedRelayUrl = null,
                    onSelectRelay = { }
                )
            },
            floatingActionButton = {
                FloatingActionButton(
                    onClick = { showPostModal = true },
                    containerColor = LineGreen,
                    contentColor = Color.White,
                    shape = CircleShape
                ) {
                    Icon(Icons.Default.Add, contentDescription = "投稿する")
                }
            },
            containerColor = nuruColors.bgPrimary
        ) { padding ->
            HorizontalPager(
                state = pagerState,
                beyondBoundsPageCount = 1,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                verticalAlignment = Alignment.Top
            ) { page ->
                TimelineContent(
                    viewModel = viewModel,
                    repository = repository,
                    feedType = FeedType.FOLLOWING,
                    onProfileClick = { viewingPubkey = it },
                    onHashtagClick = { tag ->
                        val q = if (tag.startsWith("#")) tag else "#$tag"
                        viewModel.search(q)
                        showSearchModal = true
                    },
                    myPubkey = myPubkey,
                    onReplyLongPress = { eventId -> onNoteClick?.invoke(eventId, null) },
                    onNoteClick = onNoteClick
                )
            }
        }

        if (showPostModal) {
            PostModal(
                myPubkey = myPubkey,
                pictureUrl = myPictureUrl,
                displayName = myDisplayName,
                repository = repository,
                onDismiss = { showPostModal = false },
                onSuccess = {
                    showPostModal = false
                    viewModel.refresh()
                }
            )
        }
    }

    if (viewingPubkey != null) {
        val homeViewModel: io.nurunuru.app.viewmodel.HomeViewModel = androidx.lifecycle.viewmodel.compose.viewModel(
            key = "profile_$viewingPubkey",
            factory = io.nurunuru.app.viewmodel.HomeViewModel.Factory(repository, myPubkey)
        )
        UserProfileModal(
            pubkey = viewingPubkey!!,
            viewModel = homeViewModel,
            repository = repository,
            onDismiss = { viewingPubkey = null },
            onStartDM = { pk -> viewingPubkey = null; onStartDM(pk) },
            onNoteClick = { eventId, post ->
                viewingPubkey = null
                onNoteClick?.invoke(eventId, post)
            }
        )
    }

    if (showSearchModal) {
        SearchModal(
            viewModel = viewModel,
            repository = repository,
            onClose = { showSearchModal = false; viewModel.clearSearch() },
            onProfileClick = { viewingPubkey = it },
            myPubkey = myPubkey
        )
    }

    if (showNotificationsModal) {
        NotificationModal(
            repository = repository,
            prefs = prefs,
            myPubkey = myPubkey,
            onClose = { showNotificationsModal = false },
            onProfileClick = { viewingPubkey = it },
            onNoteClick = { eventId, post -> showNotificationsModal = false; onNoteClick?.invoke(eventId, post) }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimelineContent(
    viewModel: TimelineViewModel,
    repository: io.nurunuru.app.data.NostrRepository,
    feedType: FeedType,
    onProfileClick: (String) -> Unit,
    onHashtagClick: (String) -> Unit,
    myPubkey: String,
    onReplyLongPress: (String) -> Unit = {},
    onNoteClick: ((String, ScoredPost?) -> Unit)? = null
) {
    val uiState by viewModel.uiState.collectAsState()
    val nuruColors = LocalNuruColors.current
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()

    val pullRefreshState = rememberPullToRefreshState()
    if (pullRefreshState.isRefreshing) {
        LaunchedEffect(Unit) {
            val selectedRelay = uiState.selectedRelayUrl
            if (feedType == FeedType.GLOBAL && selectedRelay != null) {
                viewModel.selectRelayFeed(selectedRelay)
            } else {
                viewModel.refresh()
            }
        }
    }
    val isRefreshing = if (feedType == FeedType.GLOBAL) uiState.isGlobalRefreshing else uiState.isFollowingRefreshing
    LaunchedEffect(isRefreshing) {
        if (!isRefreshing) pullRefreshState.endRefresh()
    }

    // 絵文字キャッシュ事前ロード（リアクション長押し時に即表示するため）
    LaunchedEffect(myPubkey) {
        if (myPubkey.isNotEmpty()) {
            fetchAndCacheEmojis(myPubkey, repository)
        }
    }

    val isRelaySelected = feedType == FeedType.GLOBAL && uiState.selectedRelayUrl != null

    // distinctBy は ViewModel 側で保証済みだが、非同期 state 更新の
    // フレーム境界で重複が紛れ込んだ場合の最終防衛として残す。
    val displayPosts = when {
        isRelaySelected -> uiState.relayPosts
        feedType == FeedType.GLOBAL -> uiState.globalPosts
        else -> uiState.followingPosts
    }.distinctBy { it.event.id }
    val pendingPosts = when {
        isRelaySelected -> uiState.pendingRelayPosts
        feedType == FeedType.GLOBAL -> uiState.pendingGlobalPosts
        else -> uiState.pendingFollowingPosts
    }
    val isLoading = when {
        isRelaySelected -> uiState.isRelayFeedLoading
        feedType == FeedType.GLOBAL -> uiState.isGlobalLoading
        else -> uiState.isFollowingLoading
    }
    val isLoadingMore = when {
        isRelaySelected -> uiState.isGlobalLoadingMore
        feedType == FeedType.GLOBAL -> uiState.isGlobalLoadingMore
        else -> uiState.isFollowingLoadingMore
    }
    val hasMore = when {
        isRelaySelected -> uiState.hasMoreRelay
        feedType == FeedType.GLOBAL -> uiState.hasMoreGlobal
        else -> uiState.hasMoreFollowing
    }
    val shouldLoadMore by remember(displayPosts.size, isLoadingMore, hasMore, isRelaySelected) {
        derivedStateOf {
            if (displayPosts.isEmpty() || isLoadingMore || !hasMore) false
            else {
                val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
                lastVisible >= displayPosts.size - 20
            }
        }
    }
    LaunchedEffect(shouldLoadMore, feedType, displayPosts.size) {
        if (shouldLoadMore) viewModel.loadMore(feedType)
    }
    val error = if (!isRelaySelected && feedType == FeedType.GLOBAL) uiState.globalError
                else if (!isRelaySelected) uiState.followingError
                else null

    Box(
        modifier = Modifier
            .fillMaxSize()
            .nestedScroll(pullRefreshState.nestedScrollConnection)
            .background(nuruColors.bgPrimary)
    ) {
        when {
            isLoading && displayPosts.isEmpty() -> {
                TimelineLoadingSkeleton()
            }
            error != null && displayPosts.isEmpty() -> {
                TimelineErrorState(onRetry = {
                    if (feedType == FeedType.GLOBAL) viewModel.loadGlobalTimeline()
                    else viewModel.loadFollowingTimeline()
                })
            }
            displayPosts.isEmpty() && !isLoading -> {
                TimelineEmptyState(
                    feedType = feedType,
                    isFollowListEmpty = uiState.followList.isEmpty()
                )
            }
            else -> {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(top = 4.dp)
                ) {
                    items(displayPosts, key = { it.event.id }) { post ->
                        val notInterestedCallback = if (feedType == FeedType.GLOBAL && !isRelaySelected) {
                            { viewModel.setNotInterested(post.event.id) }
                        } else null

                        if (post.event.kind == 30023) {
                            LongFormPostItem(
                                post = post,
                                onLike = { emoji, tags -> viewModel.likePost(post.event.id, emoji, tags) },
                                onRepost = { viewModel.repostPost(post.event.id) },
                                onProfileClick = onProfileClick,
                                repository = repository,
                                onDelete = if (post.event.pubkey == myPubkey) { { viewModel.deletePost(post.event.id) } } else null,
                                onMute = { viewModel.muteUser(post.event.pubkey) },
                                onReport = { type, content -> viewModel.reportEvent(post.event.id, post.event.pubkey, type, content) },
                                onBirdwatch = { type, content, url -> viewModel.submitBirdwatch(post.event.id, post.event.pubkey, type, content, url) },
                                onNotInterested = notInterestedCallback,
                                birdwatchNotes = uiState.birdwatchNotes[post.event.id] ?: emptyList(),
                                isOwnPost = post.event.pubkey == myPubkey,
                                onHashtagClick = onHashtagClick,
                                onReplyMultiTap = { onNoteClick?.invoke(post.event.id, post) ?: onReplyLongPress(post.event.id) }
                            )
                        } else {
                            PostItem(
                                post = post,
                                onLike = { emoji, tags -> viewModel.likePost(post.event.id, emoji, tags) },
                                onRepost = { viewModel.repostPost(post.event.id) },
                                onProfileClick = onProfileClick,
                                repository = repository,
                                onDelete = if (post.event.pubkey == myPubkey) { { viewModel.deletePost(post.event.id) } } else null,
                                onMute = { viewModel.muteUser(post.event.pubkey) },
                                onReport = { type, content -> viewModel.reportEvent(post.event.id, post.event.pubkey, type, content) },
                                onBirdwatch = { type, content, url -> viewModel.submitBirdwatch(post.event.id, post.event.pubkey, type, content, url) },
                                onNotInterested = notInterestedCallback,
                                onBookmark = { viewModel.toggleBookmark(post.event.id, post.isBookmarked) },
                                birdwatchNotes = uiState.birdwatchNotes[post.event.id] ?: emptyList(),
                                isOwnPost = post.event.pubkey == myPubkey,
                                onHashtagClick = onHashtagClick,
                                onNoteClick = { id -> onNoteClick?.invoke(id, null) },
                                onReplyMultiTap = { onNoteClick?.invoke(post.event.id, post) ?: onReplyLongPress(post.event.id) },
                                myPubkey = myPubkey
                            )
                        }
                    }
                    if (isLoadingMore) {
                        item(key = "loading-more-${feedType.name}") {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 20.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator(color = LineGreen, strokeWidth = 2.dp)
                            }
                        }
                    }
                }
            }
        }

        PullToRefreshContainer(
            state = pullRefreshState,
            modifier = Modifier.align(Alignment.TopCenter),
            containerColor = if (pullRefreshState.isRefreshing || pullRefreshState.progress > 0f) MaterialTheme.colorScheme.surface else Color.Transparent,
            contentColor = LineGreen
        )

        // 新着投稿ピル通知
        AnimatedVisibility(
            visible = pendingPosts.isNotEmpty(),
            enter = fadeIn() + slideInVertically { -it },
            exit = fadeOut() + slideOutVertically { -it },
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 8.dp)
        ) {
            NewPostsPill(
                pendingPosts = pendingPosts,
                onClick = {
                    viewModel.flushPendingPosts(feedType)
                    coroutineScope.launch { listState.scrollToItem(0) }
                }
            )
        }
    }
}
