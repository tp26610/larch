# Ardia v0.2.39 安全與隱私審查報告

- 審查對象：https://github.com/mantrakp04/ardia ，tag `v0.2.39`
- 實際審查的 commit：`91e17a5655519d2dc385ec8452432469232ff9af`（"Release 0.2.39"，2026-10-21 23:39 -0700，作者 mantrakp04）。tag 為輕量 tag，指向此 commit，未簽章。
- 審查日期：2026-10-23。方法：只讀原始碼，clone 到暫存資料夾；沒有執行、安裝、build 任何東西，也沒有下載二進位檔。
- 路徑皆相對於 repo 根目錄。「已確認」＝我在該 commit 的程式碼或文件中直接讀到；「推測」＝推論或無法由原始碼判斷。

## 結論

**目前不建議把 Ardia 當唯一主力瀏覽器，也不建議現在就把全部密碼與登入狀態交給它。可以當第二瀏覽器試用。**

這個結論主要不是因為我找到惡意或可疑的程式碼。我沒有找到：沒有混淆程式碼、沒有硬寫的可疑外送端點、沒有偷讀 cookie 或密碼後送出的路徑。隱私聲明和程式碼大致吻合，Chromium 補丁的做工也比我預期的謹慎。

真正的風險在「信任一個人與一條很新的發佈鏈」：

1. **供應鏈集中在單一個人。** 所有使用者的自動更新，只靠一把 Sparkle EdDSA 私鑰把關；這把鑰匙存放在維護者那台 Mac 的登入鑰匙圈（`docs/releasing.md:89-92`），同一台機器也持有 Apple Developer ID 與公證金鑰。repo 沒有 CI、沒有程式碼審查、沒有可重現建置，發佈的二進位檔是維護者在本機 build 的。這把鑰匙或那台機器失守，最壞情況是惡意更新被推給全部使用者，而且更新預設自動安裝。
2. **專案極年輕且是單人 + AI 代理開發。** 首個 commit 2026-09-25，不到 4 週 1451 個 commit，其中 1445 個（99.5%）來自同一人，39 個 stable 版本。`AGENTS.md` 明說「Move fast」「Commit straight to main」，由 AI 子代理實作。沒有證據顯示有第二個人審過程式碼。
3. **Safe Browsing 被整個編譯掉**（`engine/patches/build/gn_defines.sh:25` `safe_browsing_mode=0`）。沒有釣魚/惡意網站警告、沒有下載掃描。內建 uBlock Origin 只能部分補償。
4. **「de-Googled」不等於不連 Google。** 預設搜尋引擎是 Google，且預設開啟搜尋建議，會把你在網址列打的字送到 `suggestqueries.google.com`（`apps/browser/src/store/settings.ts:79,83`、`packages/core/src/engines.ts`）。Chrome Web Store 擴充功能更新與元件更新也會連 Google。
5. **專案正在大幅變動。** v0.2.39 之後 57 個 commit 內，引擎已改成 Helium 0.19.4 為底、授權改為 GPL-3.0、加入 Helium 的濾鏡清單鏡像等新的網路依賴。你今天裝的穩定版，幾天內就會自動更新成這個我沒審過的版本。

更正一個前提：**v0.2.39 的授權是 Apache-2.0**（`LICENSE`、`NOTICE`、`README.md:225`），不是 GPL-3.0。切換成 GPL-3.0 是在 tag 之後（commit `8129b3d4`，2026-10-22，原因是新引擎帶入 Helium 的 GPL 補丁）。GitHub 頁面顯示 GPL-3.0 是因為看的是 main。內建的 uBlock Origin 本身是 GPL-3.0。

若仍要使用，建議：密碼留在獨立的密碼管理器、不要啟用 Ardia 的密碼同步；把搜尋引擎改成 DuckDuckGo/Brave 並關閉搜尋建議；Google 登入先用一個次要帳號測；自動更新改為手動（Settings 內可切換，`Updater.swift` 有 `setAutomaticDownloads`），每次更新前看一下 release notes 與 Chromium 版本。

