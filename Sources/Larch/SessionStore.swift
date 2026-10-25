import Foundation

/// 重開後還原 Tab：順序、自訂名稱、目前選中的 Tab。只存 http(s)。
struct SessionSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var url: String
        var customTitle: String?
    }
    var version = 1
    var tabs: [Entry]
    var active: Int
}

enum SessionStore {
    static let fileName = "session.json"

    static func load(_ storage: Storage) -> SessionSnapshot? {
        guard var snap = storage.read(fileName, as: SessionSnapshot.self), snap.version == 1 else { return nil }
        snap.tabs = snap.tabs.filter { InputNormalizer.isHTTP(URL(string: $0.url)) }
        guard !snap.tabs.isEmpty else { return nil }
        snap.active = min(max(0, snap.active), snap.tabs.count - 1)
        return snap
    }

    @MainActor
    static func snapshot(of tabs: TabManager) -> SessionSnapshot {
        var entries: [SessionSnapshot.Entry] = []
        var active = 0
        for tab in tabs.tabs {
            guard let url = tab.displayURL, InputNormalizer.isHTTP(url) else { continue }
            if tab === tabs.activeTab { active = entries.count }
            entries.append(.init(url: url.absoluteString, customTitle: tab.customTitle))
        }
        return SessionSnapshot(tabs: entries, active: active)
    }
}
