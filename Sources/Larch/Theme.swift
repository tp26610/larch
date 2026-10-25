import AppKit

enum Theme {
    static let sidebarWidth: CGFloat = 264
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
