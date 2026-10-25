# Backlog

## 接下來（依序）
1. Little Arc：Alt+點連結（及外部連結）先在獨立小視窗開啟，可關閉或加進 Tabs
2. Ctrl+Tab MRU：最近使用 Tab 切換（Electron 版踩過的坑：不要攔截 keyUp，見 ../my-browser/CLAUDE.md）
3. Spaces（仿 Arc）：側邊欄可切換多個 Space，各自有自己的釘選區、一般 Tab、名稱與主題色；待釐清：Space 之間是否各自獨立登入（類似 Profile，WKWebsiteDataStore 可用識別碼隔離）、切換手勢與快捷鍵、側邊欄底部的 Space 切換列、與現有 Pinned tabs / 資料夾的資料結構關係（pins.json 需加 space 欄位並遷移）
4. 從 Arc 匯入：把 Arc 的 Spaces、置頂 Tab 與資料夾（含巢狀）、名稱匯入 Larch；待調查：Arc 本機資料位置與格式（推測在 `~/Library/Application Support/Arc/` 底下的 sidebar JSON，需實際確認）、哪些能匯入（結構與網址應可行，登入狀態與 cookie 是加密的，可能無法匯入，需重新登入）、先做唯讀解析並預覽再匯入，不修改 Arc 的資料；依賴 Spaces 的資料結構，建議在 Spaces 之後做
5. 書籤（Brian 不太用，優先度低；Pinned tabs + 巢狀資料夾已完成）

## 已知缺口（未排序）
- 邊用邊記的問題放這裡
- 歷史 UI、清除歷史/瀏覽資料
- 資料夾圖示/顏色、釘選「重設為原網址」、拖曳到資料夾上懸停自動展開、多選
- 下載：可取消、下載清單；目前只顯示最新一筆
- 說明頁上的上一頁/下一頁行為未驗證
- 正式簽章與公證（Developer ID）；目前 ad-hoc
- 冷啟動開外部連結時會多一個空白 Tab（有還原的 Tab 時不明顯）

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
- Command Palette 完成：⌘T / ⌘L、動作模式（Tab 鍵進入）與 17 個動作、類型標籤與快捷鍵、近用排序（Ctrl+Tab 切換器仍在待辦）
