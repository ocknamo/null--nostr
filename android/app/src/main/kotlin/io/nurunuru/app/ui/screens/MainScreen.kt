package io.nurunuru.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Alignment
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import io.nurunuru.app.NuruNuruApp
import io.nurunuru.app.data.NostrClient
import io.nurunuru.app.data.NostrRepository
import io.nurunuru.app.data.SecureKeyManager
import io.nurunuru.app.data.prefs.AppPreferences
import io.nurunuru.app.ui.components.ConnectionStatusBanner
import io.nurunuru.app.ui.theme.LineGreen
import io.nurunuru.app.ui.theme.LocalNuruColors
import io.nurunuru.app.viewmodel.*

enum class BottomTab(val label: String) {
    HOME("ホーム"),
    TALK("トーク"),
    TIMELINE("タイムライン"),
    MINIAPP("ミニアプリ")
}

@Composable
fun BottomTab.getIcon(isSelected: Boolean): ImageVector {
    return when (this) {
        BottomTab.HOME -> io.nurunuru.app.ui.icons.NuruIcons.Home(isSelected)
        BottomTab.TALK -> io.nurunuru.app.ui.icons.NuruIcons.Talk(isSelected)
        BottomTab.TIMELINE -> io.nurunuru.app.ui.icons.NuruIcons.Timeline(isSelected)
        BottomTab.MINIAPP -> io.nurunuru.app.ui.icons.NuruIcons.Grid(isSelected)
    }
}

