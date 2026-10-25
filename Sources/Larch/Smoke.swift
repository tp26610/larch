import AppKit
import Network
import WebKit

/// 本機假網站（Network.framework），讓 smoke 不依賴外網。
final class FixtureServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fixture")
    private(set) var port: UInt16 = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let once = OnceBox()
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state, let self, once.take() {
                    self.port = self.listener.port?.rawValue ?? 0
                    c.resume()
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    private final class OnceBox: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let req = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            let path = req.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            if path.hasPrefix("/auth") {
                let ok = req.contains("Authorization: Basic dGVzdDpwdw==")
                let body = ok ? Self.html("Authed", "ok") : Self.html("Denied")
                let head = ok ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"Fixture\"\r\n"
                let full = head + "Content-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(full.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
                return
            }
            let (type, body, delay) = Self.route(path)
            let extra = path.hasPrefix("/file") ? "Content-Disposition: attachment; filename=\"report.txt\"\r\n" : ""
            let head = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\n\(extra)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            self.queue.asyncAfter(deadline: .now() + delay) {
                conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
    }

    private static func html(_ title: String, _ body: String = "", head: String = "") -> Data {
        Data("<!doctype html><html><head><meta charset=\"utf-8\"><title>\(title)</title>\(head)</head><body>\(body)</body></html>".utf8)
    }

    private static func route(_ path: String) -> (String, Data, Double) {
        switch path.split(separator: "?").first.map(String.init) ?? "/" {
        case "/a": return ("text/html; charset=utf-8", html("Page A", "<h1>A</h1>", head: "<link rel=\"icon\" href=\"/icon.png\">"), 0)
        case "/doc": return ("text/html; charset=utf-8", html("Design Notes — Little Window", "<style>body{font:16px -apple-system,sans-serif;max-width:640px;margin:40px auto;color:#222}h1{font-size:28px}p{line-height:1.6;color:#444}</style><h1>Design notes</h1><p>Peek at a link in a small window, then close it or add it to your tabs. The page keeps its scroll position and login when it moves.</p><p>Press Esc or ⌘W to close. Press ⌘O or ⌘Return to add it to Tabs.</p>"), 0)
        case "/b": return ("text/html; charset=utf-8", html("Page B", "<h1>B</h1>"), 0)
        case "/c": return ("text/html; charset=utf-8", html("頁面 C"), 0)
        case "/slow": return ("text/html; charset=utf-8", html("Slow Page"), 1.5)
        case "/text": return ("text/html; charset=utf-8", html("Text Page", "<p>alpha needle beta</p>"), 0)
        case "/popup": return ("text/html; charset=utf-8", html("Popup Opener", "<a id=\"l\" href=\"/b\" target=\"_blank\">b</a><a id=\"n\" href=\"/child\" target=\"pop\">c</a><script>addEventListener('message',e=>{document.title='got:'+e.data})</script>"), 0)
        case "/child": return ("text/html; charset=utf-8", html("Child", "<script>if(window.opener){window.opener.postMessage('hi','*');window.close()}</script>"), 0)
        case "/xss": return ("text/html; charset=utf-8", html("<img src=x onerror=document.title='pwned'>"), 0)
        case "/file": return ("text/plain", Data("hello download".utf8), 0)
        case "/icon.png":
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            return ("image/png", rep.representation(using: .png, properties: [:]) ?? Data(), 0)
        default: return ("text/html; charset=utf-8", html("Home"), 0)
        }
    }
}

@MainActor
enum Smoke {
    static var passed = 0
    static var failed = 0

    static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if ok { passed += 1; print("  ok   \(name)") } else { failed += 1; print("  FAIL \(name) \(detail())") }
    }

    static func wait(_ timeout: Double = 8, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return cond()
    }

    static func keyEvent(_ chars: String, _ mods: NSEvent.ModifierFlags, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: mods.contains(.shift) ? chars.uppercased() : chars, charactersIgnoringModifiers: mods.contains(.shift) ? chars.uppercased() : chars,
                         isARepeat: false, keyCode: 0)!
    }

    /// 走真實選單的快捷鍵比對（與按鍵實際路徑一致）。
    static func press(_ chars: String, _ mods: NSEvent.ModifierFlags, in window: NSWindow) -> Bool {
        NSApp.mainMenu?.performKeyEquivalent(with: keyEvent(chars, mods, in: window)) ?? false
    }

    static func run(_ app: AppDelegate) async {
        setvbuf(stdout, nil, _IOLBF, 0)
        do { try await body(app) } catch { print("  FAIL exception \(error)"); failed += 1 }
        UserDefaults.standard.removePersistentDomain(forName: "larch-smoke-\(getpid())")
        print("\n\(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }

    /// 真實網站檢查：載入網址、印出標題與最終網址，並把側邊欄與網頁各存成 PNG（不需要螢幕錄製權限）。
    /// 用法：Larch --live-check https://accounts.google.com /tmp/out  → /tmp/out-sidebar.png、/tmp/out-page.png
    static func liveCheck(_ app: AppDelegate, url: String, outPrefix: String) async {
        let c = app.controller!
        c.submitAddress(url)
        _ = await wait(20) { c.tabs.activeTab?.isLoading == false && c.tabs.activeTab?.url != nil }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        guard let tab = c.tabs.activeTab else { exit(1) }
        print("title: \(tab.pageTitle)\nurl: \(tab.url?.absoluteString ?? "-")\nfavicon: \(tab.favicon != nil)")
        func save(_ image: NSImage?, _ path: String) {
            guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: path))
        }
        save(await withCheckedContinuation { k in tab.webView.takeSnapshot(with: nil) { img, _ in k.resume(returning: img) } }, outPrefix + "-page.png")
        let sb = c.sidebar
        if let rep = sb.bitmapImageRepForCachingDisplay(in: sb.bounds) {
            sb.cacheDisplay(in: sb.bounds, to: rep)
            let img = NSImage(size: sb.bounds.size); img.addRepresentation(rep)
            save(img, outPrefix + "-sidebar.png")
        }
        exit(0)
    }

    static func body(_ app: AppDelegate) async throws {
        let server = try FixtureServer()
        await server.start()
        let c = app.controller!
        let tm = c.tabs

        print("normalizeInput")
        let n = InputNormalizer.normalize
        check("完整網址", n("https://example.com/x")?.url.absoluteString == "https://example.com/x")
        check("裸網域補 https", n("example.com")?.url.absoluteString == "https://example.com")
        check("localhost 用 http", n("localhost:3000/a")?.url.absoluteString == "http://localhost:3000/a")
        check("IP 用 http", n("127.0.0.1:8080")?.url.absoluteString == "http://127.0.0.1:8080")
        check("空白轉搜尋", n("hello world")?.kind == .search)
        check("中文轉搜尋並編碼", n("你好")?.url.absoluteString.hasPrefix(InputNormalizer.searchPrefix + "%E4%BD%A0") == true)
        check("拒絕 file:", n("file:///etc/passwd") == nil)
        check("拒絕 javascript:", n("javascript://x") == nil)
        check("空字串", n("   ") == nil)

        print("啟動")
        check("啟動時有一個空白分頁", tm.tabs.count == 1 && tm.activeTab?.url == nil)
        check("視窗可見", c.window.isVisible)
        check("網址列取得焦點", c.addressField.currentEditor() != nil)

        print("網址列導航")
        c.addressField.stringValue = server.url("/a").absoluteString
        check("Enter 送出成功", c.submitAddress(c.addressField.stringValue))
        check("載入 Page A", await wait { tm.activeTab?.pageTitle == "Page A" })
        check("網址列顯示網址", await wait { c.addressField.stringValue == server.url("/a").absoluteString })
        check("側邊欄標題", c.sidebar.rowViews.first?.titleText == "Page A")
        check("favicon 載入", await wait { tm.activeTab?.favicon != nil })

        print("新增與切換")
        let t1 = tm.activeTab!
        let t2 = tm.newTab(url: server.url("/b"))
        check("新增後有兩個 Tab 且切到新的", tm.tabs.count == 2 && tm.activeTab === t2)
        check("側邊欄兩列", c.sidebar.rowViews.count == 2)
        check("卡片顯示新 Tab 的 view", c.root.card.subviews.first === t2.webView)
        check("載入 Page B", await wait { t2.pageTitle == "Page B" })
        tm.select(t1)
        check("切回第一個", tm.activeTab === t1 && c.root.card.subviews.first === t1.webView)
        check("網址列跟著切換", c.addressField.stringValue == server.url("/a").absoluteString)

        print("上一頁 / 下一頁 / 重新整理")
        c.submitAddress(server.url("/c").absoluteString)
        check("中文標題不亂碼", await wait { t1.pageTitle == "頁面 C" })
        check("可後退", await wait { c.sidebar.backButton.isEnabled })
        c.goBack()
        check("後退到 A", await wait { t1.pageTitle == "Page A" })
        check("可前進", await wait { c.sidebar.forwardButton.isEnabled })
        c.goForward()
        check("前進到 C", await wait { t1.pageTitle == "頁面 C" })
        c.reload()
        check("重新整理後仍在 C", await wait { !t1.isLoading } && t1.pageTitle == "頁面 C")

        print("載入指示（Tab 列）")
        c.submitAddress(server.url("/slow").absoluteString)
        let row1 = c.sidebar.rowViews[0]
        check("載入中 Tab 列顯示 spinner", await wait { row1.isShowingSpinner })
        check("載入完成 spinner 消失", await wait(6) { !row1.isShowingSpinner && t1.pageTitle == "Slow Page" })

        print("關閉與還原")
        tm.select(t2)
        c.closeCurrentTab()
        check("關閉後剩一個並切到它", tm.tabs.count == 1 && tm.activeTab === t1)
        check("closedStack 記下 http URL", tm.closedStack.last?.url == server.url("/b"))
        let blank = tm.newTab()
        c.closeCurrentTab()
        check("空白分頁不進 closedStack", tm.closedStack.count == 1 && blank.url == nil)
        check("⌘⇧T 走選單還原", press("t", [.command, .shift], in: c.window))
        check("還原後 URL 正確", await wait { tm.activeTab?.url == server.url("/b") } && tm.closedStack.isEmpty)
        check("還原後載入 Page B", await wait { tm.activeTab?.pageTitle == "Page B" })
        for i in 0..<30 { // 上限 25
            let t = tm.newTab(url: server.url("/b?\(i)"))
            _ = await wait { t.url != nil }
            tm.close(t)
        }
        check("closedStack 最多 25 筆", tm.closedStack.count == TabManager.maxClosed)
        while tm.restoreLast() != nil {}
        while tm.tabs.count > 1 { tm.close(tm.tabs.last!) }
        check("清理後剩一個 Tab", tm.tabs.count == 1)
        let last = tm.tabs[0]
        tm.close(last)
        check("關掉最後一個會補一個空白分頁", tm.tabs.count == 1 && tm.activeTab?.url == nil)

        print("改名")
        let t = tm.activeTab!
        c.submitAddress(server.url("/a").absoluteString)
        _ = await wait { t.pageTitle == "Page A" }
        let row = c.sidebar.rowViews[0]
        row.beginRename()
        check("進入改名狀態", row.isEditing && !row.renameField.isHidden)
        row.renameField.stringValue = "我的標題"
        row.finishRename(commit: true)
        check("Enter 確認後顯示自訂名稱", t.customTitle == "我的標題" && row.titleText == "我的標題")
        row.beginRename()
        row.renameField.stringValue = "不要"
        _ = row.control(row.renameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        check("Esc 取消保留原名", t.customTitle == "我的標題" && !row.isEditing)
        row.beginRename()
        row.renameField.stringValue = "   "
        _ = row.control(row.renameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check("清空還原網頁標題", t.customTitle == nil && row.titleText == "Page A")
        t.customTitle = "保留我"
        tm.close(t)
        check("還原時帶回自訂名稱", tm.restoreLast()?.customTitle == "保留我")

        print("安全")
        let xss = tm.newTab(url: server.url("/xss"))
        check("網頁標題當純文字", await wait { xss.pageTitle.hasPrefix("<img") } && c.sidebar.rowViews.last?.titleText.hasPrefix("<img") == true)
        let perm = tm.newTab(url: server.url("/a"))
        _ = await wait { perm.pageTitle == "Page A" }
        let denied = try? await perm.webView.callAsyncJavaScript(
            "try { await navigator.mediaDevices.getUserMedia({audio:true}); return 'granted' } catch (e) { return e.name }",
            contentWorld: .page)
        check("麥克風權限被拒", ["NotAllowedError", "NotFoundError", "TypeError"].contains(denied as? String ?? ""), "\(String(describing: denied))")
        let po = tm.newTab(url: server.url("/popup"))
        _ = await wait { po.pageTitle == "Popup Opener" }
        _ = try? await po.webView.evaluateJavaScript("document.getElementById('l').click()")
        let nTabs = tm.tabs.count
        check("target=_blank 開新 Tab（插在來源之後並切過去）", await wait { tm.activeTab?.pageTitle == "Page B" } && tm.tabs.count == nTabs + 1
              && tm.tabs[(tm.tabs.firstIndex { $0 === po } ?? 0) + 1] === tm.activeTab)
        let popTab = tm.activeTab!
        _ = try? await po.webView.evaluateJavaScript("document.getElementById('n').click()")
        check("具名彈出視窗開新 Tab 並可 postMessage 給 opener 後 window.close", await wait { po.pageTitle == "got:hi" }, "\(po.pageTitle) tabs=\(tm.tabs.map(\.pageTitle))")
        check("window.close() 關掉彈出 Tab", await wait { !tm.tabs.contains { $0.pageTitle == "Child" } })
        tm.close(popTab)
        tm.select(po)
        c.submitAddress("file:///etc/hosts")
        check("file: 被拒絕", po.url?.scheme == "http")

        print("版面與側邊欄")
        let card = c.root.card
        let sw = Theme.sidebarWidth
        check("卡片四周 8px", card.frame.minX == sw && card.frame.minY == 8 && c.root.bounds.width - card.frame.maxX == 8
              && c.root.bounds.height - card.frame.maxY == 8, "\(card.frame)")
        let center = c.root.convert(NSPoint(x: card.frame.midX, y: card.frame.midY), to: nil)
        let hit = c.root.hitTest(c.root.superview?.convert(center, from: nil) ?? center)
        check("卡片中心 hit 到網頁而非可拖曳視圖", hit != nil && !(hit!.mouseDownCanMoveWindow))
        let edge = c.root.hitTest(NSPoint(x: card.frame.midX, y: 3))
        check("卡片下緣 8px 邊框可拖曳視窗", edge === c.root && edge!.mouseDownCanMoveWindow)
        check("⌘S 走選單隱藏側邊欄", press("s", .command, in: c.window))
        c.root.layoutSubtreeIfNeeded()
        check("側邊欄隱藏後卡片靠左 8px", c.root.sidebar.isHidden && card.frame.minX == 8, "\(card.frame)")
        _ = press("s", .command, in: c.window)
        c.root.layoutSubtreeIfNeeded()
        check("再按一次顯示", !c.root.sidebar.isHidden && card.frame.minX == sw)
        c.window.makeFirstResponder(tm.activeTab?.webView)
        send("s", .control, in: c.window)
        c.root.layoutSubtreeIfNeeded()
        check("Ctrl+S（焦點在網頁）隱藏側邊欄", c.root.sidebar.isHidden && card.frame.minX == 8)
        send("s", .control, in: c.window)
        c.root.layoutSubtreeIfNeeded()
        check("Ctrl+S 再按一次顯示", !c.root.sidebar.isHidden && card.frame.minX == sw)
        check("⌘L 叫出命令列（在目前 Tab 導航）", press("l", .command, in: c.window) && c.root.palette.isOpen && !c.root.card.isHidden)
        c.root.palette.dismiss()
        let before = tm.tabs.count
        check("⌘T 叫出覆蓋層而非直接新增空白分頁", press("t", .command, in: c.window) && c.root.palette.isOpen && tm.tabs.count == before)
        c.root.palette.dismiss()

        try await sessionChecks(server, app)
        try await externalChecks(server, app)
        try await downloadChecks(server, app)
        try await errorPageChecks(server, app)
        try await findZoomChecks(server, app)
        try await authChecks(server, app)
        try await historyChecks(server, app)
        try await closeKeyChecks(server, app)
        try await littleChecks(server, app)
        try await littleRoutingChecks(server, app)
        try await paletteChecks(server, app)
        try await doubleClickChecks(server, app)
        try await trafficLightChecks(server, app)
        try await loadingChecks(server, app)
        try await pinChecks(server, app)
        try await actionChecks(server, app)
    }
}

extension Smoke {
    static func tempStorage(_ tag: String) -> Storage {
        Storage(directory: FileManager.default.temporaryDirectory.appendingPathComponent("larch-\(tag)-\(UUID().uuidString)"))
    }

    static func sessionChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("Session restore")
        let storage = tempStorage("session")
        let c2 = BrowserWindowController(dataStore: .nonPersistent(), storage: storage, autosave: false)
        check("無存檔時開一個空白分頁", c2.tabs.tabs.count == 1 && c2.tabs.activeTab?.displayURL == nil)
        let a = c2.tabs.newTab(url: server.url("/a"), customTitle: "第一")
        let b = c2.tabs.newTab(url: server.url("/b"))
        c2.tabs.newTab(url: server.url("/c"))
        c2.tabs.select(b)
        _ = a
        c2.flushPersistence()
        let snap = SessionStore.load(storage)
        check("存檔只含 http(s) 分頁，順序與選中正確", snap?.tabs.map(\.url) == [server.url("/a"), server.url("/b"), server.url("/c")].map(\.absoluteString)
              && snap?.active == 1, "\(String(describing: snap))")
        check("自訂名稱有存", snap?.tabs.first?.customTitle == "第一")
        c2.window.close()
        let c3 = BrowserWindowController(dataStore: .nonPersistent(), storage: storage, autosave: false)
        check("重開還原三個 Tab", c3.tabs.tabs.count == 3)
        check("還原選中的 Tab 與自訂名稱", c3.tabs.activeTab?.displayURL == server.url("/b") && c3.tabs.tabs[0].customTitle == "第一")
        check("還原後會載入頁面", await wait { c3.tabs.activeTab?.pageTitle == "Page B" })
        c3.window.close()

        let bad = tempStorage("bad")
        try FileManager.default.createDirectory(at: bad.directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: bad.directory.appendingPathComponent(SessionStore.fileName))
        let c4 = BrowserWindowController(dataStore: .nonPersistent(), storage: bad, autosave: false)
        check("壞檔不影響啟動", c4.tabs.tabs.count == 1)
        c4.window.close()
        let evil = tempStorage("evil")
        evil.write(SessionStore.fileName, SessionSnapshot(tabs: [.init(url: "file:///etc/passwd", customTitle: nil), .init(url: "javascript://x", customTitle: nil)], active: 5))
        check("非 http(s) 不還原", SessionStore.load(evil) == nil)
    }
}

