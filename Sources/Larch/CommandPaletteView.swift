import AppKit

/// 一列候選。標題與網址用 stringValue 純文字顯示。
@MainActor
final class PaletteRowView: NSView {
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var isSelected = false { didSet { layer?.backgroundColor = isSelected ? Theme.paletteSelection.cgColor : NSColor.clear.cgColor } }
    private(set) var item: PaletteItem

    override var mouseDownCanMoveWindow: Bool { false }
    var titleText: String { titleLabel.stringValue }
    var badgeText: String { badgeLabel.stringValue }
    var shortcutText: String { shortcutLabel.isHidden ? "" : shortcutLabel.stringValue }

    init(item: PaletteItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        let symbol: String
        switch item.kind {
        case .openOrSearch: symbol = "magnifyingglass"
        case .tab: symbol = "rectangle.on.rectangle"
        case .pin: symbol = "pin"
        case .action: symbol = "command"
        case .history: symbol = "clock"
        }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = Theme.paletteMuted
        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = Theme.paletteText
        subtitleLabel.stringValue = item.subtitle
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = Theme.paletteMuted
        for l in [titleLabel, subtitleLabel] {
            l.lineBreakMode = .byTruncatingTail
            l.cell?.usesSingleLineMode = true
            l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        badgeLabel.stringValue = item.badge
        badgeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        badgeLabel.textColor = Theme.paletteMuted
        shortcutLabel.stringValue = item.shortcut ?? ""
        shortcutLabel.font = .systemFont(ofSize: 12)
        shortcutLabel.textColor = Theme.paletteMuted
        shortcutLabel.isHidden = item.shortcut == nil
        for l in [badgeLabel, shortcutLabel] { l.setContentCompressionResistancePriority(.required, for: .horizontal) }
        let right = NSStackView(views: [shortcutLabel, badgeLabel])
        right.orientation = .horizontal
        right.spacing = 10
        right.translatesAutoresizingMaskIntoConstraints = false
        addSubview(right)
        subtitleLabel.isHidden = item.subtitle.isEmpty
        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        for v in [icon, text] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 46),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

private final class PaletteFlippedView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 蓋在整個視窗內容上的命令列覆蓋層：⌘T 搜尋 + 開新 Tab、⌘L 在目前 Tab 導航；Tab 鍵進入動作模式。
/// 與資料來源無關：由 `provider` 供應候選、`onPick` 處理選取。
@MainActor
final class CommandPaletteView: NSView, NSTextFieldDelegate {
    static let panelWidth: CGFloat = 600
    static let fieldHeight: CGFloat = 52
    static let rowHeight: CGFloat = 46
    static let rowSpacing: CGFloat = 2
    static let maxVisibleRows = 8

    let field = NSTextField()
    private let panel = PaletteFlippedView()
    private let scroll = NSScrollView()
    private let listDoc = PaletteFlippedView()
    private let list = NSStackView()
    private let divider = NSView()
    private let chip = NSTextField(labelWithString: "Actions")

    var provider: ((String, PaletteMode) -> [PaletteItem])?
    var onPick: ((PaletteItem) -> Void)?
    /// 覆蓋層關閉後（含選取）呼叫，讓外部還原焦點。
    var onDismiss: (() -> Void)?
    /// 面板水平置中、垂直定位所參考的區域（網頁卡片）。
    var anchorFrame: NSRect = .zero { didSet { needsLayout = true } }
    /// 一般模式的提示文字（由外部依 ⌘T / ⌘L 設定）。
    var placeholder = "Search or enter address" { didSet { updateChrome() } }

    private(set) var mode: PaletteMode = .normal
    private(set) var items: [PaletteItem] = []
    private(set) var selectedIndex = 0
    private var rowViews: [PaletteRowView] = []

    var isOpen: Bool { !isHidden }
    var panelFrame: NSRect { panel.frame }
    var rows: [PaletteRowView] { rowViews }
    var isChipVisible: Bool { !chip.isHidden }
    var chipText: String { chip.stringValue }
    /// 目前可見的列數（最多 maxVisibleRows，超出捲動）。
    var visibleRowCount: Int { min(rowViews.count, Self.maxVisibleRows) }

    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        panel.wantsLayer = true
        panel.layer?.backgroundColor = Theme.paletteBackground.cgColor
        panel.layer?.cornerRadius = Theme.paletteRadius
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = Theme.paletteBorder.cgColor
        panel.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor(white: 0, alpha: 0.28)
            s.shadowBlurRadius = 30
            s.shadowOffset = NSSize(width: 0, height: -10)
            return s
        }()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.textColor = Theme.paletteText
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = self
        chip.font = .systemFont(ofSize: 12, weight: .semibold)
        chip.textColor = Theme.paletteText
        chip.alignment = .center
        chip.wantsLayer = true
        chip.layer?.backgroundColor = Theme.paletteSelection.cgColor
        chip.layer?.cornerRadius = 6
        chip.isHidden = true
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.paletteBorder.cgColor
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = Self.rowSpacing
        list.translatesAutoresizingMaskIntoConstraints = true
        listDoc.addSubview(list)
        scroll.documentView = listDoc
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false // 滾輪/觸控板/↑↓ 仍可捲動；不佔寬度（「永遠顯示捲軸」會讓內容變窄）
        for v in [field, chip, divider, scroll] { panel.addSubview(v) }
        addSubview(panel)
        updateChrome()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 開關與模式

    func present() {
        isHidden = false
        mode = .normal
        field.stringValue = ""
        updateChrome()
        refresh()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func dismiss() {
        guard isOpen else { return }
        isHidden = true
        field.stringValue = ""
        items = []
        mode = .normal
        updateChrome()
        onDismiss?()
    }

    /// Tab 進入動作模式（保留已輸入的文字作為動作的查詢）。
    func enterActions() {
        guard mode != .actions else { return }
        mode = .actions
        updateChrome()
        refresh()
    }

    /// Backspace（輸入框為空）或 Shift+Tab 離開動作模式。
    func exitActions() {
        guard mode == .actions else { return }
        mode = .normal
        updateChrome()
        refresh()
    }

    private func updateChrome() {
        chip.isHidden = mode != .actions
        field.placeholderString = mode == .actions ? "Type an action…" : placeholder
        needsLayout = true
    }

    // MARK: 候選

    func refresh() {
        items = provider?(field.stringValue, mode) ?? []
        selectedIndex = 0
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = items.enumerated().map { i, item in
            let row = PaletteRowView(item: item)
            row.onClick = { [weak self] in self?.pick(i) }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            return row
        }
        // 換了一批結果：回到最上面（否則會停在舊的捲動位置，選取列在畫面外）。
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        updateSelection()
        needsLayout = true
    }

    private func updateSelection() {
        for (i, r) in rowViews.enumerated() { r.isSelected = i == selectedIndex }
        ensureSelectedVisible()
    }

    /// 以列高計算位置（不依賴尚未版面的 frame），把選取的列捲進可視範圍。
    private func ensureSelectedVisible() {
        guard !rowViews.isEmpty else { return }
        let y = CGFloat(selectedIndex) * (Self.rowHeight + Self.rowSpacing)
        listDoc.scrollToVisible(NSRect(x: 0, y: y - 4, width: 1, height: Self.rowHeight + 8))
    }

    /// 目前捲動的可視範圍（文件座標）。
    var visibleListRect: NSRect { scroll.contentView.bounds }
    /// 選取列在文件座標中的位置。
    var selectedRowRect: NSRect {
        NSRect(x: 0, y: CGFloat(selectedIndex) * (Self.rowHeight + Self.rowSpacing), width: 1, height: Self.rowHeight)
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + items.count) % items.count
        updateSelection()
    }

    func pick(_ index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        dismiss()
        onPick?(item)
    }

    // MARK: 輸入

    func controlTextDidChange(_ obj: Notification) { refresh() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): pick(selectedIndex); return true
        case #selector(NSResponder.cancelOperation(_:)): dismiss(); return true
        case #selector(NSResponder.moveDown(_:)): moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
        case #selector(NSResponder.insertTab(_:)): enterActions(); return true
        case #selector(NSResponder.insertBacktab(_:)): exitActions(); return true
        case #selector(NSResponder.deleteBackward(_:)):
            if mode == .actions, field.stringValue.isEmpty { exitActions(); return true }
            return false
        default: return false
        }
    }

    // MARK: 版面與滑鼠

    override func layout() {
        super.layout()
        let w = min(Self.panelWidth, max(240, anchorFrame.width - 40))
        let n = rowViews.count
        let shown = visibleRowCount
        let contentH = n == 0 ? 0 : CGFloat(n) * Self.rowHeight + CGFloat(n - 1) * Self.rowSpacing
        let viewH = shown == 0 ? 0 : CGFloat(shown) * Self.rowHeight + CGFloat(shown - 1) * Self.rowSpacing
        let listAreaH = n == 0 ? 0 : viewH + 16
        let h = Self.fieldHeight + (n == 0 ? 0 : 1) + listAreaH
        // anchorFrame 以非翻轉座標給（RootView），這裡 isFlipped，換算成由上往下。
        let top = bounds.height - anchorFrame.maxY + max(40, anchorFrame.height * 0.14)
        panel.frame = NSRect(x: anchorFrame.midX - w / 2, y: top, width: w, height: h)
        var fieldX: CGFloat = 20
        if !chip.isHidden {
            let cw = chip.attributedStringValue.size().width + 18
            chip.frame = NSRect(x: 16, y: (Self.fieldHeight - 22) / 2, width: cw, height: 22)
            fieldX = 16 + cw + 8
        }
        field.frame = NSRect(x: fieldX, y: (Self.fieldHeight - 24) / 2, width: w - fieldX - 20, height: 24)
        divider.isHidden = n == 0
        divider.frame = NSRect(x: 0, y: Self.fieldHeight, width: w, height: 1)
        scroll.isHidden = n == 0
        scroll.frame = NSRect(x: 8, y: Self.fieldHeight + 9, width: w - 16, height: viewH)
        listDoc.frame = NSRect(x: 0, y: 0, width: w - 16, height: contentH)
        list.frame = listDoc.bounds
        ensureSelectedVisible()
    }

    /// 點面板外關閉；面板內的點擊由子視圖處理。
    override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { dismiss() }
    }

    /// 開啟時吞掉所有滑鼠事件，不讓底下的網頁收到。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isOpen else { return nil }
        return super.hitTest(point) ?? self
    }
}
