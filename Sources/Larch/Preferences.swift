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

    /// ⌘Q 與沒有 Tab 時按 ⌘W 是否跳出「Quit Larch?」確認；選「Quit, and don't ask again」後為 false。
    var confirmQuitOnEmpty: Bool {
        get { defaults.object(forKey: "confirmQuitOnEmpty") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "confirmQuitOnEmpty") }
    }

    /// 使用者允許「某網站直接開啟某 scheme 的外部 App」的記錄，格式 `scheme|host`（仿 Chrome：按網站記，不是全域）。
    var allowedExternalApps: Set<String> {
        get { Set(defaults.stringArray(forKey: "allowedExternalApps") ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: "allowedExternalApps") }
    }

    /// slack.com 與其子網域預設可開 slack://（桌面 App 登入交接）；其餘看使用者記錄。
    func isExternalAppAllowed(scheme: String, host: String) -> Bool {
        let h = host.lowercased(), s = scheme.lowercased()
        if s == "slack", h == "slack.com" || h.hasSuffix(".slack.com") { return true }
        return !h.isEmpty && allowedExternalApps.contains("\(s)|\(h)")
    }

    func allowExternalApp(scheme: String, host: String) {
        guard !host.isEmpty else { return }
        allowedExternalApps.insert("\(scheme.lowercased())|\(host.lowercased())")
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