extension Smoke {
    static func externalChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("外部開啟（設定為新 Tab）")
        let c = app.controller!
        c.prefs.externalLinksInLittle = false
        let before = c.tabs.tabs.count
        let current = c.tabs.activeTab
        app.application(NSApp, open: [server.url("/b")])
        check("外部連結新開 Tab 而非取代", c.tabs.tabs.count == before + 1 && c.tabs.tabs.contains { $0 === current })
        check("新 Tab 載入外部連結", await wait { c.tabs.activeTab?.pageTitle == "Page B" })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mb-html-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("doc.html")
        try Data("<meta charset=utf-8><title>本機檔案</title>".utf8).write(to: file)
        app.application(NSApp, open: [file, URL(string: "mailto:a@b.c")!])
        check("本機 .html 可開，mailto 忽略", await wait { c.tabs.activeTab?.pageTitle == "本機檔案" } && c.tabs.tabs.count == before + 2)
        c.submitAddress(file.absoluteString)
        check("網址列仍拒絕 file:", c.tabs.activeTab?.pageTitle == "本機檔案")
        c.prefs.externalLinksInLittle = true
    }
}

extension Smoke {
    static func downloadChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("下載")
        let c = app.controller!
        let dm = c.tabs.downloads
        let t = c.tabs.newTab()
        t.load(server.url("/file?1"))
        check("附件被下載而非顯示", await wait { dm.latest?.state == .finished })
        let first = dm.directory.appendingPathComponent("report.txt")
        check("存成 report.txt 且內容正確", (try? String(contentsOf: first, encoding: .utf8)) == "hello download")
        check("側邊欄顯示完成提示", !c.sidebar.downloadButton.isHidden && c.sidebar.downloadButton.title.contains("report.txt"))
        t.load(server.url("/file?2"))
        check("重名加序號", await wait { FileManager.default.fileExists(atPath: dm.directory.appendingPathComponent("report (1).txt").path) })
        check("檔名不可穿越路徑", dm.uniqueDestination(for: "../../evil.txt").deletingLastPathComponent().path == dm.directory.path
              && dm.uniqueDestination(for: ".hidden").lastPathComponent == "hidden")
        c.tabs.close(t)
    }
}

extension Smoke {
    static func errorPageChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("錯誤頁")
        let c = app.controller!
        let t = c.tabs.newTab()
        let tmp = try FixtureServer()
        await tmp.start()
        let dead = tmp.url("/x")
        tmp.stop()
        try? await Task.sleep(nanoseconds: 200_000_000)
        c.submitAddress(dead.absoluteString)
        check("連不上顯示說明頁", await wait { t.errorURL == dead && t.pageTitle == "Can't connect to the server" }, "\(t.pageTitle) \(String(describing: t.errorURL)) \(String(describing: t.url))")
        check("網址列仍是失敗網址", c.addressField.stringValue == dead.absoluteString)
        let text = try? await t.webView.evaluateJavaScript("document.body.innerText") as? String
        check("頁面含失敗網址文字", text?.contains(dead.absoluteString) == true)
        c.submitAddress("http://nonexistent-host.invalid/")
        check("DNS 失敗說明", await wait { t.pageTitle == "Can't find the server" })
        c.submitAddress(server.url("/b").absoluteString)
        check("之後正常導航並清除錯誤狀態", await wait { t.pageTitle == "Page B" && t.errorURL == nil })
        let evil = ErrorPage.html(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost,
                                              userInfo: [NSLocalizedDescriptionKey: "<script>alert(1)</script>"]),
                                  url: URL(string: "http://x.test/?q=\"><script>alert(2)</script>")!)
        check("網址與錯誤文字被跳脫", !evil.contains("<script>alert"))
        let cert = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        check("憑證錯誤阻擋且無略過選項", ErrorPage.isCertificateError(cert)
              && ErrorPage.headline(for: cert).title == "Connection is not private"
              && !ErrorPage.html(for: cert, url: nil).lowercased().contains("proceed"))
        c.tabs.close(t)
    }
}

extension Smoke {
    static func findZoomChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("尋找與縮放")
        let c = app.controller!
        let t = c.tabs.newTab(url: server.url("/text"))
        _ = await wait { t.pageTitle == "Text Page" }
        check("⌘F 顯示尋找列並聚焦", press("f", .command, in: c.window) && !c.root.findBar.isHidden && c.root.findBar.field.currentEditor() != nil)
        check("找得到", await c.find("needle", backwards: false))
        check("找不到顯示 No matches", await !c.find("zzzz-none", backwards: false) && c.root.findBar.status.stringValue == "No matches")
        c.closeFind()
        check("關閉尋找列", c.root.findBar.isHidden)

        let host = server.url("/text").host!
        let other = URL(string: "http://localhost:\(server.port)/text")!
        check("預設縮放 1.0", t.webView.pageZoom == 1.0)
        check("⌘+ 放大", press("+", .command, in: c.window) && t.webView.pageZoom == 1.1)
        check("⌘- 縮小", press("-", .command, in: c.window) && t.webView.pageZoom == 1.0)
        c.zoomIn(); c.zoomIn()
        check("連按兩次放大到 1.25", t.webView.pageZoom == 1.25)
        let t2 = c.tabs.newTab(url: server.url("/b"))
        check("同網站新 Tab 套用記憶的縮放", await wait { t2.pageTitle == "Page B" } && t2.webView.pageZoom == 1.25)
        let t3 = c.tabs.newTab(url: other)
        check("不同網站不受影響", await wait { t3.pageTitle == "Text Page" } && t3.webView.pageZoom == 1.0, "\(host)")
        c.tabs.select(t)
        check("⌘0 還原", press("0", .command, in: c.window) && t.webView.pageZoom == 1.0 && c.tabs.zoom.zoom(for: host) == 1)
        c.tabs.close(t2); c.tabs.close(t3); c.tabs.close(t)
    }
}

extension Smoke {
    static func authChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("HTTP 驗證")
        let c = app.controller!
        var asked: [Tab.AuthRequest] = []
        var answer: (String, String)? = ("test", "pw")
        Tab.authPrompt = { asked.append($0); return answer }
        let t = c.tabs.newTab(url: server.url("/auth"))
        check("提示並以正確帳密通過", await wait { t.pageTitle == "Authed" } && asked.first?.realm == "Fixture" && asked.first?.isSecure == false)
        answer = nil
        let t2 = c.tabs.newTab()
        let before = asked.count
        t2.load(URL(string: "http://localhost:\(server.port)/auth")!)
        check("取消驗證不載入受保護內容", await wait { asked.count > before } && t2.pageTitle != "Authed")
        c.tabs.close(t2); c.tabs.close(t)
    }
}

