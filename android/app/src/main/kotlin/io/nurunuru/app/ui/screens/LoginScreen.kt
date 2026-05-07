package io.nurunuru.app.ui.screens

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextAlign
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.nurunuru.app.R
import io.nurunuru.app.data.ExternalSigner
import io.nurunuru.app.ui.components.SignUpModal
import io.nurunuru.app.ui.theme.LineGreen
import io.nurunuru.app.ui.theme.LocalNuruColors
import io.nurunuru.app.viewmodel.AuthState
import io.nurunuru.app.viewmodel.AuthViewModel

@Composable
fun LoginScreen(
    viewModel: AuthViewModel
) {
    val authState by viewModel.authState.collectAsState()
    val nuruColors = LocalNuruColors.current

    var nsecInput by remember { mutableStateOf("") }
    var showKey by remember { mutableStateOf(false) }
    var showSignUp by remember { mutableStateOf(false) }
    var showNsecLogin by remember { mutableStateOf(false) }
    var showOtherMethods by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    var showTermsDialog by remember { mutableStateOf(false) }
    var pendingTermsAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    fun requireTerms(action: () -> Unit) {
        if (viewModel.prefs.hasAcceptedTerms) action() else {
            pendingTermsAction = action
            showTermsDialog = true
        }
    }

    val amberLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == android.app.Activity.RESULT_OK) {
            val data = result.data
            val pubkey = data?.getStringExtra("signature") ?: data?.getStringExtra("pubKey") ?: data?.getStringExtra("result")
            if (pubkey != null) {
                viewModel.loginWithAmber(pubkey)
            }
        }
    }

    val isLoading = authState is AuthState.Checking
    val errorMsg = (authState as? AuthState.Error)?.message

    // Match Web version's initial loading state
    if (isLoading && !showNsecLogin && !showSignUp) {
        Box(
            modifier = Modifier.fillMaxSize().background(nuruColors.bgPrimary),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                val infiniteTransition = rememberInfiniteTransition(label = "logo_pulse")
                val scale by infiniteTransition.animateFloat(
                    initialValue = 0.95f,
                    targetValue = 1.05f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(1000, easing = LinearEasing),
                        repeatMode = RepeatMode.Reverse
                    ),
                    label = "scale"
                )

                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .graphicsLayer(scaleX = scale, scaleY = scale)
                        .clip(RoundedCornerShape(20.dp))
                ) {
                    androidx.compose.foundation.Image(
                        painter = painterResource(id = R.drawable.logo),
                        contentDescription = null,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
                Text(
                    text = "読み込み中...",
                    color = nuruColors.textTertiary,
                    fontSize = 14.sp
                )
            }
        }
        return
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(nuruColors.bgPrimary),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(32.dp)
        ) {
            // Logo / title
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(112.dp)
                        .shadow(12.dp, RoundedCornerShape(32.dp))
                        .clip(RoundedCornerShape(32.dp))
                        .background(nuruColors.bgSecondary)
                ) {
                    androidx.compose.foundation.Image(
                        painter = painterResource(id = R.drawable.logo),
                        contentDescription = "ぬるぬる",
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop
                    )
                }

                Text(
                    text = "ぬるぬる",
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = nuruColors.textPrimary
                )
            }

            // Options
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (!showNsecLogin) {
                    // Sign Up Button
                    Button(
                        onClick = { requireTerms { showSignUp = true } },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(64.dp)
                            .shadow(8.dp, RoundedCornerShape(20.dp), spotColor = LineGreen.copy(alpha = 0.1f)),
                        colors = ButtonDefaults.buttonColors(containerColor = LineGreen),
                        shape = RoundedCornerShape(20.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(
                                imageVector = Icons.Default.PersonAdd,
                                contentDescription = null,
                                modifier = Modifier.size(24.dp)
                            )
                            Text("新規登録", fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        }
                    }

                    // Login Button (Combined)
                    Button(
                        onClick = { requireTerms { showNsecLogin = true } },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = nuruColors.bgSecondary),
                        shape = RoundedCornerShape(20.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(
                                imageVector = Icons.Default.Login,
                                contentDescription = null,
                                modifier = Modifier.size(20.dp),
                                tint = nuruColors.textPrimary
                            )
                            Text("ログイン", fontSize = 16.sp, color = nuruColors.textPrimary)
                        }
                    }
                } else {
                    // Login options: nsec (primary) and others (collapsible)
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        // 1. Primary: Secret Key (nsec)
                        OutlinedTextField(
                            value = nsecInput,
                            onValueChange = {
                                nsecInput = it
                                if (errorMsg != null) viewModel.clearError()
                            },
                            label = { Text("秘密鍵 (nsec1...)") },
                            placeholder = { Text("nsec1...") },
                            visualTransformation = if (showKey) VisualTransformation.None else PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Password,
                                imeAction = ImeAction.Done
                            ),
                            trailingIcon = {
                                IconButton(onClick = { showKey = !showKey }) {
                                    Icon(
                                        imageVector = if (showKey) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                        contentDescription = if (showKey) "隠す" else "表示",
                                        tint = nuruColors.textTertiary
                                    )
                                }
                            },
                            isError = errorMsg != null,
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = LineGreen,
                                focusedLabelColor = LineGreen,
                                cursorColor = LineGreen,
                                unfocusedBorderColor = nuruColors.bgTertiary
                            ),
                            shape = RoundedCornerShape(16.dp)
                        )

                        AnimatedVisibility(visible = errorMsg != null) {
                            Text(
                                text = errorMsg ?: "",
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(start = 8.dp)
                            )
                        }

                        Button(
                            onClick = { requireTerms { viewModel.login(nsecInput) } },
                            enabled = nsecInput.isNotBlank() && !isLoading,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(56.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = LineGreen,
                                disabledContainerColor = LineGreen.copy(alpha = 0.3f)
                            ),
                            shape = RoundedCornerShape(20.dp)
                        ) {
                            if (isLoading) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    color = Color.White,
                                    strokeWidth = 2.dp
                                )
                            } else {
                                Text("ログイン", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                            }
                        }

                        // 2. Collapsible: Other Login Methods
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            TextButton(
                                onClick = { showOtherMethods = !showOtherMethods },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Text(
                                        "その他のログイン方法",
                                        color = nuruColors.textTertiary,
                                        fontSize = 14.sp
                                    )
                                    Icon(
                                        imageVector = if (showOtherMethods) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                                        contentDescription = null,
                                        tint = nuruColors.textTertiary,
                                        modifier = Modifier.size(20.dp)
                                    )
                                }
                            }

                            AnimatedVisibility(
                                visible = showOtherMethods,
                                enter = expandVertically() + fadeIn(),
                                exit = shrinkVertically() + fadeOut()
                            ) {
                                Column(
                                    modifier = Modifier.padding(top = 8.dp),
                                    verticalArrangement = Arrangement.spacedBy(16.dp)
                                ) {
                                    /*
                                    // Passkey Login Button (Commented out as it's buggy)
                                    Button(
                                        onClick = { viewModel.loginWithPasskey(context) },
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(56.dp),
                                        colors = ButtonDefaults.buttonColors(containerColor = LineGreen.copy(alpha = 0.1f)),
                                        border = androidx.compose.foundation.BorderStroke(1.dp, LineGreen),
                                        shape = RoundedCornerShape(16.dp)
                                    ) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                            Icon(
                                                imageVector = Icons.Default.Fingerprint,
                                                contentDescription = null,
                                                modifier = Modifier.size(20.dp),
                                                tint = LineGreen
                                            )
                                            Text("パスキーでログイン", fontSize = 16.sp, color = LineGreen, fontWeight = FontWeight.Bold)
                                        }
                                    }
                                    */

                                    // External Signer Button (NIP-55)
                                    Button(
                                        onClick = {
                                            requireTerms {
                                                try {
                                                    amberLauncher.launch(ExternalSigner.createGetPublicKeyIntent(context))
                                                } catch (e: Exception) {
                                                    android.widget.Toast.makeText(context, "外部署名アプリが見つかりません", android.widget.Toast.LENGTH_SHORT).show()
                                                }
                                            }
                                        },
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(56.dp),
                                        colors = ButtonDefaults.buttonColors(containerColor = nuruColors.bgSecondary),
                                        shape = RoundedCornerShape(16.dp)
                                    ) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                            Icon(
                                                imageVector = Icons.Default.AppShortcut,
                                                contentDescription = null,
                                                modifier = Modifier.size(20.dp),
                                                tint = nuruColors.textPrimary
                                            )
                                            Text("外部アプリでログイン (Amber等)", fontSize = 16.sp, color = nuruColors.textPrimary)
                                        }
                                    }
                                }
                            }
                        }

                        TextButton(
                            onClick = {
                                showNsecLogin = false
                                showOtherMethods = false
                            },
                            modifier = Modifier.align(Alignment.CenterHorizontally)
                        ) {
                            Text("キャンセル", color = nuruColors.textTertiary)
                        }
                    }
                }
            }

            // Footer
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "Powered by Nostr",
                    style = MaterialTheme.typography.bodySmall,
                    color = nuruColors.textTertiary
                )
                Text(
                    text = "秘密鍵はデバイス外に送信されません",
                    fontSize = 10.sp,
                    color = nuruColors.textTertiary.copy(alpha = 0.7f)
                )
            }
        }
    }

    if (showTermsDialog) {
        TermsAgreementScreen(
            onOpenTerms = { uriHandler.openUri("https://tami1A84.github.io/null--nostr/terms.html") },
            onAgree = {
                viewModel.prefs.hasAcceptedTerms = true
                showTermsDialog = false
                pendingTermsAction?.invoke()
                pendingTermsAction = null
            },
            onCancel = {
                showTermsDialog = false
                pendingTermsAction = null
            }
        )
    }

    if (showSignUp) {
        SignUpModal(
            viewModel = viewModel,
            onClose = { showSignUp = false },
            onSuccess = { pubkey ->
                showSignUp = false
                // Logged in via completeRegistration in Modal
            }
        )
    }
}

