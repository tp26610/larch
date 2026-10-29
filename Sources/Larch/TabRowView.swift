import AppKit

/// 側邊欄的一列 Tab。標題一律以純文字顯示（stringValue），不解析任何標記。
@MainActor
final class TabRowView: NSView, NSTextFieldDelegate, SidebarRow {
    /// 開著的 Tab；釘選的項目被關掉後為 nil（顯示成灰色，點一下重新開啟）。
    var tab: Tab?
    /// 釘選的節點；一般 Tab 為 nil。
    let pin: PinNode?
    let depth: Int
    var item: SidebarItem { pin.map { .pin($0.id) } ?? .tab(tab?.id ?? UUID()) }
    var onSelect: ((TabRowView) -> Void)?
    var onClose: ((TabRowView) -> Void)?
    var onRename: ((TabRowView, String) -> Void)?
    var onMenu: ((TabRowView) -> NSMenu?)?
    private var downPoint: NSPoint?

    private let iconView = NSImageView()
    private let placeholder = NSTextField(labelWithString: "")
    private let splitBadge = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    let renameField = NSTextField()
    private let closeButton = NSButton()
    private let spinner = NSProgressIndicator()
    private var hovering = false
    private var finishedEditing = true

    var isEditing: Bool { !finishedEditing }
    var closeIconName: String { closeButton.image?.accessibilityDescription ?? "" }
    var closeToolTip: String? { closeButton.toolTip }
    var isShowingSpinner: Bool { !spinner.isHidden }
    var isShowingSplitBadge: Bool { !splitBadge.isHidden }
    var titleText: String { titleLabel.stringValue }
    var isActive = false { didSet { refreshBackground() } }

    override var mouseDownCanMoveWindow: Bool { false }

    init(tab: Tab?, pin: PinNode? = nil, depth: Int = 0) {
        self.tab = tab
        self.pin = pin
        self.depth = depth
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

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.appearance = NSAppearance(named: .darkAqua) // 綠色側邊欄上顯示白色
        spinner.isHidden = true

        splitBadge.image = NSImage(systemSymbolName: "rectangle.split.2x1.fill", accessibilityDescription: "Split View")
        splitBadge.contentTintColor = Theme.text
        splitBadge.wantsLayer = true
        splitBadge.layer?.backgroundColor = Theme.panel.cgColor
        splitBadge.layer?.cornerRadius = 3
        splitBadge.isHidden = true

        for v in [iconView, placeholder, spinner, splitBadge, titleLabel, renameField, closeButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8 + CGFloat(depth) * FolderRowView.indentStep),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            spinner.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
            placeholder.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 16),
            placeholder.heightAnchor.constraint(equalToConstant: 16),
            splitBadge.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
            splitBadge.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 3),
            splitBadge.widthAnchor.constraint(equalToConstant: 9),
            splitBadge.heightAnchor.constraint(equalToConstant: 9),
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

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 從 Tab（或釘選節點）狀態同步畫面；改名中不動標題欄位。
    func update() {
        let gray = tab == nil
        titleLabel.stringValue = tab?.displayTitle ?? pin?.title ?? ""
        let loading = tab?.isLoading ?? false
        let host = (tab?.url ?? pin?.url.flatMap(URL.init(string:)))?.host
        let favicon = tab?.favicon ?? pin?.favicon.flatMap { NSImage(data: $0) }
        if loading {
            iconView.isHidden = true
            placeholder.isHidden = true
        } else if let favicon {
            iconView.image = favicon
            iconView.isHidden = false
            placeholder.isHidden = true
        } else {
            iconView.isHidden = true
            placeholder.isHidden = false
            placeholder.stringValue = String((host ?? "").replacingOccurrences(of: "www.", with: "").first.map { String($0).uppercased() } ?? "")
        }
        titleLabel.textColor = loading ? Theme.muted : gray ? Theme.text.withAlphaComponent(0.55) : Theme.text
        iconView.alphaValue = gray ? 0.55 : 1
        placeholder.alphaValue = gray ? 0.55 : 1
        spinner.isHidden = !loading
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        splitBadge.isHidden = tab?.splitPartner == nil
        refreshBackground()
    }

    private func refreshBackground() {
        layer?.backgroundColor = (isActive ? Theme.active : hovering ? Theme.hover : NSColor.clear).cgColor
        closeButton.alphaValue = (isActive || hovering) ? 0.8 : 0
        // 釘選列：第一下關閉 Tab（保留釘選），變灰後第二下才移除釘選（仿 Arc）。
        let keepPinned = pin != nil && tab != nil
        closeButton.image = NSImage(systemSymbolName: keepPinned ? "minus" : "xmark", accessibilityDescription: keepPinned ? "Close and keep pinned" : "Close tab")
        closeButton.toolTip = pin == nil ? "Close Tab" : tab != nil ? "Close and Keep Pinned" : "Remove Pin"
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; refreshBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; refreshBackground() }

    override func menu(for event: NSEvent) -> NSMenu? { onMenu?(self) }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        if event.clickCount >= 2 {
            beginRename()
        } else {
            onSelect?(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = downPoint, hypot(event.locationInWindow.x - d.x, event.locationInWindow.y - d.y) > 4, finishedEditing else { return }
        downPoint = nil
        SidebarDragSource.begin(from: self, event: event)
    }

    @objc private func closeClicked() { onClose?(self) }

    // MARK: 改名（Enter 確認、Esc 取消、清空還原網頁標題）

    func beginRename() {
        guard finishedEditing else { return }
        finishedEditing = false
        renameField.stringValue = tab?.displayTitle ?? pin?.title ?? ""
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
        if commit { onRename?(self, text) }
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
