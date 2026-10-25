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

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = Theme.card
        observations = [
            webView.observe(\.title) { [weak self] _, _ in self?.notify() },
            webView.observe(\.url) { [weak self] _, _ in self?.notify() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.notify() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.notify() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.notify() },
        ]
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
        loadFavicon()
    }

    /// 登入流程常用彈出視窗；全部留在同一個 view 內處理。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, InputNormalizer.isHTTP(navigationAction.request.url) {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: Permissions：預設全拒

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
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

    private func fetchFavicon(_ icon: URL, for pageURL: URL) {
        faviconTask?.cancel()
        var request = URLRequest(url: icon)
        request.timeoutInterval = 5
        faviconTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.webView.url == pageURL else { return }
                    self.favicon = image
                    self.notify()
                }
            }
        }
        faviconTask?.resume()
    }
}
