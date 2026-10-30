import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

/// 網址列：圓角底 + 單行輸入。
@MainActor
final class AddressBar: NSView {
    let field = NSTextField()

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.field.cgColor
        layer?.cornerRadius = 8
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = Theme.text
        field.placeholderString = "Search or enter address"
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 拖曳落點的計畫：放開時執行 commit；indicator 決定提示畫在目標列的哪裡。
struct DropPlan {
    enum Indicator { case before, after, into }
    let indicator: Indicator
    let commit: @MainActor () -> Void
}

/// 左側欄：導覽按鈕、網址列、Tab 列表、New Tab。背景可拖曳視窗，控制項不行。
@MainActor
final class SidebarView: NSView {
    let backButton = SidebarView.iconButton("chevron.left", "Back")
    let forwardButton = SidebarView.iconButton("chevron.right", "Forward")
    let reloadButton = SidebarView.iconButton("arrow.clockwise", "Reload")
    let addressBar = AddressBar()
    let newTabButton = NSButton()
    let downloadButton = NSButton()
    private let scrollView = NSScrollView()
    private let listContainer = FlippedView()
    private let stack = NSStackView()
    private let dropIndicator = DropIndicatorView()
    private var currentPlan: DropPlan?
    /// 拖曳時詢問落點：被拖的東西、游標所在列（nil = 清單下方空白）、游標在該列的垂直位置（0 上緣、1 下緣）。
    var onResolveDrop: ((SidebarItem, SidebarItem?, CGFloat) -> DropPlan?)?

    override var mouseDownCanMoveWindow: Bool { true }
    /// 所有 Tab 列，含並排成一列的 Split View 配對（展開成各自獨立的兩個）。
    var rowViews: [TabRowView] {
        stack.arrangedSubviews.flatMap { v -> [TabRowView] in
            if let row = v as? TabRowView { return [row] }
            if let pair = v as? SplitPairRowView { return [pair.left, pair.right] }
            return []
        }
    }
    /// 拖曳落點判定用：並排的 Split View 配對展開成各自獨立的兩個（有各自的 frame，靠 x 座標分辨）。
    var sidebarRows: [any SidebarRow] {
        stack.arrangedSubviews.flatMap { v -> [any SidebarRow] in
            if let row = v as? any SidebarRow { return [row] }
            if let pair = v as? SplitPairRowView { return [pair.left, pair.right] }
            return []
        }
    }

