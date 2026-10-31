import AppKit

/// 使用者偏好（UserDefaults）。smoke 以暫存的 suite 注入，不碰真實設定。
struct Preferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// 外部連結（預設瀏覽器收到的連結）是否在 Little 視窗開啟；預設開啟（Arc 的行為）。
    var externalLinksInLittle: Bool {
        get { defaults.object(forKey: "openExternalInLittle") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "openExternalInLittle") }
    }

    /// 上次調整的 Little 視窗大小。
    var littleSize: NSSize {
        get {
            let w = defaults.double(forKey: "littleWidth"), h = defaults.double(forKey: "littleHeight")
            return w >= 360 && h >= 280 ? NSSize(width: w, height: h) : NSSize(width: 960, height: 720)
        }
        nonmutating set {
            defaults.set(Double(newValue.width), forKey: "littleWidth")
            defaults.set(Double(newValue.height), forKey: "littleHeight")
        }
    }

    /// 使用者拖曳調整過的側邊欄寬度；超出範圍（或沒存過）用預設值。
    var sidebarWidth: CGFloat {
        get {
            let w = defaults.double(forKey: "sidebarWidth").rounded() // 舊版存過帶小數的寬度
            return Theme.sidebarWidthRange.contains(w) ? w : Theme.sidebarWidth
        }
        nonmutating set { defaults.set(Double(newValue), forKey: "sidebarWidth") }
    }
}