@Composable
private fun TermsAgreementScreen(
    onOpenTerms: () -> Unit,
    onAgree: () -> Unit,
    onCancel: () -> Unit
) {
    val nuruColors = LocalNuruColors.current

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = nuruColors.bgPrimary
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onCancel) {
                    Text(
                        text = "閉じる",
                        color = nuruColors.textSecondary,
                        fontSize = 14.sp
                    )
                }
                Text(
                    text = "利用規約",
                    modifier = Modifier.weight(1f),
                    color = nuruColors.textPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.width(64.dp))
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = "利用規約への同意",
                    color = nuruColors.textPrimary,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold
                )

                Text(
                    text = "ぬるぬるでは、ユーザー投稿コンテンツを安全に利用するため、以下の内容に同意してから開始してください。",
                    color = nuruColors.textSecondary,
                    fontSize = 14.sp,
                    lineHeight = 20.sp
                )

                TermsNoticeCard(
                    icon = Icons.Default.Security,
                    title = "ゼロトレランス方針",
                    bodyText = "不適切なコンテンツ、嫌がらせ、差別、脅迫、スパム、違法行為、迷惑ユーザーを一切許容しません。"
                )

                TermsNoticeCard(
                    icon = Icons.Default.Flag,
                    title = "通報機能",
                    bodyText = "不適切な投稿やプロフィール、迷惑行為を見つけた場合は、アプリ内の通報機能から報告できます。"
                )

                TermsNoticeCard(
                    icon = Icons.Default.PersonOff,
                    title = "ブロック機能",
                    bodyText = "迷惑なユーザーや表示したくないユーザーは、アプリ内のブロック機能でブロックできます。"
                )

                Surface(
                    onClick = onOpenTerms,
                    modifier = Modifier.fillMaxWidth(),
                    color = nuruColors.bgSecondary,
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Description,
                            contentDescription = null,
                            tint = LineGreen,
                            modifier = Modifier.size(20.dp)
                        )
                        Text(
                            text = "利用規約の全文を開く",
                            modifier = Modifier.weight(1f),
                            color = LineGreen,
                            fontSize = 14.sp
                        )
                        Icon(
                            imageVector = Icons.Default.OpenInNew,
                            contentDescription = null,
                            tint = LineGreen,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(nuruColors.bgPrimary)
                    .padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Button(
                    onClick = onAgree,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = LineGreen),
                    shape = RoundedCornerShape(24.dp)
                ) {
                    Text(
                        text = "利用規約に同意して開始",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }

                TextButton(onClick = onCancel) {
                    Text(
                        text = "同意しない",
                        color = nuruColors.textTertiary,
                        fontSize = 14.sp
                    )
                }
            }
        }
    }
}

@Composable
private fun TermsNoticeCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    bodyText: String
) {
    val nuruColors = LocalNuruColors.current

    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = nuruColors.bgSecondary,
        shape = RoundedCornerShape(16.dp)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = LineGreen,
                modifier = Modifier
                    .width(28.dp)
                    .size(20.dp)
            )

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = title,
                    color = nuruColors.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = bodyText,
                    color = nuruColors.textSecondary,
                    fontSize = 12.sp,
                    lineHeight = 16.sp
                )
            }
        }
    }
}
