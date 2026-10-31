import AppKit

/// 獨立於主視窗的輔助視窗（Little、History、Task Manager…）。
/// 選單動作的 target 固定是 AppDelegate，不隨 key window 改變，所以「現在該動誰」由
/// `BrowserWindowController.keyAuxiliary` 統一判斷；新增獨立視窗只要實作這個協定並加進
/// `BrowserWindowController.auxiliaryWindows`，⌘W 與選單停用規則就自動涵蓋（見 CLAUDE.md 第 23、26、28 點）。
@MainActor
protocol AuxiliaryWindow: AnyObject {
    var auxWindow: NSWindow? { get }
    /// 作用在頁面的選單動作（重新整理、上一頁/下一頁、縮放、複製網址）是否以這個視窗的頁面為目標。
    var handlesPageActions: Bool { get }
    func close()
}

extension HistoryWindowController: AuxiliaryWindow {
    var auxWindow: NSWindow? { window }
    var handlesPageActions: Bool { false }
}

extension TaskManagerWindowController: AuxiliaryWindow {
    var auxWindow: NSWindow? { window }
    var handlesPageActions: Bool { false }
}

extension LittleWindowController: AuxiliaryWindow {
    var auxWindow: NSWindow? { window }
    var handlesPageActions: Bool { true }
}
