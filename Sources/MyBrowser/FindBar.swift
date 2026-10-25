import AppKit

/// 頁內尋找列：卡片右上角的浮動小工具列。
@MainActor
final class FindBar: NSView {
    let field = NSTextField()
    let status = NSTextField(labelWithString: "")
    let prevButton = FindBar.button("chevron.up", "Previous")
    let nextButton = FindBar.button("chevron.down", "Next")
    let closeButton = FindBar.button("xmark", "Close")

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 36))
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = Theme.active.cgColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = Theme.text
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = "Find in page"
        status.font = .systemFont(ofSize: 11)
        status.textColor = Theme.muted
        let row = NSStackView(views: [field, status, prevButton, nextButton, closeButton])
        row.spacing = 4
        row.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func button(_ symbol: String, _ label: String) -> NSButton {
        let b = NSButton()
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        b.isBordered = false
        b.contentTintColor = Theme.muted
        b.toolTip = label
        b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }
}

/// 以網站（host）為單位記憶縮放比例。
@MainActor
final class ZoomStore {
    static let levels: [Double] = [0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    private let defaults: UserDefaults
    private let key = "zoomByHost"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var table: [String: Double] {
        get { defaults.dictionary(forKey: key) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: key) }
    }

    func zoom(for host: String?) -> Double {
        guard let host else { return 1 }
        let z = table[host.lowercased()] ?? 1
        return Self.levels.contains(z) ? z : 1
    }

    func set(_ zoom: Double, for host: String) {
        var t = table
        if zoom == 1 { t.removeValue(forKey: host.lowercased()) } else { t[host.lowercased()] = zoom }
        table = t
    }

    func step(from current: Double, direction: Int) -> Double {
        let i = Self.levels.enumerated().min { abs($0.element - current) < abs($1.element - current) }?.offset ?? 4
        return Self.levels[min(max(i + direction, 0), Self.levels.count - 1)]
    }
}
