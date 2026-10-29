import AppKit
import WebKit

/// 查每個分頁對應 WebContent process 的 PID 與記憶體用量；都是 WebKit/系統私有介面，拿不到就回 nil（跟 Open Web Inspector 用 `_inspector` 同一套防呆）。
/// PID 可用 `_webProcessIdentifier`（私有 KVC）；一分頁一個 process，同網域也各自獨立（2026-10-29 PoC 驗證過，見 BACKLOG.md）。
enum TaskManagerStats {
    static func pid(for webView: WKWebView) -> pid_t? {
        guard webView.responds(to: NSSelectorFromString("_webProcessIdentifier")) else { return nil }
        return webView.value(forKey: "_webProcessIdentifier") as? pid_t
    }

    static func residentMB(_ pid: pid_t) -> Double? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) { proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, size) }
        guard result == size else { return nil }
        return Double(info.pti_resident_size) / 1_048_576
    }
}

/// 一列：favicon（沒有就退回網域字首字母色塊，同 HistoryRowView）、標題/網域、記憶體、End Process 按鈕。
/// 點列本身（非按鈕）切換到該分頁。
@MainActor
final class TaskManagerRowView: NSView {
    let tab: Tab
    var onSelect: (() -> Void)?
    var onEndProcess: (() -> Void)?

    var titleText: String { titleLabel.stringValue }
    var memoryText: String { memoryLabel.stringValue }

    private let iconView = NSImageView()
    private let iconBubble = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let domainLabel = NSTextField(labelWithString: "")
    private let memoryLabel = NSTextField(labelWithString: "")
    private let endButton = NSButton()
    private var hovering = false

    override var mouseDownCanMoveWindow: Bool { false }

    init(tab: Tab, memoryMB: Double?) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true

        let host = (tab.displayURL?.host ?? "").replacingOccurrences(of: "www.", with: "")
        iconBubble.stringValue = host.first.map { String($0).uppercased() } ?? "?"
        iconBubble.font = .systemFont(ofSize: 9, weight: .semibold)
        iconBubble.textColor = Theme.paletteMuted
        iconBubble.alignment = .center
        iconBubble.wantsLayer = true
        iconBubble.layer?.backgroundColor = Theme.historyIconBubble.cgColor
        iconBubble.layer?.cornerRadius = 9

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.masksToBounds = true
        if let favicon = tab.favicon {
            iconView.image = favicon
            iconView.isHidden = false
            iconBubble.isHidden = true
        } else {
            iconView.isHidden = true
            iconBubble.isHidden = false
        }