---

## 1. 自動更新機制

### 已確認
- 使用 Sparkle 2.9.6（`apps/browser/macos/Podfile.lock:2313`），EdDSA 驗簽。
  - 預設開啟自動檢查與自動安裝：`apps/browser/macos/Ardia-macOS/Info.plist:117-120`（`SUAutomaticallyUpdate`、`SUEnableAutomaticChecks` 為 true）；每 8 小時檢查一次（`Info.plist:125-126`）。
  - 公鑰寫死在 `Info.plist:123-124`（`SUPublicEDKey`），feed 寫死在 `Info.plist:121-122`：`https://ardia.dev/appcast.xml`。
- feed 路徑：`ardia.dev/appcast.xml` 由 nginx 回 302 導到 `https://github.com/mantrakp04/ardia/releases/latest/download/appcast.xml`（`infra/site/nginx.conf:127-134`）。zip 也在 GitHub release assets（`docs/releasing.md:3-16`）。所以更新實際來源是 GitHub release，ardia.dev 只是計數的轉址層。
- `isConfigured` 要求有公鑰且 feed 為 http/https（`packages/shell/ios/Updater.swift:97-102`）。feed 可被環境變數 `ARDIA_UPDATE_FEED_URL` 或 defaults 鍵 `ACUpdateFeedURL` 覆寫（`Updater.swift:9-13`）；這需要本機已能寫你的使用者設定，且 EdDSA 仍會把關，風險低。
- 頻道：stable 預設不看 nightly；nightly 只有使用者在設定自行切換（`Updater.swift:200-205`、`docs/releasing.md:31-66`）。
- 更新驗證在 Sparkle 內部（EdDSA 簽章 zip）。`docs/releasing.md:181-189` 描述發佈前的 smoke 流程包含驗 appcast 的 EdDSA 簽章、Gatekeeper、designated requirement 比對。
- 已下載的更新在「退出時安裝」前，會被「預熱」：以隱藏方式執行一次暫存的新版 app（`Updater.swift:261-300`，受 `updatePrewarm` 開關控制）。該 app 是 Sparkle 驗證後的內容，所以不是繞過驗證，但表示新程式碼在你按下重啟前就會跑一次（我已確認會濾掉 `ARDIA_*`、`DYLD_*` 環境變數，90 秒逾時殺掉）。
- feed 中的 `fullReleaseNotesLink` 會被當成網址在 Ardia 開新分頁（`Updater.swift:341-346`）。feed 被竄改時可開任意網頁（不是程式碼執行，是一般網頁分頁）。

### 最壞情況（已確認的結構 + 推測的後果）
| 被入侵的對象 | 能做什麼 |
|---|---|
| ardia.dev（網站/nginx） | 只能改轉址或 feed 內容；沒有私鑰就無法讓客戶端接受惡意 zip。可以：停止更新、改 release notes 頁面、改 `switches.json`（見第 2 項）、看到每次檢查的來源 IP（推測，由 nginx 日誌決定）。 |
| GitHub 帳號 / repo | 同上，且可替換 release 資產，但仍需 EdDSA 私鑰才能被接受。 |
| 維護者的 Mac 或登入鑰匙圈 | **拿到 EdDSA 私鑰 + Developer ID，即可對所有自動更新的使用者推出惡意版本並通過 Gatekeeper。** 這是整個設計的單點失效。 |
- 推測：Sparkle 沒有 SUVerifyUpdateBeforeExtraction 之類的額外設定，也沒有簽章的 appcast（`Info.plist` 找不到相關鍵），但 EdDSA 對 zip 的簽章已足以擋住 feed 竄改；這點我依 Sparkle 的標準行為判斷，沒有讀 Sparkle 原始碼。
- 無法從原始碼判斷：私鑰實際的備份位置、是否有第二人持有、有沒有額外存取控制。

## 2. 對外連線與遙測

