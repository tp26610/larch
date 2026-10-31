# Backlog

## 接下來（依序）
1. Spaces（仿 Arc；尚未開工，以下是預訂的設計起點；**總估點 25**（七塊子項加總，子項各自仍遵守 1/2/3/5/8/13/21/40/? 量表，合計是例外），拆成以下七塊，個別領取）
   - 資料模型：Space = 名稱、顏色（取代固定的鼠尾草綠，由該色推導 hover / active / 進度條等配色，確保白字對比）、可選 emoji、自己的釘選區（含巢狀資料夾）與自己的一般 Tab。估點 **3**：主要是新 struct 與 `PinStore`/`TabManager` 從全域單一清單改成「依 Space 分」的資料結構，牽動面廣但單項不難。
   - 登入：所有 Space 先共用同一個 `WKWebsiteDataStore`；資料結構預留「Space 指定獨立 data store 識別碼」的欄位（只留欄位與註解，不實作）。估點 **1**：只加欄位與註解。
   - 切換：側邊欄底部一列 Space 切換列（圓點或 emoji，目前高亮，右側「+」）；Ctrl+1…9 切換（不佔用 ⌘1…⌘9）；側邊欄兩指橫滑（若穩定再做）；切換不重新載入頁面（各 Space 的 WKWebView 保留，只顯示/隱藏），過場動畫 ≤ 200ms。估點 **5**：新 UI 元件 + 多個 WKWebView 同時存活的顯示/隱藏管理，是前面沒有先例的模式。
   - 管理：右鍵重新命名、改色、改圖示、刪除（確認；其中的 Tab 一併關閉、釘選資料刪除；最後一個 Space 不能刪）；Tab / 釘選右鍵「移到 Space」或拖到切換列。估點 **5**：刪除與搬移涉及跨 Space 的資料搬動與既有拖曳（`SidebarRows.swift`）、右鍵選單邏輯擴充。
   - Command Palette：新增 New / Rename / Switch to / Move Tab to Space 動作；一般模式的 Tab 與釘選搜尋跨所有 Space（結果標示所屬 Space），選到其他 Space 的項目先切過去。估點 **5**：`PaletteActions`/`PaletteModel`/`PaletteSearch` 都要擴充跨 Space 概念，且要先切 Space 再定位項目。
   - 還原：關閉 Tab 堆疊（⌘⇧T）維持全域，還原回原本的 Space；session restore 記住最後所在的 Space 與各 Space 的 Tab / 選中項；外部連結開在目前的 Space。估點 **3**：`SessionStore`/`TabManager.closedStack` 加 Space 關聯欄位與還原邏輯。
   - 遷移：既有 `pins.json` / `session.json` 無損遷移到預設 Space「Personal」（色 #699987），需壞檔容錯與 smoke 檢查。估點 **3**：一次性遷移程式 + 壞檔容錯 + smoke 覆蓋，模式仿既有 `Storage.swift` 的容錯讀寫。
2. 從 Arc 匯入：把 Arc 的 Spaces、置頂 Tab 與資料夾（含巢狀）、名稱匯入 Larch；不匯入登入狀態（Brian 確認不需要）。待調查：Arc 本機資料位置與格式（推測在 `~/Library/Application Support/Arc/` 底下的 sidebar JSON，需實際確認）；先做唯讀解析並預覽再匯入，不修改 Arc 的資料；依賴 Spaces 的資料結構，在 Spaces 之後做。估點 **8**：格式未知需先花時間逆向 Arc 的 sidebar JSON（不確定性最大的部分），加上唯讀解析器、預覽 UI、對應到 Spaces 資料模型的匯入邏輯；依賴項目 1（Spaces）完成。

