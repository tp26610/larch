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

    override var mouseDownCanMoveWindow: Bool { true }
    var rowViews: [TabRowView] { stack.arrangedSubviews.compactMap { $0 as? TabRowView } }

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

    func setRows(_ rows: [TabRowView]) {
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

/// 視窗內容：側邊欄 + 圓角網頁卡片。四周 8px 邊框是唯一的拖曳區域，卡片本身不可拖曳。
@MainActor
final class RootView: NSView {
    let sidebar = SidebarView()
    let card = CardView()
    let findBar = FindBar()
    var sidebarVisible = true { didSet { needsLayout = true } }

    override var mouseDownCanMoveWindow: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        addSubview(sidebar)
        addSubview(card)
        addSubview(findBar)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let m = Theme.margin
        let sw = sidebarVisible ? Theme.sidebarWidth : 0
        sidebar.isHidden = !sidebarVisible
        sidebar.frame = NSRect(x: 0, y: 0, width: Theme.sidebarWidth, height: bounds.height)
        card.frame = cardFrame(sidebarWidth: sw)
        findBar.frame = NSRect(x: card.frame.maxX - 340 - 12, y: card.frame.maxY - 36 - 12, width: 340, height: 36)
    }

    func cardFrame(sidebarWidth sw: CGFloat) -> NSRect {
        let m = Theme.margin
        let x = sw == 0 ? m : sw
        return NSRect(x: x, y: m, width: max(0, bounds.width - x - m), height: max(0, bounds.height - 2 * m))
    }
}

/// 網頁卡片：圓角裁切；hit-test 底下不能有可拖曳視窗的視圖，否則會吞掉網頁捲動。
@MainActor
final class CardView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.cardRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = Theme.card.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ webView: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }
}
