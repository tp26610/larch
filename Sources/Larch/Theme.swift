import AppKit

enum Theme {
    static let sidebarWidth: CGFloat = 264
    static let sidebarWidthRange: ClosedRange<CGFloat> = 200...420
    static let margin: CGFloat = 8
    static let cardRadius: CGFloat = 10

    // Sage green frame/sidebar sampled from Arc's theme (#699987); other tones are overlays on it.
    static let panel = NSColor(srgbRed: 0x69 / 255, green: 0x99 / 255, blue: 0x87 / 255, alpha: 1)
    static let card = NSColor.white
    static let field = NSColor(white: 1, alpha: 0.22)
    static let hover = NSColor(white: 1, alpha: 0.14)
    static let active = NSColor(white: 1, alpha: 0.28)
    static let text = NSColor(white: 1, alpha: 0.95)
    static let muted = NSColor(white: 1, alpha: 0.72)
    static let accent = NSColor(white: 1, alpha: 0.95)
}

extension Theme {
    // 命令列覆蓋層（亮色面板，與白色網頁卡片一致）。
    static let paletteBackground = NSColor.white
    static let paletteBorder = NSColor(white: 0, alpha: 0.12)
    static let paletteText = NSColor(white: 0.1, alpha: 1)
    static let paletteMuted = NSColor(white: 0.42, alpha: 1)
    static let paletteSelection = NSColor(srgbRed: 0x69 / 255, green: 0x99 / 255, blue: 0x87 / 255, alpha: 0.22)
    static let paletteRadius: CGFloat = 14
}

extension Theme {
    // 載入進度條：亮色卡片上要看得清楚，比 panel 深的綠。
    static let progress = NSColor(srgbRed: 0x1F / 255, green: 0x7A / 255, blue: 0x5C / 255, alpha: 1)
}

extension Theme {
    // Little 視窗：白色色調，與主視窗的鼠尾草綠一眼區分（仿 Arc 的 Little Arc）。
    static let littleFrame = NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF3 / 255, alpha: 1)
    static let littleBorder = NSColor(white: 0, alpha: 0.18)
    static let littleToolbarText = NSColor(white: 0.16, alpha: 1)
    static let littleMuted = NSColor(white: 0.42, alpha: 1)
    static let littleIcon = NSColor(white: 0.32, alpha: 1)
    static let littlePill = NSColor(white: 0, alpha: 0.07)
    static let littleButton = NSColor(white: 0, alpha: 0.08)
}
