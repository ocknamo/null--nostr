import SwiftUI
import WebKit
import Observation

// MARK: - ScrollsViewModel

/// NIP-A5 Scrolls ミニアプリの状態と操作。
/// Android の ScrollsViewModel に対応する。
@Observable
@MainActor
final class ScrollsViewModel {

    // MARK: - State

    var scrolls:      [ScrollEvent] = []
    var favorites:    Set<String>   = []
    var isLoading:    Bool          = true
    var errorMessage: String?       = nil

    // MARK: - Dependencies

    private let repository: NostrRepository
    let pubkeyHex: String

    // MARK: - Init

    init(repository: NostrRepository, pubkeyHex: String) {
        self.repository = repository
        self.pubkeyHex  = pubkeyHex
    }

    // MARK: - Load

    func load() async {
        isLoading    = true
        errorMessage = nil

        async let fetchedScrolls   = repository.fetchScrolls()
        async let fetchedFavorites = repository.fetchFavoriteScrolls(pubkeyHex: pubkeyHex)

        let (s, f) = await (fetchedScrolls, fetchedFavorites)
        scrolls   = s
        favorites = Set(f)
        isLoading = false
    }

    // MARK: - Favorite Toggle

    func toggleFavorite(_ scroll: ScrollEvent) async {
        let id = scroll.id
        if favorites.contains(id) {
            favorites.remove(id)
            do {
                try await repository.removeFavoriteScroll(pubkeyHex: pubkeyHex, scrollId: id)
            } catch {
                // ロールバック
                favorites.insert(id)
                errorMessage = "お気に入りの削除に失敗しました"
            }
        } else {
            favorites.insert(id)
            do {
                try await repository.addFavoriteScroll(pubkeyHex: pubkeyHex, scrollId: id)
            } catch {
                // ロールバック
                favorites.remove(id)
                errorMessage = "お気に入りの追加に失敗しました"
            }
        }
    }
}

// MARK: - ScrollsView

/// NIP-A5 Scrolls ミニアプリ一覧画面。
/// Kind 1227 のスクロール（WASM ミニアプリ）を一覧表示し、
/// お気に入り登録・実行（WebView）を行う。
struct ScrollsView: View {

    let repository: NostrRepository
    let pubkeyHex:  String