### 寫死的網域（App 與 Engine 自訂碼，排除測試與 fixtures）
| 目的 | 網址 | 位置 |
|---|---|---|
| 更新 feed | `https://ardia.dev/appcast.xml` → GitHub | `Info.plist:122`、`nginx.conf:133` |
| 遙測（需勾選） | `https://ardia.dev/otel/v1/logs` | `apps/browser/src/telemetry/config.ts:1` |
| kill switch 檔 | `https://ardia.dev/switches.json` | `apps/browser/src/lib/killSwitches.ts:66` |
| 預設搜尋 | `https://www.google.com/search?q=` | `packages/core/src/omnibox.ts:6` |
| 搜尋建議（預設開） | `suggestqueries.google.com`（Google）；其他引擎各自的建議端點 | `packages/core/src/engines.ts` |
| Chrome 元件更新（僅 3 個安全元件） | `https://update.googleapis.com/service/update2/json`，下載限 `dl.google.com`、`*.gvt1.com`、`www.google.com/dl/` | `engine/patches/chromium-component-updater-security-only.patch:53-69` |
| 擴充功能更新 | `https://clients2.google.com/service/update2/json` | `engine/patches/chromium-extension-updates.patch:23` |
| 擴充功能商店 | `chromewebstore.google.com` | `apps/browser/src/components/extensions/state.ts:77,201` |
| 即時資料夾（使用者自行連接才會用） | GitHub GraphQL、Bitbucket、Notion、Atlassian、Google Drive API | `apps/browser/src/live/net.ts:15-22` |
| uBlock 濾鏡清單 | uBO 預設各清單的來源主機（uBO 自己的更新機制，延遲 600 秒） | `packages/ardiacore/scripts/ubo.sh:57` |
- 引擎的自訂 C++（`engine/ardiacore/`、`engine/chromium/src/chrome/browser/ardia/`）：我用 grep 搜尋所有寫死的 URL 與網路呼叫，沒有發現遙測或外送端點。唯一的出站取得是抓網站 favicon（`engine/ardiacore/src/ardia/core/ac_icon_fetch.mm:101-127`，`credentials_mode = kOmit`，只收 `http(s)`），目標是你正在瀏覽的網站本身。

### 與官網聲稱對照
| 官網聲稱 | 程式碼 | 結論 |
|---|---|---|
| 更新檢查只送依版本與日期的計數 | `nginx.conf:141-156`：從 User-Agent 取版本、取當天日期、是否第一次（`?first=1`），以 `proxy_pass_request_headers off` 送到蒐集器；`distinct_id` 為固定字串 `update-check`，不帶 IP 或 cookie。App 端只在該 copy 第一次檢查時加 `first=1`（`Updater.swift:215-219`）。 | **一致**。但 nginx 自己的 access log 是否記 IP，無法從 repo 判斷。 |
| Crash report 與計數須使用者勾選 | 預設 `sharing: false`（`apps/browser/src/telemetry/client.ts:33-35,64`）；關閉時會清掉佇列（`client.ts:350-353`）；只在 `isSharing()` 為真才回報原生 crash（`telemetry/errors.ts:84`）。送出內容清單在 `telemetry/copy.ts:23-74`，另有清洗程式 `telemetry/sanitize.ts` 與測試。 | **一致**。 |
| 每次啟動讀一個小檔案，用來關閉出問題的加速功能 | `killSwitchesLaunch.ts:9`、`killSwitches.ts:122-149`、`docs/kill-switches.md`：GET 靜態檔、`credentials: "omit"`、無自訂 header、5 秒逾時、4 KB 上限；**只在更新檢查開啟時才抓**。 | **一致**。（`copy.ts:14-15` 與 `docs/kill-switches.md:29-34` 都有揭露。） |

