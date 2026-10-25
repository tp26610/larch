import AppKit
import WebKit

struct ClosedTab: Equatable {
    let url: URL
    let customTitle: String?
    var pinID: UUID?
}

@MainActor
final class TabManager {
    static let maxClosed = 25

    let configuration: WKWebViewConfiguration
    let downloads: DownloadManager
    let zoom: ZoomStore
    let history: HistoryStore?
    let pins: PinStore
    private(set) var tabs: [Tab] = []
    private(set) var activeTab: Tab?
    private(set) var closedStack: [ClosedTab] = []

    /// 分頁清單增減。
    var onStructureChange: (() -> Void)?
    /// 目前分頁換了。
    var onActiveChange: (() -> Void)?
    /// 某個分頁的標題、網址、載入狀態等有變。
    var onTabChange: ((Tab) -> Void)?

    init(dataStore: WKWebsiteDataStore, downloads: DownloadManager? = nil, zoom: ZoomStore? = nil, history: HistoryStore? = nil, pins: PinStore? = nil) {
        self.history = history
        self.pins = pins ?? PinStore()
        self.zoom = zoom ?? ZoomStore()
        self.downloads = downloads ?? DownloadManager()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.preferences.isElementFullscreenEnabled = true
        configuration = config
    }

    @discardableResult
    func newTab(url: URL? = nil, customTitle: String? = nil, activate: Bool = true,
                popupConfiguration: WKWebViewConfiguration? = nil, after opener: Tab? = nil, pinID: UUID? = nil) -> Tab {
        let tab = makeTab(configuration: popupConfiguration)
        tab.pinID = pinID
        tab.customTitle = customTitle
        attach(tab)
        if let opener, let i = tabs.firstIndex(where: { $0 === opener }) { tabs.insert(tab, at: i + 1) } else { tabs.append(tab) }
        onStructureChange?()
        if let url { tab.load(url) }
        if activate || activeTab == nil { select(tab) }
        return tab
    }

    /// 建立 Tab 但不放進清單（Little 視窗用）：共用 data store、下載、縮放，瀏覽會寫入歷史。
    func makeTab(configuration: WKWebViewConfiguration? = nil) -> Tab {
        let tab = Tab(configuration: configuration ?? self.configuration)
        tab.downloads = downloads
        tab.zoomStore = zoom
        tab.onVisit = { [weak self] url, title in self?.history?.record(url: url, title: title) }
        tab.onOptionClick = { [weak self] url in self?.onOpenLittle?(url) }
        return tab
    }

    /// 接上「屬於主視窗清單」的回呼。
    private func attach(_ tab: Tab) {
        tab.popupInPlace = false
        tab.onChange = { [weak self] in self?.onTabChange?($0) }
        tab.onPopup = { [weak self] config, opener in self?.newTab(popupConfiguration: config, after: opener) }
        tab.onRequestClose = { [weak self] tab in self?.close(tab) }
        tab.onOptionClick = { [weak self] url in self?.onOpenLittle?(url) }
    }

    /// 把別處（Little 視窗）的 Tab 原封不動收進清單：同一個 WKWebView，不重新載入；插在目前 Tab 之後並選中。
    @discardableResult
    func adopt(_ tab: Tab) -> Tab {
        tab.webView.removeFromSuperview()
        attach(tab)
        if let active = activeTab, let i = tabs.firstIndex(where: { $0 === active }) { tabs.insert(tab, at: i + 1) } else { tabs.append(tab) }
        onStructureChange?()
        select(tab)
        return tab
    }

    /// Option+點連結要開 Little 視窗（由 controller 接）。
    var onOpenLittle: ((URL) -> Void)?

    private var mruCounter = 0

    /// 標記為最近使用。
    private func stamp(_ tab: Tab) {
        mruCounter += 1
        tab.mruSeq = mruCounter
    }

    /// 已開啟的 Tab（含釘選中開著的），最近使用的在前；沒用過的依清單順序排在後面。
    var mruTabs: [Tab] {
        tabs.enumerated().sorted { $0.element.mruSeq != $1.element.mruSeq ? $0.element.mruSeq > $1.element.mruSeq : $0.offset < $1.offset }.map(\.element)
    }

    func select(_ tab: Tab) {
        guard tabs.contains(where: { $0 === tab }), activeTab !== tab else { return }
        activeTab = tab
        stamp(tab)
        onActiveChange?()
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        if let url = tab.displayURL, InputNormalizer.isHTTP(url) {
            closedStack.append(ClosedTab(url: url, customTitle: tab.customTitle, pinID: tab.pinID))
            if closedStack.count > Self.maxClosed { closedStack.removeFirst(closedStack.count - Self.maxClosed) }
        }
        tabs.remove(at: index)
        tab.teardown()
        if activeTab === tab {
            activeTab = nil
            if let back = tab.opener, tabs.contains(where: { $0 === back }) {
                activeTab = back
            } else if let next = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)] {
                activeTab = next
            }
        }
        if let active = activeTab { stamp(active) } // 關閉後切到的 Tab 算最近使用
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
        let pin = closed.pinID.flatMap { id in pins.find(id) != nil && liveTab(forPin: id) == nil ? id : nil }
        return newTab(url: closed.url, customTitle: closed.customTitle, pinID: pin)
    }

    // MARK: 釘選

    func liveTab(forPin id: UUID) -> Tab? { tabs.first { $0.pinID == id } }

    /// 點釘選的項目：已開著就切過去，否則用記住的網址開新 Tab 並綁定。
    @discardableResult
    func activatePin(_ node: PinNode) -> Tab? {
        if let live = liveTab(forPin: node.id) { select(live); return live }
        guard !node.isFolder, let url = node.url.flatMap(URL.init(string:)) else { return nil }
        return newTab(url: url, pinID: node.id)
    }

    /// 把 Tab 釘到指定資料夾（nil = 最上層）。空白或非 http(s) 的 Tab 不能釘。
    @discardableResult
    func pin(_ tab: Tab, parent: UUID? = nil, index: Int? = nil) -> PinNode? {
        guard tab.pinID == nil, let url = tab.displayURL, InputNormalizer.isHTTP(url) else { return nil }
        let title = tab.customTitle ?? (tab.pageTitle.isEmpty ? (url.host ?? url.absoluteString) : tab.pageTitle)
        let node = pins.addTab(url: url, title: title, parent: parent, index: index)
        tab.pinID = node.id
        onStructureChange?()
        return node
    }

    /// 取消釘選：開著的 Tab 變回一般 Tab（排在一般區最前），灰色的則直接移除。
    func unpin(_ node: PinNode) {
        guard pins.remove(node.id) != nil else { return }
        if let live = liveTab(forPin: node.id) {
            live.pinID = nil
            if let i = tabs.firstIndex(where: { $0 === live }) {
                tabs.remove(at: i)
                let first = tabs.firstIndex { $0.pinID == nil } ?? tabs.count
                tabs.insert(live, at: first)
            }
        }
        onStructureChange?()
    }

    func togglePin(_ tab: Tab) {
        if let id = tab.pinID, let node = pins.find(id)?.node { unpin(node) } else { pin(tab) }
    }

    /// 在一般區重排：放到指定一般 Tab 之前（nil = 最後）。
    func moveTab(_ tab: Tab, before target: Tab?) {
        guard tab !== target, let from = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs.remove(at: from)
        if let target, let to = tabs.firstIndex(where: { $0 === target }) { tabs.insert(tab, at: to) } else { tabs.append(tab) }
        onStructureChange?()
    }
}
