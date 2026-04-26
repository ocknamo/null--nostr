import SwiftUI
import WebKit

// MARK: - Constants

/// Kind numbers that are approved automatically without showing a confirmation dialog.
/// Mirrors Android NostrBrowserApp.kt AUTO_APPROVED_KINDS.
private let autoApprovedKinds: Set<Int> = [1, 6, 7, 9734, 1984, 30023, 30024, 30078]

/// Human-readable Japanese labels for sensitive event kinds.
private let kindLabels: [Int: String] = [
    0:     "プロフィール更新 (Kind 0)",
    3:     "フォローリスト更新 (Kind 3)",
    4:     "ダイレクトメッセージ (Kind 4)",
    10000: "ミュートリスト更新 (Kind 10000)",
    10002: "リレーリスト更新 (Kind 10002)",
]

/// NIP-07 `window.nostr` bridge injected at document start and finish.
/// Promises are resolved / rejected via `window.__nostr_resolve` / `window.__nostr_reject`.
/// Mirrors Android NOSTR_BRIDGE_JS in NostrBrowserApp.kt.
private let nostrBridgeJS = """
(function() {
  if (window.nostr) return;

  var _cb = {};
  window.__nostr_resolve = function(id, result) {
    if (_cb[id]) { _cb[id].resolve(result); delete _cb[id]; }
  };
  window.__nostr_reject = function(id, error) {
    if (_cb[id]) { _cb[id].reject(new Error(String(error))); delete _cb[id]; }
  };

  // WebKit用デバッグ: JSエラーをネイティブへ通知
  window.addEventListener('error', function(e) {
    try {
      window.webkit.messageHandlers.nip07_jsError.postMessage({
        id: 'jserr_' + String(Date.now()) + '_' + Math.random().toString(36).substr(2, 5),
        message: String((e && e.message) || 'js error'),
        source: String((e && e.filename) || ''),
        line: Number((e && e.lineno) || 0),
        col: Number((e && e.colno) || 0)
      });
    } catch (_) {}
  });

  function _req(method, args) {
    return new Promise(function(resolve, reject) {
      var id = Math.random().toString(36).substr(2, 9) + String(Date.now());
      _cb[id] = { resolve: resolve, reject: reject };
      var msg = { id: id };
      if (args[0] !== undefined) msg.arg0 = args[0];
      if (args[1] !== undefined) msg.arg1 = args[1];
      try {
        window.webkit.messageHandlers[method].postMessage(msg);
      } catch(e) {
        reject(new Error('bridge not ready: ' + e.message));
      }
    });
  }

  function _enable() {
    return Promise.resolve(window.nostr);
  }

  window.nostr = {
    _nip07: true,
    enable: _enable,
    getPublicKey: function() { return _req('nip07_getPublicKey', []); },
    signEvent:    function(event) { return _req('nip07_signEvent', [JSON.stringify(event)]); },
    getRelays:    function() { return _req('nip07_getRelays', []); },
    nip04: {
      encrypt: function(pubkey, pt) { return _req('nip07_nip04Encrypt', [pubkey, pt]); },
      decrypt: function(pubkey, ct) { return _req('nip07_nip04Decrypt', [pubkey, ct]); }
    },
    nip44: {
      encrypt: function(pubkey, pt) { return _req('nip07_nip44Encrypt', [pubkey, pt]); },
      decrypt: function(pubkey, ct) { return _req('nip07_nip44Decrypt', [pubkey, ct]); }
    }
  };

  // NIP-07 provider ready signal (実装依存だが多くのクライアントが参照)
  try {
    window.dispatchEvent(new Event('nostr:ready'));
    document.dispatchEvent(new Event('nostr:ready'));
  } catch (_) {}
})();
"""

// MARK: - Browser Navigation State

final class NostrBrowserNavState: ObservableObject {
    @Published var canGoBack: Bool = false
    fileprivate weak var webView: WKWebView?

    func bind(webView: WKWebView) {
        self.webView = webView
        DispatchQueue.main.async { self.canGoBack = webView.canGoBack }
    }

    func refresh() {
        let can = webView?.canGoBack ?? false
        DispatchQueue.main.async { self.canGoBack = can }
    }

    @discardableResult
    func goBackIfPossible() -> Bool {
        guard let wv = webView, wv.canGoBack else { return false }
        wv.goBack()
        DispatchQueue.main.async { self.canGoBack = wv.canGoBack }
        return true
    }