    init() {
        super.init(frame: .zero)
        let toolbar = NSStackView(views: [backButton, forwardButton, reloadButton])
        toolbar.spacing = 2

        newTabButton.title = "+  New Tab"
        newTabButton.isBordered = false
        newTabButton.alignment = .left
        newTabButton.contentTintColor = Theme.muted
        newTabButton.font = .systemFont(ofSize: 13)

        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(stack)
        scrollView.documentView = listContainer
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(dropIndicator)
        registerForDraggedTypes([SidebarItem.pasteboardType])

        downloadButton.isBordered = false
        downloadButton.alignment = .left
        downloadButton.contentTintColor = Theme.accent
        downloadButton.font = .systemFont(ofSize: 12)
        downloadButton.lineBreakMode = .byTruncatingMiddle
        downloadButton.isHidden = true
        let bottom = NSStackView(views: [downloadButton, newTabButton])
        bottom.orientation = .vertical
        bottom.alignment = .leading
        bottom.spacing = 0

        for v in [toolbar, addressBar, scrollView, bottom] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            // 38px：留給 macOS 紅綠燈。
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            addressBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            addressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            addressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            addressBar.heightAnchor.constraint(equalToConstant: 34),
            scrollView.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -4),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            newTabButton.heightAnchor.constraint(equalToConstant: 32),
            newTabButton.widthAnchor.constraint(equalTo: bottom.widthAnchor),
            downloadButton.heightAnchor.constraint(equalToConstant: 26),
            downloadButton.widthAnchor.constraint(equalTo: bottom.widthAnchor),
            listContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            listContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.topAnchor.constraint(equalTo: listContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 載入中重新整理鈕換成停止（✕）。
    private(set) var isShowingStop = false
    func setLoading(_ loading: Bool) {
        isShowingStop = loading
        reloadButton.image = NSImage(systemSymbolName: loading ? "xmark" : "arrow.clockwise", accessibilityDescription: loading ? "Stop" : "Reload")
        reloadButton.toolTip = loading ? "Stop" : "Reload"
    }

    func showDownload(_ status: DownloadManager.Status?) {
        guard let status else { downloadButton.isHidden = true; return }
        downloadButton.isHidden = false
        switch status.state {
        case .running(let f): downloadButton.title = "↓ \(status.name)  \(Int(f * 100))%"
        case .finished: downloadButton.title = "✓ \(status.name) — Show in Finder"
        case .failed: downloadButton.title = "✗ \(status.name) failed"
        }
        downloadButton.toolTip = status.fileURL.path
    }

    // MARK: 拖曳落點

    private func payload(_ info: NSDraggingInfo) -> SidebarItem? {
        info.draggingPasteboard.string(forType: SidebarItem.pasteboardType).flatMap(SidebarItem.init(payload:))
    }

    private func updateDrag(_ info: NSDraggingInfo) -> NSDragOperation {
        guard let dragged = payload(info) else { return [] }
        if let event = NSApp.currentEvent { listContainer.autoscroll(with: event) }
        let point = listContainer.convert(info.draggingLocation, from: nil)
        let y = point.y
        let rows = sidebarRows
        var over: (any SidebarRow)?
        var fraction: CGFloat = 0
        var overFrame = NSRect.zero
        // 並排的 Split View 配對共用同一個 y 區間，靠 x 座標分辨左右半邊；一般列的 frame 本來就橫跨整個寬度，x 一定會落在裡面。
        for row in rows {
            let f = row.convert(row.bounds, to: listContainer)
            if y >= f.minY, y < f.maxY, point.x >= f.minX, point.x < f.maxX { over = row; fraction = (y - f.minY) / f.height; overFrame = f; break }
        }
        if over == nil, let first = rows.first, y < first.convert(first.bounds, to: listContainer).minY {
            over = first; fraction = 0; overFrame = first.convert(first.bounds, to: listContainer)
        }
        let target: SidebarItem? = over?.item
        guard let plan = onResolveDrop?(dragged, target, fraction) else {
            currentPlan = nil
            dropIndicator.isHidden = true
            return []
        }
        currentPlan = plan
        let inset = 8 + CGFloat(over?.depth ?? 0) * FolderRowView.indentStep
        if let last = rows.last, over == nil {
            overFrame = last.convert(last.bounds, to: listContainer)
            dropIndicator.show(.line, frame: NSRect(x: 8, y: overFrame.maxY, width: listContainer.bounds.width - 16, height: 2))
        } else {
            switch plan.indicator {
            case .before: dropIndicator.show(.line, frame: NSRect(x: inset, y: overFrame.minY - 1, width: listContainer.bounds.width - inset - 8, height: 2))
            case .after: dropIndicator.show(.line, frame: NSRect(x: inset, y: overFrame.maxY - 1, width: listContainer.bounds.width - inset - 8, height: 2))
            case .into: dropIndicator.show(.outline, frame: overFrame.insetBy(dx: 4, dy: 0))
            }
        }
        return .move
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropIndicator.isHidden = true; currentPlan = nil }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropIndicator.isHidden = true; currentPlan = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard updateDrag(sender) != [], let plan = currentPlan else { return false }
        dropIndicator.isHidden = true
        currentPlan = nil
        plan.commit()
        return true
    }

    func setBackgroundMenu(_ menu: NSMenu) {
        self.menu = menu
        listContainer.menu = menu
    }