### Kill switch 能改到什麼程度（已確認）
- 檔案格式 `{ "version": 1, "switches": { name: boolean } }`；程式只接受**已知名稱**（`killSwitches.ts:73,75-83`）且值必須是布林。目前已知名稱共 8 個，全是效能/啟動行為：`newTabPrewarm`、`lazySidebarRows`、`updatePrewarm`、`launchTab`、`focusedWindowFirst`、`sidebarSlide`、`sidebarSlideLean`、`chromeBatterySaver`（`killSwitches.ts:12-61`）。
- 沒有網址、沒有字串、沒有程式碼，也沒有遠端設定任何安全/隱私相關開關。**遠端能做的最壞事：關掉這 8 項效能特性（或強制為預設的開啟），造成變慢或行為回退。**
- 沒有簽章/釘選：這是普通的 HTTPS GET，ardia.dev 失守者可改這個檔，但能影響的範圍僅限上述。
- repo 內的 `apps/site/public/switches.json` 目前是空的（`{"switches": {}}`），我沒有去抓線上實際版本。
- 注意：原生側的 `KillSwitch.isOn` 對名稱沒有白名單（`Updater.swift:233-253`），但只被 `updatePrewarm` 呼叫，且快取檔由 JS 端寫入時已過濾。

### 其他發現
- **Google 仍然在線上**（對照 README「Google's pings are compiled out」）：
  - Chrome 元件更新只保留三個安全元件（CRLSet、PKI Metadata、SSL error assistant）；請求欄位被白名單裁到最少，去掉 `ping`、`cohort`、`brand`、`lang`、`hw` 等，也限制只能打上述主機並檢查每次轉址（`chromium-component-updater-security-only.patch:61-69`，`docs/engine-build.md:37`）。該文件自己承認「來源 IP 與版本仍可能讓 Google 關聯多次檢查」。
  - 擴充功能更新直接打 `clients2.google.com`；ungoogled 的 `disable-webstore-urls.patch` 被刻意跳過，因為「Ardia 需要商店與擴充更新」（`engine/patches/ungoogled-status.tsv:21`）。所以只要裝了商店擴充，Google 會看到擴充 ID、版本與 Chrome 版本。
  - 預設搜尋與搜尋建議是 Google（見上）。這不是漏洞，但與「de-Googled」的印象有落差。
- 網站（ardia.dev）本身有第一方分析與 session replay（rrweb），存在他們自己的 ClickHouse/SeaweedFS（`docs/growth.md:112-173`、`nginx.conf:76-89`）。這只針對網站訪客，不是 App 內功能；App 沒有 replay 程式碼（我 grep 過 `apps/browser/src`）。
- 所有 App 端 JS `fetch` 呼叫：遙測、kill switch、搜尋建議、即時資料夾。沒有其他。

## 3. Chromium 補丁與自訂程式碼

### 已確認
- 引擎的組成：純 Chromium `155.0.8059.84` + ungoogled-chromium（`engine/patches/build/env.sh:14-15`）+ 自己的 `series`（約 40 個補丁，`engine/patches/series`）+ 自訂層 `engine/ardiacore`、`engine/chromium`。Chromium 本體不在 repo 內，所以我只能讀「差異」。
- ungoogled 補丁套用狀態逐項記錄在 `engine/patches/ungoogled-status.tsv`（110 項）；跳過的有商店 URL（上述）、`disable-download-quarantine`（保留 macOS 下載隔離）等，理由都有寫。
- 沒有搜到混淆或動態執行：在 `engine`、`packages/*/ios`、`apps/browser/macos` 搜尋 `eval(`、`atob`、`dlopen`、`popen`、`NSTask` 等，只有 base64 編 favicon/圖片的合理用法。
- **沒有削弱 sandbox 或憑證檢查，反而有加固：**
  - `engine/ardiacore/src/ardia/core/ac_main_delegate.cc:79-110`：啟動時會移除會「打開 profile」的危險命令列參數（`disable-web-security`、`ignore-certificate-errors`、`remote-debugging-port`、`proxy-server`、`load-extension` 等）。
  - 沒有 `--no-sandbox` 或關閉 site isolation 的設定。
  - 補丁 `chromium-emudhra-distrust.patch` 在 2026-10-21 把被公開私鑰問題波及的 eMudhra 中繼 CA 與根加入封鎖清單，說明維護者有在追憑證事件。
  - DevTools 控制伺服器（供 CLI 使用）要 token、拒絕任何 Origin、命令走白名單（`chromium-devtools-control-token.patch`、`docs/engine-build.md:46`）。