@Composable
fun MainScreen(
    pubkeyHex: String,
    hasInternalKey: Boolean,
    keyManager: SecureKeyManager,
    authViewModel: AuthViewModel,
    app: NuruNuruApp
) {
    val context = LocalContext.current
    val nuruColors = LocalNuruColors.current
    var activeTab by remember { mutableStateOf(BottomTab.TIMELINE) }
    var isExternalAppOpen by remember { mutableStateOf(false) }
    var showAppSettings by remember { mutableStateOf(false) }
    var selectedNoteEventId by remember { mutableStateOf<String?>(null) }

    // Create shared NostrClient and Repository
    // NostrCache と RecommendationEngine は NuruNuruApp.onCreate() で事前生成済み。
    // remember { } は参照を保持するだけで SharedPreferences I/O は発生しない。
    val recommendationEngine = remember { app.recommendationEngine }
    val nostrClient = remember {
        if (!hasInternalKey && app.prewarmedNostrClient != null) {
            // Reuse the client pre-warmed in Application.onCreate() — relay
            // connections are already established by the time we get here.
            app.prewarmedNostrClient!!
        } else {
            val signer = if (hasInternalKey) {
                io.nurunuru.app.data.InternalSigner(keyManager)
            } else {
                io.nurunuru.app.data.ExternalSigner.apply {
                    setCurrentUser(pubkeyHex)
                }
            }
            NostrClient(
                context = context,
                relays = app.prefs.relays.toList(),
                signer = signer
            ).also { it.connect() }
        }
    }
    val nostrCache = remember { app.nostrCache }
    val repository = remember { NostrRepository(nostrClient, app.prefs, nostrCache, recommendationEngine) }

    // ViewModels
    val timelineVM: TimelineViewModel = viewModel(
        TimelineViewModel::class.java,
        factory = TimelineViewModel.Factory(repository, pubkeyHex)
    )
    val talkVM: TalkViewModel = viewModel(
        TalkViewModel::class.java,
        factory = TalkViewModel.Factory(repository, nostrClient, pubkeyHex)
    )
    val homeVM: HomeViewModel = viewModel(
        HomeViewModel::class.java,
        factory = HomeViewModel.Factory(repository, pubkeyHex)
    )
    val connectionVM: ConnectionViewModel = viewModel(
        ConnectionViewModel::class.java,
        factory = ConnectionViewModel.Factory(context.applicationContext, app.prefs.relays.toList())
    )

    // My profile for post modal avatar
    val homeState by homeVM.uiState.collectAsState()
    val myProfile = homeState.profile

    // ── バックグラウンドプリフェッチ ─────────────────────────────────────────
    // タイムライン表示中に他タブのデータをバックグラウンドで取得しておく。
    // talkVM.loadGroups() は TalkViewModel.init 内で既に呼ばれているため不要。
    LaunchedEffect(pubkeyHex) {
        launch { homeVM.loadMyProfile() }
    }

    // Disconnect on dispose
    DisposableEffect(nostrClient) {
        onDispose { nostrClient.disconnect() }
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            // Each screen should ideally handle its own top bar to manage internal state
            // but we need to coordinate insets.
            // We'll let child screens provide their top bars or keep them internal for now
            // but coordinate through MainScreen's contentWindowInsets.
        },
        bottomBar = {
            androidx.compose.animation.AnimatedVisibility(
                visible = !isExternalAppOpen,
                enter = androidx.compose.animation.fadeIn(androidx.compose.animation.core.tween(120)) +
                        androidx.compose.animation.slideInVertically(androidx.compose.animation.core.tween(120)) { it },
                exit  = androidx.compose.animation.fadeOut(androidx.compose.animation.core.tween(120)) +
                        androidx.compose.animation.slideOutVertically(androidx.compose.animation.core.tween(120)) { it }
            ) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = Color.Black,
                tonalElevation = 0.dp
            ) {
                Column(modifier = Modifier.navigationBarsPadding()) {
                    // Top border for the nav bar to match web style
                    androidx.compose.material3.HorizontalDivider(
                        color = io.nurunuru.app.ui.theme.BorderColor,
                        thickness = 0.5.dp
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        BottomTab.entries.forEach { tab ->
                            val isSelected = activeTab == tab
                            Column(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight()
                                    .clickable(
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null // No ripple for a cleaner look matching web
                                    ) {
                                        if (activeTab == tab) {
                                            when (tab) {
                                                BottomTab.TIMELINE -> timelineVM.refresh()
                                                BottomTab.TALK -> talkVM.loadGroups()
                                                BottomTab.HOME -> homeVM.refresh()
                                                BottomTab.MINIAPP -> {}
                                            }
                                        }
                                        activeTab = tab
                                    },
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center
                            ) {
                                Icon(
                                    imageVector = tab.getIcon(isSelected),
                                    contentDescription = tab.label,
                                    modifier = Modifier.size(24.dp),
                                    tint = if (isSelected) LineGreen else nuruColors.textTertiary
                                )
                                androidx.compose.foundation.layout.Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    text = tab.label,
                                    fontSize = 10.sp,
                                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                                    color = if (isSelected) LineGreen else nuruColors.textTertiary
                                )
                            }
                        }
                    }
                }
            }
            } // AnimatedVisibility
        },
        containerColor = Color.Black
    ) { paddingValues ->
        // 3タブ（HOME・TALK・TIMELINE）は常時コンポーズして状態（スクロール位置等）を保持する。
        // AnimatedVisibility は非表示時もコンポジションツリーに残るため ViewModel 状態が失われない。
        Box(modifier = Modifier.fillMaxSize().padding(paddingValues)) {
            ConnectionStatusBanner(
                viewModel = connectionVM,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .zIndex(10f)
            )


            // ── TIMELINE ──────────────────────────────────────────────────────
            androidx.compose.animation.AnimatedVisibility(
                visible = activeTab == BottomTab.TIMELINE,
                enter = androidx.compose.animation.fadeIn(androidx.compose.animation.core.tween(120)),
                exit  = androidx.compose.animation.fadeOut(androidx.compose.animation.core.tween(120)),
                modifier = Modifier.fillMaxSize()
            ) {
                TimelineScreen(
                    viewModel = timelineVM,
                    repository = repository,
                    prefs = app.prefs,
                    myPubkey = pubkeyHex,
                    myPictureUrl = myProfile?.picture,
                    myDisplayName = myProfile?.displayedName ?: "",
                    onStartDM = { partnerPubkey ->
                        talkVM.createDmConversation(partnerPubkey)
                        activeTab = BottomTab.TALK
                    },
                    onNoteClick = { eventId -> selectedNoteEventId = eventId }
                )
            }

            // ── HOME ──────────────────────────────────────────────────────────
            androidx.compose.animation.AnimatedVisibility(
                visible = activeTab == BottomTab.HOME,
                enter = androidx.compose.animation.fadeIn(androidx.compose.animation.core.tween(120)),
                exit  = androidx.compose.animation.fadeOut(androidx.compose.animation.core.tween(120)),
                modifier = Modifier.fillMaxSize()
            ) {
                HomeScreen(
                    viewModel = homeVM,
                    repository = repository,
                    onSettingsTap = { showAppSettings = true },
                    onStartDM = { partnerPubkey ->
                        talkVM.createDmConversation(partnerPubkey)
                        activeTab = BottomTab.TALK
                    },
                    onNoteClick = { eventId -> selectedNoteEventId = eventId }
                )
            }

            if (showAppSettings) {
                AppSettingsDialog(
                    onDismiss = { showAppSettings = false },
                    onLogout = {
                        showAppSettings = false
                        authViewModel.logout()
                    }
                )
            }

            // ── TALK ──────────────────────────────────────────────────────────
            androidx.compose.animation.AnimatedVisibility(
                visible = activeTab == BottomTab.TALK,
                enter = androidx.compose.animation.fadeIn(androidx.compose.animation.core.tween(120)),
                exit  = androidx.compose.animation.fadeOut(androidx.compose.animation.core.tween(120)),
                modifier = Modifier.fillMaxSize()
            ) {
                TalkScreen(viewModel = talkVM, myPubkeyHex = pubkeyHex, repository = repository)
            }

            // ── MINIAPP (Settings) — 軽量なため都度レンダリングで問題なし ────
            if (activeTab == BottomTab.MINIAPP) {
                SettingsScreen(
                    authViewModel = authViewModel,
                    repository = repository,
                    prefs = app.prefs,
                    pubkeyHex = pubkeyHex,
                    pictureUrl = myProfile?.picture,
                    onExternalAppOpenChanged = { isExternalAppOpen = it },
                    onMlsCacheCleared = { talkVM.clearStateAfterCacheClear() }
                )
            }

            // ── POST DETAIL ────────────────────────────────────────────────
            if (selectedNoteEventId != null) {
                PostDetailScreen(
                    eventId = selectedNoteEventId!!,
                    repository = repository,
                    myPubkey = pubkeyHex,
                    onBack = { selectedNoteEventId = null },
                    onProfileClick = { pubkey ->
                        selectedNoteEventId = null
                        homeVM.loadProfile(pubkey)
                        activeTab = BottomTab.HOME
                    }
                )
            }
        }
    }
}


