import AppKit

/// 主視窗。標題列隱藏且以 isMovableByWindowBackground 拖曳，系統不會處理這些區域的雙擊，這裡補上。
final class LarchWindow: NSWindow {
    /// 依系統設定（AppleActionOnDoubleClick）決定雙擊 bar 的行為。
    enum DoubleClickAction { case zoom, minimize, none }

    static func doubleClickAction(defaults: UserDefaults = .standard) -> DoubleClickAction {
        switch defaults.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": return .minimize
        case "None": return .none
        default: return .zoom // Maximize / 未設定
        }
    }

    /// 雙擊落在可拖曳視窗的區域（外框、側邊欄空白處）才處理；網頁卡片、Tab 列、按鈕、網址列不算。
    func isDraggableBar(at point: NSPoint) -> Bool {
        guard let content = contentView, let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point) else { return false }
        // 子視圖（如 Tab 列裡的文字）可能預設可拖曳，所以整條祖先鏈都要允許才算。
        var v: NSView? = hit
        while let view = v {
            if !view.mouseDownCanMoveWindow { return false }
            v = view.superview
        }
        return true
    }

    /// 回傳是否已處理（呼叫端就不再交給 super）。
    @MainActor
    @discardableResult
    func handleDoubleClick(at point: NSPoint, defaults: UserDefaults = .standard) -> Bool {
        guard isDraggableBar(at: point) else { return false }
        switch Self.doubleClickAction(defaults: defaults) {
        case .zoom: performZoom(nil)
        case .minimize: performMiniaturize(nil)
        case .none: break
        }
        return true
    }

    /// 焦點在網頁時，WKWebView 會先把按鍵交給網頁、沒被 preventDefault 才非同步回頭送選單，
    /// 網頁（如線上文件）可以擋掉關閉 Tab。⌘W / Ctrl+W / Ctrl+S 在這裡直接交給選單，同步且不可被網頁攔截。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if event.type == .keyDown, (key == "w" && (mods == .control || mods == .command)) || (key == "s" && mods == .control),
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2, MainActor.assumeIsolated({ handleDoubleClick(at: event.locationInWindow) }) { return }
        super.sendEvent(event)
    }
}
