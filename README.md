# Larch

macOS 專用瀏覽器：Swift + AppKit + 系統 WebKit（WKWebView）。Arc 式左側欄 + 圓角網頁卡片。

```bash
swift run Larch          # 開發執行
scripts/bundle.sh            # 打包成 build/Larch.app（ad-hoc 簽章）
scripts/smoke.sh             # 煙霧測試（會開視窗）
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
- 單一視窗；側邊欄（⌘S 隱藏）+ 8px 邊框的圓角網頁卡片
- ⌘T 命令列：視窗中央彈出搜尋框，輸入網址或關鍵字 Enter 以新 Tab 開啟；即時列出已開啟的 Tab（Enter/點擊直接切換）與歷史紀錄；↑↓ 選取、Esc 或點外面關閉（側邊欄「+ New Tab」同一個）
- Tab：關閉 ⌘W / Ctrl+W、切換、還原 ⌘⇧T（最多 25 筆、僅 http/https）、雙擊改名、載入中掃動光條
- 重開後還原所有 Tab（順序、自訂名稱、選中項）
- 網址列 ⌘L（網址或搜尋）、上一頁 ⌘[、下一頁 ⌘]、重新整理 ⌘R、複製網址 ⌘⇧C
- 頁內尋找 ⌘F / ⌘G / ⌘⇧G；縮放 ⌘+ ⌘- ⌘0（以網站為單位記憶）
- 下載（存到 ~/Downloads、重名加序號、側邊欄顯示進度，完成後點一下在 Finder 顯示）
- 載入失敗說明頁（憑證錯誤一律阻擋、不提供略過）；HTTP 驗證對話框
- window.open / target=_blank 開新 Tab（保留 opener，登入彈窗可用）
- 預設瀏覽器：外部連結與 .html 檔開新 Tab
- 持久登入（`WKWebsiteDataStore.default()`），Google 登入可用；網頁權限預設全拒
- 歷史紀錄寫入本機（暫無 UI）

後續見 [BACKLOG.md](BACKLOG.md)，開發脈絡見 [CLAUDE.md](CLAUDE.md)。
