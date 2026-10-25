import AppKit
import WebKit

/// 單一視窗：組裝側邊欄、卡片與 TabManager。
@MainActor
final class BrowserWindowController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let window: NSWindow
    let root = RootView()
    let tabs: TabManager
    private var rows: [UUID: TabRowView] = [:]

    var sidebar: SidebarView { root.sidebar }
    var addressField: NSTextField { root.sidebar.addressBar.field }

    init(dataStore: WKWebsiteDataStore, autosave: Bool) {
        tabs = TabManager(dataStore: dataStore)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
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
        sidebar.backButton.target = self
        sidebar.backButton.action = #selector(goBack)
        sidebar.forwardButton.target = self
        sidebar.forwardButton.action = #selector(goForward)
        sidebar.reloadButton.target = self
        sidebar.reloadButton.action = #selector(reload)
        sidebar.newTabButton.target = self
        sidebar.newTabButton.action = #selector(newTab)

        tabs.onStructureChange = { [weak self] in self?.rebuildRows() }
        tabs.onActiveChange = { [weak self] in self?.activeChanged() }
        tabs.onTabChange = { [weak self] in self?.tabChanged($0) }
        tabs.newTab()
        window.makeKeyAndOrderFront(nil)
        focusAddress()
    }

    // MARK: 同步畫面

    private func rebuildRows() {
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
            addressField.stringValue = tab.url?.absoluteString ?? ""
        }
    }

    // MARK: 動作

    @objc func newTab() {
        tabs.newTab()
    }

    @objc func closeCurrentTab() {
        if let tab = tabs.activeTab { tabs.close(tab) }
    }

    @objc func restoreTab() {
        tabs.restoreLast()
    }

    @objc func goBack() { tabs.activeTab?.webView.goBack() }
    @objc func goForward() { tabs.activeTab?.webView.goForward() }
    @objc func reload() { tabs.activeTab?.webView.reload() }

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

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            submitAddress(addressField.stringValue)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if let tab = tabs.activeTab {
                addressField.stringValue = tab.url?.absoluteString ?? ""
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