- **被削弱/關閉的安全功能：**
  - `safe_browsing_mode=0`（`gn_defines.sh:25`）：沒有 Safe Browsing 網址檢查、沒有下載保護。`chromium-safe-browsing-off-file-types.patch` 只是為了讓這個設定能編過。
  - `enable_reporting=false`（`gn_defines.sh:26`）、`enable_updater=false`（`gn_defines.sh:38`）、關掉 crash reporter（`ungoogled-status.tsv:10`）：這些屬於隱私強化。
  - 關閉 Topics、Protected Audience、歷史叢集、Live Caption（`chromium-background-features-off.patch`）：隱私強化。
- 密碼與 cookie：App 使用 Chromium 自己的密碼管理器，Safe Storage 金鑰名稱改為 `Ardia Safe Storage`（`chromium-safe-storage-name.patch`）。`ac_passwords.cc` 透過 Chrome 的 `passwordsPrivate` API，匯出功能用 Chrome 原生的 exporter，未見自製外送路徑。
- Widevine 啟用但不更新（`gn_defines.sh:15-17`；README 說 Google 尚未簽核）。
- 輔助功能：`Ardia.entitlements` 含 apple-events、相機、麥克風、藍牙、USB、行事曆、定位（`Ardia.entitlements`）。apple-events 是為了從 Dia 匯入分頁（`Info.plist:88`）。

### 推測/未涵蓋
- 我沒有逐檔細讀 `ardiacore_api.mm`（86 KB）、`ac_cookies.cc`、`ac_passwords.cc` 的全部邏輯，只確認了網路與危險 API 的 grep 結果與結構。
- React Native 外殼（`apps/browser/src`，668 個檔）與 Chromium 引擎之間有一個 JS API，JS 可以讀取歷史、書籤、cookie、密碼清單。我確認 JS 層只有上述 4 類 fetch 呼叫，但沒有逐行讀完。
- JS bundle 是打包進 App 內的（`AppDelegate.swift:81-91` 在 release 走內建 bundle；找不到 expo-updates 或 CodePush 類遠端 JS 更新），這點是好的，但我沒有逐項驗證 release 設定。

## 4. 內建功能

### iCloud 同步（`docs/sync.md`、`packages/sync`）
- **沒有自己造密碼學輪子**，使用 Apple CryptoKit：AES-256-GCM 封存檔案、HKDF-SHA256 衍生金鑰、HMAC-SHA256 產生資料夾名稱（`packages/sync/ios/Core/SyncCrypto.swift:17-40`）。
- 金鑰來源：24 個 BIP-39 單字（256 bit 來自 `SecRandomCopyBytes`，`RecoveryPhrase.swift:12-19`）。因為熵已經是 256 bit，不做密碼拉伸，這個設計合理。金鑰存在本機登入鑰匙圈，`AfterFirstUnlockThisDeviceOnly`、不同步（`SyncKeyStore.swift:18-42`）。
- 沒有伺服器：同步檔案放在你自己的 iCloud Drive 資料夾（預設 `iCloud Drive/Ardia Sync`）。檔案有 AAD 綁定路徑、padding 到 1 KiB、不壓縮。
- 隨機 96-bit nonce 搭配單一長期金鑰，在這個資料量下碰撞風險可忽略；沒有金鑰輪替機制（推測，未見相關程式）。
- 威脅模型文件明確寫「不防護：有恢復詞的人、已解鎖的 Mac、被入侵的 Ardia 二進位」。
- 可選同步項目包含**密碼**（`apps/browser/src/sync/engine.ts:54`）；同步時由 Chrome API 讀出明文後封存（`docs/sync.md:305-324`）。意味著 Ardia 二進位或恢復詞外洩就等於密碼外洩。若不想承擔，不要打開。
- 是否有人獨立審過這套加密：沒有證據。

