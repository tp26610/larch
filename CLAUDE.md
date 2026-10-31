# Larch — 專案脈絡（給 Claude Code 與未來的自己）

## 為什麼做這個
Brian（Senior Engineering Manager，台灣，用繁體中文溝通）因 Arc 將於 2026-12-22 sunset 而自製瀏覽器。核心功能依重要性：Little Arc（點連結先在小視窗看一眼）、Ctrl+Tab MRU 切換、Command Palette（⌘T）。

姊妹專案 `../my-browser`（Electron，私有專案，外部讀者無法存取，僅供作者內部參考）已有這三個功能，但 Google 登入被 Electron 擋掉，無法當主力，保留不動（只可唯讀參考）。本專案改走 macOS 專用的 Swift + 系統 WebKit：
- 安全更新跟著 macOS；Google 帳密登入以預設 UA 驗證可過（`../my-browser/experiments/webkit-login`）。
- 只做 Mac：不跨平台、不做 Chrome 擴充功能。重度 Google 網頁應用用其他瀏覽器補位。
- 已評估放棄：Dia、Ardia（只適合當第二瀏覽器）、fork Chromium。

## 決策紀錄與研究
**為什麼這樣做**（Electron 放棄的原因、為什麼不 fork Chromium、Google 登入與 passkey 的事實、Ardia 評估、安全狀態、協作與驗證限制）見 `docs/decisions.md`；Ardia 的完整審查與背景報告在 `docs/research/`。開工前先看，避免重複已驗證無效的做法（例如偽裝 Chrome 的 UA / `Sec-CH-UA`）。

## 溝通偏好
繁體中文，簡潔，結果先行，不要 emoji。commit 訊息用繁體中文，結尾加 `Co-Authored-By` 行。

## 指令
```bash
swift build
swift run Larch                 # 執行
swift test                          # 純邏輯單元測試（Swift Testing；Fuzzy / InputNormalizer / PinStore），不開視窗
scripts/smoke.sh                    # 煙霧測試（項數見跑完的輸出），驅動真實視窗與 WKWebView（會開視窗）
scripts/bundle.sh                   # build/Larch.app（Info.plist 含 http/https、html 宣告）
scripts/dmg.sh                      # build/Larch-<版本>-arm64.dmg；版本號讀根目錄 VERSION（發版流程：改 VERSION、commit、打同名 tag `v<版本>`、gh release create）
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
TabSwitcher.swift                Ctrl+Tab MRU 切換器（狀態機：快速按/按住顯示/連按/放開確認/Esc/閒置）
TabManager.swift                 tabs、activeTab、closedStack(25)、選取與關閉邏輯
InputNormalizer.swift            網址/搜尋判斷（對應 my-browser util.js normalizeInput）
Storage.swift                    Application Support JSON 讀寫（容錯）+ Debouncer
SessionStore.swift               重開還原 Tab（session.json）；HistoryStore 在 History.swift
HistoryWindow.swift              History 視窗（仿 Arc：日期卡片、搜尋、多選 Open/Delete、Clear History…）
TaskManagerWindow.swift          Task Manager 視窗（仿 Arc：列出一般 Tab 的記憶體用量、End Process 關閉分頁）
DownloadManager.swift            WKDownload → 下載資料夾，重名加序號
ErrorPage.swift                  載入失敗說明頁（全部跳脫、CSP 禁腳本）
FindBar.swift                    頁內尋找列 + ZoomStore（以 host 記縮放，存 UserDefaults）
Theme.swift                      顏色與尺寸
PinStore.swift                   釘選與資料夾的樹（PinNode）、pins.json、移動/刪除/防循環
SidebarRows.swift                SidebarItem（拖曳字串）、資料夾列、分隔線、落點提示、拖曳來源
AuxiliaryWindow.swift            輔助視窗協定（Little / History / Task Manager 共用：key window 判斷）
LittleWindow.swift               Little 視窗（LittleWindow 按鍵攔截、LittleRootView 工具列、LittleWindowController）
Preferences.swift                偏好（外部連結走 Little、Little 大小）
LoadingBarView.swift             卡片頂端載入進度條（estimatedProgress）
LarchWindow.swift                主視窗子類別（⌘W/Ctrl+W 按鍵路徑、雙擊 bar）
CommandPaletteView.swift         ⌘T 命令列覆蓋層（輸入框 + 候選列；provider / onPick 由 controller 注入，可重用）
PaletteActions.swift             動作表 PaletteActions.all（id / 標題 / 關鍵字 / 快捷鍵提示 / isAvailable / run）
PaletteModel.swift               PaletteItem 與 PaletteSearch（開啟/搜尋、已開 Tab、歷史的候選與排序）
Fuzzy.swift                      模糊比對（對應 my-browser util.js fuzzy / scoreTerms）
Smoke.swift                      FixtureServer（本機假網站）+ smoke 檢查 + liveCheck
```
- 新增快捷鍵：在 `AppDelegate.buildMenu` 加選單項。Shift 組合要用大寫 keyEquivalent（如 "T"）並加 `.shift`，否則與 ⌘T 衝突。
- smoke 以 `--smoke` 在同一個執行檔內跑，使用 `nonPersistent` data store，不污染真實登入資料。

