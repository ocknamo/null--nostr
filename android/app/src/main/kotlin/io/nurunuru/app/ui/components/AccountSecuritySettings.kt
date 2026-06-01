package io.nurunuru.app.ui.components

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.view.WindowManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.nurunuru.app.data.NostrKeyUtils
import io.nurunuru.app.data.prefs.AppPreferences
import io.nurunuru.app.ui.icons.NuruIcons
import io.nurunuru.app.ui.theme.LineGreen
import io.nurunuru.app.ui.theme.LocalNuruColors
import io.nurunuru.app.viewmodel.AuthViewModel
import kotlinx.coroutines.launch

/**
 * Shared account card for the Home settings dialog.
 * PR #1 adds this component without changing current call sites.
 */
@Composable
fun AccountStatusCard(
    prefs: AppPreferences,
    pubkeyHex: String,
    onLogoutClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val nuruColors = LocalNuruColors.current
    val npub = remember(pubkeyHex) { NostrKeyUtils.encodeNpub(pubkeyHex) ?: pubkeyHex }

    Surface(
        color = nuruColors.bgSecondary,
        shape = RoundedCornerShape(16.dp),
        modifier = modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Surface(color = LineGreen, shape = CircleShape, modifier = Modifier.size(40.dp)) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(NuruIcons.Lock, null, tint = Color.White, modifier = Modifier.size(20.dp))
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    if (prefs.isExternalSigner) "外部署名でログイン中" else "ログイン中",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    npub.take(8) + "..." + npub.takeLast(8),
                    style = MaterialTheme.typography.bodySmall,
                    color = nuruColors.textTertiary
                )
            }
            Surface(
                color = Color.Red.copy(alpha = 0.1f),
                shape = CircleShape,
                modifier = Modifier.clickable { onLogoutClick() }
            ) {
                Text(
                    "ログアウト",
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    fontSize = 12.sp,
                    color = Color.Red,
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

/**
 * Shared internal-signer security settings for Home settings.
 * Kept behavior-compatible with the existing Mini Apps MiniAppsScreen section.
 */
@Composable
fun AccountSecuritySection(
    authViewModel: AuthViewModel,
    prefs: AppPreferences,
    modifier: Modifier = Modifier
) {
    val nuruColors = LocalNuruColors.current
    val context = LocalContext.current
    var isExpanded by remember { mutableStateOf(false) }
    var showNsec by remember { mutableStateOf(false) }
    var exportedNsec by remember { mutableStateOf<String?>(null) }
    var isExportingNsec by remember { mutableStateOf(false) }
    var autoSignEnabled by remember { mutableStateOf(prefs.autoSignEnabled) }
    val coroutineScope = rememberCoroutineScope()
    val activity = remember(context) { context.findActivity() }

    // PR #2 hardening: prevent screenshots/recents snapshots while nsec is visible.
    DisposableEffect(showNsec) {
        if (showNsec) activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onDispose {
            if (showNsec) activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    Surface(
        color = nuruColors.bgSecondary,
        shape = RoundedCornerShape(16.dp),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth().clickable { isExpanded = !isExpanded },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(Icons.Outlined.Lock, null, tint = nuruColors.textSecondary, modifier = Modifier.size(20.dp))
                Text("セキュリティ設定", modifier = Modifier.weight(1f), fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                Icon(
                    if (isExpanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                    null,
                    tint = nuruColors.textTertiary
                )
            }

            AnimatedVisibility(visible = isExpanded) {
                Column(modifier = Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Surface(color = nuruColors.bgTertiary, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
                        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text("自動署名", fontWeight = FontWeight.Medium, fontSize = 14.sp)
                                Text(if (autoSignEnabled) "投稿時に認証なし" else "毎回認証を要求", fontSize = 12.sp, color = nuruColors.textTertiary)
                            }
                            Switch(
                                checked = autoSignEnabled,
                                onCheckedChange = {
                                    autoSignEnabled = it
                                    prefs.autoSignEnabled = it
                                },
                                colors = SwitchDefaults.colors(checkedTrackColor = LineGreen)
                            )
                        }
                    }

                    Button(
                        onClick = {
                            if (showNsec) {
                                showNsec = false
                                exportedNsec = null
                            } else {
                                showNsec = true
                                isExportingNsec = true
                                coroutineScope.launch {
                                    val nsec = authViewModel.getNsecForCurrentAccount(activity)
                                    exportedNsec = nsec
                                    isExportingNsec = false
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = nuruColors.bgTertiary, contentColor = MaterialTheme.colorScheme.onSurface),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text(if (showNsec) "秘密鍵を隠す" else "秘密鍵を表示", fontSize = 14.sp)
                    }

                    if (showNsec) {
                        val nsec = if (isExportingNsec) "取得中…" else (exportedNsec ?: "取得できません")
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Surface(color = Color.Red.copy(alpha = 0.1f), shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
                                Column(modifier = Modifier.padding(12.dp)) {
                                    Text("⚠️ 警告: 秘密鍵の取り扱い", color = Color.Red, fontWeight = FontWeight.Bold, fontSize = 10.sp)
                                    Text(
                                        "この鍵はあなたの身元を証明する唯一の手段です。他人に教えたり、安全でない場所に保存したりしないでください。",
                                        color = Color.Red.copy(alpha = 0.8f),
                                        fontSize = 10.sp,
                                        lineHeight = 14.sp
                                    )
                                }
                            }
                            Surface(color = nuruColors.bgTertiary, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
                                Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(text = nsec, modifier = Modifier.weight(1f), fontSize = 12.sp, color = nuruColors.textPrimary)
                                    IconButton(onClick = {
                                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                        clipboard.setPrimaryClip(ClipData.newPlainText("nsec", nsec))
                                    }) {
                                        Icon(Icons.Outlined.ContentCopy, null, modifier = Modifier.size(16.dp), tint = nuruColors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}


private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
