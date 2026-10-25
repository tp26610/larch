import Foundation

/// 覆蓋層裡的一列。標題與副標一律當純文字顯示。
struct PaletteItem {
    enum Kind { case openOrSearch, tab, pin, history, action }
    enum Action {
        case open(URL)
        case switchTab(Tab)
        case activatePin(UUID)
        case runAction(String)
    }
    let kind: Kind
    let title: String
    let subtitle: String
    let action: Action
    var shortcut: String? = nil

    /// 右側的類型標籤。
    var badge: String {
        switch kind {
        case .openOrSearch: return "Open"
        case .tab: return "Tab"
        case .pin: return "Pinned"
        case .history: return "History"
        case .action: return "Action"
        }
    }
}

/// 覆蓋層模式。之後的 Ctrl+Tab MRU 切換器可在這裡加 `.switcher`（延遲顯示、放開 Ctrl 確認、不顯示輸入框）。
enum PaletteMode { case normal, actions }

/// 依輸入組出候選列：開啟/搜尋、已開啟的 Tab、歷史。純函式式，方便測試與日後擴充動作、Tab 切換器。
@MainActor
enum PaletteSearch {
    static let maxTabs = 20
    static let maxHistory = 6

    /// 動作模式：只列動作（可用的），以標題與關鍵字比對；空查詢依動作表順序。
    static func actionResults(for query: String, controller: BrowserWindowController) -> [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var scored: [(Double, Int, PaletteAction)] = []
        for (i, a) in PaletteActions.all.enumerated() where a.isAvailable(controller) {
            let t = a.title(controller)
            let s = q.isEmpty ? 0 : max(Double(Fuzzy.score(query: q, in: t)), 0.6 * Double(Fuzzy.score(query: q, in: a.keywords)))
            if s >= 0 { scored.append((s, i, a)) }
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
        return scored.map { _, _, a in
            PaletteItem(kind: .action, title: a.title(controller), subtitle: "", action: .runAction(a.id), shortcut: a.shortcut)
        }
    }

    static func results(for query: String, tabs: [Tab], history: HistoryStore?, pins: [PinNode] = []) -> [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [PaletteItem] = []

        if let input = InputNormalizer.normalize(q) {
            let label = input.kind == .url ? "Open" : "Search"
            items.append(PaletteItem(kind: .openOrSearch, title: "\(label): \(q)", subtitle: input.kind == .url ? input.url.absoluteString : "Search with Google", action: .open(input.url)))
        }

        var openURLs = Set<String>()
        var scoredTabs: [(Int, Int, Tab)] = []
        // 最近使用的在前；模糊分數加上一點近用加成（對應 Electron 版的 recency bonus）。
        let byRecency = tabs.enumerated().sorted { $0.element.lastActiveAt > $1.element.lastActiveAt }
        for (rank, entry) in byRecency.enumerated() {
            let tab = entry.element
            if let u = tab.displayURL?.absoluteString { openURLs.insert(u) }
            let s = Fuzzy.score(query: q, in: tab.displayTitle + " " + (tab.displayURL?.absoluteString ?? ""))
            if s >= 0 { scoredTabs.append((q.isEmpty ? 0 : s, rank, tab)) }
        }
        scoredTabs.sort { $0.0 + max(0, 8 - $0.1) != $1.0 + max(0, 8 - $1.1) ? $0.0 + max(0, 8 - $0.1) > $1.0 + max(0, 8 - $1.1) : $0.1 < $1.1 }
        for (_, _, tab) in scoredTabs.prefix(maxTabs) {
            items.append(PaletteItem(kind: .tab, title: tab.displayTitle, subtitle: tab.displayURL?.absoluteString ?? "", action: .switchTab(tab)))
        }

        // 已關閉（灰色）的釘選項目：選取會用記住的網址重新開啟。
        var scoredPins: [(Int, Int, PinNode)] = []
        for (i, n) in pins.enumerated() {
            if let u = n.url { openURLs.insert(u) }
            let s = Fuzzy.score(query: q, in: n.title + " " + (n.url ?? ""))
            if s >= 0 { scoredPins.append((s, i, n)) }
        }
        scoredPins.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
        for (_, _, n) in scoredPins.prefix(maxTabs) {
            items.append(PaletteItem(kind: .pin, title: n.title, subtitle: n.url ?? "", action: .activatePin(n.id)))
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