    /// Android寄せ: WebView履歴が無い場合でも、SPAの history.back() を試してから閉じる。
    func navigateBack(orClose: @escaping () -> Void) {
        if goBackIfPossible() { return }
        guard let wv = webView else {
            DispatchQueue.main.async { orClose() }
            return
        }

        let js = "(function(){ try { if (window.history && window.history.length > 1) { window.history.back(); return true; } } catch(e) {} return false; })();"
        wv.evaluateJavaScript(js) { [weak self] result, _ in
            if let didBack = result as? Bool, didBack {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self?.refresh()
                }
            } else {
                DispatchQueue.main.async { orClose() }
            }
        }
    }

    func reset() {
        webView = nil
        DispatchQueue.main.async { self.canGoBack = false }
    }
}

// MARK: - Sign Request

/// Represents a pending NIP-07 signature (or other permission) request from JavaScript.
/// Completion handler is called with `true` (approved) or `false` (rejected).
/// Mirrors Android PermissionRequest data class.
final class SignRequest: @unchecked Sendable {
    let description: String
    private let completion: (Bool) -> Void

    init(description: String, completion: @escaping (Bool) -> Void) {
        self.description = description
        self.completion  = completion
    }

    func complete(_ approved: Bool) { completion(approved) }
}

// MARK: - NostrBrowserView

/// NIP-07 対応 Nostr WebView ブラウザ。
/// window.nostr (getPublicKey / signEvent / getRelays / nip04.encrypt / nip04.decrypt) を提供。
/// Mirrors Android NostrBrowserApp.kt.
struct NostrBrowserView: View {

    let repository:  NostrRepository
    let pubkeyHex:   String
    var initialUrl:  String? = nil
    var navState: NostrBrowserNavState? = nil
    var onCloseRequested: (() -> Void)? = nil

    @Environment(\.nuruTheme) private var theme
    @State private var currentUrl: String       = ""
    @State private var progress:   Double       = 0
    @State private var isLoading:  Bool         = false
    @State private var pendingReq: SignRequest? = nil
    @State private var loadError:  String?      = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // ── WebView 全画面（Android同等: URL表示なし）──────────────────
                NostrWebView(
                    url:        currentUrl,
                    repository: repository,
                    pubkeyHex:  pubkeyHex,
                    onProgress: { progress = $0; isLoading = $0 < 1.0 },
                    onSignReq:  { pendingReq = $0 },
                    onLoadError:{ loadError = $0 },
                    navState:   navState
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 最上部 2px ローディングバーのみ表示
                if isLoading {
                    ProgressView(value: progress)
                        .tint(NuruColors.lineGreen)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .background(Color.clear)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgPrimary)
        .onAppear {
            let fallback = "https://nostter.app"
            let candidate = (initialUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? initialUrl! : fallback
            let normalized = candidate.hasPrefix("http") ? candidate : "https://" + candidate
            if currentUrl.isEmpty {
                currentUrl = normalized
            }
        }
        // ── 読み込みエラー表示 ───────────────────────────────────────────────
        .alert("外部ミニアプリを読み込めません", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("再試行") {
                let retry = currentUrl
                currentUrl = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    currentUrl = retry
                }
                loadError = nil
            }
            Button("閉じる", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "不明なエラー")
        }
        // ── 署名確認ダイアログ (Android AlertDialog と同等) ──────────────────
        .alert("署名リクエスト", isPresented: Binding(
            get: { pendingReq != nil },
            // Dismiss by tapping outside the alert → reject the pending promise
            set: { if !$0 { pendingReq?.complete(false); pendingReq = nil } }
        )) {
            Button("承認") {
                pendingReq?.complete(true)
                pendingReq = nil
            }
            Button("拒否", role: .cancel) {
                pendingReq?.complete(false)
                pendingReq = nil
            }
        } message: {
            if let req = pendingReq {
                Text("Webサイトから以下の操作のリクエストがあります\n\n\(req.description)\n\n秘密鍵はWebサイトには公開されません")
            }
        }
    }

}

// MARK: - WKWebView Wrapper

private struct NostrWebView: UIViewRepresentable {

    let url:         String
    let repository:  NostrRepository
    let pubkeyHex:   String
    let onProgress:  (Double) -> Void
    let onSignReq:   (SignRequest) -> Void
    let onLoadError: (String) -> Void
    let navState:    NostrBrowserNavState?
    let loadTimeoutSeconds: TimeInterval = 12

