import AppKit

/// 一列候選。標題與網址用 stringValue 純文字顯示。
@MainActor
final class PaletteRowView: NSView {
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var isSelected = false { didSet { layer?.backgroundColor = isSelected ? Theme.paletteSelection.cgColor : NSColor.clear.cgColor } }
    private(set) var item: PaletteItem

    override var mouseDownCanMoveWindow: Bool { false }
    var titleText: String { titleLabel.stringValue }

    init(item: PaletteItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        let symbol: String
        switch item.kind {
        case .openOrSearch: symbol = "magnifyingglass"
        case .tab: symbol = "rectangle.on.rectangle"
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
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
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

/// 蓋在整個視窗內容上的命令列覆蓋層（目前：⌘T 搜尋 + 開新 Tab）。
/// 與資料來源無關：由 `provider` 供應候選、`onPick` 處理選取，日後可擴充成動作與 Tab 切換器。
@MainActor
final class CommandPaletteView: NSView, NSTextFieldDelegate {
    static let panelWidth: CGFloat = 600
    static let fieldHeight: CGFloat = 52

    let field = NSTextField()
    private let panel = PaletteFlippedView()
    private let list = NSStackView()
    private let divider = NSView()

    var provider: ((String) -> [PaletteItem])?
    var onPick: ((PaletteItem) -> Void)?
    /// 覆蓋層關閉後（含選取）呼叫，讓外部還原焦點。
    var onDismiss: (() -> Void)?
    /// 面板水平置中、垂直定位所參考的區域（網頁卡片）。
    var anchorFrame: NSRect = .zero { didSet { needsLayout = true } }

    private(set) var items: [PaletteItem] = []
    private(set) var selectedIndex = 0
    private var rowViews: [PaletteRowView] = []

    var isOpen: Bool { !isHidden }
    var panelFrame: NSRect { panel.frame }
    var rows: [PaletteRowView] { rowViews }

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
        field.placeholderString = "Search or enter address"
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = self
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.paletteBorder.cgColor
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2
        for v in [field, divider, list] { panel.addSubview(v) }
        addSubview(panel)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 開關

    func present() {
        isHidden = false
        field.stringValue = ""
        refresh()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func dismiss() {
        guard isOpen else { return }
        isHidden = true
        field.stringValue = ""
        items = []
        onDismiss?()
    }

    // MARK: 候選

    func refresh() {
        items = provider?(field.stringValue) ?? []
        selectedIndex = 0
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = items.enumerated().map { i, item in
            let row = PaletteRowView(item: item)
            row.onClick = { [weak self] in self?.pick(i) }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            return row
        }
        updateSelection()
        needsLayout = true
    }

    private func updateSelection() {
        for (i, r) in rowViews.enumerated() { r.isSelected = i == selectedIndex }
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
        default: return false
        }
    }

    // MARK: 版面與滑鼠

    override func layout() {
        super.layout()
        let w = min(Self.panelWidth, max(240, anchorFrame.width - 40))
        let listH = rowViews.isEmpty ? 0 : CGFloat(rowViews.count) * 46 + CGFloat(rowViews.count - 1) * 2 + 16
        let h = Self.fieldHeight + (rowViews.isEmpty ? 0 : 1) + listH
        // anchorFrame 以非翻轉座標給（RootView），這裡 isFlipped，換算成由上往下。
        let top = bounds.height - anchorFrame.maxY + max(40, anchorFrame.height * 0.14)
        panel.frame = NSRect(x: anchorFrame.midX - w / 2, y: top, width: w, height: h)
        field.frame = NSRect(x: 20, y: (Self.fieldHeight - 24) / 2, width: w - 40, height: 24)
        divider.isHidden = rowViews.isEmpty
        divider.frame = NSRect(x: 0, y: Self.fieldHeight, width: w, height: 1)
        list.frame = NSRect(x: 8, y: Self.fieldHeight + 9, width: w - 16, height: max(0, listH - 16))
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
