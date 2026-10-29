import AppKit

/// 側邊欄裡一列代表的東西。拖曳時以字串放進剪貼簿。
enum SidebarItem: Equatable {
    case tab(UUID)      // 一般 Tab（Tab.id）
    case pin(UUID)      // 釘選的項目（PinNode.id，Tab 或資料夾）
    case divider        // 釘選區與一般區的分隔線

    static let pasteboardType = NSPasteboard.PasteboardType("app.larch.sidebar-item")

    var payload: String? {
        switch self {
        case .tab(let id): return "tab:\(id.uuidString)"
        case .pin(let id): return "pin:\(id.uuidString)"
        case .divider: return nil
        }
    }

    init?(payload: String) {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "tab": self = .tab(id)
        case "pin": self = .pin(id)
        default: return nil
        }
    }
}

/// 側邊欄清單中的一列（Tab、釘選、資料夾、分隔線）。
@MainActor
protocol SidebarRow: NSView {
    var item: SidebarItem { get }
    var depth: Int { get }
}

/// 拖曳來源：共用，不持有狀態。
final class SidebarDragSource: NSObject, NSDraggingSource {
    static let shared = SidebarDragSource()

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }

    /// 從一列開始拖曳。
    @MainActor
    static func begin(from row: some SidebarRow, event: NSEvent) {
        guard let payload = row.item.payload else { return }
        let pb = NSPasteboardItem()
        pb.setString(payload, forType: SidebarItem.pasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pb)
        let image = NSImage(size: row.bounds.size)
        if let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds) {
            row.cacheDisplay(in: row.bounds, to: rep)
            image.addRepresentation(rep)
        }
        item.setDraggingFrame(row.bounds, contents: image)
        row.beginDraggingSession(with: [item], event: event, source: shared)
    }
}

/// 資料夾列：圖示 + 名稱（點一下展開/收合、雙擊改名）。名稱一律純文字。
@MainActor
final class FolderRowView: NSView, SidebarRow, NSTextFieldDelegate {
    static let indentStep: CGFloat = 16

    let node: PinNode
    let depth: Int
    var item: SidebarItem { .pin(node.id) }
    var onToggle: ((PinNode) -> Void)?
    var onRename: ((PinNode, String) -> Void)?
    var onMenu: ((FolderRowView) -> NSMenu?)?

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    let renameField = NSTextField()
    private var hovering = false
    private var finished = true
    private var downPoint: NSPoint?

    var titleText: String { label.stringValue }
    var isEditing: Bool { !finished }
    override var mouseDownCanMoveWindow: Bool { false }

    init(node: PinNode, depth: Int) {
        self.node = node
        self.depth = depth
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true

        icon.contentTintColor = Theme.text
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Theme.text
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        renameField.font = .systemFont(ofSize: 13, weight: .semibold)
        renameField.textColor = Theme.text
        renameField.drawsBackground = true
        renameField.backgroundColor = Theme.field
        renameField.isBordered = false
        renameField.focusRingType = .none
        renameField.isHidden = true
        renameField.delegate = self
        for v in [icon, label, renameField] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        let lead = 8 + CGFloat(depth) * Self.indentStep
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: lead),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            renameField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            renameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            renameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            renameField.heightAnchor.constraint(equalToConstant: 22),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update() {
        label.stringValue = node.title
        icon.image = NSImage(systemSymbolName: node.expanded ? "folder.fill" : "folder", accessibilityDescription: node.expanded ? "Open folder" : "Folder")
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; layer?.backgroundColor = Theme.hover.cgColor }
    override func mouseExited(with event: NSEvent) { hovering = false; layer?.backgroundColor = NSColor.clear.cgColor }
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?(self) }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        if event.clickCount >= 2 { beginRename() } else { onToggle?(node) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = downPoint, hypot(event.locationInWindow.x - d.x, event.locationInWindow.y - d.y) > 4, finished else { return }
        downPoint = nil
        SidebarDragSource.begin(from: self, event: event)
    }

    func beginRename() {
        guard finished else { return }
        finished = false
        renameField.stringValue = node.title
        renameField.isHidden = false
        label.isHidden = true
        window?.makeFirstResponder(renameField)
        renameField.currentEditor()?.selectAll(nil)
    }

    func finishRename(commit: Bool) {
        guard !finished else { return }
        finished = true
        let text = renameField.stringValue
        renameField.isHidden = true
        label.isHidden = false
        if window?.firstResponder === renameField.currentEditor() { window?.makeFirstResponder(nil) }
        if commit { onRename?(node, text) }
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { finishRename(commit: true); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { finishRename(commit: false); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { finishRename(commit: true) }
}

/// Split View 配對的兩個一般 Tab 並排顯示成一列（兩個 TabRowView 各佔一半寬度）。
/// 不是 SidebarRow：代表兩個項目而非一個，拖曳落點判定改成展開成 left/right 分別處理（見 SidebarView.sidebarRows）。
@MainActor
final class SplitPairRowView: NSView {
    let left: TabRowView
    let right: TabRowView
    override var mouseDownCanMoveWindow: Bool { false }

    init(left: TabRowView, right: TabRowView) {
        self.left = left
        self.right = right
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        let stack = NSStackView(views: [left, right])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 釘選區與一般區之間的分隔線（也是拖曳到「釘選區末尾 / 取消釘選」的落點）。
@MainActor
final class DividerRowView: NSView, SidebarRow {
    var item: SidebarItem { .divider }
    var depth: Int { 0 }
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 1, alpha: 0.28).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 拖曳時的落點提示：一條線（插在列之間）或圈住整列（放進資料夾）。
@MainActor
final class DropIndicatorView: NSView {
    enum Style { case line, outline }
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ style: Style, frame f: NSRect) {
        isHidden = false
        frame = f
        switch style {
        case .line:
            layer?.backgroundColor = NSColor.white.cgColor
            layer?.borderWidth = 0
            layer?.cornerRadius = 1
        case .outline:
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
            layer?.borderColor = NSColor.white.cgColor
            layer?.borderWidth = 1.5
            layer?.cornerRadius = 8
        }
    }
}
