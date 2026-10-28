import AppKit

/// 一列歷史（仿 Arc history 頁）：核取方塊、時間、favicon（沒有就退回網域字首字母的色塊）、標題/網域、「⋯」選單。
/// 標題與網址一律 stringValue 純文字顯示。
@MainActor
final class HistoryRowView: NSView {
    let entry: HistoryEntry
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleSelect: ((Bool) -> Void)?

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let timeLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let iconBubble = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let domainLabel = NSTextField(labelWithString: "")
    private let menuButton = NSButton()
    private var hovering = false

    var titleText: String { titleLabel.stringValue }
    var domainText: String { domainLabel.stringValue }
    /// true 表示顯示的是真的 favicon，false 是網域字首字母的色塊備援。
    var hasFaviconImage: Bool { !iconView.isHidden }
    var isSelected: Bool {
        get { checkbox.state == .on }
        set { checkbox.state = newValue ? .on : .off }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    init(entry: HistoryEntry, isSelected: Bool) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true

        checkbox.state = isSelected ? .on : .off
        checkbox.target = self
        checkbox.action = #selector(checkboxClicked)

        timeLabel.stringValue = Self.timeFormatter.string(from: Date(timeIntervalSince1970: entry.visitedAt))
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = Theme.paletteMuted
        timeLabel.alignment = .right
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let host = (URL(string: entry.url)?.host ?? "").replacingOccurrences(of: "www.", with: "")
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
        // 記錄當下通常還沒抓到 favicon（之後載入完成才補），這裡沒有就退回網域字首字母的色塊。
        if let data = entry.favicon, let image = NSImage(data: data) {
            iconView.image = image
            iconView.isHidden = false
            iconBubble.isHidden = true
        } else {
            iconView.isHidden = true
            iconBubble.isHidden = false
        }

        titleLabel.stringValue = entry.title.isEmpty ? entry.url : entry.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Theme.paletteText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        domainLabel.stringValue = host.isEmpty ? entry.url : host
        domainLabel.font = .systemFont(ofSize: 11)
        domainLabel.textColor = Theme.paletteMuted
        domainLabel.lineBreakMode = .byTruncatingTail
        domainLabel.cell?.usesSingleLineMode = true
        domainLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")
        menuButton.contentTintColor = Theme.paletteMuted
        menuButton.imageScaling = .scaleProportionallyDown
        menuButton.target = self
        menuButton.action = #selector(menuClicked)
        menuButton.toolTip = "More"

        let text = NSStackView(views: [titleLabel, domainLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        for v in [checkbox, timeLabel, iconView, iconBubble, text, menuButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 12),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 60),
            iconView.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            iconBubble.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            iconBubble.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBubble.widthAnchor.constraint(equalToConstant: 18),
            iconBubble.heightAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 22),
            menuButton.heightAnchor.constraint(equalToConstant: 22),
            text.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -10),
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

    /// 點列本身（非核取方塊、非選單）開啟；核取方塊只負責選取，不觸發開啟。
    override func mouseDown(with event: NSEvent) { onOpen?() }

    @objc private func checkboxClicked() { onToggleSelect?(checkbox.state == .on) }

    @objc private func menuClicked() {
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open in New Tab", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        let delete = menu.addItem(withTitle: "Delete", action: #selector(deleteFromMenu), keyEquivalent: "")
        delete.target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: menuButton)
    }

    @objc private func openFromMenu() { onOpen?() }
    @objc private func deleteFromMenu() { onDelete?() }
}

/// 一天一組：日期標頭（卡片外）+ 白色圓角卡片（內含當天的列，列間細分隔線）。
@MainActor
final class HistoryDayCardView: NSView {
    let dayText: String
    private(set) var rows: [HistoryRowView] = []

    override var mouseDownCanMoveWindow: Bool { false }

