package io.nurunuru.app.ui.miniapps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.nurunuru.app.data.NostrKeyUtils
import io.nurunuru.app.data.NostrRepository
import io.nurunuru.app.data.ScrollEvent
import io.nurunuru.app.data.addFavoriteScroll
import io.nurunuru.app.data.fetchFavoriteScrolls
import io.nurunuru.app.data.fetchScrolls
import io.nurunuru.app.data.removeFavoriteScroll
import io.nurunuru.app.data.models.UserProfile
import io.nurunuru.app.ui.components.UserAvatar
import io.nurunuru.app.ui.icons.NuruIcons
import io.nurunuru.app.ui.theme.LineGreen
import io.nurunuru.app.ui.theme.LocalNuruColors
import kotlinx.coroutines.launch

/** NIP-A5 Scrolls mini-app list and favorite manager. */
@Composable
fun ScrollsApp(repository: NostrRepository, pubkeyHex: String) {
    val nuruColors = LocalNuruColors.current
    val scope = rememberCoroutineScope()

    var scrolls by remember { mutableStateOf<List<ScrollEvent>>(emptyList()) }
    var favorites by remember { mutableStateOf<Set<String>>(emptySet()) }
    var profiles by remember { mutableStateOf<Map<String, UserProfile>>(emptyMap()) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var runningScroll by remember { mutableStateOf<ScrollEvent?>(null) }

    fun load() {
        scope.launch {
            isLoading = true
            errorMessage = null
            try {
                val fetchedScrolls = repository.fetchScrolls()
                val fetchedFavorites = repository.fetchFavoriteScrolls(pubkeyHex)
                val authorProfiles = repository.fetchProfiles(fetchedScrolls.map { it.pubkey }.distinct())
                scrolls = fetchedScrolls
                favorites = fetchedFavorites.toSet()
                profiles = authorProfiles
            } catch (e: Exception) {
                errorMessage = "スクロールの読み込みに失敗しました"
            } finally {
                isLoading = false
            }
        }
    }

    LaunchedEffect(Unit) { load() }

    if (runningScroll != null) {
        ScrollRunner(scroll = runningScroll!!, pubkeyHex = pubkeyHex, onBack = { runningScroll = null })
        return
    }

    Box(modifier = Modifier.fillMaxSize()) {
        when {
            isLoading -> {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center),
                    color = LineGreen
                )
            }
            scrolls.isEmpty() -> {
                EmptyScrollsState(
                    modifier = Modifier.align(Alignment.Center),
                    onRefresh = { load() }
                )
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    items(scrolls, key = { it.id }) { scroll ->
                        ScrollRow(
                            scroll = scroll,
                            profile = profiles[scroll.pubkey],
                            isFavorite = scroll.id in favorites,
                            onFavorite = {
                                val wasFavorite = scroll.id in favorites
                                favorites = if (wasFavorite) favorites - scroll.id else favorites + scroll.id
                                scope.launch {
                                    try {
                                        if (wasFavorite) repository.removeFavoriteScroll(pubkeyHex, scroll.id)
                                        else repository.addFavoriteScroll(pubkeyHex, scroll.id)
                                    } catch (e: Exception) {
                                        favorites = if (wasFavorite) favorites + scroll.id else favorites - scroll.id
                                        errorMessage = "お気に入りの更新に失敗しました"
                                    }
                                }
                            },
                            onRun = { runningScroll = scroll }
                        )
                    }
                }
            }
        }

        if (errorMessage != null) {
            Surface(
                modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp),
                color = nuruColors.bgSecondary,
                shape = RoundedCornerShape(12.dp)
            ) {
                Text(
                    text = errorMessage ?: "",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                    color = nuruColors.textPrimary,
                    fontSize = 13.sp
                )
            }
        }
    }
}

@Composable
private fun ScrollRow(
    scroll: ScrollEvent,
    profile: UserProfile?,
    isFavorite: Boolean,
    onFavorite: () -> Unit,
    onRun: () -> Unit
) {
    val nuruColors = LocalNuruColors.current
    Surface(
        color = nuruColors.bgSecondary,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            UserAvatar(
                pictureUrl = profile?.picture,
                displayName = profile?.displayedName ?: scroll.pubkey,
                size = 40.dp
            )

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = scroll.title,
                    color = nuruColors.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (scroll.description.isNotBlank()) {
                    Text(
                        text = scroll.description,
                        color = nuruColors.textSecondary,
                        fontSize = 12.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Text(
                    text = NostrKeyUtils.shortenPubkey(scroll.pubkey),
                    color = nuruColors.textTertiary,
                    fontSize = 10.sp
                )
                if (scroll.params.isNotEmpty()) {
                    Text(
                        text = "params: ${scroll.params.joinToString { it.name }}",
                        color = nuruColors.textTertiary,
                        fontSize = 10.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                IconButton(onClick = onFavorite) {
                    Icon(
                        imageVector = NuruIcons.Star(isFavorite),
                        contentDescription = if (isFavorite) "お気に入り解除" else "お気に入り",
                        tint = if (isFavorite) LineGreen else nuruColors.textTertiary
                    )
                }
                IconButton(onClick = onRun) {
                    Icon(
                        imageVector = Icons.Default.PlayArrow,
                        contentDescription = "実行",
                        tint = LineGreen
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyScrollsState(modifier: Modifier = Modifier, onRefresh: () -> Unit) {
    val nuruColors = LocalNuruColors.current
    Column(
        modifier = modifier.padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = NuruIcons.Backup,
            contentDescription = null,
            tint = nuruColors.textTertiary,
            modifier = Modifier.size(48.dp)
        )
        Text("スクロールがありません", color = nuruColors.textTertiary, fontSize = 14.sp)
        Text(
            "Kind 1227 のスクロールが\nリレーに見つかりませんでした",
            color = nuruColors.textTertiary,
            fontSize = 12.sp,
            textAlign = TextAlign.Center
        )
        TextButton(onClick = onRefresh) {
            Icon(Icons.Outlined.Refresh, contentDescription = null, tint = LineGreen)
            Spacer(Modifier.width(6.dp))
            Text("再読み込み", color = LineGreen)
        }
    }
}
