# Larch 決策紀錄與研究脈絡

給未來任何 session 或未來的自己：這裡記「為什麼這樣做」，以及討論時查到、但程式碼看不出來的事實。
程式架構與踩過的坑在 `CLAUDE.md`，待辦在 `BACKLOG.md`。日期是 2026-10-23 至 2026-10-25 的討論；之後若事實改變，請在對應段落更新並註明日期。

## 1. 背景

- Brian（Senior Engineering Manager，台灣）因 Arc 將於 **2026-12-22 sunset** 而自製瀏覽器。
- 最在意的功能（依重要性）：**Little Arc**（點連結先在獨立小視窗看一眼，再決定關掉或加進 Tabs）、**Ctrl+Tab 最近使用（MRU）切換**、**Command Palette**（⌘T 打關鍵字執行動作、搜 Tab / 歷史 / 開網址）。
- Dia 已評估並放棄：沒有 Little Arc 與 Command Palette。Brian 後來也決定不向 Dia 提 feature request。
- Brian 說要「盡快能當主力瀏覽器、邊用邊記問題」；他大多只是用來瀏覽網頁，重度 Google 網頁應用（Docs、Meet 等）可以改用其他瀏覽器補位。

## 2. 決策與理由

### D1. 先用 Electron 做原型（`../my-browser`，已完成）
（`../my-browser` 為私有專案，外部讀者無法存取，以下引用僅供作者內部參考。）
三個核心功能都做完並有 smoke 測試，但**沒有成為主力**，原因見 D2。踩過的坑記在 `../my-browser/CLAUDE.md`（例如 Ctrl+Tab 不可在主程序 preventDefault，否則收不到 Ctrl 放開事件）。

### D2. Electron 放棄：Google 登入被擋
- 現象：Google 登入顯示「目前無法登入帳戶 — 這個瀏覽器或應用程式可能有安全疑慮」。
- 已試並**無效**（已還原，不要再試）：User-Agent 移除 `Electron/` 與 App 名稱；改寫 `Sec-CH-UA` 加入 `Google Chrome` 品牌；注入 `navigator.userAgentData` 品牌（主 world）。
- 推論（未經 Google 證實）：Google 擋的是「內嵌框架」（Electron、CEF 只用 Chromium 最底層 `content` 層，沒有 `//chrome` 層的行為），不是單一標頭；偵測條件不公開且會變，偽裝是長期追著跑。
- 另一個問題：Chromium 安全修補要自己升級 Electron 並重新打包，沒有自動更新。

### D3. 不 fork Chromium
- 100GB 以上原始碼、首次編譯數小時、要寫 C++（Views / WebUI / Mojo）。
- 真正的成本在長期維護：Chromium 約每 4 週一個大版本、安全修補更頻繁，個人無法長期合併；落後上游就是安全風險。Brave 這類專案是整個團隊在做。
- 中間路（沒做、沒驗證）：Chrome 擴充功能（side panel、popup 視窗可接近 Little Arc；但 ⌘T、Ctrl+Tab 是瀏覽器保留鍵，攔不到）；CEF「Chrome 風格」執行模式（可能帶進 Chrome 瀏覽器層，但自訂側邊欄是否可行不確定）。

### D4. 改用 Swift + AppKit + 系統 WebKit（WKWebView），只做 macOS
- **已驗證**：最小原型（`../my-browser/experiments/webkit-login/main.swift`）以**預設 UA**、帳密登入 Google 成功，重開後登入狀態保持。工作帳號 SSO、兩步驟驗證、passkey **沒測**。
- 好處：網頁引擎由 macOS 更新（不用自己追 Chromium 修補）；Ctrl+Tab 等按鍵用原生處理，沒有 Electron 的 keyUp 坑；Little 只是一個 NSWindow。
- 代價：沒有 Chrome 擴充功能；部分網站對 WebKit 相容性略差；Widevine 不適用（Netflix 等以 FairPlay 走系統）；Electron 的 JS 程式全部重寫（功能邏輯可照搬）。
- 資料夾 `my-browser-mac` 後來改名為 `larch`；GitHub 私人 repo `tp26610/larch`。

### D5. 不用 React Native / Flutter 做跨平台
它們只負責介面，網頁內容仍要靠各平台的 webview（macOS WebKit、Windows WebView2、Linux WebKitGTK），三個引擎行為不同，等於要處理三個瀏覽器。Ardia 的做法就是 React Native 外殼 + 另外的 Chromium。Brian 只用 Mac，所以不做跨平台。

