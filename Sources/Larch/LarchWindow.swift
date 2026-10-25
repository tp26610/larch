import AppKit

/// 主視窗：攔截 ⌘W / Ctrl+W 的按鍵路徑。
final class LarchWindow: NSWindow {
    /// 焦點在網頁時，WKWebView 會先把按鍵交給網頁、沒被 preventDefault 才非同步回頭送選單，
    /// 網頁（如線上文件）可以擋掉關閉 Tab。⌘W / Ctrl+W 在這裡直接交給選單，同步且不可被網頁攔截。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock])
        if event.type == .keyDown, mods == .control || mods == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w", NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
