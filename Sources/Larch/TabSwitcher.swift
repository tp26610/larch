import AppKit

/// Ctrl+Tab 最近使用（MRU）切換。事件在 `LarchWindow.sendEvent` 處理（keyDown Tab+Control、flagsChanged 放開 Control、Esc）。
/// 不能像 Electron 版踩過的坑那樣在別處吞掉按鍵而收不到 Ctrl 放開：AppKit 的 flagsChanged 是獨立事件，
/// 在 key window 的 sendEvent 一定收得到（不論焦點在 WKWebView、欄位或覆蓋層）。
@MainActor
final class TabSwitcher {
    unowned let controller: BrowserWindowController
    /// 按住超過這個時間才顯示清單（快速按一下不閃）。
    var showDelay: TimeInterval = 0.15
    /// 閒置超過這個時間自動確認。
    var idleTimeout: TimeInterval = 10

    private(set) var isActive = false
    private(set) var isShowing = false
    private(set) var list: [Tab] = []
    private(set) var index = 0
    private var showWork: DispatchWorkItem?
    private var idleWork: DispatchWorkItem?

    init(controller: BrowserWindowController) { self.controller = controller }

    /// 回傳 true 代表事件已處理（不再往下送）。
    func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 48, mods.contains(.control), !mods.contains(.command), !mods.contains(.option) {
                // 命令列（⌘T/⌘L）開啟時不處理，避免和它自己的 Tab 鍵（動作模式）打架。
                if controller.root.palette.isOpen && !isShowing { return true }
                step(mods.contains(.shift) ? -1 : 1)
                return true
            }
            if isActive, event.keyCode == 53 { cancel(); return true }
            return false
        case .flagsChanged:
            if isActive, !event.modifierFlags.contains(.control) { commit() }
            return false
        default:
            return false
        }
    }

    /// 視窗失去 key（Ctrl 可能在 app 外放開，收不到事件）：直接確認。
    private(set) var resignCommits = 0
    func resignKey() { if isActive { resignCommits += 1; commit() } }

    private func step(_ delta: Int) {
        if !isActive {
            begin(reverse: delta < 0)
            return
        }
        guard !list.isEmpty else { return }
        index = (index + delta + list.count) % list.count
        if isShowing { controller.root.palette.setSwitcherSelection(index) }
        scheduleIdle()
    }

    private func begin(reverse: Bool) {
        list = controller.tabs.mruTabs
        guard list.count >= 2 else { list = []; return } // 只有一個 Tab：沒得切，也不顯示
        index = reverse ? list.count - 1 : 1
        isActive = true
        isShowing = false
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.showUI() } }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
        scheduleIdle()
    }

    private func showUI() {
        guard isActive, !isShowing else { return }
        isShowing = true
        let items = list.map { tab in
            PaletteItem(kind: .tab, title: tab.displayTitle, subtitle: tab.displayURL?.absoluteString ?? "",
                        action: .switchTab(tab), icon: tab.favicon)
        }
        controller.root.palette.presentSwitcher(items: items, selected: index)
    }

    private func scheduleIdle() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.commit() } }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }

    private func finish() {
        showWork?.cancel(); idleWork?.cancel()
        showWork = nil; idleWork = nil
        if isShowing { controller.root.palette.hideSwitcher() }
        isActive = false
        isShowing = false
    }

    /// 確認切換到選取的 Tab（沒顯示 UI 時就是「快速按一下」）。
    func commit() {
        guard isActive else { return }
        let target = list.indices.contains(index) ? list[index] : nil
        finish()
        list = []
        if let target, controller.tabs.tabs.contains(where: { $0 === target }) {
            controller.tabs.select(target)
            controller.window.makeFirstResponder(target.webView)
        }
    }

    func cancel() {
        guard isActive else { return }
        finish()
        list = []
    }
}
