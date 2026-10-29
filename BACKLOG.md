# Backlog

## 接下來（依序）
1. Spaces（仿 Arc；尚未開工，以下是預訂的設計起點）
   - 資料模型：Space = 名稱、顏色（取代固定的鼠尾草綠，由該色推導 hover / active / 進度條等配色，確保白字對比）、可選 emoji、自己的釘選區（含巢狀資料夾）與自己的一般 Tab。
   - 登入：所有 Space 先共用同一個 `WKWebsiteDataStore`；資料結構預留「Space 指定獨立 data store 識別碼」的欄位（只留欄位與註解，不實作）。
   - 切換：側邊欄底部一列 Space 切換列（圓點或 emoji，目前高亮，右側「+」）；Ctrl+1…9 切換（不佔用 ⌘1…⌘9）；側邊欄兩指橫滑（若穩定再做）；切換不重新載入頁面（各 Space 的 WKWebView 保留，只顯示/隱藏），過場動畫 ≤ 200ms。
   - 管理：右鍵重新命名、改色、改圖示、刪除（確認；其中的 Tab 一併關閉、釘選資料刪除；最後一個 Space 不能刪）；Tab / 釘選右鍵「移到 Space」或拖到切換列。
   - Command Palette：新增 New / Rename / Switch to / Move Tab to Space 動作；一般模式的 Tab 與釘選搜尋跨所有 Space（結果標示所屬 Space），選到其他 Space 的項目先切過去。
   - 還原：關閉 Tab 堆疊（⌘⇧T）維持全域，還原回原本的 Space；session restore 記住最後所在的 Space 與各 Space 的 Tab / 選中項；外部連結開在目前的 Space。
   - 遷移：既有 `pins.json` / `session.json` 無損遷移到預設 Space「Personal」（色 #699987），需壞檔容錯與 smoke 檢查。
2. 從 Arc 匯入：把 Arc 的 Spaces、置頂 Tab 與資料夾（含巢狀）、名稱匯入 Larch；不匯入登入狀態（Brian 確認不需要）。待調查：Arc 本機資料位置與格式（推測在 `~/Library/Application Support/Arc/` 底下的 sidebar JSON，需實際確認）；先做唯讀解析並預覽再匯入，不修改 Arc 的資料；依賴 Spaces 的資料結構，在 Spaces 之後做。

## 想法（低優先，沒有必做理由）
- 書籤：Arc 本身也沒有傳統書籤，釘選 Tab 與巢狀資料夾已取代；之後有具體需求再提升。

## 已知缺口（未排序）
- 邊用邊記的問題放這裡
- 資料夾圖示/顏色、釘選「重設為原網址」、拖曳到資料夾上懸停自動展開、多選
- 下載：可取消、下載清單；目前只顯示最新一筆
- 說明頁上的上一頁/下一頁行為未驗證
- 正式簽章與公證（Developer ID）；目前 ad-hoc

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
