# my-browser-mac

macOS 專用瀏覽器：Swift + AppKit + 系統 WebKit（WKWebView）。Arc 式左側欄 + 圓角網頁卡片。

```bash
swift run MyBrowser          # 開發執行
scripts/bundle.sh            # 打包成 build/My Browser.app（ad-hoc 簽章）
scripts/smoke.sh             # 煙霧測試（會開視窗）
```

需求：macOS 14+、Xcode 26 / Swift 6.2。

## 目前功能
- 單一視窗；側邊欄（⌘S 隱藏）+ 8px 邊框的圓角網頁卡片
- Tab：新增 ⌘T、關閉 ⌘W、切換、還原 ⌘⇧T（最多 25 筆、僅 http/https）、雙擊改名、載入中掃動光條
- 網址列 ⌘L（網址或搜尋）、上一頁 ⌘[、下一頁 ⌘]、重新整理 ⌘R、複製網址 ⌘⇧C
- 持久登入（`WKWebsiteDataStore.default()`），Google 登入可用
- 網頁權限預設全拒

後續見 [BACKLOG.md](BACKLOG.md)，開發脈絡見 [CLAUDE.md](CLAUDE.md)。
