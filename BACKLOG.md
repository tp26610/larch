# Backlog

## 接下來（依序）
1. Little Arc：Alt+點連結（及外部連結）先在獨立小視窗開啟，可關閉或加進 Tabs
2. Ctrl+Tab MRU：最近使用 Tab 切換（Electron 版踩過的坑：不要攔截 keyUp，見 ../my-browser/CLAUDE.md）
3. Command Palette：⌘T 搜尋 + 開新 Tab 已完成，動作（例如 Restore Last）與 Tab 切換器待做（元件見 CommandPaletteView / PaletteModel，擴充方式見 CLAUDE.md）
4. 書籤

## 已知缺口（未排序）
- 邊用邊記的問題放這裡
- 歷史 UI、清除歷史/瀏覽資料
- Tab 拖曳排序
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
