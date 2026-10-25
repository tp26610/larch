import AppKit
import WebKit

/// Little 視窗：先看一眼連結，再決定關掉或加進主視窗的 Tabs（仿 Arc 的 Little Arc）。
/// 標題與網址一律以純文字顯示。
@MainActor
final class LittleWindow: LarchWindow {
    var onClose: (() -> Void)?
    var onAddToTabs: (() -> Void)?
    var onReload: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    /// 網頁取得焦點時按鍵會先被 WKWebView 吃掉，所以在視窗層級攔截（與主視窗的 ⌘W 同一個做法）。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (mods, key, event.keyCode) {
        case ([], _, 53): onClose?(); return true                                 // Esc
        case ([.command], "w", _), ([.control], "w", _): onClose?(); return true  // ⌘W / Ctrl+W
        case ([.command], "o", _): onAddToTabs?(); return true                    // ⌘O
        case ([.command], _, 36), ([.command], _, 76): onAddToTabs?(); return true // ⌘Return
        case ([.command], "r", _): onReload?(); return true
        case ([.command], "[", _): onBack?(); return true
        case ([.command], "]", _): onForward?(); return true
        // 主視窗專屬的快捷鍵不要在這裡誤觸主視窗。
        case ([.control], "s", _), ([.command], "t", _), ([.command], "l", _), ([.command], "d", _), ([.command], "s", _): return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

/// Little 視窗內容：上方 44px 工具列（淺白外框，與主視窗的綠色區分）+ 圓角網頁卡片。工具列空白處可拖曳視窗。
@MainActor
final class LittleRootView: NSView {
    static let toolbarHeight: CGFloat = 44

    let card = CardView()
    let backButton = LittleRootView.iconButton("chevron.left", "Back (⌘[)")
    let forwardButton = LittleRootView.iconButton("chevron.right", "Forward (⌘])")
    let reloadButton = LittleRootView.iconButton("arrow.clockwise", "Reload (⌘R)")
    /// 中央的網址膠囊：只顯示網域（純文字）；完整標題與網址放在 toolTip。
    let pill = NSView()
    let urlLabel = NSTextField(labelWithString: "")
    let addButton = NSButton()
    private let toolbar = FlippedView()

    override var mouseDownCanMoveWindow: Bool { true }
    var toolbarHeightForTest: CGFloat { toolbar.frame.height }
    var pillText: String { urlLabel.stringValue }
    var pillToolTip: String { pill.toolTip ?? "" }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.littleFrame.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.littleBorder.cgColor
        pill.wantsLayer = true
        pill.layer?.backgroundColor = Theme.littlePill.cgColor
        pill.layer?.cornerRadius = 8
        urlLabel.font = .systemFont(ofSize: 13)
        urlLabel.textColor = Theme.littleToolbarText
        urlLabel.alignment = .center
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.cell?.usesSingleLineMode = true
        pill.addSubview(urlLabel)
        addButton.isBordered = false
        addButton.wantsLayer = true
        addButton.layer?.backgroundColor = Theme.littleButton.cgColor
        addButton.layer?.cornerRadius = 7
        let t = NSMutableAttributedString(string: "Add to Tabs", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: Theme.littleToolbarText])
        t.append(NSAttributedString(string: "  ⌘O", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.littleMuted]))
        addButton.attributedTitle = t
        addButton.toolTip = "Add to Tabs (⌘O / ⌘↩)"
        for v in [backButton, forwardButton, reloadButton, pill, addButton] { toolbar.addSubview(v) }
        addSubview(toolbar)
        addSubview(card)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = Self.toolbarHeight, m = Theme.margin
        toolbar.frame = NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        card.frame = NSRect(x: m, y: m, width: max(0, bounds.width - 2 * m), height: max(0, bounds.height - h - m))
        var x: CGFloat = 84 // 留給紅綠燈
        for b in [backButton, forwardButton, reloadButton] {
            b.frame = NSRect(x: x, y: (h - 28) / 2, width: 30, height: 28)
            x += 32
        }
        let addW: CGFloat = 124
        addButton.frame = NSRect(x: bounds.width - addW - 12, y: (h - 28) / 2, width: addW, height: 28)
        // 膠囊置中於視窗，但不壓到左右的按鈕。
        let maxW = max(60, min(440, 2 * (min(bounds.midX - x - 12, addButton.frame.minX - bounds.midX - 12))))
        pill.frame = NSRect(x: bounds.midX - maxW / 2, y: (h - 28) / 2, width: maxW, height: 28)
        urlLabel.frame = NSRect(x: 10, y: (28 - 17) / 2, width: maxW - 20, height: 17)
    }

    /// 載入中重新整理鈕換成停止。
    func setLoading(_ loading: Bool) {
        reloadButton.image = NSImage(systemSymbolName: loading ? "xmark" : "arrow.clockwise", accessibilityDescription: loading ? "Stop" : "Reload")
        reloadButton.toolTip = loading ? "Stop" : "Reload (⌘R)"
    }

    private static func iconButton(_ symbol: String, _ label: String) -> NSButton {
        let b = NSButton()
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        b.isBordered = false
        b.contentTintColor = Theme.littleIcon
        b.toolTip = label
        return b
    }
}

