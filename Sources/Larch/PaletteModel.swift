import Foundation

/// 覆蓋層裡的一列。標題與副標一律當純文字顯示。
struct PaletteItem {
    enum Kind { case openOrSearch, tab, history }
    enum Action {
        case open(URL)
        case switchTab(Tab)
    }
    let kind: Kind
    let title: String
    let subtitle: String
    let action: Action
}

/// 依輸入組出候選列：開啟/搜尋、已開啟的 Tab、歷史。純函式式，方便測試與日後擴充動作、Tab 切換器。
@MainActor
enum PaletteSearch {
    static let maxTabs = 8
    static let maxHistory = 6

    static func results(for query: String, tabs: [Tab], history: HistoryStore?) -> [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [PaletteItem] = []

        if let input = InputNormalizer.normalize(q) {
            let label = input.kind == .url ? "Open" : "Search"
            items.append(PaletteItem(kind: .openOrSearch, title: "\(label): \(q)", subtitle: input.kind == .url ? input.url.absoluteString : "Search with Google", action: .open(input.url)))
        }

        var openURLs = Set<String>()
        var scoredTabs: [(Int, Int, Tab)] = []
        for (i, tab) in tabs.enumerated() {
            if let u = tab.displayURL?.absoluteString { openURLs.insert(u) }
            let s = Fuzzy.score(query: q, in: tab.displayTitle + " " + (tab.displayURL?.absoluteString ?? ""))
            if s >= 0 { scoredTabs.append((s, i, tab)) }
        }
        scoredTabs.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
        for (_, _, tab) in scoredTabs.prefix(maxTabs) {
            items.append(PaletteItem(kind: .tab, title: tab.displayTitle, subtitle: tab.displayURL?.absoluteString ?? "", action: .switchTab(tab)))
        }

        // 沒輸入時不列歷史（只列 Tab）。已開啟的網址不重複出現。
        if !q.isEmpty, let history {
            var seen = openURLs
            var scored: [(Int, Int, HistoryEntry)] = []
            for (i, e) in history.entries.enumerated().reversed() {
                guard !seen.contains(e.url) else { continue }
                let s = Fuzzy.score(query: q, in: e.title + " " + e.url)
                if s >= 0 { seen.insert(e.url); scored.append((s, i, e)) }
            }
            scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 > $1.1 }
            for (_, _, e) in scored.prefix(maxHistory) {
                guard let url = URL(string: e.url) else { continue }
                items.append(PaletteItem(kind: .history, title: e.title.isEmpty ? e.url : e.title, subtitle: e.url, action: .open(url)))
            }
        }
        return items
    }
}