### 密碼 / passkey
- 密碼：Chromium 內建管理器（見第 3 項）。Passkey：只有 Touch ID，iCloud Keychain passkey 未支援（`README.md:81`、`docs/releasing.md:141-143` 說缺 Apple 的 entitlement）。

### 匯入其他瀏覽器
- `packages/import/ios/Core`：讀取 Chrome/Brave/Arc/Dia 等的 profile，用該瀏覽器的 Safe Storage 鑰匙圈項目（`Discovery.swift:39-49`、`ChromiumCrypto.swift:17,137`）解密密碼與 cookie；Firefox 用 PBKDF2（`FirefoxLogins.swift`）；也支援 Safari、CSV。這需要 macOS 跳出鑰匙圈授權提示，你應該逐次檢視。
- 此套件內我沒有找到任何網路呼叫（grep 無 `fetch`/`URLSession`），資料留在本機並交給 Chromium。

### uBlock Origin
- 內建完整版 uBO 1.75.0（MV2），從 `github.com/gorhill/uBlock` 的 release 下載，**SHA-256 寫死並於建置時驗證**（`packages/ardiacore/scripts/ubo.sh:6-7,19-25`）。1.75.0 目前是 uBO 最新版（2026-09-16，我用 `gh api` 查過）。
- 套件後修改（`ubo.sh:30-80`）：寫死擴充 key（固定 ID）、把 `<all_urls>` 換成 http/https/ws/wss、移除兩個訂閱/更新用的 content script、開啟 hyper-prefetch（`prefetchingDisabled: false`）、關儀表板（`noDashboard: true`，使用者在 issue #35 要求開放）。這些都已列在腳本裡，未見可疑修改。
- 備註：`prefetchingDisabled: false` 會讓 uBO 預先連線，對隱私略有影響，你可能想知道。

### 其他（會碰憑證的功能）
- 「Live folders」讓使用者貼 GitHub/Notion/Atlassian token 或做 Google Drive OAuth，token 存在 Keychain（`apps/browser/src/live/net.ts:63-65`）。Google OAuth 的 PKCE verifier/state 用 `Math.random` 產生，且 `code_challenge_method` 是 `plain`（`live/googleAuth.ts:8,31-32`），強度偏弱；影響範圍僅限這個可選功能的 localhost 回呼，風險低但不符合現代最佳實務。

## 5. 相依套件與建置

- JS：pnpm 11 + lockfile（`pnpm-lock.yaml`，約 837 個解析項目）；主要框架固定版本（`react 19.1.4`、`react-native 0.81.6`、`react-native-macos 0.81.9`），`expo ~54.0.37`、`zustand ^5` 為範圍版本，依賴 lockfile 鎖定。三個第三方套件有本地補丁（`pnpm-workspace.yaml:13-16`、`patches/`）。`esbuild` 的 build script 被關閉（`allowBuilds`）。
- iOS/macOS：CocoaPods，`Podfile.lock` 固定版本（Sparkle 2.9.6）。
- 引擎建置：從 `chromium.googlesource.com` 拉指定 tag（`engine/patches/build/01-sync.sh:13,19`），套 ungoogled-chromium 指定 tag 與 domain substitution，在維護者自己的機器（`~/chromium-build`，README 說首次 build 約 2 小時）編譯。
- 預建引擎 archive 由 GitHub release 提供，build 時用 `prebuilt-engines.tsv` 內的 SHA-256 驗證（`packages/ardiacore/scripts/fetch-engine.sh:63-65`）。注意這個 TSV 在同一個 repo、同一個維護者控制，雜湊只能防傳輸損壞，不能防維護者端被入侵。
- **沒有 CI**（repo 無 `.github/workflows`）。**沒有可重現建置**：我沒看到任何機制讓第三方能從原始碼重建出相同二進位。發佈流程由本機的 `scripts/release.sh` 與 AI 代理執行（`docs/releasing.md:175-179` 寫明「owner 已授權代理做完整發佈與部署」）。
- 簽章與公證：Developer ID（維護者個人名義，`docs/releasing.md:86`）、Hardened Runtime、notarize + staple（`docs/releasing.md:135-146`）。這證明二進位通過 Apple 的自動掃描，**不代表**它與原始碼一致。
- 授權義務：每個二進位旁都附原始碼（`docs/releasing.md:68-82`）。