    func setRows(_ rows: [NSView]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private static func iconButton(_ symbol: String, _ label: String) -> NSButton {
        let b = NSButton()
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        b.isBordered = false
        b.contentTintColor = Theme.muted
        b.toolTip = label
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }
}

/// 側邊欄與卡片交界的拖曳手把：窄窄一條，拖曳改寬度；本身不可拖動視窗（避免跟縮放打架），
/// 也不能蓋住卡片太多（否則會擋到網頁點擊/捲動，見第 1 點的坑）。
@MainActor
final class SidebarResizeHandle: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    /// 拖曳中：目前滑鼠在 RootView 座標系的 x。
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    /// 明確接手這次拖曳（NSView 預設只會往上傳），讓後續 mouseDragged/mouseUp 固定送到這裡。
    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag?(superview.convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) { onDragEnd?() }
}

/// 視窗內容：側邊欄 + 圓角網頁卡片。四周 8px 邊框是唯一的拖曳區域，卡片本身不可拖曳。
@MainActor
final class RootView: NSView {
    let sidebar = SidebarView()
    let card = CardView()
    let findBar = FindBar()
    let palette = CommandPaletteView()
    private let resizeHandle = SidebarResizeHandle()
    var sidebarWidth: CGFloat = Theme.sidebarWidth { didSet { needsLayout = true } }
    /// 拖曳放開後回報最終寬度；給 controller 存進 Preferences。
    var onSidebarWidthChange: ((CGFloat) -> Void)?
    var sidebarVisible = true { didSet { needsLayout = true; if oldValue != sidebarVisible { onSidebarVisibilityChange?(sidebarVisible) } } }
    var onSidebarVisibilityChange: ((Bool) -> Void)?
    /// 滑鼠進出左上角感應區（供側邊欄隱藏時暫時顯示紅綠燈）。
    var onCornerHover: ((Bool) -> Void)?
    static let cornerSize = NSSize(width: 90, height: 40)
    private var cornerArea: NSTrackingArea?
    var cornerRect: NSRect { NSRect(x: 0, y: bounds.height - Self.cornerSize.height, width: Self.cornerSize.width, height: Self.cornerSize.height) }

    // tracking area 不攔截事件，網頁卡片的點擊與捲動不受影響。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cornerArea { removeTrackingArea(cornerArea) }
        let area = NSTrackingArea(rect: cornerRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        cornerArea = area
    }

    override func mouseEntered(with event: NSEvent) { if event.trackingArea === cornerArea { onCornerHover?(true) } }
    override func mouseExited(with event: NSEvent) { if event.trackingArea === cornerArea { onCornerHover?(false) } }

    override var mouseDownCanMoveWindow: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        addSubview(sidebar)
        addSubview(card)
        addSubview(resizeHandle)
        addSubview(findBar)
        addSubview(palette)
        resizeHandle.onDrag = { [weak self] x in
            guard let self else { return }
            self.sidebarWidth = min(max(x, Theme.sidebarWidthRange.lowerBound), Theme.sidebarWidthRange.upperBound)
        }
        resizeHandle.onDragEnd = { [weak self] in
            guard let self else { return }
            self.onSidebarWidthChange?(self.sidebarWidth)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let m = Theme.margin
        let sw = sidebarVisible ? sidebarWidth : 0
        sidebar.isHidden = !sidebarVisible
        sidebar.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        card.frame = cardFrame(sidebarWidth: sw)
        resizeHandle.isHidden = !sidebarVisible
        resizeHandle.frame = NSRect(x: sw - 3, y: 0, width: 6, height: bounds.height)
        palette.frame = bounds
        palette.anchorFrame = card.frame
        findBar.frame = NSRect(x: card.frame.maxX - 340 - 12, y: card.frame.maxY - 36 - 12, width: 340, height: 36)
    }