## 決策與重要的坑
1. **卡片底下不可有拖曳區域**：否則 macOS 會吞掉網頁捲動。只有視窗四周 8px 邊框與側邊欄空白處可拖曳（`isMovableByWindowBackground` + 各 view 的 `mouseDownCanMoveWindow`：RootView/SidebarView/FlippedView 為 true，CardView、Tab 列、網址列為 false）。smoke 有 hit-test 驗證。
2. **登入**：`WKWebsiteDataStore.default()`。彈出視窗（`window.open`/`target=_blank`）在 `createWebViewWith` 內以同一個 view 載入並回傳 nil。
   **UA 補字尾（不是偽裝 Chrome）**：`WKWebView` 預設 UA 少了 `Version/X Safari/Y` 字尾，導致它不被辨識為「正式」瀏覽器——Google 搜尋結果頁因此退回簡化版（無 favicon、無 AI 模式/購物等分頁、無帳號頭像），真正的 Safari 不會這樣。`Tab.init`（`Tab.swift`）用 `configuration.applicationNameForUserAgent` 補上這個字尾：Safari 版本號動態讀系統的 `/Applications/Safari.app`（跟著 macOS 更新），WebKit 組建號固定用 `605.1.15`（Safari 多年未變、真 Safari 也是這個值）。這跟已驗證無效、刻意不做的「偽裝 Chrome UA / `Sec-CH-UA`」（見 `docs/decisions.md`）是兩回事：那是假裝成別的瀏覽器引擎，這裡只是把 WKWebView 本來就該有、但預設沒帶的 Safari 身分字串補回去。用 `.build/debug/Larch --live-check https://httpbin.org/user-agent /tmp/x` 可以驗證目前送出的完整 UA 字串。
3. **權限預設全拒**：媒體擷取一律 deny；僅啟用 element fullscreen。非 http/https/about/blob 的導覽（file:、mailto:、自訂 scheme）一律取消。
4. **網頁來源的標題與網址一律 `stringValue` 純文字顯示**，不用 attributed/HTML。
5. 關閉最後一個 Tab 後保持空畫面（仿 Arc：`activeTab == nil`，`CardView.showEmpty()`），不再補空白 Tab（否則空白 Tab 的 X 看起來關不掉）；啟動時仍會有一個空白 Tab。空畫面時從網址列輸入會開新 Tab。空白（無 http URL）的 Tab 不進 closedStack。
6. 預設瀏覽器註冊、外部連結走 Little，需要打包後的 .app 且 Info.plist 宣告 http/https（`scripts/bundle.sh` 已處理，Brian 已實際設為預設瀏覽器日常使用）。未打包的執行檔與 `--live-check` 不讀 Info.plist。
7. smoke 用 `NSApp.mainMenu.performKeyEquivalent` 走真實選單比對，等同按鍵路徑。
8. 沒有螢幕錄製權限時 `screencapture` 會失敗；改用 `--live-check` 存 PNG。

9. **NSWindow 要設 `isReleasedWhenClosed = false`**，否則 close() 後 ARC 重複釋放會 segfault。
10. **WebKit 對受限連接埠（如 1）回 WebKitErrorDomain 102**，與「載入被轉成下載」同碼；錯誤頁忽略 102，測連不上要用已關閉的真實埠。
11. **彈出視窗**：`createWebViewWith` 必須用 WebKit 給的 configuration 建新 Tab 並回傳其 webView，window.opener/postMessage 才會通；`webViewDidClose` 對應 window.close()。
12. 憑證錯誤不實作 server trust 挑戰，走預設處理 → 錯誤頁，刻意不提供略過。HTTP 驗證憑證用 `persistence: .none`。
13. 外部連結入口是 `application(_:open:)`；冷啟動時 controller 可能還沒建好，先放進 `pendingURLs`。本機 .html 只放行該檔案的導覽（`allowedFileURL`）；網址列與其他來源的 file: 一律拒絕。
14. 下載、歷史、session 路徑在 smoke 模式都導到暫存資料夾，不碰真實資料。
15. 說明頁（loadHTMLString）在上一頁/下一頁的歷史行為未驗證；重新整理在說明頁上會重試原網址（`reloadOrRetry`）。
16. **⌘W / Ctrl+W 由 `LarchWindow.performKeyEquivalent` 先交給選單**：焦點在 WKWebView 時，按鍵會先送進網頁、沒被 preventDefault 才非同步回頭比對選單，網頁可擋掉、smoke 也會變成非同步。Ctrl+W 是 File 選單裡獨立的「Close Tab (Ctrl+W)」項目。關閉最後一個 Tab 後保持空畫面（視窗不關）。