        titleLabel.stringValue = tab.displayTitle
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Theme.paletteText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        domainLabel.stringValue = host.isEmpty ? (tab.displayURL?.absoluteString ?? "") : host
        domainLabel.font = .systemFont(ofSize: 11)
        domainLabel.textColor = Theme.paletteMuted
        domainLabel.lineBreakMode = .byTruncatingTail
        domainLabel.cell?.usesSingleLineMode = true
        domainLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        memoryLabel.stringValue = memoryMB.map { String(format: "%.0f MB", $0) } ?? "—"
        memoryLabel.font = .systemFont(ofSize: 12)
        memoryLabel.textColor = Theme.paletteMuted
        memoryLabel.alignment = .right
        memoryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        endButton.isBordered = false
        endButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "End Process")
        endButton.contentTintColor = Theme.paletteMuted
        endButton.imageScaling = .scaleProportionallyDown
        endButton.target = self
        endButton.action = #selector(endClicked)
        endButton.toolTip = "End Process"

        let text = NSStackView(views: [titleLabel, domainLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        for v in [iconView, iconBubble, text, memoryLabel, endButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            iconBubble.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            iconBubble.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBubble.widthAnchor.constraint(equalToConstant: 18),
            iconBubble.heightAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            memoryLabel.trailingAnchor.constraint(equalTo: endButton.leadingAnchor, constant: -14),
            memoryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            memoryLabel.widthAnchor.constraint(equalToConstant: 60),
            endButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            endButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            endButton.widthAnchor.constraint(equalToConstant: 22),
            endButton.heightAnchor.constraint(equalToConstant: 22),
            text.trailingAnchor.constraint(lessThanOrEqualTo: memoryLabel.leadingAnchor, constant: -10),
            heightAnchor.constraint(equalToConstant: 40),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { hovering = true; refreshBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; refreshBackground() }

    private func refreshBackground() {
        layer?.backgroundColor = (hovering ? Theme.paletteSelection : NSColor.clear).cgColor
    }

    override func mouseDown(with event: NSEvent) { onSelect?() }

    @objc private func endClicked() { onEndProcess?() }
}

/// 整個清單包在一個白色圓角卡片裡（不分組），抄 HistoryDayCardView 的卡片風格。
@MainActor
final class TaskManagerListCardView: NSView {
    private(set) var rows: [TaskManagerRowView] = []

    override var mouseDownCanMoveWindow: Bool { false }

    init(entries: [(tab: Tab, memoryMB: Double?)], onSelect: @escaping (Tab) -> Void, onEndProcess: @escaping (Tab) -> Void) {
        super.init(frame: .zero)

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Theme.paletteBorder.cgColor
        card.layer?.masksToBounds = true

        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: card.topAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])

        for (i, entry) in entries.enumerated() {
            let row = TaskManagerRowView(tab: entry.tab, memoryMB: entry.memoryMB)
            row.onSelect = { onSelect(entry.tab) }
            row.onEndProcess = { onEndProcess(entry.tab) }
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            rows.append(row)
            if i < entries.count - 1 {
                let divider = NSView()
                divider.wantsLayer = true
                divider.layer?.backgroundColor = Theme.paletteBorder.cgColor
                divider.translatesAutoresizingMaskIntoConstraints = false
                rowsStack.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
        }

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class TaskManagerFlippedView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 視窗內容：淺灰底 + 捲動的清單卡片。
@MainActor
final class TaskManagerView: NSView {
    private let scroll = NSScrollView()
    private let listDoc = TaskManagerFlippedView()
    private(set) var card: TaskManagerListCardView?

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.historyBackground.cgColor

        listDoc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = listDoc
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            listDoc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCard(_ newCard: TaskManagerListCardView) {
        card?.removeFromSuperview()
        card = newCard
        newCard.translatesAutoresizingMaskIntoConstraints = false
        listDoc.addSubview(newCard)
        NSLayoutConstraint.activate([
            newCard.topAnchor.constraint(equalTo: listDoc.topAnchor),
            newCard.leadingAnchor.constraint(equalTo: listDoc.leadingAnchor),
            newCard.trailingAnchor.constraint(equalTo: listDoc.trailingAnchor),
            newCard.bottomAnchor.constraint(equalTo: listDoc.bottomAnchor),
        ])
    }
}

/// Task Manager 視窗：列出主視窗的一般 Tab（不含 Little），顯示記憶體用量，可個別關閉（End Process = 關閉分頁，
/// 不是真的 kill -9：WebContent process 被 kill 後 WKWebView 的後續行為沒驗證過，關閉分頁一樣能釋放資源且行為可預期）。
/// 視窗開著時每 1 秒刷新一次；關閉視窗停止計時器，避免背景空轉。
@MainActor
final class TaskManagerWindowController: NSWindowController, NSWindowDelegate {
    private let taskView = TaskManagerView()
    private weak var tabs: TabManager?
    private var timer: Timer?
    var onSelect: ((Tab) -> Void)?
    var onEndProcess: ((Tab) -> Void)?
    var rows: [TaskManagerRowView] { taskView.card?.rows ?? [] }

    init(tabs: TabManager) {
        self.tabs = tabs
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
        window.title = "Task Manager"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 320, height: 240)
        window.contentView = taskView
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        reload()
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    func reload() {
        guard let tabs else { return }
        let entries = tabs.tabs
            .map { tab -> (tab: Tab, memoryMB: Double?) in
                (tab, TaskManagerStats.pid(for: tab.webView).flatMap(TaskManagerStats.residentMB))
            }
            .sorted { ($0.memoryMB ?? -1) > ($1.memoryMB ?? -1) }
        taskView.setCard(TaskManagerListCardView(
            entries: entries,
            onSelect: { [weak self] tab in self?.onSelect?(tab) },
            onEndProcess: { [weak self] tab in self?.onEndProcess?(tab) }))
    }
}