extension Smoke {
    static func historyChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("歷史")
        let storage = tempStorage("history")
        let c = BrowserWindowController(dataStore: .nonPersistent(), storage: storage, autosave: false)
        let h = c.tabs.history!
        let t = c.tabs.newTab(url: server.url("/a"))
        check("造訪後記錄 URL 與標題", await wait { h.entries.last?.title == "Page A" }, "\(h.entries)")
        c.reload()
        _ = await wait { !t.isLoading }
        check("連續相同網址不重複", h.entries.filter { $0.url == server.url("/a").absoluteString }.count == 1)
        c.submitAddress("http://127.0.0.1:9/")
        try? await Task.sleep(nanoseconds: 500_000_000)
        check("錯誤頁與非 http 不記錄", !h.entries.contains { $0.url.hasPrefix("about:") || $0.url.contains(":9/") })
        check("搜尋標題", h.search("page a").count == 1 && h.search("zzz").isEmpty)
        c.flushPersistence()
        check("存檔後可重新載入", HistoryStore(storage: storage).entries.count == h.entries.count)
        for i in 0..<3100 { h.record(url: URL(string: "https://example.com/\(i)")!, title: "n\(i)") }
        check("超過 3000 筆裁到 2500 以內", h.entries.count <= HistoryStore.limit && h.entries.count >= HistoryStore.trimTo, "\(h.entries.count)")
        check("保留最新的", h.entries.last?.url == "https://example.com/3099")
        c.window.close()
        let bad = tempStorage("history-bad")
        try FileManager.default.createDirectory(at: bad.directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: bad.directory.appendingPathComponent(HistoryStore.fileName))
        check("壞檔回到空歷史", HistoryStore(storage: bad).entries.isEmpty)
    }
}

extension Smoke {
    /// 以 NSApp.sendEvent 送進真實按鍵路徑（含 first responder 與選單比對）。
    static func send(_ chars: String, _ mods: NSEvent.ModifierFlags, in window: NSWindow) {
        NSApp.sendEvent(keyEvent(chars, mods, in: window))
    }

    static func closeKeyChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("關閉 Tab 快捷鍵（⌘W / Ctrl+W）")
        let c = app.controller!
        let tm = c.tabs
        let w = c.window
        let focuses: [(String, () -> Void)] = [
            ("網頁內容", { w.makeFirstResponder(tm.activeTab?.webView) }),
            ("側邊欄網址列", { c.focusAddress() }),
            ("Tab 列", { w.makeFirstResponder(c.sidebar.rowViews.first) }),
        ]
        for (mods, label) in [(NSEvent.ModifierFlags.command, "⌘W"), (.control, "Ctrl+W")] {
            for (where_, focus) in focuses {
                let t = tm.newTab(url: server.url("/b"))
                _ = await wait { t.pageTitle == "Page B" }
                focus()
                let n = tm.tabs.count
                send("w", mods, in: w)
                check("\(label) 焦點在\(where_)：關閉目前 Tab", tm.tabs.count == n - 1 && !tm.tabs.contains { $0 === t })
            }
        }
        c.focusAddress()
        c.addressField.stringValue = "hello"
        c.addressField.currentEditor()?.selectedRange = NSRange(location: 5, length: 0)
        let n = tm.tabs.count
        let handled = press("a", .control, in: w) // 非 Ctrl+W 的 emacs 組合不被選單吃掉
        check("Ctrl+W 之外的 Ctrl 組合鍵不關 Tab、網址列文字不變", !handled && tm.tabs.count == n && c.addressField.stringValue == "hello")
        // 最後一個 Tab：維持現有行為，補一個空白 Tab。
        while tm.tabs.count > 1 { tm.close(tm.tabs.last!) }
        send("w", .control, in: w)
        check("Ctrl+W 關掉最後一個 Tab 會補空白 Tab", tm.tabs.count == 1 && tm.activeTab?.url == nil)
    }

    static func paletteChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("命令列覆蓋層（⌘T）")
        let c = app.controller!
        let tm = c.tabs
        let w = c.window
        let p = c.root.palette
        check("Fuzzy：子序列與邊界", Fuzzy.score(term: "gh", in: "GitHub") > 0 && Fuzzy.score(term: "zq", in: "GitHub") < 0
              && Fuzzy.score(query: "git zzz", in: "GitHub Home") < 0 && Fuzzy.score(term: "git", in: "git") > Fuzzy.score(term: "git", in: "my git"))

        // 準備資料：兩個已開啟的 Tab 與歷史（含一筆未開啟的）。
        while tm.tabs.count > 1 { tm.close(tm.tabs.last!) }
        tm.history?.record(url: server.url("/hist-only"), title: "Zebra Archive")
        let ta = tm.newTab(url: server.url("/a"))
        let tc = tm.newTab(url: server.url("/c"))
        _ = await wait { ta.pageTitle == "Page A" && tc.pageTitle == "頁面 C" }
        tm.select(tc)
        w.makeFirstResponder(tc.webView)

        let before = tm.tabs.count
        check("⌘T 走選單開啟覆蓋層", press("t", .command, in: w) && p.isOpen && tm.tabs.count == before)
        check("輸入框自動聚焦", p.field.currentEditor() != nil && w.firstResponder === p.field.currentEditor())
        c.root.layoutSubtreeIfNeeded()
        let card = c.root.card.frame
        let pf = p.panelFrame
        check("面板水平置中於網頁卡片", abs(pf.midX - card.midX) < 1 && card.contains(NSPoint(x: pf.midX, y: card.midY)), "\(pf) \(card)")

        // (a) 第一列是開啟/搜尋
        p.field.stringValue = "example.com/x"
        p.refresh()
        check("第一列是「Open: 輸入內容」", p.items.first?.kind == .openOrSearch && p.items.first?.title == "Open: example.com/x"
              && { if case .open(let u)? = p.items.first?.action { return u.absoluteString == "https://example.com/x" } else { return false } }())
        p.field.stringValue = "page"
        p.refresh()
        check("關鍵字第一列是 Search", p.items.first?.title == "Search: page")

        // (b) 比對已開啟 Tab（標題 / 網址）
        let tabItems = p.items.filter { $0.kind == .tab }
        check("比對標題找到已開啟的 Tab", tabItems.contains { if case .switchTab(let t) = $0.action { return t === ta } else { return false } })
        p.field.stringValue = "127.0.0.1"
        p.refresh()
        check("比對網址找到已開啟的 Tab", p.items.filter { $0.kind == .tab }.count >= 2)
        // (c) 歷史
        p.field.stringValue = "zebra"
        p.refresh()
        check("比對歷史紀錄（未開啟的網頁）", p.items.contains { $0.kind == .history && $0.title == "Zebra Archive" })
        p.field.stringValue = "page a"
        p.refresh()
        check("已開啟的網址不重複列在歷史", !p.items.contains { $0.kind == .history && $0.subtitle == server.url("/a").absoluteString })
        check("標題是純文字（不解析 HTML）", { () -> Bool in
            tm.history?.record(url: server.url("/hist-xss"), title: "<b>bold</b>&amp;")
            p.field.stringValue = "bold"; p.refresh()
            return p.rows.contains { $0.titleText == "<b>bold</b>&amp;" }
        }())

        // 上下鍵與 Enter 切換 Tab（不開新 Tab）
        p.field.stringValue = "page a"
        p.refresh()
        let idx = p.items.firstIndex { if case .switchTab(let t) = $0.action { return t === ta } else { return false } }!
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        check("↓ 移動選取", p.selectedIndex == 1)
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:)))
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:)))
        check("↑ 到頭會循環到最後一列", p.selectedIndex == p.items.count - 1)
        while p.selectedIndex != idx { _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:))) }
        let n = tm.tabs.count
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check("Enter 於已開啟 Tab 列：切換過去、不開新 Tab、覆蓋層關閉", tm.activeTab === ta && tm.tabs.count == n && !p.isOpen)
        check("焦點交給網頁", w.firstResponder === ta.webView)

        // 點擊已開啟 Tab 列
        _ = press("t", .command, in: w)
        p.field.stringValue = "頁面"; p.refresh()
        if let i = p.items.firstIndex(where: { $0.kind == .tab }) { p.rows[i].onClick?() }
        check("點擊 Tab 列切換過去", tm.activeTab === tc && tm.tabs.count == n && !p.isOpen)

        // Enter 以新 Tab 開啟網址
        _ = press("t", .command, in: w)
        p.field.stringValue = server.url("/b").absoluteString
        p.refresh()
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check("輸入網址 Enter 以新 Tab 開啟", tm.tabs.count == n + 1 && !p.isOpen && tm.activeTab !== tc)
        check("新 Tab 載入該網址", await wait { tm.activeTab?.pageTitle == "Page B" })
        // 搜尋
        _ = press("t", .command, in: w)
        p.field.stringValue = "hello world"; p.refresh()
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check("關鍵字以預設搜尋引擎在新 Tab 開啟", tm.tabs.count == n + 2 && tm.activeTab?.requestedURL?.absoluteString.hasPrefix(InputNormalizer.searchPrefix + "hello") == true)
        // 歷史 Enter 以新 Tab 開啟
        _ = press("t", .command, in: w)
        p.field.stringValue = "zebra"; p.refresh()
        let hi = p.items.firstIndex { $0.kind == .history }!
        p.pick(hi)
        check("歷史列 Enter 以新 Tab 開啟", tm.tabs.count == n + 3 && tm.activeTab?.requestedURL == server.url("/hist-only"))

        // Esc、點外面、空輸入
        let m = tm.tabs.count
        w.makeFirstResponder(tm.activeTab?.webView)
        _ = press("t", .command, in: w)
        p.field.stringValue = "abc"; p.refresh()
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        check("Esc 關閉覆蓋層、不新增 Tab、焦點回到網頁", !p.isOpen && tm.tabs.count == m && w.firstResponder === tm.activeTab?.webView)
        _ = press("t", .command, in: w)
        let outside = p.convert(NSPoint(x: 3, y: 3), to: nil)
        p.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: outside, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        check("點覆蓋層外面關閉", !p.isOpen && tm.tabs.count == m)
        _ = press("t", .command, in: w)
        p.field.stringValue = "   "; p.refresh()
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check("空白輸入沒有「開啟 / 搜尋」列、Enter 不開新 Tab", !p.items.contains { $0.kind == .openOrSearch } && tm.tabs.count == m)
        p.dismiss()
        // ⌘L 與 New Tab 按鈕
        // ⌘L：同一個覆蓋層，在目前 Tab 導航
        let cur = tm.newTab(url: server.url("/a?cur"))
        _ = await wait { cur.pageTitle == "Page A" }
        w.makeFirstResponder(cur.webView)
        let nBefore = tm.tabs.count
        let curURL = cur.displayURL!.absoluteString
        check("⌘L 開啟覆蓋層並預填目前網址且全選", press("l", .command, in: w) && p.isOpen && p.field.stringValue == curURL
              && p.field.currentEditor()?.selectedRange.length == (curURL as NSString).length && c.paletteNavigatesCurrentTab)
        p.field.stringValue = server.url("/b?nav").absoluteString
        p.refresh()
        _ = p.control(p.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check("⌘L Enter：在目前 Tab 載入、不開新 Tab", tm.tabs.count == nBefore && tm.activeTab === cur && cur.requestedURL == server.url("/b?nav"))
        _ = await wait { cur.pageTitle == "Page B" }
        _ = press("l", .command, in: w)
        tm.history?.record(url: server.url("/quokka"), title: "Quokka Archive")
        p.field.stringValue = "quokka"; p.refresh()
        if let i = p.items.firstIndex(where: { $0.kind == .history }) { p.pick(i) }
        check("⌘L 選歷史：在目前 Tab 導航", tm.tabs.count == nBefore && tm.activeTab === cur && cur.requestedURL == server.url("/quokka"))
        _ = press("l", .command, in: w)
        p.dismiss()
        check("⌘L 的覆蓋層之後 ⌘T 仍是開新 Tab", press("t", .command, in: w) && !c.paletteNavigatesCurrentTab)
        p.dismiss()
        c.sidebar.newTabButton.performClick(nil)
        check("側邊欄 New Tab 按鈕叫出同一個覆蓋層", p.isOpen && tm.tabs.count == m + 1)
        p.dismiss()
        // 覆蓋層開啟時擋住網頁的點擊
        _ = press("t", .command, in: w)
        let center = c.root.convert(NSPoint(x: card.midX, y: 12), to: nil)
        check("開啟時整個內容區的 hit-test 被覆蓋層攔下", c.root.hitTest(c.root.convert(center, from: nil)).map { $0 === p || $0.isDescendant(of: p) } == true)
        p.dismiss()
    }

    static func trafficLightChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("紅綠燈跟著側邊欄")
        let c = app.controller!
        guard let w = c.window as? LarchWindow else { check("視窗是 LarchWindow", false); return }
        func buttonsHidden() -> Bool { w.trafficLightButtons.allSatisfy { $0.isHidden } }
        func buttonsVisible() -> Bool { w.trafficLightButtons.count == 3 && w.trafficLightButtons.allSatisfy { !$0.isHidden && $0.alphaValue > 0.99 } }
        if !c.root.sidebarVisible { c.toggleSidebar() }
        check("側邊欄顯示時三顆按鈕都顯示", buttonsVisible())
        // 新視窗啟動時與側邊欄狀態一致。
        let c2 = BrowserWindowController(dataStore: .nonPersistent(), storage: tempStorage("tl"), autosave: false)
        check("新視窗啟動時按鈕顯示（側邊欄預設顯示）", (c2.window as! LarchWindow).trafficLightButtons.allSatisfy { !$0.isHidden })
        c2.window.close()
        let pressed = press("s", .command, in: w)
        let hid = await wait(2) { buttonsHidden() }
        check("⌘S 隱藏側邊欄 → 按鈕一起隱藏", pressed && !c.root.sidebarVisible && hid)
        c.root.layoutSubtreeIfNeeded()
        let rect = c.root.cornerRect
        check("感應區約 90x40 位於左上角", rect.width == 90 && rect.height == 40 && rect.minX == 0 && rect.maxY == c.root.bounds.height)
        let cardHit = c.root.hitTest(c.root.convert(NSPoint(x: 40, y: rect.midY), from: nil)) ?? c.root
        check("感應區內 hit 到網頁卡片、不被攔截且不可拖曳", !cardHit.mouseDownCanMoveWindow && cardHit !== c.root)
        c.root.onCornerHover?(true)
        check("隱藏期間滑鼠進入左上角 → 按鈕淡入顯示", await wait(2) { buttonsVisible() })
        c.root.onCornerHover?(false)
        check("滑鼠離開 → 再隱藏", await wait(2) { buttonsHidden() })
        send("s", .control, in: w)
        let shown = await wait(2) { buttonsVisible() }
        check("Ctrl+S 展開 → 按鈕一起顯示", c.root.sidebarVisible && shown)
        send("s", .control, in: w)
        check("Ctrl+S 再收 → 按鈕隱藏", await wait(2) { buttonsHidden() })
        c.openPalette(prefill: nil)
        c.root.palette.dismiss()
        c.focusAddress()
        let shown2 = await wait(2) { buttonsVisible() }
        check("⌘L 在側邊欄隱藏時展開側邊欄 → 按鈕顯示", c.root.sidebarVisible && shown2)
        check("真實滑鼠進出事件走 tracking area 的 owner 為 RootView", c.root.trackingAreas.contains { $0.owner === c.root && $0.rect == c.root.cornerRect })
    }

    static func doubleClickChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("雙擊視窗 bar")
        let c = app.controller!
        guard let w = c.window as? LarchWindow else { check("視窗是 LarchWindow", false); return }
        c.root.layoutSubtreeIfNeeded()
        let card = c.root.card.frame
        func win(_ p: NSPoint) -> NSPoint { c.root.convert(p, to: nil) }
        check("外框（卡片下緣）算 bar", w.isDraggableBar(at: win(NSPoint(x: card.midX, y: 3))))
        check("外框（卡片上緣）算 bar", w.isDraggableBar(at: win(NSPoint(x: card.midX, y: c.root.bounds.height - 3))))
        check("側邊欄頂端空白（紅綠燈旁）算 bar", w.isDraggableBar(at: win(NSPoint(x: Theme.sidebarWidth - 20, y: c.root.bounds.height - 10))))
        check("網頁卡片不算 bar", !w.isDraggableBar(at: win(NSPoint(x: card.midX, y: card.midY))))
        let ab = c.sidebar.addressBar.convert(NSPoint(x: 20, y: 10), to: nil)
        check("網址列不算 bar", !w.isDraggableBar(at: ab))
        let bb = c.sidebar.backButton.convert(NSPoint(x: 5, y: 5), to: nil)
        check("按鈕不算 bar", !w.isDraggableBar(at: bb))
        if let row = c.sidebar.rowViews.first {
            check("Tab 列不算 bar", !w.isDraggableBar(at: row.convert(NSPoint(x: 20, y: 10), to: nil)))
        }
        func defaults(_ v: String?) -> UserDefaults {
            let d = UserDefaults(suiteName: "larch-dc-\(getpid())")!
            d.removePersistentDomain(forName: "larch-dc-\(getpid())")
            if let v { d.set(v, forKey: "AppleActionOnDoubleClick") }
            return d
        }
        check("系統設定對應：未設定與 Maximize 為 Zoom", LarchWindow.doubleClickAction(defaults: defaults(nil)) == .zoom
              && LarchWindow.doubleClickAction(defaults: defaults("Maximize")) == .zoom)
        check("系統設定對應：Minimize / None", LarchWindow.doubleClickAction(defaults: defaults("Minimize")) == .minimize
              && LarchWindow.doubleClickAction(defaults: defaults("None")) == .none)
        check("雙擊卡片未被處理", !w.handleDoubleClick(at: win(NSPoint(x: card.midX, y: card.midY)), defaults: defaults(nil)))
        // 真實 sendEvent 路徑：雙擊外框 → zoom 切換。
        let was = w.isZoomed
        let ev = NSEvent.mouseEvent(with: .leftMouseDown, location: win(NSPoint(x: card.midX, y: 3)), modifierFlags: [], timestamp: 0,
                                    windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        let mode = LarchWindow.doubleClickAction()
        w.sendEvent(ev)
        if mode == .zoom {
            check("雙擊外框 sendEvent → 視窗 zoom 狀態切換", await wait(3) { w.isZoomed != was })
            if w.isZoomed != was { w.performZoom(nil); _ = await wait(3) { w.isZoomed == was } }
        } else {
            check("雙擊外框 sendEvent（系統設定非 Zoom，略過視窗狀態驗證）", true)
        }
    }
}