17. **⌘T 是命令列覆蓋層，不是直接新增空白 Tab**：`RootView.palette`（`CommandPaletteView`）蓋在整個視窗內容上，開啟時 `hitTest` 吞掉所有滑鼠事件，面板置中於網頁卡片。第一列固定「Open / Search: 輸入」→ 新 Tab；其次是已開啟的 Tab（切換、不開新 Tab）、歷史（新 Tab，已開啟的網址不重複）。標題與網址一律 `stringValue` 純文字。Esc 或點面板外關閉並把焦點還給原處；選取後焦點交給網頁。⌘L 也叫出同一個覆蓋層但走「目前 Tab 導航」模式（`showAddressPalette`、`paletteNavigatesCurrentTab`：預填目前網址並全選，開啟/搜尋與歷史在目前 Tab 載入，不開新 Tab；已開 Tab 與釘選仍是切換）；側邊欄網址列保留，可直接點擊輸入。**動作模式**：覆蓋層 `mode`（`PaletteMode.normal/.actions`）；`insertTab:` 進入、`insertBacktab:` 或空輸入的 `deleteBackward:` 離開（`CommandPaletteView.control`），chip 與提示文字隨模式變化，`PaletteSearch.actionResults` 只列 `isAvailable` 的動作（標題與關鍵字模糊比對，空查詢依表順序）。**新增動作 = 在 `PaletteActions.all` 加一項**（run 呼叫 controller 既有方法，不複製邏輯），快捷鍵提示是顯示用字串，要和選單一致。一般模式不列動作；Tab 排序 = 模糊分數 + 最近使用加成（`Tab.lastActiveAt`）。列最多顯示 8 列（`maxVisibleRows`），其餘用滾輪/↑↓ 捲動（選取列以「列高 × 索引」計算位置並在每次 layout 後捲進可視範圍，換一批結果會回到最上面；舊版用尚未版面的 row.frame 導致選取列跑出畫面）（刻意不顯示捲軸，避免「永遠顯示捲軸」讓內容變窄）。Open Web Inspector 用 WebKit 私有的 `_inspector.show`（`responds(to:)` 檢查，取不到就不列），`isInspectable = true`。Electron 版的 Cmd/Ctrl+Enter 是 Little Arc 的行為，不適用於 Palette。`PaletteMode` 預留 `.switcher`（Ctrl+Tab MRU 切換器之後重用）。外觀：`docs/palette-normal.png`、`docs/palette-actions.png`（smoke 在 `LARCH_SHOT_DIR` 時產生）。日後擴充其他來源：在 `PaletteItem.Action` 加 case、在 `PaletteSearch.results` 加來源。截圖/除錯：`Larch --open-palette 關鍵字` 啟動後直接叫出覆蓋層（直接執行會讀寫真實 session/history）；外觀截圖見 `docs/palette.png`。

18. **雙擊 bar 放大/還原**：標題列隱藏 + `isMovableByWindowBackground` 時系統不處理雙擊，由 `LarchWindow.sendEvent` 攔 `clickCount == 2`：hit-test 的整條祖先鏈都 `mouseDownCanMoveWindow == true`（外框、側邊欄空白）才算 bar，依 `AppleActionOnDoubleClick` 做 `performZoom`（預設 / Maximize）、`performMiniaturize`（Minimize）或不動（None）。網頁卡片、Tab 列、按鈕、網址列不處理；卡片底下仍不可有拖曳區域（第 1 點）。

19. **紅綠燈跟著側邊欄**：`RootView.onSidebarVisibilityChange` → `BrowserWindowController.syncTrafficLights` → `LarchWindow.setTrafficLights`（alpha 淡入淡出，結束後 `isHidden`）。側邊欄隱藏時，`RootView` 左上角 90x40 的 `NSTrackingArea`（`.activeAlways`，不攔截事件，網頁卡片點擊/捲動不受影響）進入時暫時顯示、離開再隱藏。全螢幕一律顯示（交給系統），進出全螢幕時重新同步。啟動時以 `syncTrafficLights(animated: false)` 對齊。截圖用 `--hide-sidebar` 旗標（注意直接執行會讀寫真實資料，見第 20 點），見 `docs/sidebar-*.png`。

