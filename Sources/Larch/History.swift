import Foundation

struct HistoryEntry: Codable, Equatable {
    var url: String
    var title: String
    var visitedAt: Double
}

private struct HistoryFile: Codable {
    var version = 1
    var entries: [HistoryEntry]
}

/// 瀏覽歷史：本機 JSON，上限 3000 筆、超過裁到 2500（沿用 Electron 版）。尚無 UI，之後給 Command Palette 用。
@MainActor
final class HistoryStore {
    static let fileName = "history.json"
    static let limit = 3000
    static let trimTo = 2500

    private let storage: Storage
    private let saver = Debouncer(delay: 2)
    /// 舊的在前、新的在後。
    private(set) var entries: [HistoryEntry]

    init(storage: Storage) {
        self.storage = storage
        let loaded = storage.read(Self.fileName, as: HistoryFile.self)
        entries = (loaded?.version == 1 ? loaded?.entries : nil)?.filter { InputNormalizer.isHTTP(URL(string: $0.url)) } ?? []
    }

    func record(url: URL, title: String, at date: Date = Date()) {
        guard InputNormalizer.isHTTP(url) else { return }
        let entry = HistoryEntry(url: url.absoluteString, title: title, visitedAt: date.timeIntervalSince1970)
        if let last = entries.last, last.url == entry.url {
            entries[entries.count - 1] = entry
        } else {
            entries.append(entry)
        }
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.trimTo) }
        saver.schedule { [weak self] in self?.save() }
    }

    /// 標題或網址包含所有關鍵字（不分大小寫），新的在前。
    func search(_ query: String, limit: Int = 50) -> [HistoryEntry] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        var out: [HistoryEntry] = []
        for e in entries.reversed() {
            let hay = (e.title + " " + e.url).lowercased()
            if terms.allSatisfy({ hay.contains($0) }) { out.append(e) }
            if out.count >= limit { break }
        }
        return out
    }

    func save() {
        storage.write(Self.fileName, HistoryFile(entries: entries))
    }

    func flush() {
        saver.flush { save() }
    }
}