    init(dayText: String, entries: [HistoryEntry], isSelected: (HistoryEntry) -> Bool,
         onOpen: @escaping (HistoryEntry) -> Void, onDelete: @escaping (HistoryEntry) -> Void,
         onToggleSelect: @escaping (HistoryEntry, Bool) -> Void) {
        self.dayText = dayText
        super.init(frame: .zero)

        let dayLabel = NSTextField(labelWithString: dayText)
        dayLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        dayLabel.textColor = Theme.paletteText

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
            let row = HistoryRowView(entry: entry, isSelected: isSelected(entry))
            row.onOpen = { onOpen(entry) }
            row.onDelete = { onDelete(entry) }
            row.onToggleSelect = { onToggleSelect(entry, $0) }
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

        for v in [dayLabel, card] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            dayLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            dayLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            dayLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: dayLabel.bottomAnchor, constant: 10),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class HistoryFlippedView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 歷史視窗的內容：搜尋欄（或多選時的選取工具列）+ 捲動的日期卡片清單 + 底部「Clear History…」。
@MainActor
final class HistoryView: NSView {
    let search = NSSearchField()
    let clearButton = NSButton(title: "Clear History…", target: nil, action: nil)

    // 多選工具列（仿 Arc：✕ 取消選取、「N selected」、Open、Delete）。
    private let selectionBar = NSView()
    let clearSelectionButton = NSButton(title: "", target: nil, action: nil)
    private let selectionCountLabel = NSTextField(labelWithString: "")
    let openSelectedButton = NSButton(title: "Open", target: nil, action: nil)
    let deleteSelectedButton = NSButton(title: "Delete", target: nil, action: nil)

    private let scroll = NSScrollView()
    private let listDoc = HistoryFlippedView()
    private let list = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No History")

    private(set) var dayCards: [HistoryDayCardView] = []

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.historyBackground.cgColor

        search.placeholderString = "Search History"
        search.focusRingType = .none
        search.font = .systemFont(ofSize: 14)