20. **載入狀態**：`Tab` 以 KVO 觀察 `isLoading` 與 `estimatedProgress`（都走 `onChange`）；`BrowserWindowController.syncLoading` 只把目前 Tab 的狀態餵給 `CardView.loadingBar`（3px、貼卡片上緣被圓角裁切、`hitTest` 為 nil 不擋點擊捲動）與停止鈕，切換 Tab 時 `animated: false` 立即反映。結束（完成、失敗、停止）一律走 `isLoading == false`，進度條衝到 100% 後淡出。Tab 列載入中以 `NSProgressIndicator` spinner 取代 favicon（舊的底部掃動光條已移除）。已知：`load()` 後立刻 `stopLoading()`（毫秒內）WebKit 會丟掉 stop、isLoading 卡住；人手點擊不會遇到，smoke 的停止檢查要先等約 0.4 秒。**注意：macOS app 忽略 `HOME` 環境變數，`HOME=...` 不能隔離資料，直接執行 Larch 會讀寫真實的 `~/Library/Application Support/Larch/`**（`--hide-sidebar`、`--open-palette` 截圖時要留意）。載入中截圖見 `docs/loading.png`。

21. **釘選與資料夾**：`PinStore` 是樹（`PinNode`：folder / tab，最上層可混放），存 `pins.json`，節點只在載入時過濾 http(s)。`Tab.pinID` 綁定節點；`TabManager.liveTab(forPin:)` / `activatePin` / `pin` / `unpin` / `moveTab`。關掉釘選 Tab 時節點保留（灰色列，`TabRowView.tab == nil`），點擊用節點網址重開並綁定；`closedStack` 與 session 都帶 `pinID`，還原時節點不存在或已被綁定就當一般 Tab。側邊欄順序：釘選樹（`PinStore.visible()`）→ `DividerRowView` → 一般 Tab（`pinID == nil`）。節點的標題與 favicon（PNG）固定代表「釘選的那一頁」：`tabChanged` 時用 `PinStore.remember(..., at: url)` 同步（不觸發重建，讓灰色列外觀正確），但 Tab 已離開釘選頁（`PinStore.isAway`：host 忽略 www. + path 忽略結尾斜線，不比 query/fragment；網址未知或非 http(s) 不算離開）就不更新。離開時 `TabRowView.showsAwayStyle` 為真，列顯示「節點 favicon + `/ 目前標題`」。改動節點只有兩條明確路徑：`TabManager.replacePinnedURL(with:)`（Replace Pinned URL with Current，網址/標題/favicon 一起換）與 `backToPinnedURL`（把 Tab 導回節點網址）；入口是釘選列右鍵「Edit Pinned Page」子選單（離開時才啟用）與 Command Palette 動作。
22. **拖曳**：`SidebarView` 是整個清單的拖曳目的地（剪貼簿型別 `app.larch.sidebar-item`，字串 `tab:<uuid>` / `pin:<uuid>`）；它只做幾何（找到游標下的列與列內位置 0~1）與畫提示，語意交給 `BrowserWindowController.resolveDrop`（回傳 `DropPlan`：提示樣式 + commit）。規則：資料夾列上 25% 之前、下 25% 之後（收合或空資料夾才算「之後」）、中間放進去；釘選 Tab 列上/下半；分隔線 = 釘到最上層末尾 / 取消釘選；一般列重排；資料夾不能放進自己的子孫或一般區；灰色釘選拖到一般區會以該網址開成一般 Tab。smoke 以假的 `NSDraggingInfo` 走 `draggingUpdated` / `performDragOperation`，真實滑鼠拖曳（拖曳影像、自動捲動手感）沒有實測。截圖/排版參考 `docs/pins.png`（smoke 在 `LARCH_SHOT_DIR=<資料夾>` 時於暫存資料產生，不碰真實資料）。

