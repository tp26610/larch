# my-browser-mac — 專案脈絡（給 Claude Code 與未來的自己）

## 為什麼做這個
Brian（Senior Engineering Manager，台灣，用繁體中文溝通）因 Arc 將於 2026-12-22 sunset 而自製瀏覽器。核心功能依重要性：Little Arc（點連結先在小視窗看一眼）、Ctrl+Tab MRU 切換、Command Palette（⌘T）。

姊妹專案 `../my-browser`（Electron）已有這三個功能，但 Google 登入被 Electron 擋掉，無法當主力，保留不動（只可唯讀參考）。本專案改走 macOS 專用的 Swift + 系統 WebKit：
- 安全更新跟著 macOS；Google 帳密登入以預設 UA 驗證可過（`../my-browser/experiments/webkit-login`）。
- 只做 Mac：不跨平台、不做 Chrome 擴充功能。重度 Google 網頁應用用其他瀏覽器補位。
- 已評估放棄：Dia、Ardia（只適合當第二瀏覽器）、fork Chromium。

## 溝通偏好
繁體中文，簡潔，結果先行，不要 emoji。commit 訊息用繁體中文，結尾加 `Co-Authored-By` 行。

## 指令
```bash
swift build
swift run MyBrowser                 # 執行
scripts/smoke.sh                    # 105 項煙霧測試，驅動真實視窗與 WKWebView（會開視窗）
scripts/bundle.sh                   # build/My Browser.app（Info.plist 含 http/https、html 宣告）
scripts/install.sh                  # 安裝到 /Applications（見 README）
.build/debug/MyBrowser --live-check https://accounts.google.com /tmp/out
                                    # 真實網站檢查：印標題/網址，存 /tmp/out-sidebar.png、/tmp/out-page.png
```
改完功能請跑 `scripts/smoke.sh`；新增行為時在 `Sources/MyBrowser/Smoke.swift` 加 check。
建置選擇：Swift Package + 腳本打包（不用 .xcodeproj，diff 乾淨、CLI 可建置）。Swift 語言模式為 5（避免 AppKit/WebKit 的嚴格並行檢查雜訊），工具鏈 6.2。

## 架構（Sources/MyBrowser）
```
main.swift / AppDelegate.swift   進入點、選單（所有快捷鍵走選單）、命令列網址、--smoke / --live-check
BrowserWindowController.swift    組裝：視窗、RootView、TabManager、網址列、動作
RootView（SidebarView.swift）    manual layout：側邊欄 + CardView；sidebarVisible 切換
SidebarView / AddressBar         側邊欄（導覽按鈕、網址列、Tab 列表、New Tab）
TabRowView.swift                 一列 Tab：favicon、標題、載入光條、改名、關閉
Tab.swift                        一個 WKWebView + navigation/UI delegate、favicon、權限
TabManager.swift                 tabs、activeTab、closedStack(25)、選取與關閉邏輯
InputNormalizer.swift            網址/搜尋判斷（對應 my-browser util.js normalizeInput）
Storage.swift                    Application Support JSON 讀寫（容錯）+ Debouncer
SessionStore.swift               重開還原 Tab（session.json）；HistoryStore 在 History.swift
DownloadManager.swift            WKDownload → 下載資料夾，重名加序號
ErrorPage.swift                  載入失敗說明頁（全部跳脫、CSP 禁腳本）
FindBar.swift                    頁內尋找列 + ZoomStore（以 host 記縮放，存 UserDefaults）
Theme.swift                      顏色與尺寸
Smoke.swift                      FixtureServer（本機假網站）+ smoke 檢查 + liveCheck
```
- 新增快捷鍵：在 `AppDelegate.buildMenu` 加選單項。Shift 組合要用大寫 keyEquivalent（如 "T"）並加 `.shift`，否則與 ⌘T 衝突。
- smoke 以 `--smoke` 在同一個執行檔內跑，使用 `nonPersistent` data store，不污染真實登入資料。

## 決策與重要的坑
1. **卡片底下不可有拖曳區域**：否則 macOS 會吞掉網頁捲動。只有視窗四周 8px 邊框與側邊欄空白處可拖曳（`isMovableByWindowBackground` + 各 view 的 `mouseDownCanMoveWindow`：RootView/SidebarView/FlippedView 為 true，CardView、Tab 列、網址列為 false）。smoke 有 hit-test 驗證。
2. **登入**：`WKWebsiteDataStore.default()` + 預設 UA（不要偽造 UA）。彈出視窗（`window.open`/`target=_blank`）在 `createWebViewWith` 內以同一個 view 載入並回傳 nil。
3. **權限預設全拒**：媒體擷取一律 deny；僅啟用 element fullscreen。非 http/https/about/blob 的導覽（file:、mailto:、自訂 scheme）一律取消。
4. **網頁來源的標題與網址一律 `stringValue` 純文字顯示**，不用 attributed/HTML。
5. 關閉最後一個 Tab 會補一個空白 Tab；空白（無 http URL）的 Tab 不進 closedStack。
6. 預設瀏覽器註冊、外部連結走 Little，需要打包後的 .app 且 Info.plist 宣告 http/https（尚未做，見 BACKLOG）。
7. smoke 用 `NSApp.mainMenu.performKeyEquivalent` 走真實選單比對，等同按鍵路徑。
8. 沒有螢幕錄製權限時 `screencapture` 會失敗；改用 `--live-check` 存 PNG。

9. **NSWindow 要設 `isReleasedWhenClosed = false`**，否則 close() 後 ARC 重複釋放會 segfault。
10. **WebKit 對受限連接埠（如 1）回 WebKitErrorDomain 102**，與「載入被轉成下載」同碼；錯誤頁忽略 102，測連不上要用已關閉的真實埠。
11. **彈出視窗**：`createWebViewWith` 必須用 WebKit 給的 configuration 建新 Tab 並回傳其 webView，window.opener/postMessage 才會通；`webViewDidClose` 對應 window.close()。
12. 憑證錯誤不實作 server trust 挑戰，走預設處理 → 錯誤頁，刻意不提供略過。HTTP 驗證憑證用 `persistence: .none`。
13. 外部連結入口是 `application(_:open:)`；冷啟動時 controller 可能還沒建好，先放進 `pendingURLs`。本機 .html 只放行該檔案的導覽（`allowedFileURL`）；網址列與其他來源的 file: 一律拒絕。
14. 下載、歷史、session 路徑在 smoke 模式都導到暫存資料夾，不碰真實資料。
15. 說明頁（loadHTMLString）在上一頁/下一頁的歷史行為未驗證；重新整理在說明頁上會重試原網址（`reloadOrRetry`）。

## 驗證狀況
- smoke 105/105 通過（macOS 26 / Swift 6.2.4）；accounts.google.com 登入頁載入成功（含 favicon）。
- 冷啟動與已執行時 `open -a` 開外部連結已用打包的 .app 實測（session.json 有新 Tab）。
- 尚未在真實視窗手動驗證：實際把它設為預設瀏覽器、真實鍵盤的 ⌘= 放大、拖曳視窗手感、紅綠燈位置、側邊欄隱藏後紅綠燈浮在網頁上、捲動手感、Google 實際帳密登入與重開後保持登入（只驗證登入頁載入；持久性依據實驗專案的結果）、下載、HTTP 驗證對話框、全螢幕影片。

## Backlog
見 `BACKLOG.md`；開工前先讀，完成後移到「已完成」。
