package io.nurunuru.app.ui.miniapps

import android.annotation.SuppressLint
import android.util.Base64
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.nurunuru.app.data.ScrollEvent
import io.nurunuru.app.ui.theme.LocalNuruColors

/**
 * Minimal NIP-A5 Scroll runner.
 *
 * Security: no private key, signer, repository, or privileged JS bridge is
 * exposed to the WebView. The generated page receives only the Scroll metadata
 * and the base64 WASM payload length for now.
 */
@Composable
fun ScrollRunner(scroll: ScrollEvent, pubkeyHex: String, onBack: () -> Unit) {
    val nuruColors = LocalNuruColors.current
    BackHandler(onBack = onBack)

    Column(modifier = Modifier.fillMaxSize().background(nuruColors.bgPrimary)) {
        Row(
            modifier = Modifier.fillMaxWidth().height(56.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る", tint = nuruColors.textPrimary)
            }
            Text(
                text = scroll.title,
                color = nuruColors.textPrimary,
                fontWeight = FontWeight.SemiBold,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = onBack) {
                Icon(Icons.Filled.Close, contentDescription = "閉じる", tint = nuruColors.textPrimary)
            }
        }
        HorizontalDivider(color = nuruColors.border, thickness = 0.5.dp)

        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                WebView(context).apply {
                    webViewClient = WebViewClient()
                    @SuppressLint("SetJavaScriptEnabled")
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = false
                    settings.allowFileAccess = false
                    settings.allowContentAccess = false
                    settings.databaseEnabled = false
                    loadDataWithBaseURL(
                        "https://scrolls.local/",
                        buildScrollHtml(scroll, pubkeyHex),
                        "text/html",
                        "UTF-8",
                        null
                    )
                }
            },
            update = { webView ->
                webView.loadDataWithBaseURL(
                    "https://scrolls.local/",
                    buildScrollHtml(scroll, pubkeyHex),
                    "text/html",
                    "UTF-8",
                    null
                )
            }
        )
    }
}

private fun buildScrollHtml(scroll: ScrollEvent, pubkeyHex: String): String {
    val wasmBytes = try { Base64.decode(scroll.wasmBase64, Base64.DEFAULT).size } catch (_: Exception) { 0 }
    val paramRows = scroll.params.joinToString("\n") { param ->
        "<li><b>${param.name.escapeHtml()}</b> (${param.type.escapeHtml()}${if (param.required) ", required" else ""}) - ${param.description.escapeHtml()}</li>"
    }
    return """
        <!doctype html>
        <html lang="ja">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            body { margin: 0; padding: 20px; background: #0A0A0A; color: #F5F5F5; font-family: sans-serif; }
            .card { background: #1C1C1E; border: 1px solid #38383A; border-radius: 16px; padding: 16px; }
            h1 { font-size: 20px; margin: 0 0 8px; }
            p, li { color: #B3B3B3; font-size: 14px; line-height: 1.5; }
            code { color: #06C755; word-break: break-all; }
            .notice { margin-top: 16px; color: #FFCC80; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>${scroll.title.escapeHtml()}</h1>
            <p>${scroll.description.escapeHtml()}</p>
            <p>author: <code>${scroll.pubkey.escapeHtml()}</code></p>
            <p>viewer: <code>${pubkeyHex.escapeHtml()}</code></p>
            <p>WASM payload: ${wasmBytes} bytes</p>
            <h2 style="font-size:16px">Params</h2>
            <ul>${paramRows.ifBlank { "<li>なし</li>" }}</ul>
            <p class="notice">Scroll runner is sandboxed. Signer/private key APIs are not exposed.</p>
          </div>
        </body>
        </html>
    """.trimIndent()
}

private fun String.escapeHtml(): String = buildString(length) {
    for (ch in this@escapeHtml) {
        when (ch) {
            '&' -> append("&amp;")
            '<' -> append("&lt;")
            '>' -> append("&gt;")
            '"' -> append("&quot;")
            '\'' -> append("&#39;")
            else -> append(ch)
        }
    }
}