23. **Little Arc**（外觀：白色色調，顏色集中在 `Theme.little*`——淺白外框與工具列、中央淺灰網域膠囊（只顯示網域，完整標題與網址在 toolTip）、右側「Add to Tabs ⌘O」按鈕、深灰圖示；主視窗維持鼠尾草綠，兩者一眼可分）：`Tab.decidePolicyFor` 在 `navigationType == .linkActivated` 且含 Option、不含 ⌘、http(s) 時 `.cancel` 並呼叫 `onOptionClick`（TabManager 接到 controller 的 `openLittle`）。Little 視窗的 Tab 由 `TabManager.makeTab()` 建立（共用 data store/下載/縮放，瀏覽寫歷史），**不在 `tabs` 清單裡**，所以關閉不進 closedStack、也不會被 session 存。`TabManager.adopt(tab)` 把它「搬進」主視窗：同一個 WKWebView、重接回呼、插在目前 Tab 之後並選中，頁面狀態不重載；`LittleWindowController.transferred` 為真時關視窗不 `teardown`。Little 內 `popupInPlace`（window.open / target=_blank 就地載入）。`LittleWindow` 是 `LarchWindow` 子類，Esc / ⌘W / Ctrl+W / ⌘O / ⌘Return / ⌘R / ⌘[ ⌘] 在視窗層級攔截（網頁焦點下也有效），並吞掉 ⌘T/⌘L/⌘S/⌘D/Ctrl+S 避免誤動主視窗。**選單動作依 key window 分派**（曾有 bug：選單 target 固定是主 controller，Little 為 key 時 ⌘W 關到主視窗的 Tab）：`BrowserWindowController.keyLittle` / `targetTab`，⌘W / Ctrl+W、⌘R、⌘[ ⌘]、縮放、複製網址（含 Markdown）在 Little 為 key 時作用在 Little 的頁面；`AppDelegate.validateMenuItem` 在 Little 為 key 時停用其餘會動主視窗的項目（New Tab、Open Location、Pin、Toggle Sidebar、Restore Closed Tab、New Folder、Duplicate、Find…），Little 沒有尋找列所以 ⌘F/⌘G 也停用。關閉 Little 後主視窗回到 key。外部連結開 Little 時 app 可能仍在啟用中、先前的 key window（主視窗）會被還原，所以 Little 開啟後會 `NSApp.activate` 並在下一輪 runloop 再確認一次自己是 key window。外部連結（`openExternal`）依 `Preferences.externalLinksInLittle`（預設 true）走 Little 或新 Tab；新 Tab 時若只有一個全新空白 Tab 就重用它（修掉冷啟動多一個空白 Tab）。同網址 300ms 內重複開 Little 會被忽略。退出前 `flushPersistence` 關閉所有 Little。截圖 `docs/little.png`（smoke 以 `LARCH_SHOT_LITTLE=1` 留住視窗，用 `screencapture -l` 分別擷取後合成；視窗擷取不含 WKWebView 內容，頁面內容是否出現取決於擷取時機）。

24. **Ctrl+Tab MRU 切換**：MRU 由 `TabManager` 在 `select` 與關閉後切換時遞增 `Tab.mruSeq`（`mruTabs` 依它排序；只含 `tabs` 清單裡的 Tab，所以灰色釘選與 Little 不在內）。事件入口是 **`LarchApplication.sendEvent`**（`main.swift` 用它當 NSApplication）→ key window 的 `LarchWindow.keyHandler`（主視窗設為 `TabSwitcher.handle`，Little 不設）：**Ctrl+Tab 是系統 key-view loop 鍵，不會走到 `NSWindow.sendEvent`，必須在 NSApplication 層處理**；keyDown Tab+Control 開始/往下、加 Shift 往上，flagsChanged 且 Control 放開 → 確認，Esc → 取消。這裡只「消耗 keyDown」，flagsChanged 與 keyUp 照常送達，所以沒有 Electron 版那個「吞掉 Ctrl+Tab 就收不到 Ctrl 放開」的坑，焦點在 WKWebView、欄位或覆蓋層都收得到。快速按（150ms 內放開）不顯示 UI 直接切；超過 `showDelay` 才用 `CommandPaletteView.presentSwitcher`（`PaletteMode.switcher`：只有清單、不搶焦點、不經過 onDismiss）；閒置 `idleTimeout`（10 秒）自動確認；視窗失去 key（Ctrl 可能在 app 外放開）視同確認。命令列（⌘T/⌘L）開著時 Ctrl+Tab 忽略（它的 Tab 鍵是動作模式）。切換清單的標題在顯示當下取得。截圖 `docs/switcher.png`。**smoke 注意**：依賴 key window 的檢查（Little、切換器、History 的 ⌘Y，甚至側邊欄拖曳縮放）需要 Larch 一直在前景，跑 smoke 時不要操作其他視窗，否則會因 app 失去啟用而偶發失敗（`ensureActive` 只在區段開頭確認一次）。**最常見的元兇是 `scripts/install.sh` 裝好、用 `open -a` 開著的真實 `/Applications/Larch.app`**：它跟 smoke 自己跑的那份執行檔搶 key window/active app，跑 smoke 前先 `pgrep -fl Larch` 確認沒有這個真實實例在跑，有的話 `osascript -e 'tell application "Larch" to quit'` 關掉再跑。

