package io.nurunuru.app.ui.components

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeWriter
import io.nurunuru.app.data.NostrKeyUtils
import io.nurunuru.app.ui.theme.LineGreen
import java.util.concurrent.Executors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QRModal(
    pubkeyHex: String,
    onDismiss: () -> Unit,
    onScannedPubkey: ((String) -> Unit)? = null
) {
    val context = LocalContext.current
    val npub = remember(pubkeyHex) { NostrKeyUtils.encodeNpub(pubkeyHex) ?: pubkeyHex }
    val qrBitmap = remember(npub) { generateQRBitmap("nostr:$npub", 512) }
    var mode by remember { mutableStateOf("表示") }
    var showScanner by remember { mutableStateOf(false) }
    var scanError by remember { mutableStateOf<String?>(null) }
    var hasCameraPermission by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasCameraPermission = granted
        if (granted) showScanner = true else scanError = "カメラ権限が必要です"
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = Color.Black
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .height(56.dp)
                ) {
                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier.align(Alignment.CenterStart).padding(start = 12.dp)
                    ) {
                        Icon(Icons.Default.Close, contentDescription = "閉じる", tint = Color.White)
                    }
                    Text(
                        "QRコード",
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp,
                        color = Color.White,
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                HorizontalDivider(color = Color(0xFF1F1F22), thickness = 0.5.dp)

                SingleChoiceSegmentedButtonRow(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 26.dp, vertical = 10.dp)
                ) {
                    listOf("表示", "スキャン").forEachIndexed { index, label ->
                        SegmentedButton(
                            selected = mode == label,
                            onClick = {
                                mode = label
                                if (label == "スキャン" && onScannedPubkey != null) {
                                    scanError = null
                                    if (hasCameraPermission) showScanner = true else permissionLauncher.launch(Manifest.permission.CAMERA)
                                }
                            },
                            shape = SegmentedButtonDefaults.itemShape(index = index, count = 2),
                            colors = SegmentedButtonDefaults.colors(
                                activeContainerColor = Color(0xFF6F6F76),
                                activeContentColor = Color.White,
                                inactiveContainerColor = Color(0xFF1F1F22),
                                inactiveContentColor = Color.White
                            )
                        ) { Text(label, fontSize = 14.sp) }
                    }
                }

                Spacer(Modifier.weight(1f))

                if (mode == "表示") {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(20.dp)
                    ) {
                        if (qrBitmap != null) {
                            Box(
                                modifier = Modifier
                                    .size(264.dp)
                                    .background(Color.White, RoundedCornerShape(12.dp))
                                    .padding(12.dp)
                            ) {
                                Image(
                                    bitmap = qrBitmap.asImageBitmap(),
                                    contentDescription = "QR Code",
                                    modifier = Modifier.fillMaxSize()
                                )
                            }
                        }

                        Text(
                            text = npub.take(20) + "...",
                            fontSize = 11.sp,
                            color = Color(0xFF9A9AA0),
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                            maxLines = 1
                        )

                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(
                                onClick = onDismiss,
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2B2B30), contentColor = Color(0xFFC8C8CE)),
                                shape = RoundedCornerShape(24.dp),
                                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)
                            ) { Text("閉じる") }

                            Button(
                                onClick = {
                                    val sendIntent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                                        putExtra(android.content.Intent.EXTRA_TEXT, "https://www.nullnull.app/p/$npub")
                                        putExtra(android.content.Intent.EXTRA_TITLE, "ぬるぬるでプロフィールを見てね")
                                        type = "text/plain"
                                    }
                                    context.startActivity(android.content.Intent.createChooser(sendIntent, "プロフィールを共有"))
                                },
                                colors = ButtonDefaults.buttonColors(containerColor = LineGreen, contentColor = Color.White),
                                shape = RoundedCornerShape(24.dp),
                                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)
                            ) {
                                Icon(Icons.Default.Share, null, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(8.dp))
                                Text("共有")
                            }
                        }
                    }
                } else {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Button(
                            onClick = {
                                scanError = null
                                if (hasCameraPermission) showScanner = true else permissionLauncher.launch(Manifest.permission.CAMERA)
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = LineGreen, contentColor = Color.White),
                            shape = RoundedCornerShape(24.dp)
                        ) { Text("スキャンを開始") }
                        scanError?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.error) }
                    }
                }

                Spacer(Modifier.weight(1f))
            }
        }
    }

    if (showScanner && onScannedPubkey != null) {
        QRScannerDialog(
            onDismiss = { showScanner = false },
            onScanned = { raw ->
                val pubkey = parseScannedNostrPubkey(raw)
                if (pubkey == null) {
                    scanError = "NostrプロフィールQRではありません"
                } else {
                    showScanner = false
                    onScannedPubkey(pubkey)
                }
            }
        )
    }
}

