import AppKit
import WebKit

/// 一個分頁 = 一個 WKWebView。同時擔任它的 navigation / UI delegate。
@MainActor
final class Tab: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    /// 使用者改的名稱；nil 代表用網頁標題。
    var customTitle: String? { didSet { onChange?(self) } }
    private(set) var favicon: NSImage?
    var onChange: ((Tab) -> Void)?
    weak var downloads: DownloadManager?
    /// window.open / target=_blank：回傳新 Tab（以 WebKit 給的 configuration 建立，保留 opener 關係）。
    var onPopup: ((WKWebViewConfiguration, Tab) -> Tab?)?
    /// 網頁呼叫 window.close()。
    weak var opener: Tab?
    var onVisit: ((URL, String) -> Void)?
    var onRequestClose: ((Tab) -> Void)?
    var zoomStore: ZoomStore?
    /// 釘選的 Tab 對應的 PinNode.id；nil 代表一般 Tab。
    var pinID: UUID?
    /// Option+點連結：取消原本的導覽，交給 Little 視窗開啟。
    var onOptionClick: ((URL) -> Void)?
    /// ⌘+點連結：取消原本的導覽，在背景開新 Tab（不搶走焦點）。
    var onCommandClick: ((URL) -> Void)?
    /// window.open / target=_blank 在同一個 view 就地開啟（Little 視窗用）。
    var popupInPlace = false
    /// 最近使用順序：越大越近（TabManager 在選中時遞增指派；命令列與 Ctrl+Tab 用）。
    var mruSeq = 0
    /// Split View 的另一半（互相指向）；nil 代表單獨顯示。只在一般（未釘選）Tab 之間成立。
    weak var splitPartner: Tab?

    private var observations: [NSKeyValueObservation] = []
    private var faviconTask: URLSessionDataTask?

    var pageTitle: String { webView.title ?? "" }
    /// 使用者要求載入的網址；頁面還沒 commit 前 webView.url 是 nil，session 存檔需要它。
    private(set) var requestedURL: URL?
    var url: URL? { webView.url }
    /// UI 與 session 看到的網址。
    var displayURL: URL? { errorURL ?? url ?? requestedURL }
    /// 載入失敗時顯示說明頁；此時網址列仍顯示失敗的網址。
    private(set) var errorURL: URL?

    /// 重新整理；說明頁上則重試原網址。
    func reloadOrRetry() {
        if let errorURL { load(errorURL) } else { webView.reload() }
    }
    var isLoading: Bool { webView.isLoading }

    var displayTitle: String {
        if let c = customTitle, !c.isEmpty { return c }
        if !pageTitle.isEmpty { return pageTitle }
        if let host = url?.host { return host }
        return "New Tab"
    }

    /// WKWebView 預設 UA 不含 `Version/X Safari/Y` 字尾（跟真正的 Safari 不同），
    /// 有些網站（例如 Google 搜尋結果頁的 favicon、AI 模式等豐富 UI）用這個判斷是不是「正式」瀏覽器，
    /// 沒有就退回簡化版——跟 Chrome 偽裝無關（那條路已驗證無效，見 docs/decisions.md），這裡只是把 WKWebView
    /// 本來就該有、但預設沒帶上的 Safari 識別字串補回去。Safari 版本號讀系統實際安裝的 Safari.app（跟著 macOS
    /// 更新）；WebKit 組建號 605.1.15 是 Safari 多年未變的固定字串，真正的 Safari 也是這個值。
    private static let safariApplicationName: String = {
        let version = Bundle(path: "/Applications/Safari.app")?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "18.0"
        return "Version/\(version) Safari/605.1.15"
    }()

    init(configuration: WKWebViewConfiguration) {
        if configuration.applicationNameForUserAgent == nil {
            configuration.applicationNameForUserAgent = Tab.safariApplicationName
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.underPageBackgroundColor = Theme.card
        observations = [
            webView.observe(\.title) { [weak self] _, _ in
                self?.notify()
                MainActor.assumeIsolated { self?.updateVisitTitle() }
            },
            webView.observe(\.url) { [weak self] _, _ in self?.notify() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.notify() },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in self?.notify() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.notify() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.notify() },
        ]
    }

    private var visitedURL: URL?

    /// 標題常在 didFinish 之後才到；補更新歷史標題。
    private func updateVisitTitle() {
        if let url = visitedURL, url == webView.url, !pageTitle.isEmpty, errorURL == nil { onVisit?(url, pageTitle) }
    }

    private func notify() {
        MainActor.assumeIsolated { onChange?(self) }
    }

    func load(_ url: URL) {
        requestedURL = url
        webView.load(URLRequest(url: url))
    }

    /// 使用者明確用「開啟檔案」交給瀏覽器的本機 HTML；只放行這一個檔案的導覽。
    private var allowedFileURL: URL?

    func loadFile(_ url: URL) {
        allowedFileURL = url.standardizedFileURL
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func teardown() {
        faviconTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        observations.removeAll()
        webView.removeFromSuperview()
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        if navigationAction.targetFrame?.isMainFrame ?? true, InputNormalizer.isHTTP(navigationAction.request.url) {
            errorURL = nil
        }
        // Option+點連結 → Little；⌘+點連結 → 背景開新 Tab（一般點擊、彈出視窗與登入流程不受影響；⌥⌘+點兩者都不攔截）。
        let mods = navigationAction.modifierFlags
        if navigationAction.navigationType == .linkActivated, mods.contains(.option), !mods.contains(.command),
           let url = navigationAction.request.url, InputNormalizer.isHTTP(url), let onOptionClick {
            decisionHandler(.cancel)
            onOptionClick(url)
            return
        }
        if navigationAction.navigationType == .linkActivated, mods.contains(.command), !mods.contains(.option),
           let url = navigationAction.request.url, InputNormalizer.isHTTP(url), let onCommandClick {
            decisionHandler(.cancel)
            onCommandClick(url)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if scheme == "file", let allowed = allowedFileURL, navigationAction.request.url?.standardizedFileURL == allowed {
            decisionHandler(.allow)
            return
        }
        // 只放行 http(s) 與 about/blob；mailto:、file:、自訂 scheme 一律拒絕。
        decisionHandler(["http", "https", "about", "blob"].contains(scheme) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let attachment = disposition.hasPrefix("attachment")
        decisionHandler(attachment || !navigationResponse.canShowMIMEType ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloads?.adopt(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloads?.adopt(download)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        requestedURL = nil
        if let host = webView.url?.host, InputNormalizer.isHTTP(webView.url) { webView.pageZoom = zoomStore?.zoom(for: host) ?? 1 }
        favicon = nil
        notify()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    private func showError(_ error: Error) {
        let ns = error as NSError
        guard ErrorPage.shouldShow(ns) else { return }
        let failing = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? requestedURL
        errorURL = failing
        requestedURL = nil
        webView.loadHTMLString(ErrorPage.html(for: ns, url: failing), baseURL: nil)
        notify()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if errorURL == nil, let url = webView.url, InputNormalizer.isHTTP(url) { visitedURL = url; onVisit?(url, pageTitle) }
        loadFavicon()
    }

    /// 彈出視窗（含登入流程）開成新 Tab，並使用 WebKit 給的 configuration，window.opener / postMessage 才會正常。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        guard url == nil || InputNormalizer.isHTTP(url) || url?.scheme == "about" else { return nil }
        if popupInPlace {
            if let url, InputNormalizer.isHTTP(url) { load(url) }
            return nil
        }
        return onPopup?(configuration, self)?.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        onRequestClose?(self)
    }

    // MARK: Permissions：預設全拒

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    // MARK: HTTP 驗證（憑證只用於這次請求，不存檔）

    struct AuthRequest {
        let host: String
        let realm: String
        let isSecure: Bool
        let isRetry: Bool
    }

    /// 回傳 (帳號, 密碼)，取消回傳 nil。測試可替換。
    static var authPrompt: @MainActor (AuthRequest) -> (String, String)? = { request in
        let alert = NSAlert()
        alert.messageText = "Sign in to \(request.host)"
        var info = request.realm.isEmpty ? "" : "Realm: \(request.realm)\n"
        if request.isRetry { info += "The user name or password was rejected.\n" }
        if !request.isSecure { info += "This connection is not encrypted; the password will be sent in a form that can be read on the network." }
        alert.informativeText = info
        let user = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        user.placeholderString = "User name"
        let pass = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        pass.placeholderString = "Password"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        box.addSubview(user); box.addSubview(pass)
        alert.accessoryView = box
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = user
        return alert.runModal() == .alertFirstButtonReturn ? (user.stringValue, pass.stringValue) : nil
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        let methods = [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM]
        // 伺服器憑證等其他挑戰走預設處理（不通過就是錯誤頁，不提供略過）。
        guard methods.contains(space.authenticationMethod) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let request = AuthRequest(host: space.host, realm: space.realm ?? "", isSecure: space.protocol == "https",
                                  isRetry: challenge.previousFailureCount > 0)
        if let (user, password) = Tab.authPrompt(request) {
            completionHandler(.useCredential, URLCredential(user: user, password: password, persistence: .none))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: JS 對話框與檔案選擇（網頁正常運作所需）

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = dialog(message, frame: frame)
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = dialog(message, frame: frame)
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = dialog(prompt, frame: frame)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    private func dialog(_ message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Page"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        return alert
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    // MARK: Favicon

    private func loadFavicon() {
        guard let pageURL = webView.url, InputNormalizer.isHTTP(pageURL) else { return }
        let js = "(document.querySelector('link[rel~=\"icon\"]')||{}).href||''"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self, self.webView.url == pageURL else { return }
                var icon = URL(string: (result as? String) ?? "")
                if !InputNormalizer.isHTTP(icon) {
                    icon = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL
                }
                guard let icon, InputNormalizer.isHTTP(icon) else { return }
                self.fetchFavicon(icon, for: pageURL)
            }
        }
    }

    private func fetchFavicon(_ icon: URL, for pageURL: URL, fallbackTried: Bool = false) {
        faviconTask?.cancel()
        var request = URLRequest(url: icon)
        request.timeoutInterval = 5
        faviconTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.webView.url == pageURL else { return }
                        self.favicon = image
                        self.notify()
                    }
                }
                return
            }
            // 子網域（如登入過場頁）常沒有自己的 favicon.ico；往上一層網域再試一次。
            guard !fallbackTried, let host = icon.host, let parent = Tab.parentDomain(of: host),
                  let fallback = URL(string: "/favicon.ico", relativeTo: URL(string: "https://\(parent)"))?.absoluteURL else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.webView.url == pageURL else { return }
                    self.fetchFavicon(fallback, for: pageURL, fallbackTried: true)
                }
            }
        }
        faviconTask?.resume()
    }

    /// 簡化版 eTLD+1（取最後兩段）；只用於 favicon 的次要備援，取錯也只是備援落空，不影響正確性要求高的地方。
    /// IPv4/localhost 沒有「上一層網域」的概念，排除。smoke 直接測這個函式（network-independent）。
    static func parentDomain(of host: String) -> String? {
        guard host != "localhost", host.split(separator: ".").contains(where: { !($0.allSatisfy(\.isNumber)) }) else { return nil }
        let parts = host.split(separator: ".")
        guard parts.count > 2 else { return nil }
        return parts.suffix(2).joined(separator: ".")
    }
}