    @Environment(\.nuruTheme) private var theme
    @State private var viewModel: ScrollsViewModel? = nil
    @State private var runningScroll: ScrollEvent?  = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm: vm)
            } else {
                loadingPlaceholder
            }
        }
        .task {
            let vm = ScrollsViewModel(repository: repository, pubkeyHex: pubkeyHex)
            viewModel = vm
            await vm.load()
        }
        .sheet(item: $runningScroll) { scroll in
            ScrollRunnerView(scroll: scroll, pubkeyHex: pubkeyHex)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(vm: ScrollsViewModel) -> some View {
        if vm.isLoading {
            loadingPlaceholder
        } else if vm.scrolls.isEmpty {
            emptyState
        } else {
            scrollList(vm: vm)
        }
    }

    // MARK: - Scroll List

    private func scrollList(vm: ScrollsViewModel) -> some View {
        List {
            ForEach(vm.scrolls) { scroll in
                ScrollRow(
                    scroll:     scroll,
                    isFavorite: vm.favorites.contains(scroll.id),
                    onFavorite: {
                        Task { await vm.toggleFavorite(scroll) }
                    },
                    onRun: {
                        runningScroll = scroll
                    }
                )
                .listRowBackground(theme.bgPrimary)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparatorTint(theme.borderColor)
            }
        }
        .listStyle(.plain)
        .background(theme.bgPrimary)
        .refreshable { await vm.load() }
        .alert("エラー", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Loading / Empty

    private var loadingPlaceholder: some View {
        VStack {
            Spacer()
            ProgressView().tint(NuruColors.lineGreen)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(theme.bgPrimary)
    }

    private var emptyState: some View {
        VStack(spacing: NuruSpacing.space3) {
            Spacer()
            Image(systemName: "scroll")
                .font(.system(size: 48))
                .foregroundStyle(theme.textTertiary)
            Text("スクロールがありません")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textTertiary)
            Text("Kind 1227 のスクロールが\nリレーに見つかりませんでした")
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(theme.bgPrimary)
    }
}

// MARK: - ScrollRow

/// スクロール一覧の1行。タイトル・説明・作者アバター・ハート・実行ボタン。
private struct ScrollRow: View {

    let scroll:     ScrollEvent
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onRun:      () -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var authorProfile: UserProfile? = nil

    var body: some View {
        HStack(alignment: .top, spacing: NuruSpacing.space3) {

            // 作者アバター
            AvatarView(
                url:  authorProfile?.picture,
                name: authorProfile?.displayedName ?? scroll.pubkey,
                size: 40
            )

            // テキスト情報
            VStack(alignment: .leading, spacing: 4) {
                Text(scroll.title)
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                if !scroll.description.isEmpty {
                    Text(scroll.description)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }

                Text(scroll.pubkey.shortenedPubkey)
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // アクションボタン群
            VStack(spacing: NuruSpacing.space2) {
                // ハート（お気に入りトグル）
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(isFavorite ? NuruColors.colorError : theme.textTertiary)
                }
                .buttonStyle(.plain)

                // 実行ボタン
                Button(action: onRun) {
                    Text("実行")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NuruColors.lineGreen)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ScrollRunnerView

/// NIP-A5 Scroll 実行ビュー。
/// WKWebView に WASM base64 を注入し、JS インターフェース経由でネイティブと通信する。
struct ScrollRunnerView: View {

    let scroll:     ScrollEvent
    let pubkeyHex:  String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nuruTheme) private var theme
    @State private var logMessages: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // WebView
                ScrollWebView(
                    scroll:     scroll,
                    pubkeyHex:  pubkeyHex,
                    onLog:      { msg in logMessages.append(msg) }
                )
                .background(theme.bgPrimary)

                // デバッグログ（開発用：最大5件表示）
                if !logMessages.isEmpty {
                    Divider().background(theme.borderColor)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(logMessages.suffix(5), id: \.self) { msg in
                                Text(msg)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        .padding(NuruSpacing.space3)
                    }
                    .frame(maxHeight: 80)
                    .background(theme.bgSecondary)
                }
            }
            .navigationTitle(scroll.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(NuruColors.lineGreen)
                }
            }
        }
    }
}

// MARK: - ScrollWebView (WKWebView Wrapper)

/// WKWebView ラッパー。WASM base64 を HTML に埋め込み、`nostr.*` JS インターフェースを提供。
private struct ScrollWebView: UIViewRepresentable {

    let scroll:    ScrollEvent
    let pubkeyHex: String
    let onLog:     (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(pubkeyHex: pubkeyHex, onLog: onLog)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // JS → Swift メッセージハンドラ登録
        config.userContentController.add(context.coordinator, name: "nostr_display")
        config.userContentController.add(context.coordinator, name: "nostr_log")

        // `nostr` オブジェクトをドキュメント先頭に注入
        let bridgeScript = WKUserScript(
            source: nip_a5_bridge_js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(bridgeScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = UIColor(NuruColors.bgPrimary)
        webView.isOpaque = false
        webView.scrollView.backgroundColor = UIColor(NuruColors.bgPrimary)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 同じ Scroll の再ロードをスキップ（SwiftUI が毎フレーム呼ぶため）
        guard context.coordinator.lastLoadedScrollId != scroll.id else { return }
        context.coordinator.lastLoadedScrollId = scroll.id
        let html = buildHTML(wasmBase64: scroll.wasmBase64, meParam: pubkeyHex)
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - HTML Builder

    /// WASM base64 を埋め込んだ HTML ページを生成する。
    /// "me" パラメータは pubkeyHex で自動補完する。
    private func buildHTML(wasmBase64: String, meParam: String) -> String {
        // params のうち "me" 型 / name == "me" を自動補完
        var paramEntries = scroll.params.map { param -> String in
            let value: String
            if param.name == "me" || param.type == "pubkey" && param.name == "me" {
                value = meParam
            } else {
                value = ""
            }
            return "  \(param.name): \"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        let paramsJS = paramEntries.isEmpty
            ? "{}"
            : "{\n" + paramEntries.joined(separator: ",\n") + "\n}"

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body {
              background: #0A0A0A;
              color: #F5F5F5;
              font-family: -apple-system, sans-serif;
              padding: 16px;
              margin: 0;
            }
            #output { margin-top: 12px; }
            .post-card {
              background: #1C1C1E;
              border-radius: 12px;
              padding: 12px;
              margin-bottom: 8px;
            }
          </style>
        </head>
        <body>
          <div id="output"></div>
          <script>
            // NIP-A5 params (auto-filled by iOS runner)
            var _params = \(paramsJS);

            // WASM module (base64-encoded)
            var _wasmBase64 = "\(wasmBase64)";

            function base64ToBytes(b64) {
              var bin = atob(b64);
              var arr = new Uint8Array(bin.length);
              for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
              return arr;
            }

            // instance をスクリプトスコープで宣言し、env クロージャから参照可能にする。
            // .then() 内で代入するため、WASM 実行前に imports が呼ばれることはない。
            var instance;
            WebAssembly.instantiate(base64ToBytes(_wasmBase64), {
              env: {
                nostr_display: function(ptr, len) {
                  // WASMメモリから文字列を読む
                  var mem  = new Uint8Array(instance.exports.memory.buffer);
                  var json = new TextDecoder().decode(mem.subarray(ptr, ptr + len));
                  window.webkit.messageHandlers.nostr_display.postMessage(json);
                },
                nostr_log: function(ptr, len) {
                  var mem = new Uint8Array(instance.exports.memory.buffer);
                  var msg = new TextDecoder().decode(mem.subarray(ptr, ptr + len));
                  window.webkit.messageHandlers.nostr_log.postMessage(msg);
                }
              }
            }).then(function(result) {
              instance = result.instance;
              if (typeof instance.exports.run === 'function') {
                instance.exports.run();
              }
            }).catch(function(e) {
              window.webkit.messageHandlers.nostr_log.postMessage('WASM error: ' + e.message);
            });
          </script>
        </body>
        </html>
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

        let pubkeyHex: String
        let onLog:     (String) -> Void
        /// 最後にロードした Scroll のイベント ID。同一 ID で再ロードを防ぐ。
        var lastLoadedScrollId: String? = nil

        init(pubkeyHex: String, onLog: @escaping (String) -> Void) {
            self.pubkeyHex = pubkeyHex
            self.onLog     = onLog
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "nostr_display":
                guard let json = message.body as? String else { return }
                // ネイティブ描画: 現在は output div へ表示（PostRow は WebView 内 HTML）
                let js = """
                (function() {
                  var card = document.createElement('div');
                  card.className = 'post-card';
                  try {
                    var ev = JSON.parse(\(jsStringLiteral(json)));
                    card.textContent = ev.content || JSON.stringify(ev);
                  } catch(e) {
                    card.textContent = \(jsStringLiteral(json));
                  }
                  document.getElementById('output').appendChild(card);
                })();
                """
                DispatchQueue.main.async {
                    message.webView?.evaluateJavaScript(js, completionHandler: nil)
                }

            case "nostr_log":
                let msg = (message.body as? String) ?? String(describing: message.body)
                DispatchQueue.main.async { self.onLog(msg) }

            default:
                break
            }
        }

        // MARK: WKNavigationDelegate

        /// 外部ナビゲーションをブロック（about:blank のみ許可）。
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url?.absoluteString ?? ""
            decisionHandler(url == "about:blank" || url.isEmpty ? .allow : .cancel)
        }

        // MARK: - JS String Helper

        private func jsStringLiteral(_ s: String) -> String {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return "\"\(escaped)\""
        }
    }
}

// MARK: - NIP-A5 Bridge JS (nostr オブジェクト)

/// WebView に注入する `window.nostr` ブリッジスクリプト。
/// `nostr.display(eventJson)` と `nostr.log(message)` を提供する。
private let nip_a5_bridge_js = """
(function() {
  if (window.nostr) return;
  window.nostr = {
    display: function(eventJson) {
      try {
        window.webkit.messageHandlers.nostr_display.postMessage(
          typeof eventJson === 'string' ? eventJson : JSON.stringify(eventJson)
        );
      } catch(e) {}
    },
    log: function(message) {
      try {
        window.webkit.messageHandlers.nostr_log.postMessage(String(message));
      } catch(e) {}
    }
  };
})();
"""
