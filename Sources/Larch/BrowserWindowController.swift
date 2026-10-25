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
        tabs = TabManager(dataStore: dataStore, downloads: downloads, zoom: zoom, history: HistoryStore(storage: storage), pins: PinStore(storage: storage))
        window = LarchWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "Larch"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
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
        sidebar.newTabButton.action = #selector(showPalette)

        sidebar.downloadButton.target = self
        sidebar.downloadButton.action = #selector(downloadClicked)
        root.palette.provider = { [weak self] q in
            guard let self else { return [] }
            return PaletteSearch.results(for: q, tabs: self.tabs.tabs, history: self.tabs.history,
                                         pins: self.tabs.pins.allTabs.filter { self.tabs.liveTab(forPin: $0.id) == nil })
        }
        root.palette.onPick = { [weak self] item in self?.pick(item) }
        root.palette.onDismiss = { [weak self] in self?.paletteDismissed() }
        tabs.downloads.onChange = { [weak self] in self?.sidebar.showDownload($0) }
        tabs.onStructureChange = { [weak self] in self?.rebuildRows() }
        tabs.pins.onChange = { [weak self] in self?.rebuildRows() }
        sidebar.onResolveDrop = { [weak self] dragged, over, f in self?.resolveDrop(dragged, over: over, fraction: f) }
        sidebar.setBackgroundMenu(makeBackgroundMenu())
        tabs.onActiveChange = { [weak self] in self?.activeChanged() }
        tabs.onTabChange = { [weak self] in self?.tabChanged($0) }
        root.onSidebarVisibilityChange = { [weak self] _ in self?.syncTrafficLights() }
        root.onCornerHover = { [weak self] in self?.cornerHover = $0; self?.syncTrafficLights() }
        syncTrafficLights(animated: false)
        restoreSession()
        window.makeKeyAndOrderFront(nil)
        focusAddress()
    }

    // MARK: 紅綠燈

    private var cornerHover = false

    /// 側邊欄顯示時一直顯示；隱藏時只有滑鼠在左上角感應區才顯示。
    func syncTrafficLights(animated: Bool = true) {
        (window as? LarchWindow)?.setTrafficLights(visible: root.sidebarVisible || cornerHover, animated: animated)
    }

    func windowDidEnterFullScreen(_ notification: Notification) { syncTrafficLights(animated: false) }
    func windowDidExitFullScreen(_ notification: Notification) { syncTrafficLights(animated: false) }

    // MARK: Session

    private func restoreSession() {
        restoring = true
        defer { restoring = false }
        if let snap = SessionStore.load(storage) {
            var active: Tab?
            for (i, entry) in snap.tabs.enumerated() {
                // 釘選的 Tab 要對得上現存節點、且沒有別的 Tab 已綁定，否則當一般 Tab。
                let pinID = entry.pinID.flatMap(UUID.init(uuidString:)).flatMap { id in
                    tabs.pins.find(id)?.node.isFolder == false && tabs.liveTab(forPin: id) == nil ? id : nil
                }
                let tab = tabs.newTab(url: URL(string: entry.url), customTitle: entry.customTitle, activate: false, pinID: pinID)
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
        tabs.history?.flush()
        tabs.pins.flush()
    }

    // MARK: 同步畫面

    private func rebuildRows() {
        scheduleSessionSave()
        var live = Set(tabs.tabs.filter { $0.pinID == nil }.map(\.id))
        let visiblePins = tabs.pins.visible()
        live.formUnion(visiblePins.map(\.node.id))
        rows = rows.filter { live.contains($0.key) }
        folderRows = folderRows.filter { live.contains($0.key) }
        var ordered: [NSView] = []
        for (node, depth) in visiblePins {
            if node.isFolder {
                let row = folderRows[node.id] ?? makeFolderRow(node, depth: depth)
                row.update()
                ordered.append(row)
            } else {
                let liveTab = tabs.liveTab(forPin: node.id)
                // 層級或綁定的 Tab 變了就重建這一列（depth 是 init 參數）。
                var row = rows[node.id]
                if row == nil || row!.depth != depth { row = makePinRow(node, depth: depth) }
                row!.tab = liveTab
                row!.isActive = liveTab != nil && liveTab === tabs.activeTab
                row!.update()
                ordered.append(row!)
            }
        }
        ordered.append(DividerRowView())
        for tab in tabs.tabs where tab.pinID == nil {
            let row = rows[tab.id] ?? makeRow(tab)
            row.isActive = tab === tabs.activeTab
            ordered.append(row)
        }
        sidebar.setRows(ordered)
    }

    private var folderRows: [UUID: FolderRowView] = [:]

    private func makeRow(_ tab: Tab) -> TabRowView {
        let row = TabRowView(tab: tab)
        wire(row)
        rows[tab.id] = row
        return row
    }

    private func makePinRow(_ node: PinNode, depth: Int) -> TabRowView {
        let row = TabRowView(tab: tabs.liveTab(forPin: node.id), pin: node, depth: depth)
        wire(row)
        rows[node.id] = row
        return row
    }

    private func wire(_ row: TabRowView) {
        row.onSelect = { [weak self] row in
            guard let self else { return }
            if let pin = row.pin { self.tabs.activatePin(pin) } else if let tab = row.tab { self.tabs.select(tab) }
        }
        row.onClose = { [weak self] row in if let tab = row.tab { self?.tabs.close(tab) } }
        row.onRename = { [weak self] row, text in
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let tab = row.tab { tab.customTitle = t.isEmpty ? nil : t }
            if let pin = row.pin { self?.tabs.pins.rename(pin.id, to: t); row.update() }
        }
        row.onMenu = { [weak self] row in self?.menu(for: row) }
    }

    private func makeFolderRow(_ node: PinNode, depth: Int) -> FolderRowView {
        let row = FolderRowView(node: node, depth: depth)
        row.onToggle = { [weak self] node in self?.tabs.pins.setExpanded(node.id, !node.expanded) }
        row.onRename = { [weak self] node, text in self?.tabs.pins.rename(node.id, to: text) }
        row.onMenu = { [weak self] row in self?.menu(for: row) }
        folderRows[node.id] = row
        return row
    }

    // MARK: 釘選與資料夾的操作

    private func menuItem(_ title: String, _ sel: Selector, id: UUID? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        return item
    }

    private func menu(for row: TabRowView) -> NSMenu {
        let m = NSMenu()
        if let pin = row.pin {
            m.addItem(menuItem("Unpin", #selector(unpinClicked(_:)), id: pin.id))
            m.addItem(menuItem("Rename", #selector(renameClicked(_:)), id: pin.id))
            if row.tab != nil { m.addItem(menuItem("Close Tab", #selector(closeRowClicked(_:)), id: pin.id)) }
        } else if let tab = row.tab {
            m.addItem(menuItem("Pin Tab", #selector(pinTabClicked(_:)), id: tab.id))
            m.addItem(menuItem("Rename", #selector(renameClicked(_:)), id: tab.id))
            m.addItem(menuItem("Close Tab", #selector(closeRowClicked(_:)), id: tab.id))
        }
        m.addItem(.separator())
        m.addItem(menuItem("New Folder", #selector(newFolderClicked(_:))))
        return m
    }

    private func menu(for row: FolderRowView) -> NSMenu {
        let m = NSMenu()
        m.addItem(menuItem("Rename", #selector(renameClicked(_:)), id: row.node.id))
        m.addItem(menuItem("New Folder Inside", #selector(newFolderClicked(_:)), id: row.node.id))
        m.addItem(.separator())
        m.addItem(menuItem("Delete Folder (Keep Contents)", #selector(deleteFolderClicked(_:)), id: row.node.id))
        return m
    }

    private func makeBackgroundMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(menuItem("New Folder", #selector(newFolderClicked(_:))))
        return m
    }

    private func tab(withID id: UUID) -> Tab? { tabs.tabs.first { $0.id == id } }

    @objc private func pinTabClicked(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID, let t = tab(withID: id) { tabs.pin(t) }
    }

    @objc private func unpinClicked(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID, let n = tabs.pins.find(id)?.node { tabs.unpin(n) }
    }

    @objc private func closeRowClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if let t = tab(withID: id) ?? tabs.liveTab(forPin: id) { tabs.close(t) }
    }

    @objc private func renameClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        beginRename(id)
    }

    @objc private func deleteFolderClicked(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { tabs.pins.deleteFolder(id) }
    }

    @objc private func newFolderClicked(_ sender: NSMenuItem?) {
        _ = newFolder(inside: sender?.representedObject as? UUID)
    }

    /// 新資料夾（預設在最上層末尾）並進入改名。
    @discardableResult
    func newFolder(inside parent: UUID? = nil) -> PinNode {
        if !root.sidebarVisible { root.sidebarVisible = true }
        let node = tabs.pins.addFolder(parent: parent)
        beginRename(node.id)
        return node
    }

    @objc func newFolderAction() { newFolder() }

    @objc func togglePinAction() {
        if let tab = tabs.activeTab { tabs.togglePin(tab) }
    }

    private func beginRename(_ id: UUID) {
        if let r = folderRows[id] { r.beginRename() } else if let r = rows[id] ?? rows.values.first(where: { $0.tab?.id == id }) { r.beginRename() }
    }

    // MARK: 拖曳

    enum DropDest { case pins(parent: UUID?, index: Int), regular(before: UUID?) }

    /// 依被拖的東西與游標位置算出落點。nil = 不能放。
    func resolveDrop(_ dragged: SidebarItem, over: SidebarItem?, fraction f: CGFloat) -> DropPlan? {
        let pins = tabs.pins
        let regular = tabs.tabs.filter { $0.pinID == nil }
        var draggedFolder: PinNode?
        if case .pin(let id) = dragged, let n = pins.find(id)?.node, n.isFolder { draggedFolder = n }
        func pinsDest(parent: UUID?, index: Int, _ ind: DropPlan.Indicator) -> DropPlan? {
            if let df = draggedFolder, let parent, parent == df.id || pins.isDescendant(parent, of: df.id) { return nil }
            let d = DropDest.pins(parent: parent, index: index)
            return DropPlan(indicator: ind) { [weak self] in self?.execute(dragged, d) }
        }
        func regularDest(before: UUID?, _ ind: DropPlan.Indicator) -> DropPlan? {
            guard draggedFolder == nil else { return nil }
            let d = DropDest.regular(before: before)
            return DropPlan(indicator: ind) { [weak self] in self?.execute(dragged, d) }
        }
        switch over {
        case nil:
            return draggedFolder != nil ? pinsDest(parent: nil, index: pins.roots.count, .after) : regularDest(before: nil, .after)
        case .divider?:
            if case .tab = dragged { return pinsDest(parent: nil, index: pins.roots.count, .into) }
            if draggedFolder != nil { return pinsDest(parent: nil, index: pins.roots.count, .into) }
            return regularDest(before: regular.first?.id, .into)
        case .pin(let id)?:
            guard let loc = pins.find(id) else { return nil }
            let parentID = loc.parent?.id
            if loc.node.isFolder {
                if f < 0.25 { return pinsDest(parent: parentID, index: loc.index, .before) }
                if f > 0.75, !loc.node.expanded || loc.node.children.isEmpty { return pinsDest(parent: parentID, index: loc.index + 1, .after) }
                return pinsDest(parent: id, index: 0, .into)
            }
            return f < 0.5 ? pinsDest(parent: parentID, index: loc.index, .before) : pinsDest(parent: parentID, index: loc.index + 1, .after)
        case .tab(let id)?:
            guard let i = regular.firstIndex(where: { $0.id == id }) else { return nil }
            if f < 0.5 { return regularDest(before: id, .before) }
            return regularDest(before: i + 1 < regular.count ? regular[i + 1].id : nil, .after)
        }
    }

    func execute(_ dragged: SidebarItem, _ dest: DropDest) {
        switch (dragged, dest) {
        case (.tab(let id), .pins(let parent, let index)):
            if let t = tab(withID: id) { tabs.pin(t, parent: parent, index: index) }
        case (.tab(let id), .regular(let before)):
            if let t = tab(withID: id) { tabs.moveTab(t, before: before.flatMap(tab(withID:))) }
        case (.pin(let id), .pins(let parent, let index)):
            tabs.pins.move(id, toParent: parent, index: index)
        case (.pin(let id), .regular(let before)):
            guard let node = tabs.pins.find(id)?.node, !node.isFolder else { return }
            let target = before.flatMap(tab(withID:))
            if let live = tabs.liveTab(forPin: id) {
                tabs.unpin(node)
                tabs.moveTab(live, before: target)
            } else if let url = node.url.flatMap(URL.init(string:)) {
                // 灰色的釘選拖到一般區：以該網址開成一般 Tab。
                tabs.unpin(node)
                let t = tabs.newTab(url: url, activate: false)
                tabs.moveTab(t, before: target)
            }
        default: break
        }
    }

    private func activeChanged() {
        closeFind()
        scheduleSessionSave()
        for tab in tabs.tabs { rows[tab.pinID ?? tab.id]?.isActive = tab === tabs.activeTab }
        if let tab = tabs.activeTab {
            root.card.show(tab.webView)
            syncToolbar(tab)
            syncLoading(tab, animated: false)
            window.title = tab.displayTitle
        }
        if tabs.activeTab?.url == nil { focusAddress() } else if window.firstResponder === addressField.currentEditor() {
            window.makeFirstResponder(tabs.activeTab?.webView)
        }
    }

    private func tabChanged(_ tab: Tab) {
        scheduleSessionSave()
        rows[tab.pinID ?? tab.id]?.update()
        if let pid = tab.pinID {
            var png: Data?
            if let img = tab.favicon, let tiff = img.tiffRepresentation { png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) }
            let hasTitle = tab.customTitle?.isEmpty == false || !tab.pageTitle.isEmpty
            tabs.pins.remember(pid, title: hasTitle ? tab.displayTitle : nil, favicon: png)
        }
        if tab === tabs.activeTab {
            syncToolbar(tab)
            syncLoading(tab)
            window.title = tab.displayTitle
        }
    }

    /// 進度條與重新整理/停止按鈕只反映目前選中的 Tab。
    private func syncLoading(_ tab: Tab, animated: Bool = true) {
        root.card.loadingBar.update(loading: tab.isLoading, progress: tab.webView.estimatedProgress, animated: animated)
        sidebar.setLoading(tab.isLoading)
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

    // MARK: 命令列覆蓋層

    private weak var paletteReturnFocus: NSResponder?

    /// ⌘T / New Tab 按鈕：叫出搜尋 + 開新 Tab 的覆蓋層（已開啟時重新全選輸入）。
    @objc func showPalette() { openPalette(prefill: nil) }

    func openPalette(prefill: String?) {
        if !root.palette.isOpen {
            let r = window.firstResponder
            paletteReturnFocus = (r as? NSTextView)?.delegate as? NSResponder ?? r
        }
        root.palette.present()
        if let prefill, !prefill.isEmpty {
            root.palette.field.stringValue = prefill
            root.palette.field.currentEditor()?.selectedRange = NSRange(location: (prefill as NSString).length, length: 0)
            root.palette.refresh()
        }
    }

    private func pick(_ item: PaletteItem) {
        switch item.action {
        case .open(let url): tabs.newTab(url: url)
        case .switchTab(let tab): tabs.select(tab)
        case .activatePin(let id): if let n = tabs.pins.find(id)?.node { tabs.activatePin(n) }
        }
        window.makeFirstResponder(tabs.activeTab?.webView)
    }

    /// 取消時把焦點還給原本的位置；選取後由 pick 把焦點交給網頁。
    private func paletteDismissed() {
        if let r = paletteReturnFocus, window.firstResponder === root.palette.field.currentEditor() || window.firstResponder === window {
            window.makeFirstResponder(r)
        }
        if window.firstResponder === window || window.firstResponder == nil { window.makeFirstResponder(tabs.activeTab?.webView) }
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
    @objc func reload() {
        guard let tab = tabs.activeTab else { return }
        if tab.isLoading { tab.webView.stopLoading() } else { tab.reloadOrRetry() }
    }

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
