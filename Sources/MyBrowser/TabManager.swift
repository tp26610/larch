import AppKit
import WebKit

struct ClosedTab: Equatable {
    let url: URL
    let customTitle: String?
}

@MainActor
final class TabManager {
    static let maxClosed = 25

    let configuration: WKWebViewConfiguration
    private(set) var tabs: [Tab] = []
    private(set) var activeTab: Tab?
    private(set) var closedStack: [ClosedTab] = []

    /// 分頁清單增減。
    var onStructureChange: (() -> Void)?
    /// 目前分頁換了。
    var onActiveChange: (() -> Void)?
    /// 某個分頁的標題、網址、載入狀態等有變。
    var onTabChange: ((Tab) -> Void)?

    init(dataStore: WKWebsiteDataStore) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.preferences.isElementFullscreenEnabled = true
        configuration = config
    }

    @discardableResult
    func newTab(url: URL? = nil, customTitle: String? = nil, activate: Bool = true) -> Tab {
        let tab = Tab(configuration: configuration)
        tab.customTitle = customTitle
        tab.onChange = { [weak self] in self?.onTabChange?($0) }
        tabs.append(tab)
        onStructureChange?()
        if let url { tab.load(url) }
        if activate || activeTab == nil { select(tab) }
        return tab
    }

    func select(_ tab: Tab) {
        guard tabs.contains(where: { $0 === tab }), activeTab !== tab else { return }
        activeTab = tab
        onActiveChange?()
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        if let url = tab.displayURL, InputNormalizer.isHTTP(url) {
            closedStack.append(ClosedTab(url: url, customTitle: tab.customTitle))
            if closedStack.count > Self.maxClosed { closedStack.removeFirst(closedStack.count - Self.maxClosed) }
        }
        tabs.remove(at: index)
        tab.teardown()
        if activeTab === tab {
            activeTab = nil
            if let next = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)] {
                activeTab = next
            }
        }
        onStructureChange?()
        if tabs.isEmpty {
            newTab()
        } else {
            onActiveChange?()
        }
    }

    @discardableResult
    func restoreLast() -> Tab? {
        guard let closed = closedStack.popLast() else { return nil }
        return newTab(url: closed.url, customTitle: closed.customTitle)
    }
}
