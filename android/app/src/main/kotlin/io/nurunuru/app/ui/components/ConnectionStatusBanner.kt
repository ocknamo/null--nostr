package io.nurunuru.app.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.nurunuru.app.ui.icons.NuruIcons
import io.nurunuru.app.viewmodel.ConnectionViewModel

/**
 * Top connection status banner shown only while offline / not fully connected.
 * Mirrors iOS MainTabView.ConnectionStatusBanner.
 */
@Composable
fun ConnectionStatusBanner(
    viewModel: ConnectionViewModel,
    modifier: Modifier = Modifier
) {
    val state by viewModel.uiState.collectAsState()

    AnimatedVisibility(
        visible = !state.isFullyConnected,
        enter = fadeIn(),
        exit = fadeOut(),
        modifier = modifier
    ) {
        val bannerColor = if (state.isOnline) Color(0xFFCC6600) else Color(0xFFB31A1A)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(bannerColor)
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(
                imageVector = NuruIcons.Warning,
                contentDescription = null,
                tint = Color.White
            )
            Text(
                text = state.statusMessage,
                color = Color.White,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium
            )
            Spacer(Modifier.weight(1f))
            if (state.isOnline) {
                Text(
                    text = "再接続",
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color.White.copy(alpha = 0.2f))
                        .clickable { viewModel.refreshRelayHealth() }
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                )
            }
        }
    }
}