        clearSelectionButton.isBordered = false
        clearSelectionButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Clear selection")
        clearSelectionButton.contentTintColor = Theme.paletteMuted
        selectionCountLabel.font = .systemFont(ofSize: 13, weight: .medium)
        selectionCountLabel.textColor = Theme.paletteText
        openSelectedButton.bezelStyle = .rounded
        deleteSelectedButton.bezelStyle = .rounded
        let bar = NSStackView(views: [clearSelectionButton, selectionCountLabel, NSView(), openSelectedButton, deleteSelectedButton])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 10
        bar.translatesAutoresizingMaskIntoConstraints = false
        selectionBar.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: selectionBar.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: selectionBar.trailingAnchor),
            bar.centerYAnchor.constraint(equalTo: selectionBar.centerYAnchor),
        ])
        selectionBar.isHidden = true

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 16
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
        clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        clearButton.imagePosition = .imageLeading

        emptyLabel.textColor = Theme.paletteMuted
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        for v in [search, selectionBar, scroll, clearButton, emptyLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            search.heightAnchor.constraint(equalToConstant: 32),
            selectionBar.topAnchor.constraint(equalTo: search.topAnchor),
            selectionBar.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            selectionBar.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            selectionBar.heightAnchor.constraint(equalTo: search.heightAnchor),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -14),
            listDoc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            clearButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            clearButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 換一批日期卡片；空清單顯示 emptyText。
    func setGroups(_ cards: [HistoryDayCardView], emptyText: String) {
        dayCards.forEach { $0.removeFromSuperview() }
        dayCards = cards
        for v in cards {
            list.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        emptyLabel.stringValue = emptyText
        emptyLabel.isHidden = !cards.isEmpty
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// n > 0 時換成選取工具列（取代搜尋欄），否則顯示搜尋欄。
    func setSelectionCount(_ n: Int) {
        search.isHidden = n > 0
        selectionBar.isHidden = n == 0
        selectionCountLabel.stringValue = "\(n) selected"
    }

    var isSelectionBarVisible: Bool { !selectionBar.isHidden }
}

/// History 視窗：瀏覽、搜尋、多選開啟/刪除、單筆刪除、清除歷史。
/// 不即時跟著 HistoryStore 變化，每次顯示時重新讀取。
@MainActor
final class HistoryWindowController: NSWindowController {
    /// 顯示的最大筆數（搜尋與不搜尋都用這個上限，避免筆數多時清單過重）。
    static let displayLimit = 300

    private let historyView = HistoryView()
    private let store: HistoryStore
    var onOpen: ((URL) -> Void)?
    /// 使用者按下「Clear History…」；由 controller 決定清除範圍（可彈 alert），完成後呼叫 refresh()。
    var onClearRequested: (() -> Void)?

    private struct EntryID: Hashable {
        let url: String
        let visitedAt: Double
        init(_ entry: HistoryEntry) { url = entry.url; visitedAt = entry.visitedAt }
    }

    /// 目前清單顯示的（已過濾的）資料，供多選的 Open/Delete 反查用。
    private var currentEntries: [HistoryEntry] = []
    private var selected: Set<EntryID> = []

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    init(store: HistoryStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 680),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
        window.title = "History"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 460, height: 360)
        window.contentView = historyView
        window.center()
        super.init(window: window)
        historyView.search.target = self
        historyView.search.action = #selector(searchChanged)
        historyView.clearButton.target = self
        historyView.clearButton.action = #selector(clearClicked)
        historyView.clearSelectionButton.target = self
        historyView.clearSelectionButton.action = #selector(clearSelectionClicked)
        historyView.openSelectedButton.target = self
        historyView.openSelectedButton.action = #selector(openSelectedClicked)
        historyView.deleteSelectedButton.target = self
        historyView.deleteSelectedButton.action = #selector(deleteSelectedClicked)
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    var searchField: NSSearchField { historyView.search }
    var dayCards: [HistoryDayCardView] { historyView.dayCards }
    var clearButton: NSButton { historyView.clearButton }
    var clearSelectionButton: NSButton { historyView.clearSelectionButton }
    var openSelectedButton: NSButton { historyView.openSelectedButton }
    var deleteSelectedButton: NSButton { historyView.deleteSelectedButton }
    var selectedCount: Int { selected.count }
    var isSelectionMode: Bool { historyView.isSelectionBarVisible }

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
        currentEntries = entries
        selected = selected.intersection(entries.map(EntryID.init))
        historyView.setGroups(groupedCards(entries), emptyText: query.isEmpty ? "No History" : "No Results")
        historyView.setSelectionCount(selected.count)
    }

    private func groupedCards(_ entries: [HistoryEntry]) -> [HistoryDayCardView] {
        var cards: [HistoryDayCardView] = []
        var currentDay: String?
        var bucket: [HistoryEntry] = []
        let cal = Calendar.current
        func flush() {
            guard let day = currentDay, !bucket.isEmpty else { return }
            cards.append(makeCard(day: day, entries: bucket))
            bucket = []
        }
        for entry in entries {
            let label = Self.dayLabel(for: Date(timeIntervalSince1970: entry.visitedAt), calendar: cal)
            if label != currentDay { flush(); currentDay = label }
            bucket.append(entry)
        }
        flush()
        return cards
    }

    private func makeCard(day: String, entries: [HistoryEntry]) -> HistoryDayCardView {
        HistoryDayCardView(
            dayText: day, entries: entries,
            isSelected: { [weak self] in self?.selected.contains(EntryID($0)) == true },
            onOpen: { [weak self] in self?.open($0) },
            onDelete: { [weak self] in self?.delete($0) },
            onToggleSelect: { [weak self] entry, on in self?.toggleSelection(entry, on: on) })
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

    private func toggleSelection(_ entry: HistoryEntry, on: Bool) {
        let id = EntryID(entry)
        if on { selected.insert(id) } else { selected.remove(id) }
        historyView.setSelectionCount(selected.count)
    }

    @objc private func clearSelectionClicked() {
        selected.removeAll()
        reload()
    }

    @objc private func openSelectedClicked() {
        for entry in currentEntries where selected.contains(EntryID(entry)) { open(entry) }
        selected.removeAll()
        reload()
    }

    @objc private func deleteSelectedClicked() {
        for entry in currentEntries where selected.contains(EntryID(entry)) { store.delete(entry) }
        selected.removeAll()
        reload()
    }

    @objc private func clearClicked() { onClearRequested?() }
}
