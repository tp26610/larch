# Larch

macOS 專用瀏覽器：Swift + AppKit + 系統 WebKit（WKWebView）。Arc 式左側欄 + 圓角網頁卡片。

```bash
swift run Larch          # 開發執行
scripts/bundle.sh            # 打包成 build/Larch.app（ad-hoc 簽章）
scripts/smoke.sh             # 煙霧測試（會開視窗）
swift scripts/make-icon.swift  # 重新產生 App 圖示 assets/AppIcon.icns
```

需求：macOS 14+、Xcode 26 / Swift 6.2。

## 安裝並設為預設瀏覽器
```bash
scripts/install.sh      # 打包、ad-hoc 簽章、複製到 /Applications/Larch.app 並向 LaunchServices 註冊
```
1. 打開 `/Applications/Larch.app`。
2. 選單 Larch > Make Default Browser…，在系統對話框按「使用 Larch」（http 與 https 各一次）。
   或：系統設定 > 桌面與 Dock > 預設網頁瀏覽器 > Larch。
3. 之後其他 App 的連結與 .html 檔會在這裡開新 Tab（已執行或冷啟動都一樣）。

Gatekeeper：自己在這台 Mac 建置並安裝的 app 沒有隔離標記，不會被擋。若 .app 是經 AirDrop / 下載 / 壓縮檔從別處拿來的，第一次開啟被擋時：
```bash
xattr -dr com.apple.quarantine "/Applications/Larch.app"
```
或在 Finder 對 app 按右鍵 > 打開 > 打開；或系統設定 > 隱私權與安全性 > 「仍要打開」。
每次重新安裝會換簽章身分（ad-hoc），系統可能要求重新確認預設瀏覽器；登入資料存放在系統 WebKit 的 data store（依 bundle id），重裝不會遺失。
資料位置：`~/Library/Application Support/Larch/`（session.json、history.json）；下載存到 `~/Downloads`。

## 目前功能
- 單一視窗；側邊欄（⌘S / Ctrl+S 隱藏，紅綠燈一起收合；隱藏時滑鼠移到左上角會暫時顯示；拖曳與卡片的交界可調寬度，200~420px，重開後記住）+ 8px 邊框的圓角網頁卡片；雙擊外框或側邊欄空白處放大/還原視窗（依系統「按兩下視窗標題列」設定）
- Little Arc：按住 Option 點連結，在獨立的小視窗先看一眼（Esc / ⌘W 關閉；⌘O、⌘Return 或「Add to Tabs」把同一個頁面搬進主視窗成為新 Tab，不重新載入）。其他 App 傳來的外部連結（Larch 設為預設瀏覽器時）預設也在 Little 開，File 選單「Open External Links in Little Window」可關掉改成新 Tab。可同時開多個，共用登入；命令列動作 Open in Little Window 可把目前頁面丟進 Little
- Ctrl+Tab 最近使用（MRU）切換：快速按一下切到上一個用過的 Tab（不顯示任何東西）；按住 Ctrl 超過約 0.15 秒會顯示切換清單（favicon、標題、網址，依最近使用排序），按住 Ctrl 連按 Tab 往下、Ctrl+Shift+Tab 往上，放開 Ctrl 確認、Esc 取消、閒置 10 秒自動確認。範圍是主視窗所有開著的 Tab（灰色釘選不列）；命令列開著或 Little 為前景時不處理。命令列動作「Switch to Previous Tab」做同樣的快速切換
- ⌘T 命令列：視窗中央彈出搜尋框，輸入網址或關鍵字 Enter 以新 Tab 開啟；即時列出已開啟的 Tab（Enter/點擊直接切換）與歷史紀錄；↑↓ 選取、Esc 或點外面關閉（側邊欄「+ New Tab」同一個）；每列右側顯示類型（Open / Tab / Pinned / History / Action）與快捷鍵，超過 8 列可捲動
- 動作模式：覆蓋層按 Tab 鍵進入（輸入框左側出現 Actions chip，保留已輸入文字），只列動作；Backspace（輸入框為空）或 Shift+Tab 離開。動作：Restore Last Closed Tab、New Blank Tab、Close Tab、Close Other Tabs、Duplicate Tab（⌃⇧D）、Reload Tab、Copy Tab URL、Copy Tab URL as Markdown（⌘⌥⇧C）、Rename Tab、Pin/Unpin Tab（⌘D）、New Folder（⌘⇧N）、Toggle Sidebar、Zoom In/Out/Reset、Find in Page、Open Web Inspector；不適用目前狀態的動作不列出
- Tab：關閉 ⌘W / Ctrl+W、切換、還原 ⌘⇧T（最多 25 筆、僅 http/https）、雙擊改名
- 釘選 Tab 與巢狀資料夾（仿 Arc）：側邊欄上方是釘選區（資料夾可無限巢狀，最上層也可以是單獨的釘選 Tab），分隔線下是一般 Tab。⌘D 釘選/取消釘選目前 Tab、⌘⇧N 新資料夾、右鍵選單（Pin / Unpin / Rename / New Folder / Delete Folder）；拖曳可放進資料夾、重排、跨區釘選或取消釘選。釘選列的 ✕ 是兩段式（仿 Arc）：第一下（「−」圖示）關閉 Tab、那一列保留變灰，第二下（✕）才移除釘選；關掉後那一列保留變灰，點一下用記住的網址重新開啟；⌘T 命令列也找得到。資料存 `pins.json`
- 載入狀態：網頁卡片頂端真實進度條（只反映目前 Tab）、Tab 列 favicon 位置換成 spinner、重新整理鈕載入中變停止（✕）
- 重開後還原所有 Tab（順序、自訂名稱、選中項）
- ⌘L 同一個命令列但在目前 Tab 導航（預填並全選目前網址，不開新 Tab）；側邊欄網址列仍可直接點擊輸入、上一頁 ⌘[、下一頁 ⌘]、重新整理 ⌘R、複製網址 ⌘⇧C
- 頁內尋找 ⌘F / ⌘G / ⌘⇧G；縮放 ⌘+ ⌘- ⌘0（以網站為單位記憶）
- 下載（存到 ~/Downloads、重名加序號、側邊欄顯示進度，完成後點一下在 Finder 顯示）
- 載入失敗說明頁（憑證錯誤一律阻擋、不提供略過）；HTTP 驗證對話框
- window.open / target=_blank 開新 Tab（保留 opener，登入彈窗可用）
- 預設瀏覽器：外部連結與 .html 檔開新 Tab
- 持久登入（`WKWebsiteDataStore.default()`），Google 登入可用；網頁權限預設全拒
- 歷史紀錄寫入本機（暫無 UI）

決策與研究脈絡見 [docs/decisions.md](docs/decisions.md)（含 `docs/research/` 的 Ardia 報告）。後續見 [BACKLOG.md](BACKLOG.md)，開發脈絡見 [CLAUDE.md](CLAUDE.md)。