## 6. 專案健康度

- 年齡與規模：GitHub repo 建立於 2026-06-19，但 git 歷史從 2026-09-25 才開始（推測歷史曾被重建或搬移，我沒查證）；約 393 星、35 forks、39 個 issue（`gh api` 結果）。目前版本 0.2.x，在 2026-09-25 到 2026-10-22 共發佈 39 個 stable、約 30 個 nightly。
- 維護者：`git shortlog` 顯示 1451 commits：mantrakp04 1445、其餘 4 位共 6 個。GitHub contributors：mantrakp04 1502、其餘各 1–3。**實質單人專案**。作者 GitHub 帳號 2021 年建立，有 62 個公開 repo，50 followers。
- 提交行為：每天 40–190 個 commit，commit 直接進 main（`AGENTS.md`）。`AGENTS.md` 說明使用 AI 子代理實作並以另一個模型做風險邏輯審查；這是流程自述，我無法驗證是否真的執行。**沒有任何簽章 commit**（`git log --format=%G?`：2 個 E、其餘 N）。
- 近期大改動：v0.2.22 才從 CEF 換成 ArdiaCore；v0.2.31（10-09）才換純 Chromium；v0.2.38（10-18）才升 Chromium 155；v0.2.39 之後引擎再改為 Helium 底（`d730de33`，10-22）。這是快速且頻繁的架構更動，不是穩定期。
- 沒有看到可疑的新 commit 或外部人員加入可疑程式；4 位外部貢獻者共 6 個 commit。我沒有逐個審查這 6 個 commit 的內容。
- 沒有 `SECURITY.md`，GitHub community profile 沒列安全政策。沒有漏洞回報管道的書面承諾。
- 正面：文件非常詳細（`docs/engine-build.md`、`docs/sync.md`、`docs/kill-switches.md` 解釋了每個決策與威脅模型）；有單元測試與 smoke 流程；開源且附原始碼；遙測預設關閉且有清洗；kill switch 設計受限。
- v0.2.39 之後，main 上又出現新的外部依賴：Helium 的濾鏡清單鏡像（`bc0dade8`、`80698ef3` 等，後續又在開關間反覆）、Helium 的 bangs 清單（`0cb7eebc`）。這些不在我審查範圍內，但代表網路行為在快速變動。

## Chromium 版本落差與追上游安全修補的速度

