import AppKit

/// 一列歷史。標題與網址一律 stringValue 純文字顯示；hover 顯示刪除按鈕。
@MainActor
final class HistoryRowView: NSView {
    let entry: HistoryEntry
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let urlLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var hovering = false

    var titleText: String { titleLabel.stringValue }
    var urlText: String { urlLabel.stringValue }
    var deleteAlpha: CGFloat { deleteButton.alphaValue }

    override var mouseDownCanMoveWindow: Bool { false }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    init(entry: HistoryEntry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        titleLabel.stringValue = entry.title.isEmpty ? entry.url : entry.title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = Theme.paletteText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        urlLabel.stringValue = entry.url
        urlLabel.font = .systemFont(ofSize: 11)
        urlLabel.textColor = Theme.paletteMuted
        urlLabel.lineBreakMode = .byTruncatingTail
        urlLabel.cell?.usesSingleLineMode = true
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.stringValue = Self.timeFormatter.string(from: Date(timeIntervalSince1970: entry.visitedAt))
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = Theme.paletteMuted
        timeLabel.alignment = .right
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove from History")
        deleteButton.contentTintColor = Theme.paletteMuted
        deleteButton.imageScaling = .scaleProportionallyDown
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.alphaValue = 0
        deleteButton.toolTip = "Remove from History"

        let text = NSStackView(views: [titleLabel, urlLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        for v in [text, timeLabel, deleteButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -10),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 70),
            text.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -10),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 40),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { hovering = true; refreshBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; refreshBackground() }

    private func refreshBackground() {
        layer?.backgroundColor = (hovering ? Theme.paletteSelection : NSColor.clear).cgColor
        deleteButton.alphaValue = hovering ? 0.8 : 0
    }

    override func mouseDown(with event: NSEvent) { onOpen?() }
    @objc private func deleteClicked() { onDelete?() }
}

/// 一天一列的日期標頭（不可互動）。
@MainActor
final class HistoryDayHeaderView: NSView {
    let text: String

    override var mouseDownCanMoveWindow: Bool { false }

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.paletteMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class HistoryFlippedView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 歷史視窗的內容：搜尋欄 + 捲動清單（依日期分組）+ 底部「Clear History…」。
@MainActor
final class HistoryView: NSView {
    let search = NSSearchField()
    let clearButton = NSButton(title: "Clear History…", target: nil, action: nil)
    private let scroll = NSScrollView()
    private let listDoc = HistoryFlippedView()
    private let list = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No History")

    private(set) var rowViews: [NSView] = []

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.paletteBackground.cgColor

        search.placeholderString = "Search History"
        search.focusRingType = .none

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        listDoc.translatesAutoresizingMaskIntoConstraints = false
        listDoc.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: listDoc.topAnchor),
            list.bottomAnchor.constraint(equalTo: listDoc.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: listDoc.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: listDoc.trailingAnchor),
        ])

        scroll.documentView = listDoc
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        clearButton.bezelStyle = .rounded

        emptyLabel.textColor = Theme.paletteMuted
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        for v in [search, scroll, clearButton, emptyLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -14),
            listDoc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            clearButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            clearButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 換一批列；空清單顯示 emptyText。
    func setRows(_ views: [NSView], emptyText: String) {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = views
        for v in views {
            list.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        emptyLabel.stringValue = emptyText
        emptyLabel.isHidden = !views.isEmpty
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// History 視窗：瀏覽、搜尋、刪除單筆、清除歷史。不即時跟著 HistoryStore 變化，每次顯示時重新讀取。
@MainActor
final class HistoryWindowController: NSWindowController {
    /// 顯示的最大筆數（搜尋與不搜尋都用這個上限，避免筆數多時清單過重）。
    static let displayLimit = 300

    private let historyView = HistoryView()
    private let store: HistoryStore
    var onOpen: ((URL) -> Void)?
    /// 使用者按下「Clear History…」；由 controller 決定清除範圍（可彈 alert），完成後呼叫 refresh()。
    var onClearRequested: (() -> Void)?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    init(store: HistoryStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
        window.title = "History"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 360, height: 300)
        window.contentView = historyView
        window.center()
        super.init(window: window)
        historyView.search.target = self
        historyView.search.action = #selector(searchChanged)
        historyView.clearButton.target = self
        historyView.clearButton.action = #selector(clearClicked)
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    var searchField: NSSearchField { historyView.search }
    var rowViews: [NSView] { historyView.rowViews }
    var clearButton: NSButton { historyView.clearButton }

    func show() {
        reload()
        window?.makeKeyAndOrderFront(nil)
    }

    /// 清除完成後外部呼叫，重新整理清單。
    func refresh() { reload() }

    @objc private func searchChanged() { reload() }

    private func reload() {
        let query = historyView.search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = query.isEmpty
            ? Array(store.entries.suffix(Self.displayLimit).reversed())
            : store.search(query, limit: Self.displayLimit)
        historyView.setRows(groupedRows(entries), emptyText: query.isEmpty ? "No History" : "No Results")
    }

    private func groupedRows(_ entries: [HistoryEntry]) -> [NSView] {
        var views: [NSView] = []
        var lastDay: String?
        let cal = Calendar.current
        for entry in entries {
            let date = Date(timeIntervalSince1970: entry.visitedAt)
            let label = Self.dayLabel(for: date, calendar: cal)
            if label != lastDay {
                views.append(HistoryDayHeaderView(text: label))
                lastDay = label
            }
            let row = HistoryRowView(entry: entry)
            row.onOpen = { [weak self] in self?.open(entry) }
            row.onDelete = { [weak self] in self?.delete(entry) }
            views.append(row)
        }
        return views
    }

    private static func dayLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }

    private func open(_ entry: HistoryEntry) {
        guard let url = URL(string: entry.url) else { return }
        onOpen?(url)
    }

    private func delete(_ entry: HistoryEntry) {
        store.delete(entry)
        reload()
    }

    @objc private func clearClicked() { onClearRequested?() }
}