extension Smoke {
    static func loadingChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("載入狀態（進度條 / spinner / 停止鈕）")
        let c = app.controller!
        let tm = c.tabs
        let bar = c.root.card.loadingBar
        if !c.root.sidebarVisible { c.toggleSidebar() }
        let idle = tm.newTab(url: server.url("/b"))
        _ = await wait { idle.pageTitle == "Page B" && !idle.isLoading }
        _ = await wait(3) { !bar.isActive && !bar.isVisible }
        check("閒置時進度條不顯示、按鈕是重新整理", !bar.isActive && !bar.isVisible && !c.sidebar.isShowingStop)

        let slow = tm.newTab(url: server.url("/slow?1"))
        check("載入中進度條出現並有寬度", await wait { bar.isActive && bar.isVisible && bar.fraction > 0 })
        check("載入中重新整理鈕變停止", await wait { c.sidebar.isShowingStop })
        let row = c.sidebar.rowViews.first { $0.tab === slow }
        check("載入中 Tab 列有 spinner", row?.isShowingSpinner == true)
        check("進度條貼在卡片上緣、高度 3px", bar.frame.height == 3 && abs(bar.frame.maxY - c.root.card.bounds.height) < 0.5 && c.root.card.subviews.contains { $0 === bar },
              "\(bar.frame)")
        check("進度條不接收滑鼠（hit-test 為 nil）", bar.hitTest(NSPoint(x: 5, y: 1)) == nil)
        // 切換 Tab 各自反映
        tm.select(idle)
        check("切到閒置 Tab 立即不顯示進度條與停止鈕", !bar.isActive && !bar.isVisible && !c.sidebar.isShowingStop)
        check("背景 Tab 仍在載入、列上有 spinner", slow.isLoading && row?.isShowingSpinner == true)
        tm.select(slow)
        check("切回載入中的 Tab 立即顯示進度條與停止鈕", bar.isActive && bar.isVisible && c.sidebar.isShowingStop)
        check("載入完成後進度條淡出、按鈕還原、spinner 消失", await wait(6) { !slow.isLoading && !bar.isActive && !bar.isVisible && !c.sidebar.isShowingStop && row?.isShowingSpinner == false })

        // 停止鈕
        c.submitAddress(server.url("/slow?2").absoluteString)
        check("再次載入進入載入狀態", await wait { slow.isLoading && c.sidebar.isShowingStop })
        try? await Task.sleep(nanoseconds: 400_000_000)
        c.sidebar.reloadButton.performClick(nil)
        check("按停止：停止載入並還原狀態", await wait(3) { !slow.isLoading && !bar.isActive && !c.sidebar.isShowingStop }, "loading=\(slow.isLoading) active=\(bar.isActive) stop=\(c.sidebar.isShowingStop) active tab=\(tm.activeTab === slow)")
        check("停止後 Tab 列沒有 spinner、沒有錯誤頁", row?.isShowingSpinner == false && slow.errorURL == nil, "\(String(describing: slow.errorURL)) \(String(describing: row?.isShowingSpinner))")
        // 失敗頁也會結束
        let tmp = try FixtureServer()
        await tmp.start()
        let dead = tmp.url("/x")
        tmp.stop()
        try? await Task.sleep(nanoseconds: 200_000_000)
        c.submitAddress(dead.absoluteString)
        check("導航失敗顯示說明頁並結束載入狀態", await wait { slow.errorURL == dead && !slow.isLoading && !bar.isActive && !c.sidebar.isShowingStop && row?.isShowingSpinner == false })
        // 重新整理（非載入中）仍是重新整理
        check("載入結束後按鈕可再次重新整理", !c.sidebar.isShowingStop)
        tm.close(slow); tm.close(idle)
    }
}

extension Smoke {
    static func pinChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("釘選與資料夾")
        // PinStore 單元
        let st = tempStorage("pins")
        let ps = PinStore(storage: st)
        let f1 = ps.addFolder(name: "Private", parent: nil)
        let f2 = ps.addFolder(name: "Ninja", parent: f1.id)
        let a = ps.addTab(url: server.url("/a"), title: "A", parent: f2.id)
        let loose = ps.addTab(url: server.url("/b"), title: "B", parent: nil)
        check("巢狀資料夾與最上層單獨的釘選 Tab", ps.roots.map(\.id) == [f1.id, loose.id] && ps.find(a.id)?.parent?.id == f2.id)
        check("visible() 深度優先並帶層級", ps.visible().map { "\($0.node.title)\($0.depth)" } == ["Private0", "Ninja1", "A2", "B0"])
        f2.expanded = false
        check("收合的資料夾不列出內容", ps.visible().map(\.node.title) == ["Private", "Ninja", "B"])
        f2.expanded = true
        check("不能把資料夾放進自己的子孫", !ps.move(f1.id, toParent: f2.id, index: 0) && !ps.move(f1.id, toParent: f1.id, index: 0))
        check("移動 Tab 到最上層最前面", ps.move(a.id, toParent: nil, index: 0) && ps.roots.first?.id == a.id && ps.find(a.id)?.parent == nil)
        check("同層往後移的索引修正", ps.move(a.id, toParent: nil, index: 3) && ps.roots.last?.id == a.id)
        ps.addTab(url: server.url("/c"), title: "C", parent: f2.id)
        ps.deleteFolder(f2.id)
        check("刪資料夾：內容移到上一層原位置", ps.find(f2.id) == nil && ps.children(of: f1.id).map(\.title) == ["C"])
        ps.flush()
        let again = PinStore(storage: st)
        check("存檔後重新載入（結構與展開狀態）", again.visible().map { "\($0.node.title)\($0.depth)" } == ps.visible().map { "\($0.node.title)\($0.depth)" })
        let bad = tempStorage("pins-bad")
        bad.write(PinStore.fileName, ["version": AnyEncodable(1), "roots": AnyEncodable([PinNode(kind: .tab, title: "evil", url: "file:///etc/passwd"), PinNode(kind: .folder, title: "ok")])])
        check("非 http(s) 的釘選載入時被丟掉", PinStore(storage: bad).roots.map(\.title) == ["ok"])
        check("拖曳字串可來回轉換", SidebarItem(payload: SidebarItem.pin(a.id).payload!) == .pin(a.id) && SidebarItem(payload: "x:1") == nil)