    func makeCoordinator() -> Coordinator {
        Coordinator(
            repository: repository,
            pubkeyHex:  pubkeyHex,
            onProgress: onProgress,
            onSignReq:  onSignReq,
            onLoadError: onLoadError,
            navState: navState,
            loadTimeoutSeconds: loadTimeoutSeconds
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Register all NIP-07 message handler names
        let handler = context.coordinator
        for name in [
            "nip07_getPublicKey",
            "nip07_signEvent",
            "nip07_getRelays",
            "nip07_nip04Encrypt",
            "nip07_nip04Decrypt",
            "nip07_nip44Encrypt",
            "nip07_nip44Decrypt",
            "nip07_jsError",
        ] {
            config.userContentController.add(handler, name: name)
        }

        // WebKit検出対策: document-start でも window.nostr を先行注入
        let userScript = WKUserScript(
            source: nostrBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        // Android合わせ: didStart / didFinish でも再注入（保険）
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // WebKit互換重視: 不透明背景 + iOS Safari寄せ描画
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.keyboardDismissMode = .onDrag
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.allowsBackForwardNavigationGestures = true
        // 標準UAを利用（WebKit判定の差異を最小化）
        webView.customUserAgent = nil
        webView.addObserver(
            context.coordinator,
            forKeyPath: "estimatedProgress",
            options: .new,
            context: nil
        )
        context.coordinator.webView = webView
        navState?.bind(webView: webView)

        if let firstUrl = URL(string: url) {
            context.coordinator.lastRequestedUrlKey = normalizedUrlKey(firstUrl)
            let req = URLRequest(
                url: firstUrl,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            )
            webView.load(req)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let requested = URL(string: url) else { return }

        // リダイレクト末尾スラッシュ差分などで無限リロードしないよう、
        // "要求URLが変わった時だけ" 再読み込みする。
        let requestedKey = normalizedUrlKey(requested)
        if context.coordinator.lastRequestedUrlKey == requestedKey {
            return
        }

        context.coordinator.lastRequestedUrlKey = requestedKey
        let req = URLRequest(
            url: requested,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        webView.load(req)
    }

    private func normalizedUrlKey(_ u: URL) -> String {
        var comps = URLComponents(url: u, resolvingAgainstBaseURL: false)
        var path = comps?.path ?? ""
        if path == "/" { path = "" }
        comps?.path = path
        comps?.fragment = nil
        return (comps?.string ?? u.absoluteString).lowercased()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {

        let repository: NostrRepository
        let pubkeyHex:  String
        let onProgress: (Double) -> Void
        let onSignReq:  (SignRequest) -> Void
        let onLoadError: (String) -> Void
        let navState: NostrBrowserNavState?
        let loadTimeoutSeconds: TimeInterval
        weak var webView: WKWebView?
        private var timeoutWorkItem: DispatchWorkItem?
        var lastRequestedUrlKey: String? = nil

        init(
            repository: NostrRepository,
            pubkeyHex:  String,
            onProgress: @escaping (Double) -> Void,
            onSignReq:  @escaping (SignRequest) -> Void,
            onLoadError: @escaping (String) -> Void,
            navState: NostrBrowserNavState?,
            loadTimeoutSeconds: TimeInterval = 12
        ) {
            self.repository = repository
            self.pubkeyHex  = pubkeyHex
            self.onProgress = onProgress
            self.onSignReq  = onSignReq
            self.onLoadError = onLoadError
            self.navState = navState
            self.loadTimeoutSeconds = loadTimeoutSeconds
        }

        // MARK: Progress KVO

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            if keyPath == "estimatedProgress", let wv = webView {
                DispatchQueue.main.async { self.onProgress(wv.estimatedProgress) }
            }
        }

        // MARK: Navigation / Loading

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onProgress(0.05)
            scheduleLoadTimeout()
            webView.evaluateJavaScript(nostrBridgeJS, completionHandler: nil)
            navState?.refresh()
        }

        // Re-inject bridge on each navigation (mirrors Android onPageFinished)
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            cancelLoadTimeout()
            webView.evaluateJavaScript(nostrBridgeJS)
            onProgress(1.0)
            navState?.refresh()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleLoadError(error)
        }

        private func handleLoadError(_ error: Error) {
            cancelLoadTimeout()
            let ns = error as NSError
            // NSURLErrorCancelled(-999) は画面遷移/再読込時に発生する想定内キャンセルのため無視
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            onLoadError(error.localizedDescription)
        }

        private func scheduleLoadTimeout() {
            cancelLoadTimeout()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let msg = "読み込みがタイムアウトしました。WebKit互換の問題またはサイト側制限の可能性があります。"
                self.onLoadError(msg)
            }
            timeoutWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + loadTimeoutSeconds, execute: item)
        }

        private func cancelLoadTimeout() {
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            navState?.refresh()
            // mailto/tel などは外部へ
            if let scheme = navigationAction.request.url?.scheme?.lowercased(),
               ["mailto", "tel", "sms"].contains(scheme),
               let u = navigationAction.request.url {
                DispatchQueue.main.async { UIApplication.shared.open(u) }
                decisionHandler(.cancel)
                return
            }

            // 通常は許可。_blank は createWebViewWith で同一WebViewに寄せる
            decisionHandler(.allow)
        }

        // target=_blank support
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // WebContent process crash recovery
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        // MARK: NIP-07 Message Dispatch

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body  = message.body as? [String: Any],
                  let reqId = body["id"] as? String
            else { return }

            switch message.name {

            // ── getPublicKey ───────────────────────────────────────────────
            case "nip07_getPublicKey":
                resolve(reqId: reqId, jsonValue: "\"\(pubkeyHex)\"")

            // ── signEvent ──────────────────────────────────────────────────
            case "nip07_signEvent":
                guard let eventJson = body["arg0"] as? String else {
                    reject(reqId: reqId, error: "イベントJSON が見つかりません")
                    return
                }
                handleSignEvent(reqId: reqId, eventJson: eventJson)

            // ── getRelays ──────────────────────────────────────────────────
            case "nip07_getRelays":
                Task {
                    let json = await repository.getRelaysJson()
                    self.resolve(reqId: reqId, jsonValue: json)
                }

            // ── nip04.encrypt ──────────────────────────────────────────────
            case "nip07_nip04Encrypt":
                guard let pubkey    = body["arg0"] as? String,
                      let plaintext = body["arg1"] as? String
                else {
                    reject(reqId: reqId, error: "引数が不正です")
                    return
                }
                Task {
                    if let result = await repository.nip04EncryptForBridge(pubkey, plaintext) {
                        self.resolve(reqId: reqId, jsonValue: "\"\(result.jsEscaped)\"")
                    } else {
                        self.reject(reqId: reqId, error: "暗号化に失敗しました")
                    }
                }

            // ── nip04.decrypt ──────────────────────────────────────────────
            case "nip07_nip04Decrypt":
                guard let pubkey     = body["arg0"] as? String,
                      let ciphertext = body["arg1"] as? String
                else {
                    reject(reqId: reqId, error: "引数が不正です")
                    return
                }
                Task {
                    if let result = await repository.nip04DecryptForBridge(pubkey, ciphertext) {
                        self.resolve(reqId: reqId, jsonValue: "\"\(result.jsEscaped)\"")
                    } else {
                        self.reject(reqId: reqId, error: "復号に失敗しました")
                    }
                }

            // ── nip44.encrypt ──────────────────────────────────────────────
            case "nip07_nip44Encrypt":
                guard let pubkey    = body["arg0"] as? String,
                      let plaintext = body["arg1"] as? String
                else {
                    reject(reqId: reqId, error: "引数が不正です")
                    return
                }
                Task {
                    if let result = await repository.nip44EncryptForBridge(pubkey, plaintext) {
                        self.resolve(reqId: reqId, jsonValue: "\"\(result.jsEscaped)\"")
                    } else {
                        self.reject(reqId: reqId, error: "NIP-44暗号化に失敗しました")
                    }
                }

            // ── nip44.decrypt ──────────────────────────────────────────────
            case "nip07_nip44Decrypt":
                guard let pubkey     = body["arg0"] as? String,
                      let ciphertext = body["arg1"] as? String
                else {
                    reject(reqId: reqId, error: "引数が不正です")
                    return
                }
                Task {
                    if let result = await repository.nip44DecryptForBridge(pubkey, ciphertext) {
                        self.resolve(reqId: reqId, jsonValue: "\"\(result.jsEscaped)\"")
                    } else {
                        self.reject(reqId: reqId, error: "NIP-44復号に失敗しました")
                    }
                }

            // ── JS error log ───────────────────────────────────────────────
            case "nip07_jsError":
                let message = (body["message"] as? String) ?? "js error"
                let source  = (body["source"] as? String) ?? ""
                let line    = (body["line"] as? Int) ?? 0
                let col     = (body["col"] as? Int) ?? 0
                AppLogger.log("NostrBrowser", "JS error: \(message) @\(source):\(line):\(col)")
                // request id がある仕様のため resolve して詰まりを防ぐ
                resolve(reqId: reqId, jsonValue: "null")

            default:
                break
            }
        }

