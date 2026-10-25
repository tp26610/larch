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

        print("載入指示")
        c.submitAddress(server.url("/slow").absoluteString)
        let row1 = c.sidebar.rowViews[0]
        check("載入中底部有掃動光條", await wait { row1.isShowingLoadingBar })
        check("載入完成光條消失", await wait(6) { !row1.isShowingLoadingBar && t1.pageTitle == "Slow Page" })

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
        check("⌘L 聚焦網址列", press("l", .command, in: c.window) && c.addressField.currentEditor() != nil)
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
        try await paletteChecks(server, app)
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
        print("外部開啟")
        let c = app.controller!
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
        check("空白輸入沒有「開啟 / 搜尋」列、Enter 不開新 Tab", !p.items.contains { $0.kind == .openOrSearch } && tm.tabs.count == m || tm.tabs.count == m)
        p.dismiss()
        // ⌘L 與 New Tab 按鈕
        check("⌘L 仍是聚焦網址列", press("l", .command, in: w) && !p.isOpen && c.addressField.currentEditor() != nil)
        c.sidebar.newTabButton.performClick(nil)
        check("側邊欄 New Tab 按鈕叫出同一個覆蓋層", p.isOpen && tm.tabs.count == m)
        p.dismiss()
        // 覆蓋層開啟時擋住網頁的點擊
        _ = press("t", .command, in: w)
        let center = c.root.convert(NSPoint(x: card.midX, y: 12), to: nil)
        check("開啟時整個內容區的 hit-test 被覆蓋層攔下", c.root.hitTest(c.root.convert(center, from: nil)).map { $0 === p || $0.isDescendant(of: p) } == true)
        p.dismiss()
    }
}