/// 一個 Little 視窗與它的 Tab（同一個 WKWebView）。
@MainActor
final class LittleWindowController: NSObject, NSWindowDelegate {
    let window: LittleWindow
    let root = LittleRootView()
    let tab: Tab
    var onClosed: ((LittleWindowController) -> Void)?
    /// 加到 Tabs：交出 Tab（搬移同一個 WKWebView）。
    var onAddToTabs: ((Tab) -> Void)?
    private let prefs: Preferences
    private var transferred = false
    private var closed = false

    init(tab: Tab, prefs: Preferences, near mainFrame: NSRect?, cascade: Int) {
        self.tab = tab
        self.prefs = prefs
        let size = prefs.littleSize
        window = LittleWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "Little Window"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = Theme.littleFrame
        window.minSize = NSSize(width: 520, height: 360)
        window.contentView = root
        window.delegate = self
        if let mainFrame {
            let f = window.frame
            let offset = CGFloat(cascade % 8) * 26
            window.setFrameOrigin(NSPoint(x: mainFrame.midX - f.width / 2 + offset, y: mainFrame.midY - f.height / 2 - offset))
        } else {
            window.center()
        }
        window.onClose = { [weak self] in self?.close() }
        window.onAddToTabs = { [weak self] in self?.addToTabs() }
        window.onReload = { [weak self] in self?.reloadOrStop() }
        window.onBack = { [weak self] in self?.tab.webView.goBack() }
        window.onForward = { [weak self] in self?.tab.webView.goForward() }
        root.backButton.target = self; root.backButton.action = #selector(back)
        root.forwardButton.target = self; root.forwardButton.action = #selector(forward)
        root.reloadButton.target = self; root.reloadButton.action = #selector(reloadClicked)
        root.addButton.target = self; root.addButton.action = #selector(addClicked)

        tab.popupInPlace = true
        tab.onChange = { [weak self] _ in self?.sync() }
        tab.onRequestClose = { [weak self] _ in self?.close() }
        root.card.show(tab.webView)
        sync()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tab.webView)
    }

    var isClosed: Bool { closed }

    private func sync() {
        let url = tab.displayURL
        root.urlLabel.stringValue = url?.host ?? url?.absoluteString ?? ""
        root.pill.toolTip = [tab.displayTitle, url?.absoluteString ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        root.backButton.isEnabled = tab.webView.canGoBack
        root.forwardButton.isEnabled = tab.webView.canGoForward
        root.setLoading(tab.isLoading)
        root.card.loadingBar.update(loading: tab.isLoading, progress: tab.webView.estimatedProgress)
        window.title = tab.displayTitle
    }

    @objc private func back() { tab.webView.goBack() }
    @objc private func forward() { tab.webView.goForward() }
    @objc private func reloadClicked() { reloadOrStop() }
    @objc private func addClicked() { addToTabs() }

    private func reloadOrStop() {
        if tab.isLoading { tab.webView.stopLoading() } else { tab.reloadOrRetry() }
    }

    func close() { window.close() }

    func addToTabs() {
        guard !closed else { return }
        transferred = true
        onAddToTabs?(tab)
        window.close()
    }

    func windowDidResize(_ notification: Notification) {
        guard !closed else { return }
        prefs.littleSize = window.contentView?.frame.size ?? window.frame.size
    }

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        if !transferred { tab.teardown() } // 搬走的 Tab 屬於主視窗，不能銷毀
        tab.onChange = nil
        onClosed?(self)
    }
}