        // 視窗層級
        let sto = tempStorage("pinwin")
        let c = BrowserWindowController(dataStore: .nonPersistent(), storage: sto, autosave: false)
        let tm = c.tabs
        let w = c.window
        let t1 = tm.newTab(url: server.url("/a"))
        let t2 = tm.newTab(url: server.url("/b"))
        _ = await wait { t1.pageTitle == "Page A" && t2.pageTitle == "Page B" }
        tm.select(t1)
        check("空白 Tab 不能釘", tm.pin(tm.tabs[0]) == nil)
        func menuHas(_ title: String, _ key: String) -> Bool { NSApp.mainMenu?.items.contains { $0.submenu?.items.contains { $0.title == title && $0.keyEquivalent == key } == true } == true }
        check("選單有 ⌘D 釘選與 ⌘⇧N 新資料夾", menuHas("Pin / Unpin Tab", "d") && menuHas("New Folder", "N"))
        c.togglePinAction()
        check("釘選目前 Tab（⌘D 的動作）", t1.pinID != nil && tm.pins.roots.count == 1 && tm.pins.roots[0].title == "Page A")
        func kinds() -> [String] { c.sidebar.sidebarRows.map { switch $0.item { case .divider: return "—"; case .pin: return "pin"; case .tab: return "tab" } } }
        check("側邊欄順序：釘選、分隔線、一般 Tab", kinds() == ["pin", "—", "tab", "tab"], "\(kinds())")
        let pinRow = c.sidebar.rowViews.first { $0.pin != nil }!
        check("釘選列綁定開著的 Tab 且為選中", pinRow.tab === t1 && pinRow.isActive)
        // 關閉：節點留著變灰
        tm.close(t1)
        check("關掉釘選的 Tab：節點保留、列變灰（無 Tab）", tm.pins.roots.count == 1 && tm.liveTab(forPin: tm.pins.roots[0].id) == nil
              && c.sidebar.rowViews.first { $0.pin != nil }?.tab == nil)
        let grayRow = c.sidebar.rowViews.first { $0.pin != nil }!
        check("釘選列 ✕ 提示：開著=Close and Keep Pinned、灰色=Remove Pin", grayRow.closeToolTip == "Remove Pin")
        check("灰色列仍顯示標題", c.sidebar.rowViews.first { $0.pin != nil }?.titleText == "Page A")
        // ✕ 兩段式：先關 Tab、再移除釘選
        let open0 = tm.pins.roots[0]
        tm.activatePin(open0)
        let openRow = c.sidebar.rowViews.first { $0.pin != nil }!
        check("開著的釘選列 ✕ 提示是 Close and Keep Pinned、圖示是「−」", openRow.closeToolTip == "Close and Keep Pinned" && openRow.closeIconName == "Close and keep pinned")
        openRow.onClose?(openRow)
        check("第一下 ✕：關閉 Tab、釘選保留（灰色）", tm.pins.roots.count == 1 && tm.liveTab(forPin: open0.id) == nil)
        let grayRow2 = c.sidebar.rowViews.first { $0.pin != nil }!
        grayRow2.onClose?(grayRow2)
        check("灰色列圖示換回「✕」", grayRow2.closeIconName == "Close tab")
        check("第二下 ✕：移除釘選", tm.pins.roots.isEmpty && !c.sidebar.rowViews.contains { $0.pin != nil })
        tm.pins.addTab(url: server.url("/a"), title: "Page A", parent: nil)
        // 點灰色列：用記住的網址重新開啟並綁定
        let node = tm.pins.roots[0]
        c.sidebar.rowViews.first { $0.pin != nil }?.onSelect?(c.sidebar.rowViews.first { $0.pin != nil }!)
        let reopened = tm.activeTab
        check("點灰色列：重新開啟並綁定、成為目前 Tab", reopened?.pinID == node.id && reopened?.displayURL == server.url("/a"))
        check("重新開啟後載入", await wait { reopened?.pageTitle == "Page A" })
        // session 還原後仍綁定
        c.flushPersistence()
        let snap = SessionStore.load(sto)
        check("session 存 pinID", snap?.tabs.contains { $0.pinID == node.id.uuidString } == true)
        c.window.close()
        let c2 = BrowserWindowController(dataStore: .nonPersistent(), storage: sto, autosave: false)
        check("重開後釘選仍在並綁定還原的 Tab", c2.tabs.pins.roots.count == 1 && c2.tabs.liveTab(forPin: c2.tabs.pins.roots[0].id) != nil)

        // 資料夾 UI
        let tm2 = c2.tabs
        let folder = c2.newFolder()
        check("⌘⇧N／新增資料夾後進入改名", c2.sidebar.sidebarRows.contains { ($0 as? FolderRowView)?.isEditing == true })
        let fr = c2.sidebar.sidebarRows.compactMap { $0 as? FolderRowView }.first { $0.node.id == folder.id }!
        fr.renameField.stringValue = "<b>工作</b>"
        fr.finishRename(commit: true)
        check("資料夾改名（純文字）", folder.title == "<b>工作</b>" && fr.titleText == "<b>工作</b>")

        // 拖曳落點與執行
        let reg = tm2.newTab(url: server.url("/c"))
        _ = await wait { reg.pageTitle == "頁面 C" }
        let regRow = c2.sidebar.rowViews.first { $0.tab === reg }!
        check("拖到資料夾中間 → 放進資料夾", { c2.resolveDrop(.tab(reg.id), over: .pin(folder.id), fraction: 0.5)?.indicator == .into }())
        c2.resolveDrop(.tab(reg.id), over: .pin(folder.id), fraction: 0.5)?.commit()
        check("一般 Tab 拖進資料夾 → 釘在裡面", reg.pinID != nil && tm2.pins.find(reg.pinID!)?.parent?.id == folder.id && folder.expanded)
        check("資料夾內的釘選列縮排一層", c2.sidebar.rowViews.first { $0.tab === reg }?.depth == 1)
        check("資料夾不能拖進自己", c2.resolveDrop(.pin(folder.id), over: .pin(reg.pinID!), fraction: 0.5) == nil)
        // 收合
        fr.onToggle?(folder)
        check("收合後內容列消失", !c2.sidebar.rowViews.contains { $0.tab === reg })
        fr.onToggle?(folder)
        check("再展開內容列回來", c2.sidebar.rowViews.contains { $0.tab === reg })
        // 資料夾內釘選拖到一般區 → 取消釘選
        let regs = tm2.tabs.filter { $0.pinID == nil }
        c2.resolveDrop(.pin(reg.pinID!), over: .tab(regs[0].id), fraction: 0.1)?.commit()
        check("釘選拖到一般區 → 取消釘選且排在目標前", reg.pinID == nil && tm2.tabs.filter { $0.pinID == nil }.first === reg)
        // 一般區重排
        let order = tm2.tabs.filter { $0.pinID == nil }
        c2.resolveDrop(.tab(order[0].id), over: .tab(order.last!.id), fraction: 0.9)?.commit()
        check("一般區拖到最後面", tm2.tabs.filter { $0.pinID == nil }.last === order[0])
        // 分隔線：一般 Tab → 釘到最上層末尾；釘選 → 取消
        let last = tm2.tabs.filter { $0.pinID == nil }.last!
        c2.resolveDrop(.tab(last.id), over: .divider, fraction: 0.5)?.commit()
        check("拖到分隔線 → 釘到最上層（單獨一個 Tab）", last.pinID != nil && tm2.pins.find(last.pinID!)?.parent == nil && tm2.pins.roots.last?.id == last.pinID)
        c2.resolveDrop(.pin(last.pinID!), over: .divider, fraction: 0.5)?.commit()
        check("釘選拖到分隔線 → 取消釘選", last.pinID == nil)
        check("資料夾不能放到一般區", c2.resolveDrop(.pin(folder.id), over: .tab(regs[0].id), fraction: 0.1) == nil)
        // 右鍵「Unpin」與灰色釘選拖到一般區
        let gray = tm2.pins.addTab(url: server.url("/b"), title: "灰", parent: nil)
        let before = tm2.tabs.count
        c2.resolveDrop(.pin(gray.id), over: .divider, fraction: 0.5)?.commit()
        check("灰色釘選拖到一般區 → 開成一般 Tab（節點移除）", tm2.pins.find(gray.id) == nil && tm2.tabs.count == before + 1)
        // 命令列找得到灰色釘選
        let g2 = tm2.pins.addTab(url: server.url("/hist-pin"), title: "Zebra Pinned", parent: nil)
        c2.openPalette(prefill: "zebra pinned")
        check("⌘T 命令列列出灰色釘選", c2.root.palette.items.contains { if case .activatePin(let id) = $0.action { return id == g2.id } else { return false } })
        if let i = c2.root.palette.items.firstIndex(where: { $0.kind == .pin }) { c2.root.palette.pick(i) }
        check("選取灰色釘選 → 開啟並綁定", tm2.activeTab?.pinID == g2.id)
        c2.window.close()
        try await dragGeometryChecks(server)
    }

    /// 真實的 draggingUpdated / performDragOperation 路徑（以假的 NSDraggingInfo 餵進去）。
    static func dragGeometryChecks(_ server: FixtureServer) async throws {
        let c = BrowserWindowController(dataStore: .nonPersistent(), storage: tempStorage("drag"), autosave: false)
        let tm = c.tabs
        let folder = tm.pins.addFolder(name: "F", parent: nil)
        let t = tm.newTab(url: server.url("/a"))
        _ = await wait { t.pageTitle == "Page A" }
        c.window.setContentSize(NSSize(width: 1000, height: 700))
        c.root.layoutSubtreeIfNeeded()
        c.sidebar.layoutSubtreeIfNeeded()
        let rows = c.sidebar.sidebarRows
        guard let fRow = rows.first(where: { $0.item == .pin(folder.id) }), let tRow = rows.first(where: { $0.item == .tab(t.id) }) else {
            check("拖曳測試前置：資料夾列與 Tab 列存在", false); return
        }
        func drag(_ item: SidebarItem, onto row: NSView, fraction f: CGFloat) -> NSDragOperation {
            let pb = NSPasteboard(name: NSPasteboard.Name("larch-test-\(UUID().uuidString)"))
            pb.clearContents()
            pb.setString(item.payload!, forType: SidebarItem.pasteboardType)
            let local = NSPoint(x: row.bounds.midX, y: row.bounds.height * f)
            let inWindow = row.convert(local, to: nil)
            return c.sidebar.draggingUpdated(FakeDraggingInfo(pasteboard: pb, location: inWindow))
        }
        check("draggingUpdated：Tab 拖到資料夾中間 → 允許", drag(.tab(t.id), onto: fRow, fraction: 0.5) == .move)
        check("draggingUpdated：資料夾拖到一般 Tab → 拒絕", drag(.pin(folder.id), onto: tRow, fraction: 0.5) == [])
        let pb = NSPasteboard(name: NSPasteboard.Name("larch-test-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString(SidebarItem.tab(t.id).payload!, forType: SidebarItem.pasteboardType)
        let loc = fRow.convert(NSPoint(x: fRow.bounds.midX, y: fRow.bounds.height * 0.5), to: nil)
        let info = FakeDraggingInfo(pasteboard: pb, location: loc)
        _ = c.sidebar.draggingUpdated(info)
        check("performDragOperation 執行放入資料夾", c.sidebar.performDragOperation(info) && t.pinID != nil && tm.pins.find(t.pinID!)?.parent?.id == folder.id)
        if let dir = ProcessInfo.processInfo.environment["LARCH_SHOT_DIR"] { try? await sidebarShot(server, dir) }
        c.window.close()
    }

    /// 截圖用（LARCH_SHOT_DIR 指定資料夾）：在 smoke 的暫存資料中做出像 Arc 的釘選樹並存 PNG。
    static func sidebarShot(_ server: FixtureServer, _ dir: String) async throws {
        let c = BrowserWindowController(dataStore: .nonPersistent(), storage: tempStorage("shot"), autosave: false)
        let ps = c.tabs.pins
        func tab(_ title: String, _ path: String, in parent: PinNode?) { ps.addTab(url: server.url(path), title: title, parent: parent?.id) }
        let pr = ps.addFolder(name: "Pull Requests", parent: nil)
        tab("10/24 名單與戰績", "/a", in: pr)
        let priv = ps.addFolder(name: "Private", parent: nil)
        tab("固定支出", "/a", in: priv)
        let ninja = ps.addFolder(name: "忍者必須死", parent: priv.id)
        tab("Ninja Must Die - Project Editor", "/b", in: ninja)
        tab("家族戰出席紀錄", "/c", in: ninja)
        ps.addFolder(name: "FamAcc", parent: priv.id)
        ps.addFolder(name: "Hantek", parent: nil)
        tab("edclub: Personalized Learning Paths", "/a", in: nil)
        let live = c.tabs.newTab(url: server.url("/b"))
        _ = await wait { live.pageTitle == "Page B" }
        c.tabs.pin(live, parent: ninja.id, index: 2)
        c.tabs.newTab(url: server.url("/c"))
        c.window.setContentSize(NSSize(width: 900, height: 620))
        try? await Task.sleep(nanoseconds: 400_000_000)
        c.root.layoutSubtreeIfNeeded()
        if let rep = c.root.bitmapImageRepForCachingDisplay(in: c.root.bounds) {
            c.root.cacheDisplay(in: c.root.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/pins.png"))
        }
        c.window.close()
    }
}

struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ v: Encodable) { value = v }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    let location: NSPoint
    init(pasteboard: NSPasteboard, location: NSPoint) { self.pasteboard = pasteboard; self.location = location }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}