@Composable
private fun AppSettingsDialog(
    onDismiss: () -> Unit,
    onLogout: () -> Unit
) {
    val uriHandler = LocalUriHandler.current
    val nuruColors = LocalNuruColors.current
    var showLogoutConfirm by remember { mutableStateOf(false) }
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = nuruColors.bgPrimary
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("設定", fontWeight = FontWeight.Bold, fontSize = 20.sp, modifier = Modifier.weight(1f))
                    IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, contentDescription = "閉じる") }
                }
                HorizontalDivider(color = nuruColors.border, thickness = 0.5.dp)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    AppSettingsRow(Icons.Default.PanTool, "プライバシーポリシー", "個人情報とデータの取り扱いを確認") { uriHandler.openUri("https://tami1A84.github.io/null--nostr/privacy.html") }
                    AppSettingsRow(Icons.Default.Description, "利用規約", "禁止事項、通報、ブロックについて確認") { uriHandler.openUri("https://tami1A84.github.io/null--nostr/terms.html") }
                    AppSettingsRow(Icons.Default.Logout, "ログアウト", "このデバイスから秘密鍵を削除します", Color.Red) { showLogoutConfirm = true }
                }
            }
        }
    }
    if (showLogoutConfirm) {
        AlertDialog(
            onDismissRequest = { showLogoutConfirm = false },
            title = { Text("ログアウト") },
            text = { Text("ログアウトします。秘密鍵はこのデバイスから削除されます。") },
            confirmButton = { TextButton(onClick = onLogout) { Text("ログアウト", color = Color.Red) } },
            dismissButton = { TextButton(onClick = { showLogoutConfirm = false }) { Text("キャンセル") } }
        )
    }
}

@Composable
private fun AppSettingsRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    titleColor: Color? = null,
    onClick: () -> Unit
) {
    val nuruColors = LocalNuruColors.current
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Surface(color = nuruColors.bgSecondary, shape = androidx.compose.foundation.shape.CircleShape, modifier = Modifier.size(40.dp)) {
            Box(contentAlignment = Alignment.Center) { Icon(icon, null, tint = titleColor ?: nuruColors.textSecondary) }
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold, color = titleColor ?: nuruColors.textPrimary)
            Text(subtitle, fontSize = 12.sp, color = nuruColors.textTertiary)
        }
        if (titleColor == null) Icon(Icons.Default.ChevronRight, null, tint = nuruColors.textTertiary)
    }
}