## 想法（低優先，沒有必做理由）
- 書籤：Arc 本身也沒有傳統書籤，釘選 Tab 與巢狀資料夾已取代；之後有具體需求再提升。
- Cmd+T 命令列優化（對照 Arc 截圖整理，2026-10-29；依標題比對 Tab/Pin/History 已經在 `PaletteSearch.results`／`Fuzzy.score` 實作且經 Brian 實測確認 OK，以下是另外三個還沒做的方向，之後要做再從這裡挑）：
  1. **Google 打字建議（ghost 候選）**：Arc 在搜尋列最上面會即時列出幾筆 Google 建議（如輸入「固定支出」會跑出「固定支出保障倍數」「固定支出表格」「固定支出 とは」），這是呼叫搜尋引擎的 suggest API（如 `https://www.google.com/complete/search?client=firefox&q=...`），Larch 目前只有一行固定的「Search: 輸入文字」。做法：`PaletteSearch` 或 `CommandPaletteView` 加非同步請求（debounce，避免每個按鍵都打網路），回來後插在 `openOrSearch` 之後、Tab/History 之前；要處理請求順序錯亂（晚送出的查詢先回來）與離線/失敗時不顯示。估點 **5**：第一個牽涉網路請求與非同步競態的 Palette 功能，debounce/race/失敗處理都要新寫，且要留意外部 API 相依與隱私（查詢字串送到 Google）。
  2. **預設選取邏輯**：Arc 在有強匹配的既有項目（如標題完全等於輸入）時，預設高亮選的是那筆資料而不是「Search with Google」；Larch 目前 `results()` 永遠把 `openOrSearch` 放第一筆，`CommandPaletteView` 預設選取第一列。要討論怎麼定義「夠強的匹配」（如標題完全相等、或 `Fuzzy.score` 超過某門檻）才改變預設選取，避免打幾個字就跳走、選錯。估點 **3**：邏輯集中在 `PaletteSearch.results`/`Fuzzy.score`，改動範圍小，但門檻定義需要來回調整手感。
  3. **空白輸入時的豐富建議列表**：Arc 空白時混合顯示釘選/最近常用（含內容摘要文字、Switch to Tab／Archived 等標籤），Larch 目前空白時只列「目前開啟中的 Tab」（`results()` 的 `!q.isEmpty` 才查歷史）。要做的話是空白時也納入釘選與最近歷史（依最近造訪/次數排序），但「內容摘要」這塊 Arc 應該是另外存了頁面文字索引，Larch 目前沒有、工程量較大，可以先不做，只做清單來源擴充。估點 **3**：排除內容摘要後，只是擴充 `results()` 空查詢時的來源（釘選 + 歷史）與排序，沿用既有 `PaletteModel` 結構。

- Little Window 不搶走前景 App 焦點（2026-10-30 討論，仿 Arc）：
  1. **視窗化 App 在前景時**（如點 Slack 連結開 Little，畫面停留在 Slack）：`LittleWindow` 改成 `NSPanel` + `.nonactivatingPanel`，用 `orderFrontRegardless()` 顯示、不呼叫 `NSApp.activate`，改記住呼叫當下的 frontmost app 並在顯示後 reactivate 回去。估點 **5**：現有 Little 整套 key window 攔截（Esc/⌘W/⌘O/⌘Return 等，見 CLAUDE.md 第 23 點）要在「key window 但 app 非 active」狀態下重新驗證，WKWebView 的點擊/輸入手感也要重新確認。
  2. **全螢幕 App 在前景時**（如全螢幕遊戲，畫面停留在遊戲，Little 浮在上面；仿 Arc/1Password autofill 蓋在全螢幕遊戲上的效果）：在 1 的基礎上疊加 `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` 讓視窗跨 Space 顯示。估點 **8**：依賴 1 先完成；跨 Space 疊加在不同 macOS 版本行為有落差（已知有渲染/點擊穿透的小毛病），需要額外在全螢幕情境下重新驗證整套互動。

- 主題色可自選（2026-10-30）：目前側邊欄與視窗外框固定鼠尾草綠（`Theme.swift`），改成使用者可從幾組預設主題色中挑選，預設色參考 Arc 的主題色（實際色票需對照 Arc 截圖整理）。做法：`Theme` 的顏色改由「主色」推導 hover / active / 進度條 / 選取底色等，確保白字對比（可與 Spaces 資料模型的「顏色」共用同一套推導函式）；選色入口可放選單或 Command Palette 動作（如 Change Theme Color…），選擇存 `Preferences`（UserDefaults），切換時即時重繪。與項目 1 Spaces 的重疊：Spaces 做完後每個 Space 自帶顏色，這項就退化成「全域預設色 / Space 配色預設色票」，所以若 Spaces 近期要做，建議併入 Spaces 的「資料模型」子項而不單獨做。估點 **3**：主要是 `Theme` 顏色改成可變並由單一主色推導、預設色票與選色 UI，既有視圖要確認都吃 `Theme` 而非寫死色碼。

