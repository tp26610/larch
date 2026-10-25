# Backlog

## 接下來（依序）
1. Little Arc：Alt+點連結（及外部連結）先在獨立小視窗開啟，可關閉或加進 Tabs
2. Ctrl+Tab MRU：最近使用 Tab 切換（Electron 版踩過的坑：不要攔截 keyUp，見 ../my-browser/CLAUDE.md）
3. Command Palette：⌘T 改為 Palette（現在 ⌘T 暫為新增分頁）；動作、搜 Tab / 歷史 / 開網址
4. Session restore：重開後還原 Tab（含自訂名稱）
5. 打包與預設瀏覽器註冊：Info.plist 加 CFBundleURLTypes（http/https）、簽章、處理外部連結
6. 書籤

## 已知缺口（未排序）
- 載入失敗的錯誤頁（目前停在空白）
- 下載（`WKDownload`）、HTTP 驗證對話框
- 歷史紀錄（Palette 前置）
- Tab 拖曳排序
- 側邊欄隱藏時紅綠燈浮在網頁上
- 尋找頁面內文字（⌘F）、縮放
- 彈出視窗目前全部在同一 view 內處理（登入夠用，但 window.open 的 opener 關係不保留）

## 已完成
- 單一視窗、側邊欄（⌘S）、圓角卡片與邊框拖曳
- Tab 新增/關閉/切換/還原（25 筆）/雙擊改名/載入光條/favicon
- 網址列、上一頁/下一頁/重新整理、複製網址
- 持久登入（default data store）、權限預設全拒
- smoke 測試（58 項）、打包腳本、--live-check