    func cardFrame(sidebarWidth sw: CGFloat) -> NSRect {
        let m = Theme.margin
        let x = sw == 0 ? m : sw
        return NSRect(x: x, y: m, width: max(0, bounds.width - x - m), height: max(0, bounds.height - 2 * m))
    }
}

/// Split View 中間的分隔線：延續第 1 點的規則，卡片底下不可有拖曳區域。
@MainActor
final class SplitDividerView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 網頁卡片：圓角裁切；hit-test 底下不能有可拖曳視窗的視圖，否則會吞掉網頁捲動。
/// 單一 Tab（`show`）或兩個 Tab 並排（`showSplit`，固定 50/50）；`layout()` 在卡片縮放時維持比例。
@MainActor
final class CardView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    private enum Mode { case single(NSView), split(NSView, NSView) }
    private var mode: Mode?
    private let divider = SplitDividerView()
    private let unsplitButton = NSButton()
    private var onUnsplit: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.cardRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = Theme.card.cgColor

        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 0, alpha: 0.12).cgColor

        unsplitButton.isBordered = false
        unsplitButton.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "Exit Split View")
        unsplitButton.toolTip = "Exit Split View"
        unsplitButton.contentTintColor = NSColor(white: 0.25, alpha: 1)
        unsplitButton.wantsLayer = true
        unsplitButton.layer?.backgroundColor = NSColor(white: 1, alpha: 0.92).cgColor
        unsplitButton.layer?.cornerRadius = 11
        unsplitButton.target = self
        unsplitButton.action = #selector(unsplitClicked)
    }

    required init?(coder: NSCoder) { fatalError() }

    let loadingBar = LoadingBarView()

    /// 單一 Tab 顯示。
    func show(_ webView: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        mode = .single(webView)
        onUnsplit = nil
        addSubview(webView)
        addSubview(loadingBar)
        relayout()
    }

    /// 沒有任何 Tab 時：卡片保持空白（仿 Arc）。
    func showEmpty() {
        subviews.forEach { $0.removeFromSuperview() }
        mode = nil
        onUnsplit = nil
        addSubview(loadingBar)
        relayout()
    }

    /// 兩個 Tab 並排顯示（固定 50/50，中間窄分隔線），右上角按鈕退出分割。
    func showSplit(_ left: NSView, _ right: NSView, onUnsplit: @escaping () -> Void) {
        subviews.forEach { $0.removeFromSuperview() }
        mode = .split(left, right)
        self.onUnsplit = onUnsplit
        addSubview(left)
        addSubview(right)
        addSubview(divider)
        addSubview(loadingBar)
        addSubview(unsplitButton)
        relayout()
    }

    /// 目前是否顯示 Split View（smoke 用）。
    var isSplit: Bool { if case .split = mode { return true } else { return false } }

    /// 分隔線在卡片座標系的 frame（非分割時為 nil）；smoke 用來算出精準的 hit-test 落點。
    var dividerFrameForTesting: NSRect? { isSplit ? divider.frame : nil }

    override func layout() {
        super.layout()
        relayout()
    }

    private func relayout() {
        switch mode {
        case .single(let v):
            v.frame = bounds
        case .split(let left, let right):
            let gap: CGFloat = 1
            let half = ((bounds.width - gap) / 2).rounded(.down)
            left.frame = NSRect(x: 0, y: 0, width: half, height: bounds.height)
            divider.frame = NSRect(x: half, y: 0, width: gap, height: bounds.height)
            right.frame = NSRect(x: half + gap, y: 0, width: bounds.width - half - gap, height: bounds.height)
            unsplitButton.frame = NSRect(x: half - 11, y: bounds.height - 34, width: 22, height: 22)
        case nil:
            break
        }
        // 進度條在網頁之上、貼卡片上緣（卡片圓角裁切），但不接收事件。
        loadingBar.frame = NSRect(x: 0, y: bounds.height - LoadingBarView.height, width: bounds.width, height: LoadingBarView.height)
    }

    @objc private func unsplitClicked() { onUnsplit?() }
}