## 技術債（2026-10-31 盤點；依「成本低、防呆價值高」優先排序；Spaces 優先權低，所以拆 controller 降為碰到再做）
1. 「key window 分派」收斂：`closeCurrentTab()` 目前逐一檢查 History / Task Manager / Little 是否為 key window（CLAUDE.md 第 23、26、28 點同類 bug 出現三次），每加一個獨立視窗就要手動補。改成「目前 key 視窗負責處理」的協定或 responder chain，並檢查其他固定 target 的選單動作。估點 **3**。
2. 純邏輯單元測試：`Fuzzy`、`InputNormalizer`、`PinStore` 的樹操作（移動/刪除/防循環）改用 XCTest/Swift Testing，跑得快且不用開視窗；executableTarget 可用 `@testable import`。估點 **3**。
3. 拆 `BrowserWindowController.swift`（853 行、88 個函式）：Little、輔助視窗（History / Task Manager）、拖曳落點 `resolveDrop` 拆成 extension 或獨立 coordinator，日後要大改（如 Spaces，目前優先權低、可能不做）時才不會全擠在這一個類別。估點 **5**：純搬移不改行為，但牽動面廣，每步都要靠 smoke 確認沒壞。 **不急**：沒有近期功能卡在它，改到該區域時再順手拆。
4. `Smoke.swift`（2162 行，約佔原始碼 29%）編進正式執行檔，出貨的 app 帶著假網站伺服器。至少分檔，長期考慮拆成獨立 target。估點 **5**：要處理 smoke 與主程式之間的 internal 存取與 `--smoke` 進入點。
5. CI：目前沒有 `.github`。先加只跑 `swift build` 的 workflow（smoke 要開真實視窗，不能在 headless 環境跑，不納入）。估點 **2**。 **目前價值低，暫不做**（單人開發、本機已跑 build 與 smoke，CI 只跑 build 保護力有限）；有外部貢獻者發 PR 或要自動發版時再做，屆時 build 檢查可併入發版流程。

