package io.nurunuru.app.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.nurunuru.app.data.models.ScoredPost
import io.nurunuru.app.ui.icons.NuruIcons
import io.nurunuru.app.ui.theme.LocalNuruColors
import kotlinx.coroutines.launch

@Composable
fun PostActions(
    post: ScoredPost,
    onLike: () -> Unit,
    onLikeLongPress: () -> Unit = {},
    onRepost: () -> Unit,
    onQuoteRepost: (() -> Unit)? = null,
    onZap: () -> Unit,
    onZapLongPress: () -> Unit = {},
    onBookmark: (() -> Unit)? = null
) {
    val nuruColors = LocalNuruColors.current
    val scope = rememberCoroutineScope()
    var likeInFlight by remember(post.event.id) { mutableStateOf(false) }
    var repostInFlight by remember(post.event.id) { mutableStateOf(false) }
    var bookmarkInFlight by remember(post.event.id) { mutableStateOf(false) }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(24.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Like
        ActionButton(
            icon = NuruIcons.Like(post.isLiked),
            count = post.likeCount,
            onClick = {
                if (likeInFlight) return@ActionButton
                likeInFlight = true
                scope.launch {
                    try { onLike() } finally { likeInFlight = false }
                }
            },
            enabled = !likeInFlight,
            onLongClick = onLikeLongPress,
            tint = if (post.isLiked) nuruColors.lineGreen else nuruColors.textTertiary,
            animate = post.isLiked
        )
        // Repost (長押しで引用RT)
        ActionButton(
            icon = NuruIcons.Repost,
            count = post.repostCount,
            onClick = {
                if (repostInFlight) return@ActionButton
                repostInFlight = true
                scope.launch {
                    try { onRepost() } finally { repostInFlight = false }
                }
            },
            enabled = !repostInFlight,
            onLongClick = onQuoteRepost,
            tint = if (post.isReposted) nuruColors.lineGreen else nuruColors.textTertiary,
            animate = post.isReposted
        )
        // Zap (Bitcoin icon)
        ActionButton(
            icon = NuruIcons.Bitcoin,
            count = (post.zapAmount / 1000).toInt(),
            onClick = onZap,
            onLongClick = onZapLongPress,
            tint = nuruColors.textTertiary,
            animate = false
        )
        // Bookmark
        if (onBookmark != null) {
            ActionButton(
                icon = NuruIcons.Bookmark(post.isBookmarked),
                count = 0,
                onClick = {
                    if (bookmarkInFlight) return@ActionButton
                    bookmarkInFlight = true
                    scope.launch {
                        try { onBookmark() } finally { bookmarkInFlight = false }
                    }
                },
                enabled = !bookmarkInFlight,
                tint = if (post.isBookmarked) nuruColors.lineGreen else nuruColors.textTertiary,
                animate = post.isBookmarked
            )
        }

        // Client tag (via)
        val client = post.event.getTagValue("client")
        if (client != null) {
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = if (client.startsWith("via ")) client else "via $client",
                style = MaterialTheme.typography.labelSmall,
                color = nuruColors.textTertiary.copy(alpha = 0.6f),
                fontSize = 10.sp
            )
        } else {
            Spacer(modifier = Modifier.weight(1f))
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ActionButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    count: Int,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    tint: Color,
    animate: Boolean = false
) {
    val scale = remember { Animatable(1f) }

    LaunchedEffect(animate) {
        if (animate) {
            scale.animateTo(
                targetValue = 1.3f,
                animationSpec = tween(durationMillis = 150, easing = FastOutSlowInEasing)
            )
            scale.animateTo(
                targetValue = 1f,
                animationSpec = tween(durationMillis = 150, easing = FastOutSlowInEasing)
            )
        }
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .alpha(if (enabled) 1f else 0.45f)
            .combinedClickable(
                enabled = enabled,
                onClick = onClick,
                onLongClick = onLongClick
            )
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier
                .size(20.dp)
                .graphicsLayer {
                    scaleX = scale.value
                    scaleY = scale.value
                }
        )
        if (count > 0) {
            Text(
                text = formatCount(count),
                style = MaterialTheme.typography.bodySmall,
                color = tint
            )
        }
    }
}

private fun formatCount(count: Int): String = when {
    count >= 1000 -> "${count / 1000}K"
    else -> count.toString()
}
