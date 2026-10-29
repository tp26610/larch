import AppKit

/// Command Palette 的動作表（對應 my-browser main.js 的 ACTIONS）。新增動作只要在 `all` 加一項。
/// 動作一律呼叫 controller 既有的方法（與選單同一份邏輯）。
struct PaletteAction {
    let id: String
    /// 標題可依狀態變化（例如 Pin / Unpin）。
    let title: @MainActor (BrowserWindowController) -> String
    let keywords: String
    /// 快捷鍵提示（顯示用）。
    let shortcut: String?
    /// 不適用目前狀態時為 false，動作不列出。
    let isAvailable: @MainActor (BrowserWindowController) -> Bool
    let run: @MainActor (BrowserWindowController) -> Void
}

@MainActor
enum PaletteActions {
    private static func fixed(_ s: String) -> @MainActor (BrowserWindowController) -> String { { _ in s } }
    private static let always: @MainActor (BrowserWindowController) -> Bool = { _ in true }
    private static let hasTab: @MainActor (BrowserWindowController) -> Bool = { $0.tabs.activeTab != nil }
    private static let hasPage: @MainActor (BrowserWindowController) -> Bool = { InputNormalizer.isHTTP($0.tabs.activeTab?.displayURL) }

    static let all: [PaletteAction] = [
        PaletteAction(id: "restore", title: fixed("Restore Last Closed Tab"), keywords: "reopen undo closed recent", shortcut: "⌘⇧T",
                      isAvailable: { !$0.tabs.closedStack.isEmpty }, run: { $0.restoreTab() }),
        PaletteAction(id: "previousTab", title: fixed("Switch to Previous Tab"), keywords: "mru recent last back switch", shortcut: "⌃⇥",
                      isAvailable: { $0.tabs.tabs.count >= 2 }, run: { $0.switchToPreviousTab() }),
        PaletteAction(id: "new", title: fixed("New Blank Tab"), keywords: "create open empty", shortcut: nil,
                      isAvailable: always, run: { $0.newBlankTab() }),
        PaletteAction(id: "close", title: fixed("Close Tab"), keywords: "remove", shortcut: "⌘W",
                      isAvailable: hasTab, run: { $0.closeCurrentTab() }),
        PaletteAction(id: "closeOthers", title: fixed("Close Other Tabs"), keywords: "clean up remove", shortcut: nil,
                      isAvailable: { $0.otherRegularTabs().count > 0 }, run: { $0.closeOtherTabs() }),
        PaletteAction(id: "unsplit", title: fixed("Exit Split View"), keywords: "split unsplit combine side by side", shortcut: nil,
                      isAvailable: { $0.tabs.activeTab?.splitPartner != nil }, run: { $0.exitSplitView() }),
        PaletteAction(id: "duplicate", title: fixed("Duplicate Tab"), keywords: "copy clone", shortcut: "⌃⇧D",
                      isAvailable: hasPage, run: { $0.duplicateTab() }),
        PaletteAction(id: "reload", title: fixed("Reload Tab"), keywords: "refresh", shortcut: "⌘R",
                      isAvailable: hasTab, run: { $0.reload() }),
        PaletteAction(id: "copyUrl", title: fixed("Copy Tab URL"), keywords: "link address", shortcut: "⌘⇧C",
                      isAvailable: hasPage, run: { $0.copyURL() }),
        PaletteAction(id: "copyMd", title: fixed("Copy Tab URL as Markdown"), keywords: "link address", shortcut: "⌘⌥⇧C",
                      isAvailable: hasPage, run: { $0.copyURLAsMarkdown() }),
        PaletteAction(id: "rename", title: fixed("Rename Tab"), keywords: "title name", shortcut: nil,
                      isAvailable: hasTab, run: { $0.renameActiveTab() }),
        PaletteAction(id: "pin", title: { $0.tabs.activeTab?.pinID == nil ? "Pin Tab" : "Unpin Tab" }, keywords: "pin unpin favorite keep", shortcut: "⌘D",
                      isAvailable: { c in c.tabs.activeTab?.pinID != nil || InputNormalizer.isHTTP(c.tabs.activeTab?.displayURL) }, run: { $0.togglePinAction() }),
        PaletteAction(id: "newFolder", title: fixed("New Folder"), keywords: "pinned group create", shortcut: "⌘⇧N",
                      isAvailable: always, run: { $0.newFolderAction() }),
        PaletteAction(id: "sidebar", title: fixed("Toggle Sidebar"), keywords: "hide show tabs", shortcut: "⌘S / ⌃S",
                      isAvailable: always, run: { $0.toggleSidebar() }),
        PaletteAction(id: "zoomIn", title: fixed("Zoom In"), keywords: "bigger larger", shortcut: "⌘+",
                      isAvailable: hasPage, run: { $0.zoomIn() }),
        PaletteAction(id: "zoomOut", title: fixed("Zoom Out"), keywords: "smaller", shortcut: "⌘-",
                      isAvailable: hasPage, run: { $0.zoomOut() }),
        PaletteAction(id: "zoomReset", title: fixed("Reset Zoom"), keywords: "actual size 100", shortcut: "⌘0",
                      isAvailable: hasPage, run: { $0.zoomReset() }),
        PaletteAction(id: "find", title: fixed("Find in Page"), keywords: "search text", shortcut: "⌘F",
                      isAvailable: hasPage, run: { $0.showFind() }),
        PaletteAction(id: "little", title: fixed("Open in Little Window"), keywords: "peek preview little arc", shortcut: nil,
                      isAvailable: hasPage, run: { $0.openActiveTabInLittle() }),
        PaletteAction(id: "inspector", title: fixed("Open Web Inspector"), keywords: "devtools developer console inspect", shortcut: nil,
                      isAvailable: { $0.canOpenInspector }, run: { $0.openInspector() }),
        PaletteAction(id: "history", title: fixed("Show All History"), keywords: "history past visited browsing", shortcut: "⌘Y",
                      isAvailable: always, run: { $0.showHistory() }),
        PaletteAction(id: "clearHistory", title: fixed("Clear History…"), keywords: "delete erase browsing data", shortcut: nil,
                      isAvailable: always, run: { $0.confirmClearHistory() }),
        PaletteAction(id: "taskManager", title: fixed("Show Task Manager"), keywords: "memory process cpu performance", shortcut: nil,
                      isAvailable: always, run: { $0.showTaskManager() }),
    ]

    static func find(_ id: String) -> PaletteAction? { all.first { $0.id == id } }
}