## 已知缺口（未排序）
- 邊用邊記的問題放這裡
- 資料夾圖示/顏色（2026-10-30 定案範圍，Brian 對 Arc 細節沒有強烈想法，以最小可用為原則，日後看 Arc 實際畫面再調）：① **顏色**只有一個主色，從一組預設色票挑選（可與主題色的色票共用），只用來給資料夾圖示上色，不改列背景、不改文字色；沒設定就維持現在的預設外觀。② **圖示**以 emoji 為主（系統 emoji 選擇器或一小組常用 emoji），不做 SF Symbol 挑選器；有 emoji 時顏色不生效（emoji 本身帶色），所以顏色只作用在預設資料夾圖示。③ 資料：`PinNode`（folder）加可選的 `icon`（emoji 字串）與 `color`（色票識別字串）兩個欄位，存 `pins.json`，舊檔缺欄位用預設，載入時對壞值容錯。④ 入口：資料夾右鍵選單加「Change Icon…」「Change Color…」；Command Palette 動作暫不做。⑤ 展開/收合時圖示維持不變（不做展開版圖示）。不做的：自訂色碼挑選器、SF Symbol 挑選器、列背景染色。估點 **3**：`PinNode`/`PinStore` 加欄位與容錯載入，側邊欄資料夾列（`SidebarRows.swift`）依欄位繪製，右鍵選單加兩項與一個簡單的選色/選 emoji 面板，需補 smoke。
- 拖曳到資料夾上懸停自動展開。估點 **3**：`SidebarView` 拖曳目的地已有幾何判定（第 22 點），加「停留 N 毫秒後展開資料夾」的計時器與狀態，要避免跟既有插入線提示互相干擾。
- 多選（Tab / 釘選的側邊欄多選批次操作，如多選後批次關閉/刪除/移動）。估點 **5**：History 視窗已有多選模式可參考（核取方塊 + 選取工具列），但側邊欄要再處理拖曳與多選共存、以及 Tab 與釘選混合選取時動作的可用性判斷。
- 下載：可取消、下載清單；目前只顯示最新一筆。估點 **5**：`DownloadManager.swift` 目前應該只追蹤單筆狀態，要改成清單（含歷史）、新增取消（`WKDownload.cancel`）、加一個顯示清單的 UI（可能類似 History 視窗的簡化版）。
- 說明頁上的上一頁/下一頁行為未驗證。估點 **1**：這是驗證 / 補 smoke check 的工作，不是新功能；真的發現壞掉才會另外估修復的點數。
- http 網站的安全處理（2026-10-31，起因：信件追蹤連結 `http://` 在 Larch 報 `NSURLErrorDomain -1022`，已在 `scripts/bundle.sh` 的 Info.plist 加 `NSAllowsArbitraryLoadsInWebContent` 放行 http，Brian 已實測該連結可開（2026-10-31））：放行後補兩項保守措施。① **優先用 https**（估點 **3**）：網址列輸入或外部連結為 http 時先試 https，失敗（連線錯誤、逾時）才退回原本的 http，仿 Safari / Chrome 的 HTTPS-first；要決定逾時門檻、`localhost` 與 IP 位址不升級、退回時不要重複寫歷史，需補 smoke。② **http 頁面「不安全」標示**（估點 **2**）：目前頁為 http（非 localhost）時，網址列顯示警示圖示與 toolTip；只改顯示，不擋載入。注意 `--live-check` 與未打包的執行檔不讀 Info.plist，重現不出 ATS 錯誤，驗證要用打包後的 .app。
- 正式簽章與公證（Developer ID）；目前 ad-hoc。估點 **3**：主要是流程（申請 Developer ID、entitlements、`scripts/bundle.sh` 加簽章與 notarize 步驟），程式碼改動不多，但依賴 Apple Developer 帳號與 notarization 審核時間，等待時間不算入點數。
## 已完成
- 單一視窗、側邊欄（⌘S）、圓角卡片與邊框拖曳
- Tab 新增/關閉/切換/還原（25 筆）/雙擊改名/載入光條/favicon
- 網址列、上一頁/下一頁/重新整理、複製網址
- 持久登入（default data store）、權限預設全拒
- smoke 測試（58 項）、打包腳本、--live-check
- Session restore、預設瀏覽器註冊與外部連結、下載、載入失敗頁、尋找與縮放、HTTP 驗證、彈出視窗開新 Tab、歷史紀錄（無 UI）
- ⌘T 命令列覆蓋層：開新 Tab / 搜尋、比對已開 Tab 與歷史（模糊比對）、上下鍵與 Esc、New Tab 按鈕共用
- 雙擊視窗 bar 放大/還原（依系統設定）、Ctrl+W 關閉 Tab
- 紅綠燈跟著側邊欄收合，隱藏時滑鼠移到左上角暫時顯示
- 載入狀態：卡片頂端進度條、Tab 列 spinner、重新整理變停止
- Pinned tabs 與巢狀資料夾（⌘D、⌘⇧N、右鍵選單、拖曳、灰色已關閉釘選、重開後還原）；一般 Tab 拖曳排序
- Command Palette 完成：⌘T / ⌘L、動作模式（Tab 鍵進入）與 17 個動作、類型標籤與快捷鍵、近用排序

