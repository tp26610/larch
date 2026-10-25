import AppKit
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: BrowserWindowController!
    let smoke: Bool

    init(smoke: Bool) { self.smoke = smoke }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        // smoke 用暫存的 data store，不污染真實 cookie。
        let store: WKWebsiteDataStore = smoke ? .nonPersistent() : .default()
        let storage = smoke ? Storage(directory: FileManager.default.temporaryDirectory.appendingPathComponent("larch-smoke-\(getpid())"))
                            : .standard
        controller = BrowserWindowController(dataStore: store, storage: storage, downloads: DownloadManager(directory: smoke ? storage.directory.appendingPathComponent("Downloads") : FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]), zoom: ZoomStore(defaults: smoke ? (UserDefaults(suiteName: "larch-smoke-\(getpid())") ?? .standard) : .standard), autosave: !smoke)
        NSApp.activate(ignoringOtherApps: true)
        // 命令列給的網址在新分頁開啟（open -a ... --args URL）。
        for arg in CommandLine.arguments.dropFirst() {
            if let input = InputNormalizer.normalize(arg), input.kind == .url { controller.tabs.newTab(url: input.url) }
        }
        if !pendingURLs.isEmpty { controller.openExternal(pendingURLs); pendingURLs = [] }
        if let i = CommandLine.arguments.firstIndex(of: "--live-check"), i + 2 < CommandLine.arguments.count {
            let url = CommandLine.arguments[i + 1], out = CommandLine.arguments[i + 2]
            Task { @MainActor in await Smoke.liveCheck(self, url: url, outPrefix: out) }
        } else if smoke {
            Task { @MainActor in await Smoke.run(self) }
        }
    }

    /// 冷啟動時可能在 controller 建好之前就收到網址，先暫存。
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let controller { controller.openExternal(urls) } else { pendingURLs += urls }
    }

    @objc func makeDefaultBrowser() {
        let appURL = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                if let error { NSLog("Larch: 設為預設瀏覽器失敗（\(scheme)）：\(error.localizedDescription)") }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { controller?.flushPersistence() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller.window.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: 選單（快捷鍵全部走選單，避免與網頁內容搶按鍵）

    @objc func newTab() { controller.newTab() }
    @objc func closeTab() { controller.closeCurrentTab() }
    @objc func restoreTab() { controller.restoreTab() }
    @objc func focusAddress() { controller.focusAddress() }
    @objc func reload() { controller.reload() }
    @objc func goBack() { controller.goBack() }
    @objc func goForward() { controller.goForward() }
    @objc func toggleSidebar() { controller.toggleSidebar() }
    @objc func showFind() { controller.showFind() }
    @objc func findNext() { controller.findMenuNext() }
    @objc func findPrevious() { controller.findMenuPrevious() }
    @objc func zoomIn() { controller.zoomIn() }
    @objc func zoomOut() { controller.zoomOut() }
    @objc func zoomReset() { controller.zoomReset() }
    @objc func copyURL() { controller.copyURL() }

    func buildMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        func item(_ title: String, _ sel: Selector?, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        let me = self
        add("Larch", [
            item("About Larch", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            item("Make Default Browser…", #selector(makeDefaultBrowser), target: me),
            .separator(),
            item("Hide Larch", #selector(NSApplication.hide(_:)), "h"),
            item("Quit Larch", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("File", [
            item("New Tab", #selector(newTab), "t", target: me),
            item("Open Location", #selector(focusAddress), "l", target: me),
            item("Close Tab", #selector(closeTab), "w", target: me),
            item("Close Tab (Ctrl+W)", #selector(closeTab), "w", .control, target: me),
            item("Restore Closed Tab", #selector(restoreTab), "T", [.command, .shift], target: me),
        ])
        add("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            .separator(),
            item("Find…", #selector(showFind), "f", target: me),
            item("Find Next", #selector(findNext), "g", target: me),
            item("Find Previous", #selector(findPrevious), "G", [.command, .shift], target: me),
            .separator(),
            item("Copy URL", #selector(copyURL), "C", [.command, .shift], target: me),
        ])
        add("View", [
            item("Toggle Sidebar", #selector(toggleSidebar), "s", target: me),
            item("Zoom In", #selector(zoomIn), "+", target: me),
            item("Zoom In (⌘=)", #selector(zoomIn), "=", target: me),
            item("Zoom Out", #selector(zoomOut), "-", target: me),
            item("Actual Size", #selector(zoomReset), "0", target: me),
            .separator(),
            item("Reload", #selector(reload), "r", target: me),
            item("Back", #selector(goBack), "[", target: me),
            item("Forward", #selector(goForward), "]", target: me),
        ])
        add("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ])
        return main
    }
}
