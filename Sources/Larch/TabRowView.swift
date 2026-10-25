import AppKit

/// 側邊欄的一列 Tab。標題一律以純文字顯示（stringValue），不解析任何標記。
@MainActor
final class TabRowView: NSView, NSTextFieldDelegate {
    let tab: Tab
    var onSelect: ((Tab) -> Void)?
    var onClose: ((Tab) -> Void)?
    var onRename: ((Tab, String) -> Void)?

    private let iconView = NSImageView()
    private let placeholder = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    let renameField = NSTextField()
    private let closeButton = NSButton()
    private let loadingLayer = CAGradientLayer()
    private var hovering = false
    private var finishedEditing = true

    var isEditing: Bool { !finishedEditing }
    var isShowingLoadingBar: Bool { !loadingLayer.isHidden && loadingLayer.animation(forKey: "sweep") != nil }
    var titleText: String { titleLabel.stringValue }
    var isActive = false { didSet { refreshBackground() } }

    override var mouseDownCanMoveWindow: Bool { false }

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.masksToBounds = true
        placeholder.alignment = .center
        placeholder.font = .systemFont(ofSize: 10)
        placeholder.textColor = Theme.muted
        placeholder.wantsLayer = true
        placeholder.layer?.backgroundColor = Theme.field.cgColor
        placeholder.layer?.cornerRadius = 4

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = Theme.text
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        renameField.font = .systemFont(ofSize: 13)
        renameField.textColor = Theme.text
        renameField.drawsBackground = true
        renameField.backgroundColor = Theme.field
        renameField.isBordered = false
        renameField.focusRingType = .none
        renameField.isHidden = true
        renameField.delegate = self

        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeButton.contentTintColor = Theme.muted
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.alphaValue = 0

        for v in [iconView, placeholder, titleLabel, renameField, closeButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            placeholder.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 16),
            placeholder.heightAnchor.constraint(equalToConstant: 16),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            renameField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            renameField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            renameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            renameField.heightAnchor.constraint(equalToConstant: 22),
        ])

        loadingLayer.colors = [NSColor.clear.cgColor, Theme.accent.cgColor, NSColor.clear.cgColor]
        loadingLayer.startPoint = CGPoint(x: 0, y: 0.5)
        loadingLayer.endPoint = CGPoint(x: 1, y: 0.5)
        loadingLayer.isHidden = true
        layer?.addSublayer(loadingLayer)

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 從 Tab 狀態同步畫面；改名中不動標題欄位。
    func update() {
        titleLabel.stringValue = tab.displayTitle
        if let favicon = tab.favicon {
            iconView.image = favicon
            iconView.isHidden = false
            placeholder.isHidden = true
        } else {
            iconView.isHidden = true
            placeholder.isHidden = false
            placeholder.stringValue = String((tab.url?.host ?? "").replacingOccurrences(of: "www.", with: "").first.map { String($0).uppercased() } ?? "")
        }
        titleLabel.textColor = tab.isLoading ? Theme.muted : Theme.text
        setLoading(tab.isLoading)
    }

    private func setLoading(_ on: Bool) {
        loadingLayer.isHidden = !on
        if on {
            guard loadingLayer.animation(forKey: "sweep") == nil else { return }
            let width = max(bounds.width, 200)
            loadingLayer.frame = CGRect(x: 0, y: 0, width: width * 0.4, height: 2)
            let anim = CABasicAnimation(keyPath: "position.x")
            anim.fromValue = -width * 0.2
            anim.toValue = width * 1.2
            anim.duration = 1.1
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            loadingLayer.add(anim, forKey: "sweep")
        } else {
            loadingLayer.removeAnimation(forKey: "sweep")
        }
    }

    private func refreshBackground() {
        layer?.backgroundColor = (isActive ? Theme.active : hovering ? Theme.hover : NSColor.clear).cgColor
        closeButton.alphaValue = (isActive || hovering) ? 0.8 : 0
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; refreshBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; refreshBackground() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            beginRename()
        } else {
            onSelect?(tab)
        }
    }

    @objc private func closeClicked() { onClose?(tab) }

    // MARK: 改名（Enter 確認、Esc 取消、清空還原網頁標題）

    func beginRename() {
        guard finishedEditing else { return }
        finishedEditing = false
        renameField.stringValue = tab.displayTitle
        renameField.isHidden = false
        titleLabel.isHidden = true
        window?.makeFirstResponder(renameField)
        renameField.currentEditor()?.selectAll(nil)
    }

    func finishRename(commit: Bool) {
        guard !finishedEditing else { return }
        finishedEditing = true
        let text = renameField.stringValue
        renameField.isHidden = true
        titleLabel.isHidden = false
        if window?.firstResponder === renameField.currentEditor() { window?.makeFirstResponder(nil) }
        if commit { onRename?(tab, text) }
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            finishRename(commit: true)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            finishRename(commit: false)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishRename(commit: true)
    }
}
