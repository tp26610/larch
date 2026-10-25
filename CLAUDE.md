# Larch — 專案脈絡（給 Claude Code 與未來的自己）

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
swift run Larch                 # 執行
scripts/smoke.sh                    # 221 項煙霧測試，驅動真實視窗與 WKWebView（會開視窗）
scripts/bundle.sh                   # build/Larch.app（Info.plist 含 http/https、html 宣告）
scripts/install.sh                  # 安裝到 /Applications（見 README）
.build/debug/Larch --live-check https://accounts.google.com /tmp/out
                                    # 真實網站檢查：印標題/網址，存 /tmp/out-sidebar.png、/tmp/out-page.png
```
改完功能請跑 `scripts/smoke.sh`；新增行為時在 `Sources/Larch/Smoke.swift` 加 check。
建置選擇：Swift Package + 腳本打包（不用 .xcodeproj，diff 乾淨、CLI 可建置）。Swift 語言模式為 5（避免 AppKit/WebKit 的嚴格並行檢查雜訊），工具鏈 6.2。

## 架構（Sources/Larch）
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
PinStore.swift                   釘選與資料夾的樹（PinNode）、pins.json、移動/刪除/防循環
SidebarRows.swift                SidebarItem（拖曳字串）、資料夾列、分隔線、落點提示、拖曳來源
LoadingBarView.swift             卡片頂端載入進度條（estimatedProgress）
LarchWindow.swift                主視窗子類別（⌘W/Ctrl+W 按鍵路徑、雙擊 bar）
CommandPaletteView.swift         ⌘T 命令列覆蓋層（輸入框 + 候選列；provider / onPick 由 controller 注入，可重用）
PaletteModel.swift               PaletteItem 與 PaletteSearch（開啟/搜尋、已開 Tab、歷史的候選與排序）
Fuzzy.swift                      模糊比對（對應 my-browser util.js fuzzy / scoreTerms）
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
16. **⌘W / Ctrl+W 由 `LarchWindow.performKeyEquivalent` 先交給選單**：焦點在 WKWebView 時，按鍵會先送進網頁、沒被 preventDefault 才非同步回頭比對選單，網頁可擋掉、smoke 也會變成非同步。Ctrl+W 是 File 選單裡獨立的「Close Tab (Ctrl+W)」項目。關閉最後一個 Tab 會補一個空白 Tab（視窗不關）。

17. **⌘T 是命令列覆蓋層，不是直接新增空白 Tab**：`RootView.palette`（`CommandPaletteView`）蓋在整個視窗內容上，開啟時 `hitTest` 吞掉所有滑鼠事件，面板置中於網頁卡片。第一列固定「Open / Search: 輸入」→ 新 Tab；其次是已開啟的 Tab（切換、不開新 Tab）、歷史（新 Tab，已開啟的網址不重複）。標題與網址一律 `stringValue` 純文字。Esc 或點面板外關閉並把焦點還給原處；選取後焦點交給網頁。⌘L 仍是聚焦側邊欄網址列、在目前 Tab 導航。日後擴充 Command Palette：在 `PaletteItem.Action` 加 case、在 `PaletteSearch.results` 加來源。截圖/除錯：`Larch --open-palette 關鍵字` 啟動後直接叫出覆蓋層（直接執行會讀寫真實 session/history）；外觀截圖見 `docs/palette.png`。

18. **雙擊 bar 放大/還原**：標題列隱藏 + `isMovableByWindowBackground` 時系統不處理雙擊，由 `LarchWindow.sendEvent` 攔 `clickCount == 2`：hit-test 的整條祖先鏈都 `mouseDownCanMoveWindow == true`（外框、側邊欄空白）才算 bar，依 `AppleActionOnDoubleClick` 做 `performZoom`（預設 / Maximize）、`performMiniaturize`（Minimize）或不動（None）。網頁卡片、Tab 列、按鈕、網址列不處理；卡片底下仍不可有拖曳區域（第 1 點）。

19. **紅綠燈跟著側邊欄**：`RootView.onSidebarVisibilityChange` → `BrowserWindowController.syncTrafficLights` → `LarchWindow.setTrafficLights`（alpha 淡入淡出，結束後 `isHidden`）。側邊欄隱藏時，`RootView` 左上角 90x40 的 `NSTrackingArea`（`.activeAlways`，不攔截事件，網頁卡片點擊/捲動不受影響）進入時暫時顯示、離開再隱藏。全螢幕一律顯示（交給系統），進出全螢幕時重新同步。啟動時以 `syncTrafficLights(animated: false)` 對齊。截圖用 `--hide-sidebar` 旗標（注意直接執行會讀寫真實資料，見第 20 點），見 `docs/sidebar-*.png`。

20. **載入狀態**：`Tab` 以 KVO 觀察 `isLoading` 與 `estimatedProgress`（都走 `onChange`）；`BrowserWindowController.syncLoading` 只把目前 Tab 的狀態餵給 `CardView.loadingBar`（3px、貼卡片上緣被圓角裁切、`hitTest` 為 nil 不擋點擊捲動）與停止鈕，切換 Tab 時 `animated: false` 立即反映。結束（完成、失敗、停止）一律走 `isLoading == false`，進度條衝到 100% 後淡出。Tab 列載入中以 `NSProgressIndicator` spinner 取代 favicon（舊的底部掃動光條已移除）。已知：`load()` 後立刻 `stopLoading()`（毫秒內）WebKit 會丟掉 stop、isLoading 卡住；人手點擊不會遇到，smoke 的停止檢查要先等約 0.4 秒。**注意：macOS app 忽略 `HOME` 環境變數，`HOME=...` 不能隔離資料，直接執行 Larch 會讀寫真實的 `~/Library/Application Support/Larch/`**（`--hide-sidebar`、`--open-palette` 截圖時要留意）。載入中截圖見 `docs/loading.png`。

21. **釘選與資料夾**：`PinStore` 是樹（`PinNode`：folder / tab，最上層可混放），存 `pins.json`，節點只在載入時過濾 http(s)。`Tab.pinID` 綁定節點；`TabManager.liveTab(forPin:)` / `activatePin` / `pin` / `unpin` / `moveTab`。關掉釘選 Tab 時節點保留（灰色列，`TabRowView.tab == nil`），點擊用節點網址重開並綁定；`closedStack` 與 session 都帶 `pinID`，還原時節點不存在或已被綁定就當一般 Tab。側邊欄順序：釘選樹（`PinStore.visible()`）→ `DividerRowView` → 一般 Tab（`pinID == nil`）。節點的標題與 favicon（PNG）在 `tabChanged` 時用 `PinStore.remember` 同步（不觸發重建，讓灰色列外觀正確）。
22. **拖曳**：`SidebarView` 是整個清單的拖曳目的地（剪貼簿型別 `app.larch.sidebar-item`，字串 `tab:<uuid>` / `pin:<uuid>`）；它只做幾何（找到游標下的列與列內位置 0~1）與畫提示，語意交給 `BrowserWindowController.resolveDrop`（回傳 `DropPlan`：提示樣式 + commit）。規則：資料夾列上 25% 之前、下 25% 之後（收合或空資料夾才算「之後」）、中間放進去；釘選 Tab 列上/下半；分隔線 = 釘到最上層末尾 / 取消釘選；一般列重排；資料夾不能放進自己的子孫或一般區；灰色釘選拖到一般區會以該網址開成一般 Tab。smoke 以假的 `NSDraggingInfo` 走 `draggingUpdated` / `performDragOperation`，真實滑鼠拖曳（拖曳影像、自動捲動手感）沒有實測。截圖/排版參考 `docs/pins.png`（smoke 在 `LARCH_SHOT_DIR=<資料夾>` 時於暫存資料產生，不碰真實資料）。

## 驗證狀況
- smoke 221/221 通過（macOS 26 / Swift 6.2.4）；accounts.google.com 登入頁載入成功（含 favicon）。
- 冷啟動與已執行時 `open -a` 開外部連結已用打包的 .app 實測（session.json 有新 Tab）。
- 尚未在真實視窗手動驗證：實際把它設為預設瀏覽器、真實鍵盤的 ⌘= 放大、拖曳視窗手感、紅綠燈位置、側邊欄隱藏時滑鼠實際移到左上角的紅綠燈淡入淡出、全螢幕進出、捲動手感、Google 實際帳密登入與重開後保持登入（只驗證登入頁載入；持久性依據實驗專案的結果）、下載、HTTP 驗證對話框、全螢幕影片。

## Backlog
見 `BACKLOG.md`；開工前先讀，完成後移到「已完成」。