        // MARK: - signEvent: auto-approve or show dialog

        private func handleSignEvent(reqId: String, eventJson: String) {
            let kind = kindFromJson(eventJson)

            if autoApprovedKinds.contains(kind) {
                // Common kinds: approve silently (no dialog)
                performSign(reqId: reqId, eventJson: eventJson)
            } else {
                // Sensitive kinds: show confirmation dialog
                let label = kindLabels[kind] ?? "イベント署名 (Kind \(kind))"
                DispatchQueue.main.async {
                    let req = SignRequest(description: label) { [weak self] approved in
                        guard let self else { return }
                        if approved {
                            self.performSign(reqId: reqId, eventJson: eventJson)
                        } else {
                            self.reject(reqId: reqId, error: "ユーザーが拒否しました")
                        }
                    }
                    self.onSignReq(req)
                }
            }
        }

        private func performSign(reqId: String, eventJson: String) {
            Task {
                guard let data = eventJson.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let kindAny = dict["kind"]
                else {
                    self.reject(reqId: reqId, error: "イベントのパースに失敗しました")
                    return
                }

                let kind: Int
                if let k = kindAny as? Int {
                    kind = k
                } else if let k = kindAny as? NSNumber {
                    kind = k.intValue
                } else {
                    self.reject(reqId: reqId, error: "kind が不正です")
                    return
                }

                let content = (dict["content"] as? String) ?? ""
                let createdAt: Int64? = {
                    if let v = dict["created_at"] as? Int64 { return v }
                    if let v = dict["created_at"] as? Int { return Int64(v) }
                    if let v = dict["created_at"] as? NSNumber { return v.int64Value }
                    if let v = dict["createdAt"] as? Int64 { return v }
                    if let v = dict["createdAt"] as? Int { return Int64(v) }
                    if let v = dict["createdAt"] as? NSNumber { return v.int64Value }
                    return nil
                }()

                let rawTags = (dict["tags"] as? [[Any]]) ?? []

                // Android同様、数値タグも文字列化して保持
                let tags: [[String]] = rawTags.compactMap { row in
                    let strs = row.compactMap { String(describing: $0) }
                    return strs.isEmpty ? nil : strs
                }

                do {
                    let signed = try await repository.signEventForBridge(
                        kind: kind,
                        tags: tags,
                        content: content,
                        createdAt: createdAt
                    )
                    if let jsonData = try? JSONEncoder().encode(signed),
                       let jsonStr  = String(data: jsonData, encoding: .utf8) {
                        self.resolve(reqId: reqId, jsonValue: jsonStr)
                    } else {
                        self.reject(reqId: reqId, error: "署名結果のシリアライズに失敗しました")
                    }
                } catch {
                    self.reject(reqId: reqId, error: "署名に失敗しました")
                }
            }
        }