### D6. 登入資料：所有視窗共用同一個 `WKWebsiteDataStore.default()`
**bundle id 是 `com.brianyeh.larch`，登入資料依 bundle id 存放，之後不要改**，否則所有人要重新登入。將來做 Spaces 時先共用同一個 data store（同 Arc 預設），資料結構預留各 Space 指定獨立 data store 識別碼的欄位。

### D7. 名稱與圖示
名稱 **Larch**（落葉松，/lɑːrtʃ/）；與 arch（拱門）只差一個字母，容易看錯。圖示：白底圓角方塊（同 Arc 的亮底）+ 三層由深到淺的鼠尾草綠樹，由 `scripts/make-icon.swift` 產生。外框與側邊欄色 `#699987` 取樣自 Arc 的主題。

### D8. 外觀與互動取向（仿 Arc）
亮色網頁卡片 + 鼠尾草綠外框；外框與側邊欄空白處可拖曳視窗，**網頁卡片底下不可有拖曳區域**（否則 macOS 會吞掉網頁捲動，Electron 版踩過）；紅綠燈跟著側邊欄收合；Little 視窗用白色色調，與主視窗一眼可分；⌘T 是命令列覆蓋層（搜尋 + 開新 Tab），Tab 鍵進入動作模式。

### D9. 書籤降級、Spaces 與 Arc 匯入列入待辦
- 書籤：Brian 認為不重要；Arc 本身也沒有傳統書籤，釘選 Tab 與巢狀資料夾已取代。
- Spaces（待辦第 3 項）：設計起點寫在 `BACKLOG.md`。曾短暫開始實作，Brian 說只要列待辦，已中止，工作區無殘留。
- Arc 匯入（待辦第 4 項）：只匯入 Spaces、置頂 Tab、資料夾（含巢狀）與名稱；**不匯入登入狀態**（Brian 確認不需要）；Arc 本機資料位置與格式尚未確認（推測在 `~/Library/Application Support/Arc/`）。依賴 Spaces，建議在 Arc sunset（2026-12-22）前完成。

### D10. 暫不採用 PR 流程與 Cloud session
- Brian 決定「等主流功能好了再說」；目前直接 commit 到 `main`。
- 技術限制：Larch 是 macOS 專用（AppKit、WebKit），Cloud session 一般是 Linux 環境，無法編譯與跑 smoke，只能盲寫。若要用，得先有 GitHub Actions 的 macOS CI（`swift build` + smoke；macOS 執行時間計費倍率高，且 smoke 需要視窗環境，能否在 Actions 跑未驗證）。
- 若改走 PR，另需處理：smoke 並行會搶焦點與共用資料目錄；功能多半動同幾個檔案，並行 PR 易衝突。

### D11. 暫不改用資料庫，資料維持 JSON
- 現況：歷史上限 3000 筆（`History.swift` 的 `limit`），釘選、session、偏好都很小；整份載入記憶體，搜尋是陣列掃描，寫入以 `Debouncer` 整檔重寫。
- 不換的理由：專案目前零依賴；換 DB 要重做 `Storage.swift` 的容錯讀寫與 smoke 的暫存路徑隔離，還要寫遷移；JSON 壞了可直接用文字編輯器修。
- 重新評估的觸發條件（門檻是粗估，沒實測，到時先量啟動時間與檔案大小）：歷史上限要拉到數萬筆以上或 JSON 超過約 10–20 MB；需要頁面內容全文搜尋（SQLite FTS5）；需要聚合統計類查詢；多個 process 同時寫入或跨裝置同步；實際遇過 JSON 寫到一半損毀。
- 若要換，只動 `HistoryStore`，釘選與 session 資料小且整棵樹存取，繼續用 JSON。換之前先把 favicon 拆成獨立檔案或以 host 去重，通常就能把檔案縮回小量。

## 3. 外部評估：Ardia（真 Chromium 的第二瀏覽器）

- Ardia（https://ardia.dev ，repo `mantrakp04/ardia`）是 Arc 式側邊欄、真 Chromium、免費開源的 Mac 瀏覽器，Google 登入不會像 Electron 被擋（它用 Chrome 自己的框架，這點我們沒有實際驗證）。
- 兩份完整報告在 `docs/research/`：
  - `ardia-audit-report.md`：原始碼審查（審 tag `v0.2.39`，commit `91e17a5655519d2dc385ec8452432469232ff9af`）。
  - `ardia-team-report.md`：團隊與專案背景（只用公開資料）。
