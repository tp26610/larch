import Foundation

/// 把使用者輸入轉成可載入的網址（邏輯對應 my-browser 的 util.js normalizeInput）。
enum InputKind { case url, search }

struct NormalizedInput: Equatable {
    let url: URL
    let kind: InputKind
}

enum InputNormalizer {
    static let searchPrefix = "https://www.google.com/search?q="

    private static let schemeRe = try! Regex(#"^[a-z][a-z0-9+.-]*://"#).ignoresCase()
    private static let localRe = try! Regex(#"^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?([/?#].*)?$"#).ignoresCase()
    private static let hostRe = try! Regex(#"^[^\s/?#]+\.[a-z]{2,}(:\d+)?([/?#].*)?$"#).ignoresCase()

    static func isHTTP(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// 空字串或不允許的 scheme（file:、javascript: ...）回傳 nil。
    static func normalize(_ text: String) -> NormalizedInput? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }

        if t.firstMatch(of: schemeRe) != nil {
            guard let u = URL(string: t), isHTTP(u) else { return nil }
            return NormalizedInput(url: u, kind: .url)
        }
        if t.wholeMatch(of: localRe) != nil, let u = URL(string: "http://\(t)") {
            return NormalizedInput(url: u, kind: .url)
        }
        if !t.contains(where: \.isWhitespace), t.wholeMatch(of: hostRe) != nil, let u = URL(string: "https://\(t)") {
            return NormalizedInput(url: u, kind: .url)
        }
        let q = t.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? t
        return URL(string: searchPrefix + q).map { NormalizedInput(url: $0, kind: .search) }
    }
}
