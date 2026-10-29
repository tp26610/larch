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
    let prefs: Preferences
    private let sessionSaver = Debouncer()
    private var restoring = false

    var sidebar: SidebarView { root.sidebar }
    var addressField: NSTextField { root.sidebar.addressBar.field }

    init(dataStore: WKWebsiteDataStore, storage: Storage, downloads: DownloadManager? = nil, zoom: ZoomStore? = nil, prefs: Preferences = Preferences(), autosave: Bool) {
        self.prefs = prefs
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
        root.palette.provider = { [weak self] q, mode in
            guard let self else { return [] }
            if mode == .actions { return PaletteSearch.actionResults(for: q, controller: self) }
            return PaletteSearch.results(for: q, tabs: self.tabs.tabs, history: self.tabs.history,
                                         pins: self.tabs.pins.allTabs.filter { self.tabs.liveTab(forPin: $0.id) == nil })
        }
        root.palette.onPick = { [weak self] item in self?.pick(item) }
        root.palette.onDismiss = { [weak self] in self?.paletteDismissed() }
        tabs.downloads.onChange = { [weak self] in self?.sidebar.showDownload($0) }
        tabs.onOpenLittle = { [weak self] in self?.openLittle($0) }
        tabs.onStructureChange = { [weak self] in self?.rebuildRows() }
        tabs.pins.onChange = { [weak self] in self?.rebuildRows() }
        sidebar.onResolveDrop = { [weak self] dragged, over, f in self?.resolveDrop(dragged, over: over, fraction: f) }
        sidebar.setBackgroundMenu(makeBackgroundMenu())
        tabs.onActiveChange = { [weak self] in self?.activeChanged() }
        tabs.onTabChange = { [weak self] in self?.tabChanged($0) }
        (window as? LarchWindow)?.keyHandler = { [weak self] event in self?.switcher.handle(event) ?? false }
        root.onSidebarVisibilityChange = { [weak self] _ in self?.syncTrafficLights() }
        root.onCornerHover = { [weak self] in self?.cornerHover = $0; self?.syncTrafficLights() }
        root.sidebarWidth = prefs.sidebarWidth
        root.onSidebarWidthChange = { [weak self] in self?.prefs.sidebarWidth = $0 }
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

    lazy var switcher = TabSwitcher(controller: self)

    func windowDidResignKey(_ notification: Notification) { switcher.resignKey() }

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
        closeAllLittles()
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
        var handledSplit = Set<UUID>()
        for tab in tabs.tabs where tab.pinID == nil {
            if handledSplit.contains(tab.id) { continue }
            let row = rows[tab.id] ?? makeRow(tab)
            row.isActive = tab === tabs.activeTab
            if let partner = tab.splitPartner {
                // Split View 配對：兩個一般 Tab 並排顯示成一列，左右順序跟卡片一致（依 tabs 清單順序）。
                let partnerRow = rows[partner.id] ?? makeRow(partner)
                partnerRow.isActive = partner === tabs.activeTab
                handledSplit.insert(partner.id)
                let tabIsLeft = (tabs.tabs.firstIndex { $0 === tab } ?? 0) < (tabs.tabs.firstIndex { $0 === partner } ?? 0)
                ordered.append(SplitPairRowView(left: tabIsLeft ? row : partnerRow, right: tabIsLeft ? partnerRow : row))
            } else {
                ordered.append(row)
            }
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
        row.onClose = { [weak self] row in
            if let tab = row.tab { self?.tabs.close(tab) } else if let pin = row.pin, let self { self.tabs.unpin(pin) }
        }
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

    enum DropDest { case pins(parent: UUID?, index: Int), regular(before: UUID?), split(UUID) }

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
            // 另一個一般 Tab 拖到中間（25%~75%）→ 並排顯示（Split View），兩側維持原本的重排行為。
            if case .tab(let draggedID) = dragged, draggedID != id, f >= 0.25, f <= 0.75 {
                return DropPlan(indicator: .into) { [weak self] in self?.execute(dragged, .split(id)) }
            }
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
        case (.tab(let id), .split(let targetID)):
            if let a = tab(withID: id), let b = tab(withID: targetID) { tabs.split(a, with: b) }
        default: break
        }
    }

    private func activeChanged() {
        closeFind()
        scheduleSessionSave()
        let partner = tabs.activeTab?.splitPartner
        for tab in tabs.tabs { rows[tab.pinID ?? tab.id]?.isActive = tab === tabs.activeTab || tab === partner }
        if let tab = tabs.activeTab {
            if let partner {
                // 左右順序依一般 Tab 清單的順序，與誰是「目前 Tab」無關，切換到另一半時畫面不會跳動。
                let order = tabs.tabs
                let tabIsLeft = (order.firstIndex { $0 === tab } ?? 0) < (order.firstIndex { $0 === partner } ?? 0)
                let (left, right) = tabIsLeft ? (tab, partner) : (partner, tab)
                root.card.showSplit(left.webView, right.webView) { [weak self] in self?.exitSplitView() }
            } else {
                root.card.show(tab.webView)
            }
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
        var faviconPNG: Data?
        if let img = tab.favicon, let tiff = img.tiffRepresentation { faviconPNG = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) }
        if let pid = tab.pinID {
            let hasTitle = tab.customTitle?.isEmpty == false || !tab.pageTitle.isEmpty
            tabs.pins.remember(pid, title: hasTitle ? tab.displayTitle : nil, favicon: faviconPNG)
        }
        if let png = faviconPNG, let url = tab.url, InputNormalizer.isHTTP(url) {
            tabs.history?.updateFavicon(url: url, favicon: png)
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
        guard let tab = targetTab, let host = tab.url?.host, InputNormalizer.isHTTP(tab.url) else { return }
        let next = direction == 0 ? 1 : tabs.zoom.step(from: tab.webView.pageZoom, direction: direction)
        tabs.zoom.set(next, for: host)
        for other in tabs.tabs where other.url?.host?.lowercased() == host.lowercased() { other.webView.pageZoom = next }
        tab.webView.pageZoom = next // Little 的 Tab 不在 tabs 清單裡
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

    /// ⌘L：同一個覆蓋層，但結果在目前的 Tab 導航（不開新 Tab）；預填目前網址並全選。
    @objc func showAddressPalette() {
        openPalette(prefill: tabs.activeTab?.displayURL?.absoluteString, navigatesCurrentTab: true)
    }

    /// 這次覆蓋層的「開啟 / 搜尋」與歷史是否在目前 Tab 導航（⌘L）而不是開新 Tab（⌘T）。
    private(set) var paletteNavigatesCurrentTab = false

    func openPalette(prefill: String?, navigatesCurrentTab: Bool = false) {
        paletteNavigatesCurrentTab = navigatesCurrentTab
        root.palette.placeholder = navigatesCurrentTab ? "Search or enter address (current tab)" : "Search or enter address (new tab)"
        if !root.palette.isOpen {
            let r = window.firstResponder
            paletteReturnFocus = (r as? NSTextView)?.delegate as? NSResponder ?? r
        }
        root.palette.present()
        if let prefill, !prefill.isEmpty {
            root.palette.field.stringValue = prefill
            if navigatesCurrentTab {
                root.palette.field.currentEditor()?.selectAll(nil)
            } else {
                root.palette.field.currentEditor()?.selectedRange = NSRange(location: (prefill as NSString).length, length: 0)
            }
            root.palette.refresh()
        }
    }

    private func pick(_ item: PaletteItem) {
        switch item.action {
        case .open(let url):
            if paletteNavigatesCurrentTab, let tab = tabs.activeTab { tab.load(url) } else { tabs.newTab(url: url) }
        case .switchTab(let tab): tabs.select(tab)
        case .activatePin(let id): if let n = tabs.pins.find(id)?.node { tabs.activatePin(n) }
        case .runAction(let id):
            // 動作自己決定焦點（改名、尋找、再開覆蓋層等），這裡不強制交給網頁。
            if let a = PaletteActions.find(id), a.isAvailable(self) { a.run(self) }
            return
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

    // MARK: 動作表用的操作（與選單共用）

    /// 空白 Tab，接著叫出覆蓋層輸入網址（在這個新 Tab 導航）。
    /// 動作「Switch to Previous Tab」：切到最近使用的上一個 Tab。
    func switchToPreviousTab() {
        let mru = tabs.mruTabs
        if mru.count >= 2 { tabs.select(mru[1]); window.makeFirstResponder(mru[1].webView) }
    }

    func newBlankTab() {
        tabs.newTab()
        showAddressPalette()
    }

    /// 除了目前 Tab 以外的一般（未釘選）Tab。
    func otherRegularTabs() -> [Tab] { tabs.tabs.filter { $0 !== tabs.activeTab && $0.pinID == nil } }

    func closeOtherTabs() {
        for t in otherRegularTabs() { tabs.close(t) }
    }

    /// 動作「Exit Split View」：目前 Tab 回到單一畫面。
    func exitSplitView() {
        if let tab = tabs.activeTab { tabs.unsplit(tab) }
    }

    @objc func selectPreviousTab() { tabs.selectAdjacent(offset: -1) }
    @objc func selectNextTab() { tabs.selectAdjacent(offset: 1) }

    @objc func duplicateTab() {
        guard let tab = tabs.activeTab, let url = tab.displayURL, InputNormalizer.isHTTP(url) else { return }
        tabs.newTab(url: url, customTitle: tab.pinID == nil ? tab.customTitle : nil, after: tab)
    }

    @objc func copyURLAsMarkdown() {
        guard let tab = targetTab, let url = tab.displayURL?.absoluteString else { return }
        let title = tab.displayTitle.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(title)](\(url))", forType: .string)
    }

    func renameActiveTab() {
        guard let tab = tabs.activeTab else { return }
        if !root.sidebarVisible { root.sidebarVisible = true }
        root.layoutSubtreeIfNeeded()
        beginRename(tab.pinID ?? tab.id)
    }

    /// 開 Web Inspector 需要 WebKit 的私有介面；取不到就不提供這個動作。
    var canOpenInspector: Bool {
        guard let wv = tabs.activeTab?.webView, wv.isInspectable, wv.responds(to: NSSelectorFromString("_inspector")),
              let insp = wv.value(forKey: "_inspector") as? NSObject else { return false }
        return insp.responds(to: NSSelectorFromString("show"))
    }

    func openInspector() {
        guard canOpenInspector, let insp = tabs.activeTab?.webView.value(forKey: "_inspector") as? NSObject else { return }
        insp.perform(NSSelectorFromString("show"))
    }

    @objc func closeCurrentTab() {
        // History 視窗為 key window 時，⌘W 關閉它本身，絕不動主視窗的 Tab。
        if let hw = historyWindow, hw.window?.isKeyWindow == true { hw.close(); return }
        // Little 為 key window 時，⌘W 只關 Little，絕不動主視窗的 Tab。
        if let little = keyLittle { little.close(); return }
        if let tab = tabs.activeTab { tabs.close(tab) }
    }

    /// 外部要求開啟（預設瀏覽器的連結、.html 檔）。http(s) 連結依設定在 Little 視窗開啟（預設）或新 Tab；
    /// 都不取代現有分頁。.html 檔一律新 Tab。若目前只有一個全新的空白 Tab（冷啟動），就直接用它，不多開空白 Tab。
    func openExternal(_ urls: [URL]) {
        for url in urls {
            if InputNormalizer.isHTTP(url) {
                if prefs.externalLinksInLittle { openLittle(url) } else { openInNewTab(url) }
            } else if url.isFileURL, ["html", "htm"].contains(url.pathExtension.lowercased()) {
                (pristineBlankTab() ?? tabs.newTab()).loadFile(url)
            }
        }
        if littles.isEmpty { window.makeKeyAndOrderFront(nil) }
    }

    /// 新 Tab 開網址；若只有一個全新的空白 Tab 則重用它。
    @discardableResult
    func openInNewTab(_ url: URL) -> Tab {
        if let blank = pristineBlankTab() { blank.load(url); return blank }
        return tabs.newTab(url: url)
    }

    /// 唯一的 Tab 且從未載入任何網址（剛啟動的空白 Tab）。
    private func pristineBlankTab() -> Tab? {
        guard tabs.tabs.count == 1, let t = tabs.tabs.first, t.pinID == nil, t.displayURL == nil, t.customTitle == nil else { return nil }
        return t
    }

    // MARK: Little 視窗

    private(set) var littles: [LittleWindowController] = []
    private var lastLittle: (url: URL, at: Date)?

    /// 開 Little 視窗（可同時多個）。只接受 http(s)；同一個網址 300ms 內重複開啟忽略。
    @discardableResult
    func openLittle(_ url: URL) -> LittleWindowController? {
        guard InputNormalizer.isHTTP(url) else { return nil }
        if let last = lastLittle, last.url == url, Date().timeIntervalSince(last.at) < 0.3 { return nil }
        lastLittle = (url, Date())
        let tab = tabs.makeTab()
        let little = LittleWindowController(tab: tab, prefs: prefs, near: window.isVisible ? window.frame : nil, cascade: littles.count)
        little.onAddToTabs = { [weak self] tab in
            guard let self else { return }
            self.tabs.adopt(tab)
            self.window.makeKeyAndOrderFront(nil)
        }
        little.onClosed = { [weak self] l in
            guard let self else { return }
            self.littles.removeAll { $0 === l }
            // 關閉 Little 後焦點回到主視窗（搬進 Tabs 時 adopt 已處理）。
            if !self.window.isMiniaturized { self.window.makeKeyAndOrderFront(nil) }
        }
        littles.append(little)
        tab.load(url)
        return little
    }

    /// 動作「Open in Little Window」：以目前 Tab 的網址開一個 Little 視窗。
    func openActiveTabInLittle() {
        if let url = tabs.activeTab?.displayURL { openLittle(url) }
    }

    /// 目前是 key window 的 Little（選單動作依 key window 決定作用對象）。
    var keyLittle: LittleWindowController? { littles.first { $0.window.isKeyWindow } }

    /// 選單動作的目標頁面：Little 為 key window 時是它的頁面，否則是主視窗目前的 Tab。
    var targetTab: Tab? { keyLittle?.tab ?? tabs.activeTab }

    func closeAllLittles() {
        for l in littles { l.close() }
    }

    @objc func restoreTab() {
        tabs.restoreLast()
    }

    // MARK: History 視窗

    private(set) var historyWindow: HistoryWindowController?

    enum HistoryClearRange { case lastHour, today, all }

    /// 清除歷史前的確認（範圍 + 是否清除）；取消回傳 nil。測試可替換，避免真的彈出模態對話框。
    static var clearHistoryPrompt: @MainActor () -> HistoryClearRange? = {
        let alert = NSAlert()
        alert.messageText = "Clear History"
        alert.informativeText = "This removes browsing history. It can't be undone."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        popup.addItems(withTitles: ["Last Hour", "Today", "All Time"])
        popup.selectItem(at: 2)
        alert.accessoryView = popup
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        switch popup.indexOfSelectedItem {
        case 0: return .lastHour
        case 1: return .today
        default: return .all
        }
    }

    @objc func showHistory() {
        guard let history = tabs.history else { return }
        let hw = historyWindow ?? makeHistoryWindow(history)
        hw.show()
    }

    private func makeHistoryWindow(_ history: HistoryStore) -> HistoryWindowController {
        let hw = HistoryWindowController(store: history)
        hw.onOpen = { [weak self] url in self?.openInNewTab(url) }
        hw.onClearRequested = { [weak self] in self?.confirmClearHistory() }
        historyWindow = hw
        return hw
    }

    @objc func confirmClearHistory() {
        guard let history = tabs.history, let range = Self.clearHistoryPrompt() else { return }
        let cutoff: Date?
        switch range {
        case .lastHour: cutoff = Date().addingTimeInterval(-3600)
        case .today: cutoff = Calendar.current.startOfDay(for: Date())
        case .all: cutoff = nil
        }
        history.clear(after: cutoff)
        historyWindow?.refresh()
    }

    @objc func goBack() { targetTab?.webView.goBack() }
    @objc func goForward() { targetTab?.webView.goForward() }
    @objc func reload() {
        guard let tab = targetTab else { return }
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
        guard let url = targetTab?.url?.absoluteString else { return }
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