@Composable
private fun QRScannerDialog(
    onDismiss: () -> Unit,
    onScanned: (String) -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = Color.Black
        ) {
            Box(Modifier.fillMaxSize()) {
                QRScannerPreview(onScanned = onScanned)
                IconButton(
                    onClick = onDismiss,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .statusBarsPadding()
                        .padding(12.dp)
                ) {
                    Icon(Icons.Default.Close, contentDescription = "閉じる", tint = Color.White)
                }
                Surface(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                        .padding(24.dp),
                    color = Color.Black.copy(alpha = 0.65f),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text(
                        "プロフィールQRを枠内に合わせてください",
                        color = Color.White,
                        fontSize = 14.sp,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalGetImage::class)
@Composable
private fun QRScannerPreview(onScanned: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val executor = remember { Executors.newSingleThreadExecutor() }
    val didScan = remember { java.util.concurrent.atomic.AtomicBoolean(false) }
    val cameraProviderRef = remember { java.util.concurrent.atomic.AtomicReference<ProcessCameraProvider?>() }

    DisposableEffect(Unit) {
        onDispose {
            cameraProviderRef.get()?.unbindAll()
            executor.shutdown()
        }
    }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            val previewView = PreviewView(ctx).apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
            }
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val cameraProvider = cameraProviderFuture.get()
                cameraProviderRef.set(cameraProvider)
                val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
                val analyzer = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { analysis ->
                        val reader = MultiFormatReader().apply {
                            setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE)))
                        }
                        analysis.setAnalyzer(executor) { imageProxy ->
                            if (!didScan.get()) {
                                decodeQr(imageProxy, reader)?.let { text ->
                                    if (didScan.compareAndSet(false, true)) {
                                        previewView.post { onScanned(text) }
                                    }
                                }
                            }
                            imageProxy.close()
                        }
                    }
                try {
                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analyzer
                    )
                } catch (_: Exception) { }
            }, ContextCompat.getMainExecutor(context))
            previewView
        }
    )
}

@OptIn(ExperimentalGetImage::class)
private fun decodeQr(imageProxy: ImageProxy, reader: MultiFormatReader): String? {
    return try {
        val image = imageProxy.image ?: return null
        val width = image.width
        val height = image.height
        val plane = image.planes[0]
        val buffer = plane.buffer
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val y = ByteArray(width * height)
        val row = ByteArray(rowStride)
        var out = 0
        for (rowIndex in 0 until height) {
            buffer.position(rowIndex * rowStride)
            buffer.get(row, 0, minOf(rowStride, buffer.remaining()))
            var col = 0
            while (col < width) {
                y[out++] = row[col * pixelStride]
                col++
            }
        }
        val source = PlanarYUVLuminanceSource(y, width, height, 0, 0, width, height, false)
        val bitmap = BinaryBitmap(HybridBinarizer(source))
        reader.decodeWithState(bitmap).text
    } catch (_: Exception) {
        null
    } finally {
        reader.reset()
    }
}

private fun parseScannedNostrPubkey(raw: String): String? {
    val value = raw.trim()
        .removePrefix("nostr:")
        .substringBefore("?")
        .trim()
    NostrKeyUtils.parseNostrLink(value)?.let { link ->
        if (link.type == "npub" || link.type == "nprofile") return link.id
    }
    return NostrKeyUtils.parsePublicKey(value)
}

private fun generateQRBitmap(content: String, size: Int): Bitmap? {
    return try {
        val hints = mapOf(EncodeHintType.MARGIN to 1)
        val bitMatrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size, hints)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
        for (x in 0 until size) {
            for (y in 0 until size) {
                bitmap.setPixel(x, y, if (bitMatrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
            }
        }
        bitmap
    } catch (e: Exception) { null }
}
