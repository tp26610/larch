import AppKit

/// 「Quit Larch?」確認覆蓋層（仿 Arc：沒有任何 Tab 時再按 ⌘W 會問是否退出）。
/// 蓋在整個視窗內容上，開啟時吞掉滑鼠事件；Enter 退出、Esc 取消、再按一次 ⌘W 視同退出。
@MainActor
final class QuitConfirmView: NSView {
    private let panel = NSView()
    private let neverAskButton = QuitConfirmView.makeButton("Quit, and don’t ask again")
    private let cancelButton = QuitConfirmView.makeButton("Cancel", hint: "ESC")
    private let quitButton = QuitConfirmView.makeButton("Quit", hint: "⏎", primary: true)
    private let titleLabel = NSTextField(labelWithString: "Quit Larch?")
    private let icon = NSImageView()

    var onQuit: (() -> Void)?
    var onQuitAndNeverAsk: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var isOpen = false

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.25).cgColor
        panel.wantsLayer = true
        panel.layer?.backgroundColor = Theme.paletteBackground.cgColor
        panel.layer?.cornerRadius = 28
        panel.layer?.borderColor = Theme.paletteBorder.cgColor
        panel.layer?.borderWidth = 1
        panel.shadow = { let s = NSShadow(); s.shadowBlurRadius = 24; s.shadowColor = NSColor(white: 0, alpha: 0.25); return s }()
        addSubview(panel)
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        titleLabel.textColor = Theme.paletteText
        [icon, titleLabel, neverAskButton, cancelButton, quitButton].forEach(panel.addSubview)
        neverAskButton.target = self; neverAskButton.action = #selector(neverAsk)
        cancelButton.target = self; cancelButton.action = #selector(cancel)
        quitButton.target = self; quitButton.action = #selector(quit)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func makeButton(_ title: String, hint: String? = nil, primary: Bool = false) -> NSButton {
        HintButton(title: title, hint: hint, primary: primary)
    }

    func present() {
        isHidden = false
        isOpen = true
        needsLayout = true
        window?.makeFirstResponder(self)
    }

    func dismiss() {
        isOpen = false
        isHidden = true
    }

    @objc func quit() { dismiss(); onQuit?() }
    @objc func neverAsk() { dismiss(); onQuitAndNeverAsk?() }
    @objc func cancel() { dismiss(); onCancel?() }

    override func layout() {
        super.layout()
        let w: CGFloat = 480, h: CGFloat = 250
        panel.frame = NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        icon.frame = NSRect(x: 40, y: h - 40 - 50, width: 50, height: 50)
        titleLabel.sizeToFit()
        titleLabel.frame.origin = NSPoint(x: 40, y: h - 40 - 50 - 20 - titleLabel.frame.height)
        var right = w - 40
        for b in [quitButton, cancelButton, neverAskButton] {
            b.sizeToFit()
            b.frame.origin = NSPoint(x: right - b.frame.width, y: 36)
            right = b.frame.minX - 10
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { isHidden ? nil : (super.hitTest(point) ?? self) }
    override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { cancel() }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: quit()      // Return / Enter
        case 53: cancel()        // Esc
        default: super.keyDown(with: event)
        }
    }

    /// 開著時 ⌘W 視同確認退出（Arc 的連按手感）。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isOpen else { return false }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" { quit() }
        return true // 開著時吞掉其他快捷鍵，避免動到後面的視窗
    }
}

/// 自繪按鈕：標題 + 右側鍵帽樣式的快捷鍵提示（如 ESC、⏎），讓提示一眼看得出是按鍵。
@MainActor
private final class HintButton: NSButton {
    private let label = NSTextField(labelWithString: "")
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let hasHint: Bool

    init(title: String, hint: String?, primary: Bool) {
        hasHint = hint != nil
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        let fg: NSColor = primary ? .white : Theme.paletteText
        layer?.backgroundColor = (primary ? NSColor(srgbRed: 0x2B / 255, green: 0x1F / 255, blue: 0xF0 / 255, alpha: 1)
                                          : NSColor(white: 0, alpha: 0.07)).cgColor
        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = fg
        addSubview(label)
        if let hint {
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 5
            badge.layer?.backgroundColor = (primary ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.10)).cgColor
            badgeLabel.stringValue = hint
            badgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            badgeLabel.textColor = primary ? .white : Theme.paletteMuted
            badge.addSubview(badgeLabel)
            addSubview(badge)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func sizeToFit() {
        label.sizeToFit(); badgeLabel.sizeToFit()
        var w = label.frame.width + 28
        if hasHint { w += max(badgeLabel.frame.width + 12, 26) + 8 }
        frame.size = NSSize(width: w, height: 34)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        label.frame.origin = NSPoint(x: 14, y: (bounds.height - label.frame.height) / 2)
        guard hasHint else { return }
        let bw = max(badgeLabel.frame.width + 12, 26), bh: CGFloat = 20
        badge.frame = NSRect(x: bounds.width - 10 - bw, y: (bounds.height - bh) / 2, width: bw, height: bh)
        badgeLabel.frame.origin = NSPoint(x: (bw - badgeLabel.frame.width) / 2, y: (bh - badgeLabel.frame.height) / 2)
    }
}