- Little Arc：Option+點連結、外部連結（預設瀏覽器）預設走 Little（File 選單可關）、加到 Tabs 搬移同一個 WKWebView、多視窗、Esc/⌘W/⌘O/⌘Return、命令列動作 Open in Little Window；順手修掉冷啟動多一個空白 Tab
- Ctrl+Tab 最近使用（MRU）切換：快速按、按住顯示清單、連按/反向、放開確認、Esc、閒置自動確認；命令列動作 Switch to Previous Tab
- Favicon 抓不到時（頁面沒有 `<link rel="icon">`，網域自己的 `/favicon.ico` 也 404，常見於 Google OAuth 登入/同意過場頁如 accounts.google.com）失敗再往上一層網域（eTLD+1 簡化版，排除 IPv4/localhost）試一次 `/favicon.ico`
- History 視窗（獨立視窗，`HistoryWindow.swift`，外觀仿 Arc）：搜尋欄 + 依日期分組（Today / Yesterday / 日期）的白色卡片清單、每列顯示真的 favicon（`HistoryStore.updateFavicon`，抓不到才退回字首字母色塊）、核取方塊多選（勾選後搜尋欄變選取工具列：Open / Delete / ✕ 取消）、每列「⋯」選單（Open in New Tab / Delete）、底部「Clear History…」依範圍（Last Hour / Today / All Time）清除（`HistoryStore.delete` / `clear(after:)`）；選單新增「History」（⌘Y 開啟、Clear History…）、Command Palette 動作 Show All History / Clear History…
- Split View：拖一個一般 Tab 到另一個一般 Tab 中間並排顯示（固定 50/50，右上角退出按鈕，Command Palette 動作 Exit Split View）；側邊欄把配對的兩個 Tab 顯示成同一列、左右並排兩顆膠囊（不是疊成兩列）；關閉、釘選或拖去重排其中一半都會自動解除配對。已知限制：不可拖曳調整比例、視窗重開不記得配對、側邊欄拖曳排序的插入線沒考慮半寬。
- ⌘+點連結：比照 Option+點連結的攔截方式，在 `Tab.decidePolicyFor` 新增 `onCommandClick`，於 `TabManager.attach` 接到 `newTab(activate: false, after: 來源 Tab)`，插在來源之後、背景開新 Tab 不切換焦點；⌥⌘+點、非 http(s)、非點連結事件不受影響。
- Task Manager（獨立視窗，`TaskManagerWindow.swift`，仿 Arc）：列出主視窗的一般 Tab（v1 不含 Little），依記憶體從高到低排序（`_webProcessIdentifier` 取 PID、`proc_pidinfo` 查 RSS，都是私有/系統介面，拿不到時該列顯示「—」），視窗開著時每 1 秒刷新；每列「End Process」＝關閉分頁（不是真的 kill -9），點列本身切換到該分頁；選單加在 Window、Command Palette 動作 Show Task Manager；`closeCurrentTab()` 補上這個視窗的 key window 判斷（⌘W 關視窗本身不動 Tab）。
- Repo 轉 public 前準備（2026-10-30）：加 MIT LICENSE；`ardia-team-report.md` 精簡成不含維護者個人背景的摘要；CLAUDE.md / `docs/decisions.md` 標註 `../my-browser` 為私有專案。注意：舊版報告仍留在 git 歷史，若要徹底清除需 `git filter-repo` 改寫歷史（本次選擇不做）。
- 技術債：CLAUDE.md 文件不一致修正（2026-10-31）：指令區與驗證區的 smoke 項數不再寫死（驗證區註明最後一次記錄的 455 項），第 6 點「預設瀏覽器註冊尚未做」改為已處理。
- 技術債：私有介面預警（2026-10-31）：`Smoke.swift` 新增 `privateAPIChecks` 4 項，確認 `_webProcessIdentifier` 取得有效 PID、`proc_pidinfo` 查得到記憶體、`_inspector` 回應 `show`、UA 含 `Version/X Safari/Y`；macOS 大版本更新後跑 smoke 即可看出哪個介面失效。
- 釘選的網址操作（2026-10-31）：釘選節點的標題/favicon 固定代表釘選那一頁（`PinStore.remember` 只在 Tab 沒離開釘選頁時更新）；離開（`PinStore.isAway`：比 host 忽略 www. + path 忽略結尾斜線，不比 query/fragment）時列顯示「釘選頁 favicon + / + 目前標題」；釘選列右鍵「Edit Pinned Page」子選單（Replace Pinned URL with Current / Back to Pinned URL，僅離開時可用）與同名 Command Palette 動作。未做：手動 Edit… 對話框。已知取捨：釘選頁一載入就被網站導向到不同 host/path（如 example.com → www.example.com/home 以外的路徑）會一直算「離開」，用 Replace 修正。