25. **側邊欄拖曳縮放**：`RootView`（`SidebarView.swift`）把寬度從常數 `Theme.sidebarWidth` 改成可變的 `sidebarWidth` 屬性，`layout()` 用它取代原本處處引用的常數（常數保留當預設值與 smoke 的基準值）。交界處疊一個窄 6px 的 `SidebarResizeHandle`（`resizeHandle.frame = NSRect(x: sw-3, width: 6, ...)`），`mouseDownCanMoveWindow` 回 `false`（否則會跟第 1 點「卡片底下不可拖曳」與視窗拖曳打架）、覆寫空的 `mouseDown` 明確接手這次拖曳（NSView 預設往上傳，拖曳中途可能被吞）、`resetCursorRects` 給 resize 游標。拖曳範圍夾在 `Theme.sidebarWidthRange`（200...420，刻意放 `Theme.swift` 而非 `RootView`，因為 `Preferences.sidebarWidth` 的 getter 也要用、`RootView` 是 `@MainActor` 類別型別但 `Preferences` 不是，放常數型別裡兩邊都能用，不會有 actor isolation 警告）；放開滑鼠才透過 `onSidebarWidthChange` 存進 `Preferences.sidebarWidth`（UserDefaults），下次啟動 `BrowserWindowController.init` 讀回來餵給 `root.sidebarWidth`。smoke 用合成的 `NSEvent.mouseEvent` + `window.sendEvent` 走真實 hit-test 路徑（跟雙擊 bar 的測法一樣），測完要把寬度與 Preferences 都還原成預設值，否則後面假設預設寬度的檢查（卡片四周 8px 那段）會跟著壞掉。

26. **History 視窗**（`HistoryWindow.swift`，外觀仿 Arc 的 history 頁）：跟 Command Palette 不同，這是一般標題列 NSWindow（不是覆蓋層），因為要瀏覽/刪除整份歷史而不只是挑一筆。`HistoryWindowController` 持有 `HistoryStore`，每次 `show()` 才重新讀取（不即時跟著歷史變化），依搜尋欄內容用 `store.search` 或取最近 `displayLimit`（300）筆，依日期分組成 `HistoryDayCardView`（日期標頭文字 + 白色圓角卡片，卡片內是當天的 `HistoryRowView` 用 `NSStackView` 疊起來、列間一條 1px 分隔線；頁面底色 `Theme.historyBackground` 淺灰，卡片白底仿 Arc 的「卡片浮在淺灰頁面上」）。一列：核取方塊、時間、favicon（`HistoryEntry.favicon` PNG Data；`BrowserWindowController.tabChanged` 比照 `PinStore.remember` 的做法，把 `tab.favicon` 轉 PNG 後用 `HistoryStore.updateFavicon(url:favicon:)` 補到該網址最近一筆——record() 當下通常還沒抓到，不是記錄時另外發網路請求；`record()` 同網址覆寫最後一筆時要保留原本的 favicon，否則重新整理會把它洗掉）、沒有 favicon 就退回網域字首字母的圓形色塊、標題/網域、右側「⋯」選單（Open in New Tab / Delete，取代原本 hover 才出現的 x）。**多選**（仿 Arc）：核取方塊只負責選取（`onToggleSelect`，不觸發開啟；點列本身仍是開啟），`HistoryWindowController.selected`（`Set<EntryID>`，以 `url+visitedAt` 當 key）在 `reload()` 時跟現有清單取交集避免殘留；有勾選時搜尋欄會換成選取工具列（`HistoryView.setSelectionCount`：✕ 取消全部、「N selected」、Open、Delete），Open/Delete 完成後清空選取並換回搜尋欄。`HistoryStore.delete(_:)` 以 `url + visitedAt` 比對刪單筆；`clear(after:)` 清全部（nil）或清「造訪時間晚於等於 cutoff」的那些，供底部「Clear History…」的 Last Hour / Today / All Time 用（跟多選的 Delete 不同，這個有二次確認）。**清除前的確認彈 `NSAlert`**（標題 + `NSPopUpButton` 選範圍）包成 `BrowserWindowController.clearHistoryPrompt`（跟 `Tab.authPrompt` 同一招的可替換 static closure），smoke 才能不跳出真的模態視窗。選單新增「History」（`AppDelegate.buildMenu`：Show All History ⌘Y、Clear History…）；Command Palette 動作表加 `history` / `clearHistory`。**smoke 要注意**：`showHistory()` 會 `makeKeyAndOrderFront` 搶走 key window，測完要關視窗並把主視窗叫回 key，否則會像 Little/切換器一樣因為 key window 跑掉而間接讓後面的檢查不穩；另外點歷史開新 Tab 的測試要先避開「唯一的全新空白 Tab 會被重用」規則（第 23 點），先多開一個 Tab 再測。**⌘W 誤關 Tab 的坑重現過一次**：「Close Tab」選單項 target 固定是 `AppDelegate`（見 `buildMenu`），不管哪個視窗是 key 都會直接呼叫 `controller.closeCurrentTab()`，這跟第 23 點 Little 曾踩過的坑是同一類。`closeCurrentTab()` 已依序檢查 History 視窗、Little 是否為 key window，是則關閉該視窗本身而非動 Tab；**已收斂（2026-10-31）**：獨立視窗實作 `AuxiliaryWindow`（`AuxiliaryWindow.swift`）並加進 `BrowserWindowController.auxiliaryWindows`，`keyAuxiliary` 就會涵蓋它；`closeCurrentTab()` 與 `AppDelegate.validateMenuItem`（輔助視窗為 key 時停用會動主視窗的項目，只有 `handlesPageActions` 的 Little 另允許頁面動作）都改走這一處，不必再逐一補判斷。**坑**：`AppDelegate` 必須明確宣告 `NSMenuItemValidation`，否則 `validateMenuItem` 不會暴露給 Objective-C、AppKit 永遠不呼叫（曾因此 History / Task Manager 為 key 時 ⌘T 仍會叫出命令列；Little 看起來正常只是因為 `LittleWindow` 自己吞了按鍵）。smoke 要用真實按鍵（`press`）驗證，不能只直接呼叫 `validateMenuItem`。