- v0.2.39 使用 Chromium `155.0.8059.84`（`env.sh:14`，commit `adee1f03`，2026-10-18）。
- 官方：Chrome 155 於 10 月初開始穩定版推出（[來源](https://piunikaweb.com/2026/10/01/chrome-155-rollout-desktop-android-ios/)），155.0.8059.84/.85 在 10-15 發佈，修 10 個漏洞含 1 個 Critical 的 Prerender UAF（[來源](https://piunikaweb.com/2026/10/19/latest-chrome-updates-security-bug-fixes/)）。我查到的資料中，155 的穩定版最新是 `.84`（Linux）/`.85`（Windows/Mac）；Chrome 156 已在 10-22 進入 early stable（`156.0.8078.12/.13`，[來源](https://chromereleases.googleblog.com/)）。
- 所以：v0.2.39 在小版本上落後官方約 `.84` vs `.85`（差一個 Mac 小版本，我查不到 .85 的內容差異），而 156 還在小比例推出。落差目前很小。
- 追修補速度（從 repo 歷史推算）：
  - 10-09 才從 CEF 154.0.28 換到純 Chromium `154.0.8037.97`（`0.2.31`）。在這之前使用的是 CEF 的 154 分支，不是 Chrome 官方穩定版的小版本。
  - Chrome 155 於約 10 月初放出，Ardia 的第一個 155 版是 10-18（`0.2.38-nightly.5`、`0.2.38`），**落後約 10–12 天**，期間 155.0.8059.79（10-13，7 個 Critical）也沒追上。
  - 155.0.8059.84 在官方 10-15 發佈後約 3 天就進了 repo。
- 判斷：目前每次上游更新要維護者手動重新 build（約 2 小時以上），沒有自動化追蹤上游的機制，因此落後天數取決於維護者當天是否有空。以每 2–4 週一個大版本、期間多次安全小版本的 Chrome 節奏，Ardia 比 Chrome 慢數天是常態，風險比官方 Chrome 高。未來若維護者停更，安全補丁就會停。
- 我無法驗證這些版本號在發佈的二進位內是否真如宣稱（只看到原始碼 pin 住的值）。

## 這次審查查不到的事

- **Chromium 本體**：只讀了 Ardia 加的補丁與程式；上游 Chromium、ungoogled-chromium 的補丁內容，與 Helium 的補丁，都沒審。
- **發佈的二進位是否與原始碼一致**：沒有下載或檢視 DMG/zip/引擎 archive，也沒有可重現建置可供比對。notarization 不能證明這件事。
- **維護者帳號與機器安全**：GitHub 帳號有沒有 2FA、EdDSA 私鑰與 Developer ID 實際怎麼保管、`ardia.dev` 主機（Fly.io）與 DNS 的安全，都無法從原始碼得知。
- **線上實際狀態**：`ardia.dev/switches.json` 與 `appcast.xml` 的實際內容、nginx 是否另外記錄 IP、遙測後端的保留與存取控制（`infra/telemetry` 我只看到存在，未細讀）。
- **未來版本**：本報告只對 `91e17a5`。v0.2.40 nightly 已換成 Helium 引擎、授權改 GPL-3.0、加入新網路依賴；我沒審。
- **程式碼覆蓋率**：我針對更新、連線、補丁、同步、匯入、uBO、建置做了定向閱讀與 grep，並非 1854 個檔案逐行審計。尤其 React Native 外殼的大部分 UI 邏輯與 `ardiacore_api.mm` 內文沒有讀完。
- **Google 登入是否可用**：本報告沒測，也不能由原始碼判斷。
- **第三方相依套件**：沒有逐一檢查 npm/CocoaPods 套件的原始碼或已知漏洞。

## 附：關鍵證據索引
- 更新：`apps/browser/macos/Ardia-macOS/Info.plist:117-126`、`packages/shell/ios/Updater.swift:9-13,97-102,200-219,261-300,341-346`、`infra/site/nginx.conf:127-156`、`docs/releasing.md:3-16,86-92,175-189`
- kill switch：`apps/browser/src/lib/killSwitches.ts:12-83,111-149`、`killSwitchesLaunch.ts:9`、`docs/kill-switches.md`
- 遙測：`apps/browser/src/telemetry/config.ts:1`、`client.ts:33-35,350-353`、`copy.ts:13-74`
- 引擎：`engine/patches/build/env.sh:14-15`、`gn_defines.sh:25-26,38`、`chromium-component-updater-security-only.patch:53-69`、`chromium-extension-updates.patch:23`、`ungoogled-status.tsv:10,21`、`engine/ardiacore/src/ardia/core/ac_main_delegate.cc:79-110`
- 同步：`packages/sync/ios/Core/SyncCrypto.swift:17-40`、`RecoveryPhrase.swift:12-19`、`SyncKeyStore.swift:18-42`、`docs/sync.md`
- uBO：`packages/ardiacore/scripts/ubo.sh:6-7,19-25,30-80`
- 搜尋預設：`apps/browser/src/store/settings.ts:79,83`、`packages/core/src/engines.ts`
- 專案：`AGENTS.md`、`git shortlog`、`gh api repos/mantrakp04/ardia/releases`
