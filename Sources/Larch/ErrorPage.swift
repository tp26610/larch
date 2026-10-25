import Foundation

/// 載入失敗的說明頁。網址與錯誤文字一律跳脫成純文字；頁面無腳本（CSP 禁止）。
enum ErrorPage {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// 取消與被轉成下載的載入不算失敗。
    static func shouldShow(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return false }
        if error.domain == "WebKitErrorDomain" && error.code == 102 { return false }
        return true
    }

    static func isCertificateError(_ error: NSError) -> Bool {
        error.domain == NSURLErrorDomain && [
            NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
            NSURLErrorClientCertificateRejected,
        ].contains(error.code)
    }

    static func headline(for error: NSError) -> (title: String, detail: String) {
        if isCertificateError(error) {
            return ("Connection is not private",
                    "The site's security certificate could not be trusted. The page was blocked to protect you. This browser does not offer a way to bypass certificate errors.")
        }
        switch error.domain == NSURLErrorDomain ? error.code : 0 {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return ("Can't find the server", "The address could not be resolved. Check the spelling or your network connection.")
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            return ("Can't connect to the server", "The server refused the connection or is not running.")
        case NSURLErrorTimedOut:
            return ("The server took too long to respond", "Try again in a moment.")
        case NSURLErrorNotConnectedToInternet:
            return ("You are offline", "Check your internet connection.")
        default:
            return ("Can't open this page", "The page failed to load.")
        }
    }

    static func html(for error: NSError, url: URL?) -> String {
        let (title, detail) = headline(for: error)
        let urlText = escape(url?.absoluteString ?? "")
        let retry = url.map { "<p><a href=\"\(escape($0.absoluteString))\">Try Again</a></p>" } ?? ""
        let tech = escape("\(error.localizedDescription) (\(error.domain) \(error.code))")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <title>\(escape(title))</title>
        <style>
        body{font:15px/1.5 -apple-system,sans-serif;background:#15161a;color:#e6e7ea;margin:0;display:grid;place-items:center;height:100vh}
        main{max-width:520px;padding:24px}h1{font-size:22px;margin:0 0 8px}.u{color:#8b90a0;word-break:break-all}
        a{color:#7aa2ff}.t{color:#8b90a0;font-size:12px;margin-top:24px}
        </style></head><body><main>
        <h1>\(escape(title))</h1><p>\(escape(detail))</p><p class="u">\(urlText)</p>\(retry)<p class="t">\(tech)</p>
        </main></body></html>
        """
    }
}
