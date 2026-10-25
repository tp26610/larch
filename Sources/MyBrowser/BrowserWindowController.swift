import AppKit
import WebKit

/// 單一視窗：組裝側邊欄、卡片與 TabManager。
@MainActor
final class BrowserWindowController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let window: NSWindow
    let root = RootView()
    let tabs: TabManager
    private var rows: [UUID: TabRowView] = [:]
    let storage: Storage
    private let sessionSaver = Debouncer()
    private var restoring = false

    var sidebar: SidebarView { root.sidebar }
    var addressField: NSTextField { root.sidebar.addressBar.field }

    init(dataStore: WKWebsiteDataStore, storage: Storage, downloads: DownloadManager? = nil, zoom: ZoomStore? = nil, autosave: Bool) {
        self.storage = storage
        tabs = TabManager(dataStore: dataStore, downloads: downloads, zoom: zoom)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "My Browser"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.panel
        window.minSize = NSSize(width: 640, height: 400)
        window.contentView = root
        window.delegate = self
        window.center()
        if autosave { window.setFrameAutosaveName("MainWindow") }

        addressField.delegate = self
        let fb = root.findBar
        fb.field.delegate = self
        fb.nextButton.target = self; fb.nextButton.action = #selector(findNext)
        fb.prevButton.target = self; fb.prevButton.action = #selector(findPrevious)
        fb.closeButton.target = self; fb.closeButton.action = #selector(closeFind)
        sidebar.backButton.target = self
        sidebar.backButton.action = #selector(goBack)
        sidebar.forwardButton.target = self
        sidebar.forwardButton.action = #selector(goForward)
        sidebar.reloadButton.target = self
        sidebar.reloadButton.action = #selector(reload)
        sidebar.newTabButton.target = self
        sidebar.newTabButton.action = #selector(newTab)

        sidebar.downloadButton.target = self
        sidebar.downloadButton.action = #selector(downloadClicked)
        tabs.downloads.onChange = { [weak self] in self?.sidebar.showDownload($0) }
        tabs.onStructureChange = { [weak self] in self?.rebuildRows() }
        tabs.onActiveChange = { [weak self] in self?.activeChanged() }
        tabs.onTabChange = { [weak self] in self?.tabChanged($0) }
        restoreSession()
        window.makeKeyAndOrderFront(nil)
        focusAddress()
    }

    // MARK: Session

    private func restoreSession() {
        restoring = true
        defer { restoring = false }
        if let snap = SessionStore.load(storage) {
            var active: Tab?
            for (i, entry) in snap.tabs.enumerated() {
                let tab = tabs.newTab(url: URL(string: entry.url), customTitle: entry.customTitle, activate: false)
                if i == snap.active { active = tab }
            }
            if let active { tabs.select(active) }
        } else {
            tabs.newTab()
        }
    }

    private func scheduleSessionSave() {
        guard !restoring else { return }
        sessionSaver.schedule { [weak self] in self?.saveSession() }
    }

    private func saveSession() {
        storage.write(SessionStore.fileName, SessionStore.snapshot(of: tabs))
    }

    /// 結束前把尚未寫出的狀態存檔。
    func flushPersistence() {
        sessionSaver.flush { saveSession() }
    }

    // MARK: 同步畫面

    private func rebuildRows() {
        scheduleSessionSave()
        let live = Set(tabs.tabs.map(\.id))
        rows = rows.filter { live.contains($0.key) }
        var ordered: [TabRowView] = []
        for tab in tabs.tabs {
            let row = rows[tab.id] ?? makeRow(tab)
            row.isActive = tab === tabs.activeTab
            ordered.append(row)
        }
        sidebar.setRows(ordered)
    }

    private func makeRow(_ tab: Tab) -> TabRowView {
        let row = TabRowView(tab: tab)
        row.onSelect = { [weak self] in self?.tabs.select($0) }
        row.onClose = { [weak self] in self?.tabs.close($0) }
        row.onRename = { tab, text in
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            tab.customTitle = t.isEmpty ? nil : t
        }
        rows[tab.id] = row
        return row
    }

    private func activeChanged() {
        closeFind()
        scheduleSessionSave()
        for tab in tabs.tabs { rows[tab.id]?.isActive = tab === tabs.activeTab }
        if let tab = tabs.activeTab {
            root.card.show(tab.webView)
            syncToolbar(tab)
            window.title = tab.displayTitle
        }
        if tabs.activeTab?.url == nil { focusAddress() } else if window.firstResponder === addressField.currentEditor() {
            window.makeFirstResponder(tabs.activeTab?.webView)
        }
    }

    private func tabChanged(_ tab: Tab) {
        scheduleSessionSave()
        rows[tab.id]?.update()
        if tab === tabs.activeTab {
            syncToolbar(tab)
            window.title = tab.displayTitle
        }
    }

    private func syncToolbar(_ tab: Tab) {
        sidebar.backButton.isEnabled = tab.webView.canGoBack
        sidebar.forwardButton.isEnabled = tab.webView.canGoForward
        if addressField.currentEditor() == nil {
            addressField.stringValue = tab.displayURL?.absoluteString ?? ""
        }
    }

    // MARK: 動作

    // MARK: 尋找與縮放

    @objc func showFind() {
        root.findBar.isHidden = false
        window.makeFirstResponder(root.findBar.field)
        root.findBar.field.currentEditor()?.selectAll(nil)
    }

    @objc func closeFind() {
        guard !root.findBar.isHidden else { return }
        root.findBar.isHidden = true
        root.findBar.status.stringValue = ""
        tabs.activeTab?.webView.evaluateJavaScript("getSelection().removeAllRanges()", completionHandler: nil)
        if root.findBar.field.currentEditor() != nil { window.makeFirstResponder(tabs.activeTab?.webView) }
    }

    @objc func findNext() { Task { await find(backwards: false) } }
    @objc func findPrevious() { Task { await find(backwards: true) } }
    @objc func findMenuNext() { if root.findBar.isHidden { showFind() } else { findNext() } }
    @objc func findMenuPrevious() { if root.findBar.isHidden { showFind() } else { findPrevious() } }

    /// 在目前網頁找字，回傳是否找到（會捲動並反白）。
    @discardableResult
    func find(_ text: String? = nil, backwards: Bool) async -> Bool {
        let query = text ?? root.findBar.field.stringValue
        guard let web = tabs.activeTab?.webView, !query.isEmpty else {
            root.findBar.status.stringValue = ""
            return false
        }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        let found = (try? await web.find(query, configuration: config))?.matchFound ?? false
        root.findBar.status.stringValue = found ? "" : "No matches"
        return found
    }

    func zoom(direction: Int) {
        guard let tab = tabs.activeTab, let host = tab.url?.host, InputNormalizer.isHTTP(tab.url) else { return }
        let next = direction == 0 ? 1 : tabs.zoom.step(from: tab.webView.pageZoom, direction: direction)
        tabs.zoom.set(next, for: host)
        for other in tabs.tabs where other.url?.host?.lowercased() == host.lowercased() { other.webView.pageZoom = next }
    }

    @objc func zoomIn() { zoom(direction: 1) }
    @objc func zoomOut() { zoom(direction: -1) }
    @objc func zoomReset() { zoom(direction: 0) }

    @objc func downloadClicked() {
        tabs.downloads.revealLatest()
        if case .finished? = tabs.downloads.latest?.state { tabs.downloads.dismiss() }
    }

    @objc func newTab() {
        tabs.newTab()
    }

    @objc func closeCurrentTab() {
        if let tab = tabs.activeTab { tabs.close(tab) }
    }

    /// 外部要求開啟（預設瀏覽器的連結、.html 檔）：一律新開 Tab，不取代現有分頁。
    func openExternal(_ urls: [URL]) {
        for url in urls {
            if InputNormalizer.isHTTP(url) {
                tabs.newTab(url: url)
            } else if url.isFileURL, ["html", "htm"].contains(url.pathExtension.lowercased()) {
                tabs.newTab().loadFile(url)
            }
        }
        window.makeKeyAndOrderFront(nil)
    }

    @objc func restoreTab() {
        tabs.restoreLast()
    }

    @objc func goBack() { tabs.activeTab?.webView.goBack() }
    @objc func goForward() { tabs.activeTab?.webView.goForward() }
    @objc func reload() { tabs.activeTab?.reloadOrRetry() }

    @objc func toggleSidebar() {
        root.sidebarVisible.toggle()
        if !root.sidebarVisible, window.firstResponder === addressField.currentEditor() {
            window.makeFirstResponder(tabs.activeTab?.webView)
        }
    }

    @objc func focusAddress() {
        if !root.sidebarVisible { root.sidebarVisible = true }
        window.makeFirstResponder(addressField)
        addressField.currentEditor()?.selectAll(nil)
    }

    @objc func copyURL() {
        guard let url = tabs.activeTab?.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    /// 網址列 Enter。成功回傳 true。
    @discardableResult
    func submitAddress(_ text: String) -> Bool {
        guard let input = InputNormalizer.normalize(text) else {
            NSSound.beep()
            return false
        }
        if tabs.activeTab == nil { tabs.newTab() }
        tabs.activeTab?.load(input.url)
        window.makeFirstResponder(tabs.activeTab?.webView)
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === root.findBar.field { Task { await find(backwards: false) } }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === root.findBar.field {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                Task { await find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true) }
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) { closeFind(); return true }
            return false
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            submitAddress(addressField.stringValue)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if let tab = tabs.activeTab {
                addressField.stringValue = tab.displayURL?.absoluteString ?? ""
                window.makeFirstResponder(tab.webView)
            }
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let tab = tabs.activeTab { syncToolbar(tab) }
    }
}