27. **Split View**（仿 Arc 的分割畫面）：拖一個一般 Tab 到另一個一般 Tab 列的中間（25%~75%，`BrowserWindowController.resolveDrop` 的 `.tab(let id)?` case，邊緣仍是原本的重排）→ `TabManager.split(_:with:)`。資料模型是 `Tab.splitPartner`（`weak var`，互指，只在未釘選的一般 Tab 之間成立）；`close(_:)` 與 `pin(_:)` 會先 `breakSplit` 解除配對（關掉或釘選其中一半，另一半自動回到單一畫面）。**卡片**：`CardView.showSplit(left:right:onUnsplit:)` 固定 50/50、中間 1px `SplitDividerView`（延續第 1 點：卡片底下不可拖曳視窗）、右上角退出按鈕；`layout()` 覆寫 `relayout()` 在卡片縮放時維持比例（沒有用 autoresizingMask，因為無法讓兩塊精確維持 50/50）。左右順序固定依 `tabs.tabs` 清單順序（不是誰是 activeTab），切到配對中的另一半畫面不會跳動；切到第三個 Tab 回到單一畫面，但配對本身還在，切回去又恢復。**側邊欄**：配對的兩個 Tab 顯示成同一列、左右並排兩顆膠囊（`SplitPairRowView`，內部一個水平 `NSStackView` 裝兩個既有的 `TabRowView`，`.fillEqually`），而不是疊成兩個全寬列——這是看過 Arc 實際畫面後補上的，原本以為卡片分割兩塊就夠了。`rows[tab.id]` 字典仍是每個 Tab 各自一個 `TabRowView`（menu/rename/close 邏輯不變），只有 `rebuildRows()` 組 `ordered` 陣列時把配對的兩個包進 `SplitPairRowView` 再塞進去。`SidebarView.rowViews` / `sidebarRows` 因此要攤平（遇到 `SplitPairRowView` 展開成 `[left, right]`），且**拖曳落點判定原本只比對 y 區間**（假設一欄一列），兩個並排的配對列現在共用同一個 y 區間，改成 y 與 x 都要落在該列的 frame 內才算 over，否則永遠只會命中先遍歷到的那個。`TabRowView` 新增 `splitBadge`（右下角小圖示，`tab?.splitPartner != nil` 時顯示）。`split()` / `unsplit()` 除了 `onActiveChange?()` 也要呼叫 `onStructureChange?()`（側邊欄要重新分組成並排/拆開，只改 `isActive` 不夠）；`rebuildRows()` 對配對兩邊各自算 `isActive`（而不是只有被拖的那個），比原本「只有 `activeChanged()` 知道 partner」更穩，不依賴呼叫順序。**退出分割**：卡片按鈕、Command Palette 動作 `unsplit`（Exit Split View）都呼叫 `BrowserWindowController.exitSplitView()` → `tabs.unsplit(tab)`；**把配對中的 Tab 拖去重排**（不是拖到中間要求配對）也視同拖出 Split View：`TabManager.moveTab` 先 `breakSplit`，若被拖的或它原本的另一半正是 `activeTab` 就額外呼叫 `onActiveChange?()` 讓卡片跟著回到單一畫面（`onStructureChange?()` 只會重排側邊欄，不會動卡片）。已知缺口：固定 50/50 不可拖曳調整、視窗重開不記得配對（session 不存）、側邊欄拖曳排序時的插入線沒有考慮半寬（仍畫滿版寬）。**曾踩過的坑**：`breakSplit` 一開始只通知 partner（`partner.onChange?(partner)`），沒通知被解除配對的 tab 自己；`split()`/`unsplit()` 當下沒事是因為各自在外面又補呼叫了一次該 tab 的 `onChange`，但 `moveTab`（拖去重排視同拖出）只呼叫 `breakSplit(tab)` 就結束，導致被拖出的 tab 自己那列的 `splitBadge` 沒有重新 `update()`、卡在顯示的狀態。修法是讓 `breakSplit` 一律通知兩邊（`tab.onChange?(tab)` 也放進去），`split()`/`unsplit()` 外面的重複呼叫跟著拿掉。**這類「配對/連動狀態」的教訓**：任何會動到 `splitPartner` 的地方，兩邊都要各自觸發一次 `onChange`，不能假設呼叫端會記得幫忙補。