- **結論**：沒有找到惡意或可疑程式碼，隱私聲明與程式碼大致吻合；但風險在發佈鏈與信任單一個人：實質單人 + AI 代理開發、公開歷史約 1 個月、沒有 CI、沒有可重現建置、自動更新只靠一把存在維護者 Mac 登入鑰匙圈的 Sparkle EdDSA 私鑰、Safe Browsing 被編譯掉、預設搜尋與建議仍送 Google、專案正大幅變動（v0.2.39 之後引擎改為 Helium 為底、授權由 Apache-2.0 改為 GPL-3.0）。**建議當第二瀏覽器試用，不當唯一主力，也不把全部密碼交給它。**
- 審查的限制：只讀它「改過的部分」，Chromium 本體沒審；無法證明發佈的二進位與原始碼一致；維護者帳號與機器安全查不到；結果只對該 commit 有效。
- 自己 build Chromium 類瀏覽器可補上「二進位與原始碼一致」，但更新要自己追、沒有簽章，不建議。

## 4. 安全狀態

**WebKit 路線解決了**：引擎安全更新由 macOS 提供；網頁權限預設全拒；憑證錯誤預設阻擋且不提供略過；UI 中網頁來源的標題與網址一律純文字。

**尚未解決（要當長期主力前）**：
- 正式簽章與公證（Apple Developer Program，US$99/年，Brian 還沒有）；目前 ad-hoc 簽章，每次重裝簽章身分會變，系統可能要求重新確認預設瀏覽器。
- 自動更新：Sparkle 這類機制需要 Developer ID 簽章；沒有的話就是手動重新 build 並 `scripts/install.sh`。
- **Passkey**：在 WKWebView 內存取系統 passkey（含 iCloud 鑰匙圈與實體安全金鑰），需要 Apple 核發的 entitlement `com.apple.developer.web-browser.public-key-credential`，要用專用表單申請（依 Apple 工程師在開發者論壇的說法，須由帳號 Account Holder 送出），且需 Developer ID 簽章。論壇上核准經驗不一致（有人卡在「已提交」），時間與成功率沒有保證；個人帳號是否符合資格不確定。實體安全金鑰在 WKWebView 是否可用，沒有查到足夠資料，需實測。目前帳密登入可用，passkey 通常是可選。
- `history.json`、`session.json` 是明文（存在 `~/Library/Application Support/Larch/`）。
- Safe Browsing 類的釣魚網站警告：WKWebView 預設行為，Larch 沒有特別驗證或自訂。

## 5. 工作方式與驗證限制（協作時請注意）

- **自動化測試不等於真實手感**：smoke 用合成事件（`NSApp.sendEvent`）驅動，沒有真的敲鍵盤或拖曳。已發生案例：Little 為目前視窗時 ⌘W 關到主視窗 Tab，是 Brian 實測才抓到（根因：選單動作 target 固定是主視窗 controller）。凡涉及快捷鍵、焦點、拖曳、手勢，請在回報中明講哪些只靠自動化驗證。
- smoke 注意：依賴 key window 的檢查（Little 與 Ctrl+Tab 切換器）需要 Larch 一直在前景，跑 smoke 時不要操作其他視窗，否則偶發失敗。
- 直接執行 Larch（`swift run`、`--hide-sidebar`、`--open-palette`）會讀寫真實的 `~/Library/Application Support/Larch/`，macOS app 忽略 `HOME` 環境變數，無法用它隔離。
- `swift run` 不是 `.app`：沒有 Info.plist 圖示（程式會從 `assets/` 補 Dock 圖示）、不能設為預設瀏覽器、登入資料位置與正式 app 不同。要當預設瀏覽器請用 `scripts/install.sh`。
- 多個 session 同時改同一個 repo 會共用 working tree，不要並行寫同一組檔案；session 的工作路徑是啟動時綁定的，資料夾改名後該 session 失效。
- 溝通：繁體中文、簡潔、結果先行、不要 emoji；commit 訊息繁體中文，結尾加 `Co-Authored-By`；使用中遇到的問題 Brian 會記進 `BACKLOG.md`。

## 6. 已知限制（Brian 已接受）

- 沒有 Chrome 擴充功能；部分網站可能對 WebKit 相容性較差，重度 Google 網頁應用以其他瀏覽器補位。
- Windows / Linux 不在範圍內。Electron 版（`../my-browser`）保留作參考，不再主動開發。
