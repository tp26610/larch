import AppKit

enum Theme {
    static let sidebarWidth: CGFloat = 264
    static let margin: CGFloat = 8
    static let cardRadius: CGFloat = 10

    static let panel = NSColor(srgbRed: 0x1b / 255, green: 0x1d / 255, blue: 0x22 / 255, alpha: 1)
    static let card = NSColor(srgbRed: 0x15 / 255, green: 0x16 / 255, blue: 0x1a / 255, alpha: 1)
    static let hover = NSColor(srgbRed: 0x26 / 255, green: 0x29 / 255, blue: 0x32 / 255, alpha: 1)
    static let active = NSColor(srgbRed: 0x2f / 255, green: 0x33 / 255, blue: 0x40 / 255, alpha: 1)
    static let text = NSColor(srgbRed: 0xe6 / 255, green: 0xe7 / 255, blue: 0xea / 255, alpha: 1)
    static let muted = NSColor(srgbRed: 0x8b / 255, green: 0x90 / 255, blue: 0xa0 / 255, alpha: 1)
    static let accent = NSColor(srgbRed: 0x7a / 255, green: 0xa2 / 255, blue: 0xff / 255, alpha: 1)
}