28. **Task Manager**（`TaskManagerWindow.swift`，仿 Arc）：架構仿 History 視窗（一般標題列 NSWindow，不是覆蓋層），但資料即時變化，不是一次性讀取——`TaskManagerWindowController.show()` 立刻 `reload()` 一次並啟動 1 秒 `Timer`，`windowWillClose`（`NSWindowDelegate`）停止並清空 timer，避免視窗關閉後背景還在空轉。**v1 範圍只列主視窗的一般 Tab**（`tabs.tabs`），不含 Little 視窗的 Tab（Little 的 Tab 不在這個清單裡，架構上要另外接線，之後有需要再補）。**取得 process 資訊靠兩個私有介面**：`WKWebView` 的 `_webProcessIdentifier`（私有 KVC，`responds(to:)` 防呆，取不到該列記憶體顯示「—」，不影響其他列）取得 WebContent process 的 PID；`proc_pidinfo(PROC_PIDTASKINFO)`（系統 libproc）查常駐記憶體（RSS）。這跟 UA 補字尾（第 2 點）、Open Web Inspector 用 `_inspector`（第 17 點）是同一類「用私有介面補齊功能，版本變動就重新驗證」的風險，不是新的做法。**一分頁一個 process 的假設**：2026-10-29 PoC 驗證過，就算兩個分頁開同一個網域也拿到不同 PID，所以 UI 不用處理「多分頁共用一個 process」的合併顯示（跟 Chrome/Arc 可能共用 renderer process 的行為不同，WKWebView 預設設定下看起來是分開的，但這只驗證過少量分頁、同一次執行，不保證所有情境都這樣）。依記憶體從高到低排序，`reload()` 整批重建列（跟 History 一樣，Tab 數量不多，效能沒問題）。**「End Process」按鈕＝關閉分頁**（呼叫既有的 `tabs.close(tab)`），**不是真的 kill -9**：WebContent process 被 kill 後 WKWebView 的後續行為沒驗證過（可能顯示當機頁、可能需要手動 reload），關閉分頁一樣能釋放資源、行為可預期，風險低。點列本身切換到該分頁。選單加在「Window」（`AppDelegate.buildMenu`，無預設快捷鍵）；Command Palette 動作表加 `taskManager`。**`closeCurrentTab()` 補上 key window 判斷**（跟第 26 點 History/Little 一樣的教訓）：Task Manager 視窗為 key window 時 ⌘W 關視窗本身，不動主視窗 Tab。

## 驗證狀況
- smoke 全數通過（最後一次記錄為 475 項，macOS 26 / Swift 6.2.4；項數會隨新增 check 變動，以實際輸出為準）；accounts.google.com 登入頁載入成功（含 favicon）。
- 冷啟動與已執行時 `open -a` 開外部連結已用打包的 .app 實測（session.json 有新 Tab）。
- Google 實際帳密登入與重開後保持登入：已實測，正常。
- Split View：卡片左右分割、側邊欄配對列並排顯示，已在真實視窗用滑鼠拖曳實測。
- Brian 已日常使用 Larch（2026-10-30 確認），以下皆已在真實使用中驗證、手感正常：實際設為預設瀏覽器、外部連結走 Little 的實際流程、Option+點連結與 Little 視窗操作（拖曳/雙擊/縮放）、視窗操作（拖曳視窗、雙擊 bar 放大還原、側邊欄收合時紅綠燈淡入淡出、進出全螢幕）、HTTP 驗證對話框、History 視窗真實捲動/hover 刪除、Task Manager 1 秒刷新手感。
- 尚未驗證、Brian 評估不急：下載、真實鍵盤 ⌘= 放大、全螢幕影片（2026-10-30 決定暫不優先驗證）。

## Backlog
見 `BACKLOG.md`；開工前先讀，完成後移到「已完成」。