        // MARK: - JS Bridge Helpers

        /// Call `window.__nostr_resolve(id, jsonValue)` in the WebView.
        private func resolve(reqId: String, jsonValue: String) {
            let safeId = reqId.jsSafeId
            let js = "window.__nostr_resolve('\(safeId)', \(jsonValue));"
            DispatchQueue.main.async { self.webView?.evaluateJavaScript(js) }
        }

        /// Call `window.__nostr_reject(id, errorMessage)` in the WebView.
        private func reject(reqId: String, error: String) {
            let safeId  = reqId.jsSafeId
            let safeMsg = error.jsEscaped
            let js = "window.__nostr_reject('\(safeId)', '\(safeMsg)');"
            DispatchQueue.main.async { self.webView?.evaluateJavaScript(js) }
        }

        // MARK: - Utilities

        private func kindFromJson(_ json: String) -> Int {
            guard let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let kind = dict["kind"] as? Int
            else { return 1 }
            return kind
        }
    }
}

// MARK: - String Helpers

private extension String {
    /// Escape a string to be safely embedded inside a single-quoted JS string literal.
    /// Mirrors Android NostrJsBridge.resolve / reject sanitization.
    var jsEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'",  with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "`",  with: "\\`")
            .replacingOccurrences(of: "\0", with: "")
    }

    /// Safe request ID for use as a JS string key.
    var jsSafeId: String { jsEscaped }
}