extension Smoke {
    static func actionChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("Command Palette：動作模式")
        let c = BrowserWindowController(dataStore: .nonPersistent(), storage: tempStorage("actions"), autosave: false)
        let tm = c.tabs
        let p = c.root.palette
        func cmd(_ sel: Selector) -> Bool { p.control(p.field, textView: NSTextView(), doCommandBy: sel) }
        func actionIDs() -> [String] { p.items.compactMap { if case .runAction(let id) = $0.action { return id } else { return nil } } }
        /// 開覆蓋層 → Tab 進動作模式 → 輸入查詢 → 執行指定動作。
        func run(_ id: String, query: String = "") {
            c.openPalette(prefill: nil)
            _ = cmd(#selector(NSResponder.insertTab(_:)))
            p.field.stringValue = query
            p.refresh()
            if let i = p.items.firstIndex(where: { if case .runAction(let a) = $0.action { return a == id } else { return false } }) { p.pick(i) } else { p.dismiss() }
        }
        let a = tm.newTab(url: server.url("/a"))
        let b = tm.newTab(url: server.url("/b"))
        let cc = tm.newTab(url: server.url("/c"))
        _ = await wait { a.pageTitle == "Page A" && b.pageTitle == "Page B" && cc.pageTitle == "頁面 C" }
        tm.select(b)

        // 一般模式不列動作
        c.openPalette(prefill: nil)
        p.field.stringValue = "restore"; p.refresh()
        check("一般模式輸入 restore 不列 Actions", !p.items.contains { $0.kind == .action } && !p.isChipVisible)
        // Tab 進入
        check("Tab 鍵進入動作模式、出現 Actions chip", cmd(#selector(NSResponder.insertTab(_:))) && p.mode == .actions && p.isChipVisible && p.chipText == "Actions")
        check("動作模式保留查詢文字、只列動作", p.field.stringValue == "restore" && p.items.allSatisfy { $0.kind == .action })
        check("沒有已關閉的 Tab 時 Restore 不列出", !actionIDs().contains("restore"))
        // 離開
        check("Shift+Tab 離開動作模式", cmd(#selector(NSResponder.insertBacktab(_:))) && p.mode == .normal && !p.isChipVisible)
        _ = cmd(#selector(NSResponder.insertTab(_:)))
        p.field.stringValue = "x"; p.refresh()
        check("輸入框有字時 Backspace 不離開（交給文字編輯）", !cmd(#selector(NSResponder.deleteBackward(_:))) && p.mode == .actions)
        p.field.stringValue = ""; p.refresh()
        check("輸入框為空 Backspace 離開動作模式", cmd(#selector(NSResponder.deleteBackward(_:))) && p.mode == .normal)
        p.dismiss()

        // 不適用的動作隱藏
        let blank = tm.newTab()
        c.openPalette(prefill: nil); _ = cmd(#selector(NSResponder.insertTab(_:)))
        let ids = actionIDs()
        check("空白 Tab：複製網址/複製為 Markdown/複製/縮放/尋找/Pin 隱藏", !ids.contains("copyUrl") && !ids.contains("copyMd") && !ids.contains("duplicate")
              && !ids.contains("zoomIn") && !ids.contains("find") && !ids.contains("pin"), "\(ids)")
        check("空白 Tab：通用動作仍在", ids.contains("close") && ids.contains("sidebar") && ids.contains("newFolder") && ids.contains("new"))
        p.dismiss()
        tm.close(blank)
        tm.select(b)

        // 外觀：標籤與快捷鍵
        c.openPalette(prefill: nil); _ = cmd(#selector(NSResponder.insertTab(_:)))
        let closeRow = p.rows.first { $0.item.title == "Close Tab" }
        check("動作列顯示類型標籤與快捷鍵", closeRow?.badgeText == "Action" && closeRow?.shortcutText == "⌘W")
        check("Open Web Inspector 與可用性一致", actionIDs().contains("inspector") == c.canOpenInspector)
        p.dismiss()

        // 關閉 → Restore 排第一
        run("close")
        check("動作 Close Tab", tm.tabs.count == 3 && !tm.tabs.contains { $0 === b })
        c.openPalette(prefill: nil); _ = cmd(#selector(NSResponder.insertTab(_:)))
        p.field.stringValue = "restore"; p.refresh()
        check("輸入 restore：Restore Last Closed Tab 排第一", p.items.first?.title == "Restore Last Closed Tab", "\(p.items.map(\.title))")
        p.dismiss()
        run("restore", query: "restore")
        check("動作 Restore Last Closed Tab", await wait { tm.activeTab?.displayURL == server.url("/b") } && tm.tabs.count == 4)

        // Duplicate
        let cur = tm.activeTab!
        run("duplicate", query: "dup")
        let ci = tm.tabs.firstIndex { $0 === cur }!
        check("動作 Duplicate Tab：同網址、緊接在原 Tab 之後", tm.tabs.count == 5 && tm.tabs[ci + 1].displayURL == cur.displayURL && tm.activeTab === tm.tabs[ci + 1])

        // Pin / Unpin（標題隨狀態變化）
        let target = tm.activeTab!
        c.openPalette(prefill: nil); _ = cmd(#selector(NSResponder.insertTab(_:)))
        check("未釘選時標題是 Pin Tab", p.items.contains { $0.title == "Pin Tab" })
        p.dismiss()
        run("pin", query: "pin")
        check("動作 Pin Tab", target.pinID != nil && tm.pins.roots.count == 1)
        c.openPalette(prefill: nil); _ = cmd(#selector(NSResponder.insertTab(_:)))
        check("已釘選時標題是 Unpin Tab", p.items.contains { $0.title == "Unpin Tab" })
        p.dismiss()
        run("pin", query: "unpin")
        check("動作 Unpin Tab", target.pinID == nil && tm.pins.roots.isEmpty)

        // Rename
        run("rename", query: "rename")
        check("動作 Rename Tab：該列進入改名", c.sidebar.rowViews.first { $0.tab === tm.activeTab }?.isEditing == true)
        c.sidebar.rowViews.first { $0.tab === tm.activeTab }?.finishRename(commit: false)

        // Copy URL / Markdown
        run("copyUrl", query: "copy tab url")
        check("動作 Copy Tab URL", NSPasteboard.general.string(forType: .string) == tm.activeTab?.displayURL?.absoluteString)
        run("copyMd", query: "markdown")
        let md = NSPasteboard.general.string(forType: .string) ?? ""
        check("動作 Copy Tab URL as Markdown", md == "[\(tm.activeTab!.displayTitle)](\(tm.activeTab!.displayURL!.absoluteString))", md)

        // 新資料夾、側邊欄、縮放、尋找、重新整理
        run("newFolder", query: "folder")
        check("動作 New Folder（進入改名）", tm.pins.roots.contains { $0.isFolder } && c.sidebar.sidebarRows.contains { ($0 as? FolderRowView)?.isEditing == true })
        c.sidebar.sidebarRows.compactMap { $0 as? FolderRowView }.first?.finishRename(commit: false)
        let sbBefore = c.root.sidebarVisible
        run("sidebar", query: "sidebar")
        check("動作 Toggle Sidebar", c.root.sidebarVisible != sbBefore)
        run("sidebar", query: "sidebar")
        check("再執行一次還原", c.root.sidebarVisible == sbBefore)
        run("zoomIn", query: "zoom in")
        check("動作 Zoom In", tm.activeTab!.webView.pageZoom > 1)
        run("zoomReset", query: "reset zoom")
        check("動作 Reset Zoom", tm.activeTab!.webView.pageZoom == 1)
        run("find", query: "find")
        check("動作 Find in Page", !c.root.findBar.isHidden)
        c.closeFind()
        let slow = tm.newTab(url: server.url("/slow?reload"))
        _ = await wait(6) { slow.pageTitle == "Slow Page" && !slow.isLoading }
        run("reload", query: "reload")
        check("動作 Reload Tab：重新載入（進入載入中）", await wait(2) { slow.isLoading })
        _ = await wait(6) { !slow.isLoading }
        tm.close(slow)

        // Close Other Tabs：保留目前與釘選
        let keep = tm.activeTab!
        let pinned = tm.tabs.first { $0 !== keep }!
        tm.pin(pinned)
        run("closeOthers", query: "other")
        check("動作 Close Other Tabs：只留目前與釘選的 Tab", Set(tm.tabs.map(ObjectIdentifier.init)) == Set([ObjectIdentifier(keep), ObjectIdentifier(pinned)]), "tabs=\(tm.tabs.count)")
        c.openPalette(prefill: nil); _ = cmd(#selector(NSResponder.insertTab(_:)))
        check("沒有其他一般 Tab 時 Close Other Tabs 隱藏", !actionIDs().contains("closeOthers"))
        p.dismiss()

        run("little", query: "little")
        check("動作 Open in Little Window：以目前網址開 Little", c.littles.count == 1 && c.littles[0].tab.requestedURL == tm.activeTab?.displayURL)
        c.closeAllLittles()

        // New Blank Tab → 空白 Tab 並叫出覆蓋層（在該 Tab 導航）
        let n = tm.tabs.count
        run("new", query: "blank")
        check("動作 New Blank Tab：多一個空白 Tab、覆蓋層以目前 Tab 導航模式開啟", tm.tabs.count == n + 1 && tm.activeTab?.displayURL == nil && p.isOpen && c.paletteNavigatesCurrentTab)
        p.dismiss()

        // 近用排序與捲動
        for i in 0..<12 { tm.newTab(url: server.url("/b?r\(i)")) }
        let latest = tm.tabs[tm.tabs.count - 3]
        tm.select(latest)
        c.openPalette(prefill: nil)
        check("空輸入：最近使用的 Tab 排在最前", p.items.first(where: { $0.kind == .tab }).map { if case .switchTab(let t) = $0.action { return t === latest } else { return false } } == true)
        c.root.layoutSubtreeIfNeeded()
        check("列數多時最多顯示 8 列（其餘捲動）", p.items.count > 8 && p.visibleRowCount == 8 && p.panelFrame.height > 8 * 46 && p.panelFrame.height < 9 * 48 + 90, "\(p.items.count) \(p.visibleRowCount) \(p.panelFrame)")
        // 捲動：↑↓ 時選取列一定在可視範圍內；換結果回到最上面。
        func selectedVisible() -> Bool { c.root.layoutSubtreeIfNeeded(); return p.visibleListRect.insetBy(dx: -1, dy: -1).contains(p.selectedRowRect) }
        c.openPalette(prefill: nil)
        c.root.layoutSubtreeIfNeeded()
        var allVisible = true
        var firstBad = ""
        for _ in 0..<(p.items.count + 2) { p.moveSelection(1); let ok = selectedVisible(); if !ok && firstBad.isEmpty { firstBad = "sel=\(p.selectedIndex) vis=\(p.visibleListRect) row=\(p.selectedRowRect)" }; allVisible = allVisible && ok }
        check("連按 ↓ 繞一圈：選取列始終在可視範圍內", allVisible && p.items.count > 8, "n=\(p.items.count) \(firstBad)")
        p.moveSelection(-1)
        check("↑ 從第一列繞到最後一列：捲到最後並可見", selectedVisible())
        p.field.stringValue = "b"; p.refresh()
        c.root.layoutSubtreeIfNeeded()
        check("換查詢後回到最上面且選取第一列可見", p.visibleListRect.minY <= 0.5 && p.selectedIndex == 0 && selectedVisible())
        c.openPalette(prefill: nil); _ = cmd(#selector(NSResponder.insertTab(_:)))
        for _ in 0..<12 { p.moveSelection(1) }
        p.field.stringValue = "re"; p.refresh()
        c.root.layoutSubtreeIfNeeded()
        check("動作模式捲到下面再改輸入：第一列（Restore 等）回到可見", p.visibleListRect.minY <= 0.5 && selectedVisible())
        p.dismiss()
        if let dir = ProcessInfo.processInfo.environment["LARCH_SHOT_DIR"] { await paletteShots(c, server, dir) }
        if ProcessInfo.processInfo.environment["LARCH_SHOT_LITTLE"] != nil { await littleHold(server) }
        c.window.close()
    }

    /// 截圖用：一般模式與動作模式（LARCH_SHOT_DIR 指定資料夾）。
    static func paletteShots(_ c: BrowserWindowController, _ server: FixtureServer, _ dir: String) async {
        let tm = c.tabs
        while tm.tabs.count > 1 { tm.close(tm.tabs.last!) }
        tm.history?.record(url: URL(string: "https://example.com/release-notes")!, title: "Release notes — Example")
        tm.history?.record(url: URL(string: "https://example.com/reports")!, title: "Quarterly reports")
        let t1 = tm.newTab(url: server.url("/a")), t2 = tm.newTab(url: server.url("/b"))
        _ = await wait { t1.pageTitle == "Page A" && t2.pageTitle == "Page B" }
        tm.pins.addTab(url: URL(string: "https://example.com/reference")!, title: "Reference docs", parent: nil)
        tm.close(t1)
        c.window.setContentSize(NSSize(width: 1000, height: 640))
        func save(_ name: String) async {
            try? await Task.sleep(nanoseconds: 300_000_000)
            c.root.layoutSubtreeIfNeeded()
            if let rep = c.root.bitmapImageRepForCachingDisplay(in: c.root.bounds) {
                c.root.cacheDisplay(in: c.root.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name))
            }
        }
        c.openPalette(prefill: "re")
        await save("palette-normal.png")
        c.root.palette.enterActions()
        await save("palette-actions.png")
        c.root.palette.dismiss()
    }
}

final class FakeNavAction: WKNavigationAction {
    private let req: URLRequest, type: WKNavigationType, mods: NSEvent.ModifierFlags
    init(_ url: URL, type: WKNavigationType = .linkActivated, mods: NSEvent.ModifierFlags = []) {
        req = URLRequest(url: url); self.type = type; self.mods = mods
        super.init()
    }
    override var request: URLRequest { req }
    override var navigationType: WKNavigationType { type }
    override var modifierFlags: NSEvent.ModifierFlags { mods }
    override var targetFrame: WKFrameInfo? { nil }
    override var shouldPerformDownload: Bool { false }
}

extension Smoke {
    static func escEvent(in w: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    }

    static func returnEvent(_ mods: NSEvent.ModifierFlags, in w: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                         characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
    }

    static func littleChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("Little 視窗")
        let suite = "larch-little-\(getpid())"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        check("外部連結走 Little 預設開啟、大小預設 960x720", Preferences(defaults: d).externalLinksInLittle && Preferences(defaults: d).littleSize == NSSize(width: 960, height: 720))
        Preferences(defaults: d).externalLinksInLittle = false
        Preferences(defaults: d).littleSize = NSSize(width: 700, height: 500)
        check("設定持久化（重新建立 Preferences 仍讀到）", !Preferences(defaults: UserDefaults(suiteName: suite)!).externalLinksInLittle
              && Preferences(defaults: UserDefaults(suiteName: suite)!).littleSize == NSSize(width: 700, height: 500))
        d.removePersistentDomain(forName: suite)

        let c = BrowserWindowController(dataStore: .nonPersistent(), storage: tempStorage("little"), prefs: Preferences(defaults: d), autosave: false)
        let tm = c.tabs
        let base = tm.newTab(url: server.url("/a"))
        _ = await wait { base.pageTitle == "Page A" }
        let closedBefore = tm.closedStack.count

        // 開啟、限流、拒絕非 http(s)
        check("非 http(s) 不開", c.openLittle(URL(string: "file:///etc/hosts")!) == nil && c.openLittle(URL(string: "mailto:a@b.c")!) == nil && c.littles.isEmpty)
        let l1 = c.openLittle(server.url("/b"))!
        check("開出 Little：不進主視窗 Tab 清單、視窗可見", c.littles.count == 1 && !tm.tabs.contains { $0 === l1.tab } && l1.window.isVisible)
        check("同網址 300ms 內重複開啟被忽略", c.openLittle(server.url("/b")) == nil && c.littles.count == 1)
        check("Little 網址膠囊顯示網域（純文字），標題與完整網址在提示", await wait { l1.tab.pageTitle == "Page B" && l1.root.pillText == "127.0.0.1" && l1.root.pillToolTip == "Page B\n" + server.url("/b").absoluteString })
        check("Little 的瀏覽寫進歷史", c.tabs.history?.entries.contains { $0.url == server.url("/b").absoluteString } == true)
        check("焦點交給網頁", l1.window.firstResponder === l1.tab.webView)
        check("Little 為白色色調（與主視窗的綠色區分）、卡片在外框內", l1.window.backgroundColor == Theme.littleFrame && l1.window.backgroundColor != Theme.panel && c.window.backgroundColor == Theme.panel && l1.root.card.superview === l1.root && !l1.window.styleMask.isEmpty)

        // 版面與拖曳區域
        l1.root.layoutSubtreeIfNeeded()
        let bar = l1.root.convert(NSPoint(x: l1.root.bounds.midX, y: l1.root.bounds.height - 4), to: nil)
        let cardPt = l1.root.convert(NSPoint(x: l1.root.card.frame.midX, y: l1.root.card.frame.midY), to: nil)
        let btn = l1.root.backButton.convert(NSPoint(x: 5, y: 5), to: nil)
        check("工具列空白處可拖曳／雙擊；網頁卡片與按鈕不可", l1.window.isDraggableBar(at: bar) && !l1.window.isDraggableBar(at: cardPt) && !l1.window.isDraggableBar(at: btn))
        check("工具列高度 44、頁面在卡片內", l1.root.toolbarHeightForTest == 44 && l1.root.card.frame.maxY <= l1.root.bounds.height - 44 + 0.5)

        // 多個 Little
        let l2 = c.openLittle(server.url("/c"))!
        check("可同時開多個 Little", c.littles.count == 2 && l1.window !== l2.window)
        // Esc / ⌘W / Ctrl+W 在網頁焦點下也能關
        check("Esc 關閉（網頁取得焦點）", l2.window.firstResponder === l2.tab.webView && l2.window.performKeyEquivalent(with: escEvent(in: l2.window)) && l2.isClosed && c.littles.count == 1)
        check("關閉後 WKWebView 被清理、不進還原堆疊", l2.tab.webView.navigationDelegate == nil && tm.closedStack.count == closedBefore)
        check("⌘W 關閉", l1.window.performKeyEquivalent(with: keyEvent("w", .command, in: l1.window)) && l1.isClosed && c.littles.isEmpty)
        let l3 = c.openLittle(server.url("/a?l3"))!
        check("Ctrl+W 關閉", l3.window.performKeyEquivalent(with: keyEvent("w", .control, in: l3.window)) && l3.isClosed)
        check("Little 內按 ⌘T / Ctrl+S 不會動到主視窗", { () -> Bool in
            let l = c.openLittle(server.url("/a?l4"))!
            let before = tm.tabs.count
            let handled = l.window.performKeyEquivalent(with: keyEvent("t", .command, in: l.window)) && l.window.performKeyEquivalent(with: keyEvent("s", .control, in: l.window))
            let ok = handled && tm.tabs.count == before && !c.root.palette.isOpen && c.root.sidebarVisible
            l.close(); return ok
        }())

        // 加到 Tabs：搬移同一個 WKWebView，不重新載入
        tm.select(base)
        let l5 = c.openLittle(server.url("/a?l5"))!
        _ = await wait { l5.tab.pageTitle == "Page A" }
        _ = try? await l5.tab.webView.evaluateJavaScript("window.__marker = 42; 1")
        let wv = l5.tab.webView
        let n = tm.tabs.count
        check("⌘O 加到 Tabs", l5.window.performKeyEquivalent(with: keyEvent("o", .command, in: l5.window)) && l5.isClosed)
        check("成為新的一般 Tab：插在原選中 Tab 之後並被選中、視窗關閉", tm.tabs.count == n + 1 && tm.activeTab === l5.tab
              && tm.tabs[(tm.tabs.firstIndex { $0 === base } ?? 0) + 1] === l5.tab && c.littles.isEmpty)
        check("搬移同一個 WKWebView 且顯示在主視窗卡片", l5.tab.webView === wv && c.root.card.subviews.first === wv && wv.superview === c.root.card)
        let marker = try? await wv.evaluateJavaScript("window.__marker") as? Int
        check("頁面狀態保留（沒有重新載入）", marker == 42, "\(String(describing: marker))")
        check("加入後不進還原堆疊、導覽仍可用", tm.closedStack.count == closedBefore && l5.tab.onRequestClose != nil && l5.tab.popupInPlace == false)
        let l6 = c.openLittle(server.url("/b?l6"))!
        _ = await wait { l6.tab.pageTitle == "Page B" }
        let n6 = tm.tabs.count
        check("⌘Return 加到 Tabs", l6.window.performKeyEquivalent(with: returnEvent(.command, in: l6.window)) && tm.tabs.count == n6 + 1 && tm.activeTab === l6.tab)
        let l7 = c.openLittle(server.url("/c?l7"))!
        let n7 = tm.tabs.count
        l7.root.addButton.performClick(nil)
        check("「Add to Tabs」按鈕加到 Tabs", tm.tabs.count == n7 + 1 && tm.activeTab === l7.tab && l7.isClosed)

        // Option+點連結
        let page = tm.newTab(url: server.url("/popup"))
        _ = await wait { page.pageTitle == "Popup Opener" }
        let tabsN = tm.tabs.count
        var seen: [URL] = []
        let prev = page.onOptionClick
        page.onOptionClick = { seen.append($0); prev?($0) }
        func decide(_ a: WKNavigationAction) -> WKNavigationActionPolicy {
            var out: WKNavigationActionPolicy = .allow
            page.webView(page.webView, decidePolicyFor: a) { out = $0 }
            return out
        }
        check("Option+點連結：取消導覽並開 Little", decide(FakeNavAction(server.url("/b?opt"), mods: .option)) == .cancel && seen == [server.url("/b?opt")] && c.littles.count == 1)
        c.littles.first?.close()
        seen = []
        check("⌘+點連結不受影響（放行、不開 Little）", decide(FakeNavAction(server.url("/b"), mods: .command)) == .allow && seen.isEmpty && c.littles.isEmpty)
        check("⌥⌘+點也不攔截", decide(FakeNavAction(server.url("/b"), mods: [.option, .command])) == .allow && seen.isEmpty)
        check("一般點擊不受影響", decide(FakeNavAction(server.url("/b"))) == .allow && seen.isEmpty)
        check("Option 但不是點連結（重新整理/表單）不攔截", decide(FakeNavAction(server.url("/b"), type: .reload, mods: .option)) == .allow && seen.isEmpty)
        check("Option+點非 http(s) 連結不開 Little", decide(FakeNavAction(URL(string: "mailto:a@b.c")!, mods: .option)) == .cancel && seen.isEmpty && c.littles.isEmpty)
        // 真實 WebKit：把帶 Option 的真實滑鼠事件送進 WKWebView（在連結座標按下/放開）。
        tm.select(page)
        c.window.makeKeyAndOrderFront(nil)
        c.window.makeFirstResponder(page.webView)
        let rect = (try? await page.webView.evaluateJavaScript("(()=>{const r=document.getElementById('l').getBoundingClientRect();return [r.left+r.width/2, r.top+r.height/2]})()")) as? [Double]
        func mouse(_ type: NSEvent.EventType, _ p: NSPoint, _ mods: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: c.window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        if let rect, rect.count == 2 {
            let inView = NSPoint(x: rect[0], y: rect[1])
            let winPt = page.webView.convert(inView, to: nil)
            c.window.sendEvent(mouse(.leftMouseDown, winPt, .option))
            c.window.sendEvent(mouse(.leftMouseUp, winPt, .option))
        }
        let viaReal = await wait(3) { c.littles.count == 1 }
        if viaReal {
            check("真實滑鼠事件：Option+點連結開 Little、原頁不導航、不新增 Tab", c.littles.first?.tab.requestedURL == server.url("/b") && page.url == server.url("/popup") && tm.tabs.count == tabsN)
            c.littles.first?.close()
        } else {
            print("   (略過：合成的 Option 滑鼠事件沒有觸發連結導覽，僅以 WKNavigationAction 單元驗證；真實手感待實測)")
        }
        // 一般點擊（無修飾鍵）真實 WebKit：target=_blank 仍是新 Tab
        _ = try? await page.webView.evaluateJavaScript("document.getElementById('l').click(); 1")
        check("一般點擊 target=_blank 仍開新 Tab（不走 Little）", await wait { tm.tabs.count == tabsN + 1 } && c.littles.isEmpty)

        // Little 內：window.open / target=_blank 就地開啟；標題純文字；錯誤頁
        let lp = c.openLittle(server.url("/popup"))!
        _ = await wait { lp.tab.pageTitle == "Popup Opener" }
        let tabsBefore = tm.tabs.count
        _ = try? await lp.tab.webView.evaluateJavaScript("document.getElementById('l').click(); 1")
        check("Little 內 target=_blank 就地開啟（不新增 Tab 或 Little）", await wait { lp.tab.pageTitle == "Page B" } && tm.tabs.count == tabsBefore && c.littles.count == 1)
        lp.close()
        let lx = c.openLittle(server.url("/xss"))!
        check("Little 標題當純文字（提示文字原樣）", await wait { lx.root.pillToolTip.hasPrefix("<img") })
        lx.close()
        let tmp = try FixtureServer()
        await tmp.start()
        let dead = tmp.url("/x")
        tmp.stop()
        try? await Task.sleep(nanoseconds: 200_000_000)
        let le = c.openLittle(dead)!
        check("Little 載入失敗顯示說明頁並結束載入狀態", await wait { le.tab.errorURL == dead && !le.tab.isLoading && !le.root.card.loadingBar.isActive })
        le.close()

        // 外部連結依設定
        let ext = BrowserWindowController(dataStore: .nonPersistent(), storage: tempStorage("ext"), prefs: Preferences(defaults: UserDefaults(suiteName: suite)!), autosave: false)
        ext.prefs.externalLinksInLittle = true
        check("冷啟動：只有一個空白 Tab", ext.tabs.tabs.count == 1 && ext.tabs.tabs[0].displayURL == nil)
        ext.openExternal([server.url("/b")])
        check("外部連結（設定開啟）走 Little，不多開 Tab", ext.littles.count == 1 && ext.tabs.tabs.count == 1 && ext.tabs.tabs[0].displayURL == nil)
        ext.closeAllLittles()
        ext.prefs.externalLinksInLittle = false
        ext.openExternal([server.url("/b")])
        check("外部連結（設定關閉）走新 Tab：重用冷啟動的空白 Tab，不多開", ext.littles.isEmpty && ext.tabs.tabs.count == 1 && ext.tabs.tabs[0].displayURL == server.url("/b"))
        ext.openExternal([server.url("/c")])
        check("之後的外部連結開新 Tab", ext.tabs.tabs.count == 2)
        // 結束時關閉所有 Little
        ext.prefs.externalLinksInLittle = true
        ext.openExternal([server.url("/a"), server.url("/b")])
        let both = ext.littles.count
        ext.flushPersistence()
        check("flush（退出前）會關閉所有 Little", both == 2 && ext.littles.isEmpty)
        // 選單項目
        let item = NSApp.mainMenu?.items.compactMap { $0.submenu?.items.first { $0.title == "Open External Links in Little Window" } }.first
        check("File 選單有「Open External Links in Little Window」勾選項", item != nil && item?.action != nil)
        ext.window.close()
        for l in c.littles { l.close() }
        c.window.close()
    }
}

extension Smoke {
    /// 截圖用：在螢幕上留住「主視窗 + Little」幾秒，外部用 screencapture 擷取。
    static func littleHold(_ server: FixtureServer) async {
        let c = BrowserWindowController(dataStore: .nonPersistent(), storage: tempStorage("hold"), autosave: false)
        let a = c.tabs.newTab(url: server.url("/doc"))
        _ = await wait { a.pageTitle.hasPrefix("Design") }
        c.tabs.pins.addTab(url: server.url("/a"), title: "Docs", parent: nil)
        c.window.setFrame(NSRect(x: 120, y: 140, width: 1100, height: 700), display: true)
        if let l = c.openLittle(server.url("/doc?peek")) {
            _ = await wait { l.tab.pageTitle.hasPrefix("Design") }
            l.window.setContentSize(NSSize(width: 760, height: 520))
            l.window.setFrameOrigin(NSPoint(x: c.window.frame.midX - l.window.frame.width / 2 + 60, y: c.window.frame.midY - l.window.frame.height / 2 - 20))
        }
        print("HOLD main=\(c.window.windowNumber) little=\(c.littles.first?.window.windowNumber ?? 0)")
        try? await Task.sleep(nanoseconds: 9_000_000_000)
    }
}

extension Smoke {
    private static func menuItem(_ title: String) -> NSMenuItem? {
        NSApp.mainMenu?.items.compactMap { $0.submenu?.items.first { $0.title == title } }.first
    }

    /// Little 為 key window 時，選單動作要依 key window 分派（回報的 bug：⌘W 關到主視窗的 Tab）。
    static func littleRoutingChecks(_ server: FixtureServer, _ app: AppDelegate) async throws {
        print("Little：選單動作依 key window 分派")
        let m = app.controller!
        let tm = m.tabs
        let base = tm.newTab(url: server.url("/a?route"))
        let other = tm.newTab(url: server.url("/b?route"))
        _ = await wait { base.pageTitle == "Page A" && other.pageTitle == "Page B" }
        tm.select(other)
        m.window.makeKeyAndOrderFront(nil)
        func newLittle(_ q: String) async -> LittleWindowController {
            let l = m.openLittle(server.url("/a?\(q)"))!
            _ = await wait { l.tab.pageTitle == "Page A" }
            return l
        }

        // ⌘W / Ctrl+W × 三種焦點，一律走 NSApp.sendEvent（真實按鍵路徑）
        for (mods, label) in [(NSEvent.ModifierFlags.command, "⌘W"), (.control, "Ctrl+W")] {
            for focus in ["網頁", "工具列", "剛開啟"] {
                let n = tm.tabs.count, active = tm.activeTab
                let l = focus == "剛開啟" ? m.openLittle(server.url("/a?fresh\(label)"))! : await newLittle("f\(focus)\(label)")
                if focus == "工具列" { l.window.makeFirstResponder(l.root.reloadButton) }
                if focus == "網頁" { l.window.makeFirstResponder(l.tab.webView) }
                let wasKey = l.window.isKeyWindow
                NSApp.sendEvent(keyEvent("w", mods, in: l.window))
                check("\(label) 焦點在 Little \(focus)：Little 關閉、主視窗 Tab 不變", wasKey && l.isClosed && tm.tabs.count == n && tm.activeTab === active && m.littles.isEmpty)
            }
        }
        // 只走選單（繞過視窗層級攔截）：根因的路徑
        do {
            let n = tm.tabs.count, active = tm.activeTab
            let l = await newLittle("menuonly")
            _ = NSApp.mainMenu?.performKeyEquivalent(with: keyEvent("w", .command, in: l.window))
            check("只走選單的 ⌘W（Little 為 key）：關 Little、不動主視窗 Tab", l.isClosed && tm.tabs.count == n && tm.activeTab === active)
        }
        do {
            let n = tm.tabs.count
            let l = await newLittle("menuonly2")
            _ = NSApp.mainMenu?.performKeyEquivalent(with: keyEvent("w", .control, in: l.window))
            check("只走選單的 Ctrl+W（Little 為 key）：關 Little、不動主視窗 Tab", l.isClosed && tm.tabs.count == n)
        }
        // 主視窗為 key window 時 ⌘W 仍關主視窗的 Tab（Little 在後面不受影響）
        do {
            let l = await newLittle("behind")
            m.window.makeKeyAndOrderFront(nil)
            let n = tm.tabs.count
            let victim = tm.activeTab
            NSApp.sendEvent(keyEvent("w", .command, in: m.window))
            check("主視窗為 key：⌘W 關主視窗目前的 Tab，Little 不受影響", tm.tabs.count == n - 1 && !tm.tabs.contains { $0 === victim } && !l.isClosed)
            l.close()
            tm.restoreLast()
        }
        // 多個 Little 各自獨立關閉；關閉後焦點回到主視窗
        do {
            let l1 = await newLittle("multi1"), l2 = await newLittle("multi2")
            l2.window.makeKeyAndOrderFront(nil)
            NSApp.sendEvent(keyEvent("w", .command, in: l2.window))
            check("兩個 Little：只關 key 的那個", l2.isClosed && !l1.isClosed && m.littles.count == 1)
            check("關閉 Little 後焦點回到主視窗", m.window.isKeyWindow)
            l1.window.makeKeyAndOrderFront(nil)
            NSApp.sendEvent(keyEvent("w", .command, in: l1.window))
            check("第二個也可獨立關閉", l1.isClosed && m.littles.isEmpty && m.window.isKeyWindow)
        }
        // Little 為 key 時：不適用的選單項目停用，且按鍵不會動到主視窗
        do {
            // 主視窗用 127.0.0.1、Little 用 localhost：縮放是依網站記憶的，不同網站才看得出作用對象。
            let l = m.openLittle(URL(string: "http://localhost:\(server.port)/a?disabled")!)!
            _ = await wait { l.tab.pageTitle == "Page A" }
            let pins = tm.pins.roots.count, tabs = tm.tabs.count, sidebar = m.root.sidebarVisible, closed = tm.closedStack.count
            let disabled = ["New Tab", "Open Location", "Pin / Unpin Tab", "Toggle Sidebar", "Restore Closed Tab", "New Folder", "Duplicate Tab", "Find…", "Find Next"]
            check("Little 為 key：不適用的選單項目停用", disabled.allSatisfy { t in menuItem(t).map { !app.validateMenuItem($0) } == true }, "\(disabled.filter { t in menuItem(t).map { app.validateMenuItem($0) } != false })")
            let allowed = ["Close Tab", "Close Tab (Ctrl+W)", "Reload", "Back", "Forward", "Zoom In", "Zoom Out", "Actual Size", "Copy URL", "Copy URL as Markdown"]
            check("Little 為 key：可套用的選單項目啟用", allowed.allSatisfy { t in menuItem(t).map { app.validateMenuItem($0) } == true })
            for (chars, mods) in [("d", NSEvent.ModifierFlags.command), ("s", .command), ("t", .command), ("l", .command), ("n", [.command, .shift]), ("t", [.command, .shift]), ("s", .control)] {
                NSApp.sendEvent(keyEvent(chars, mods, in: l.window))
            }
            check("Little 為 key 時按 ⌘D/⌘S/⌘T/⌘L/⌘⇧N/⌘⇧T/Ctrl+S：主視窗完全不動", tm.pins.roots.count == pins && tm.tabs.count == tabs && m.root.sidebarVisible == sidebar
                  && tm.closedStack.count == closed && !m.root.palette.isOpen && !l.isClosed)
            // 縮放 / 複製網址 / 重新整理 / 上一頁作用在 Little 的頁面，不是主視窗
            let mainZoom = tm.activeTab!.webView.pageZoom
            NSApp.sendEvent(keyEvent("+", .command, in: l.window))
            let zoomed = await wait(2) { l.tab.webView.pageZoom > 1 }
            check("⌘+ 作用在 Little 的頁面，主視窗 Tab 縮放不變", zoomed && tm.activeTab!.webView.pageZoom == mainZoom, "little=\(l.tab.webView.pageZoom) main=\(tm.activeTab!.webView.pageZoom)")
            NSApp.sendEvent(keyEvent("0", .command, in: l.window))
            check("⌘0 還原 Little 縮放", await wait(2) { l.tab.webView.pageZoom == 1 })
            NSApp.sendEvent(keyEvent("c", [.command, .shift], in: l.window))
            check("⌘⇧C 複製的是 Little 頁面的網址", await wait(2) { NSPasteboard.general.string(forType: .string) == l.tab.url?.absoluteString }, NSPasteboard.general.string(forType: .string) ?? "nil")
            let mainBefore = tm.activeTab!.isLoading
            NSApp.sendEvent(keyEvent("r", .command, in: l.window))
            check("⌘R 重新整理 Little 的頁面（主視窗不受影響）", await wait(3) { l.tab.isLoading } && tm.activeTab!.isLoading == mainBefore)
            _ = await wait(5) { !l.tab.isLoading }
            l.tab.load(server.url("/b?back"))
            _ = await wait { l.tab.pageTitle == "Page B" && l.root.backButton.isEnabled }
            NSApp.sendEvent(keyEvent("[", .command, in: l.window))
            check("⌘[ 上一頁作用在 Little", await wait { l.tab.pageTitle == "Page A" })
            // Esc / ⌘O / ⌘Return 在各種焦點下
            l.window.makeFirstResponder(l.root.reloadButton)
            NSApp.sendEvent(escEvent(in: l.window))
            check("Esc 在工具列焦點也關閉 Little", l.isClosed)
            let n = tm.tabs.count
            let l2 = await newLittle("o-key")
            l2.window.makeFirstResponder(l2.root.backButton)
            NSApp.sendEvent(keyEvent("o", .command, in: l2.window))
            check("⌘O 在工具列焦點加到 Tabs", l2.isClosed && tm.tabs.count == n + 1 && tm.activeTab === l2.tab)
            tm.close(l2.tab)
            let l3 = await newLittle("ret-key")
            NSApp.sendEvent(returnEvent(.command, in: l3.window))
            check("⌘Return 加到 Tabs", l3.isClosed && tm.tabs.count == n + 1)
            tm.close(l3.tab)
        }
        _ = tm.restoreLast
        m.window.makeKeyAndOrderFront(nil)
    }
}
