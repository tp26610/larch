# Ardia 團隊與專案背景調查（調查日 2026-10-23）

範圍：只看公開的專案與專業身分資訊。標記說明：【證】有來源佐證；【推】我的推測。
GitHub 數據來自公開 API（api.github.com/repos/mantrakp04/ardia 等），官網來自 ardia.dev。

## 結論

Ardia 看起來是「單人開發、AI 輔助、極高速迭代、年資只有 4 個月」的專案。沒有找到詐欺或惡意的證據，授權與原始碼公開程度比一般新專案透明；但可信度的依據幾乎全是維護者自己發布的資料。

最大的不確定性有三個：
1. 單一維護者（1502 個 commit 中他佔絕大多數），沒有公司、資金或安全流程的公開說明，長期維護與 bus factor 風險高。
2. 專案極新且變動劇烈（4 個月內改名、換引擎兩次、每天多個 release），沒有任何第三方評論或安全審計。
3. 瀏覽器會經手密碼與登入狀態，而這個專案的快速節奏代表程式碼多半未經充分外部審視（commit 全帶 Claude 共同作者標記）。

結論是「可試用、不建議在沒有備案的情況下當唯一主力」；若要用，建議先觀察幾個月，或選擇 stable 版而非 nightly。

## 1. 維護者是誰

- 【證】GitHub owner `mantrakp04`，顯示名 Mantra，帳號 2021-07 建立，62 個公開 repo、50 followers，沒有加入任何公開組織。來源：https://api.github.com/users/mantrakp04
- 【證】NOTICE 檔寫 "Copyright 2026 Mantra Patel"。來源：https://raw.githubusercontent.com/mantrakp04/ardia/main/NOTICE
- 【證】個人網站 barreloflube.dev（暱稱 barrel of lube），列出作品：Ardia、Headspace（音樂播放器）、g-spot、versionless、just-use-convex、zunos、argus，以及 "Work" 分頁的 Orchid 與 Hexclave。沒有部落格、沒有職歷、沒有學歷。來源：https://www.barreloflube.dev 、https://www.barreloflube.dev/ardia
- 【證】X 帳號：barre_of_lube（由 GitHub profile 與個人網站連結）。我沒有進一步查看其內容。
- 【證】其他貢獻者極少：`matanyall` 3、`narasaka` 2、`Neel2107` 2、`louis-co` 1 個 commit，其餘全是 mantrakp04。來源：https://api.github.com/repos/mantrakp04/ardia/contributors
- 【證】官網沒有任何團隊或公司資訊，也無版權行。來源：https://ardia.dev
- 【推】他同時在做 Orchid 與 Hexclave，可能是工作或創業；我的搜尋沒能把 Hexclave 連到他。他的 fork 清單含 stack-auth，而搜尋結果說 Hexclave 是自架的 auth/payments/analytics 平台，我推測兩者有關，但沒有證實。Ardia 官網的分析工具與他 Ardia repo 的 PR 都出現 Hexclave Analytics，顯示他在自己的產品上自用。
- 查不到：真實職歷、雇主、演講、技術文章、過去是否維護過大型開源專案。

## 2. 專案歷史與活躍度

- 【證】Repo 建立 2026-06-19；最早 commit 為 2026-09-25，名稱「Netnyahoo: Dia-parity macOS browser on a patched Chrome-style CEF」，所以公開歷史實際只有約 1 個月（repo 建立日與首個 commit 間的差距原因不明，可能是歷史被重寫或先在別處開發，【推】）。總計 1510 個 commit。來源：https://api.github.com/repos/mantrakp04/ardia/commits
- 【證】原名 Netnyahoo，0.2.33（2026-10-12）改名 Ardia，資料遷移。網站原為 netnyahoo.com。來源：https://ardia.dev/release-notes/ 、docs/growth.md
- 【證】他早先有一個 fork `mantrakp04/browser`（上游 FujiwaraChoki/mori-browser，MIT，「OSS Arc Alternative」，Electron 系），之後才做 Netnyahoo/Ardia；兩者是否有程式碼承襲未查。
- 【證】Release 節奏：到 10/23 共約 74 筆，stable 從 v0.2.7（9/29）到 v0.2.39（10/22），約 3.5 週 33 個版本；另有每天數次的 nightly（v0.2.40-nightly.5 在 10/23）。版本號停在 0.2.x。來源：https://github.com/mantrakp04/ardia/releases
- 【證】引擎演進：CEF → 自製 ArdiaCore（0.2.22，10/2）→ 純 Chromium 154（0.2.31）→ Chromium 155（0.2.38）→ 0.2.40-nightly.5 改用 Helium 的隱私 patches。來源：release notes
- 【證】Star 392、fork 35、open issue/PR 39，Discord 邀請連結在 README。首頁備份快照曾寫 44 star，說明 star 在最近一兩週內暴增（【推】可能是 X 上的曝光，docs/growth.md 稱 91% 流量來自 X）。Discord 人數我沒有加入，查不到。
- 【證】近況：issue/PR 在 10/21-10/23 一天湧入約 40 筆，多為外部使用者的功能請求與 PR（Arc 的 peek、spaces、Homebrew 等），維護者自己開的 PR 也在其中。
- 【證】repo 內有 `.claude/`、`CLAUDE.md`、`AGENTS.md`；最近 100 個 commit 全部帶 "Co-Authored-By: Claude"（含 Opus 5.5）。來源：commits API
- 【證】repo 內有 `docs/growth.md`，是以「增加 Mac 下載量」為目標的成長實驗日誌（含 A/B 測試下載按鈕）。這是行銷導向的紀錄，非惡意，但表明專案以下載數為重要目標。

## 3. 資金與營運

- 【證】官網稱免費，無付費方案，未提資金。我沒有找到 GitHub Sponsors、Open Collective、募資公告或公司實體。
- 【證】基礎設施：官網自建分析（docs/growth.md 稱 9/30 起改存自己的 ClickHouse，之前是 PostHog Cloud EU）、自動更新（Sparkle）、Apple 公證。這些有固定成本（Apple 開發者帳號、主機、CI 與 AI 工具），由誰負擔未說明。
- 【推】商業模式不明；可能為個人作品集、成長導向，或未來衍生產品。我不能斷定任何一種。
- 風險：單人專案 + 無資金說明 + 作者同時有其他產品（Orchid、Hexclave），長期維護沒有保證。專案本身 GPL-3.0，若停更他人可以 fork，但一個需要 Chromium 持續安全更新的瀏覽器，停更本身就是安全問題。

## 4. 聲譽與外部評價

- 【證】我用多組關鍵字搜尋，沒有找到 Hacker News、Reddit、媒體、部落格的獨立討論或評測；搜尋結果幾乎都是他自己的 GitHub、官網與 release 頁，以及 3 個同名 fork。沒有找到針對 Ardia 的安全、抄襲、隱私質疑。這只代表搜尋引擎沒收錄，不代表沒有（搜尋工具僅限美國且對新內容覆蓋差；X 與 Discord 無法搜尋）。
- 【證】8 倍效能宣稱：官網寫冷啟動到視窗出現，Ardia 中位數 280 ms，Dia 2262 ms；對 Helium 只快 26%，且官網自己列出 Helium 在分頁切換、還原分頁繪製勝出。環境是 M5 Pro 48GB、2026-10-19、Ardia 0.2.38-nightly.8、Dia 1.53.0、Helium 0.19.3.1，每項 3 至 6 次取中位數。方法文件在 repo 的 `docs/perf/`（含 `vs-browsers.md`）。我沒有重現測量。評語：只比冷啟動，用 nightly 版，由作者自己測，可信度屬「自報、未獨立驗證」；官網對 Helium 較勝處有揭露，這點誠實。
- 【證】Issue 區可看到真實使用者回報 bug（白畫面、IME、浮動側邊欄），維護者與數位外部貢獻者都有動作；10/16 有外部 PR 被合併。

## 5. 與其他專案的關係

- 【證】Helium（imputnet/helium-chromium，GPL-3.0）：0.2.40-nightly.5 起 Ardia 引擎以 Helium 的 patch 系列為基礎；NOTICE 因此宣告「Ardia 整體發布版本為 GPL-3.0」，Ardia 自己的原始檔另以 Apache-2.0 授權（可併入 GPL）。官網頁面只把 Helium 當對手，只在「Built on」寫 Chromium 與 uBlock Origin，沒寫 Helium；但 NOTICE 與 release notes 有完整標註。來源：NOTICE、release notes
- 【證】NOTICE 另列：Chromium、ungoogled-chromium（BSD-3，經 Helium）、Chromium Embedded Framework（早期用 CEF）、uBlock Origin（GPL-3.0，內建為獨立擴充）、Sparkle、Kagi/imput 的 bang 清單、React Native macOS（UI 殼）。
- 【證】與 Dia、Arc：官網聲明不隸屬 Google 或 The Browser Company；產品是仿效，非衍生程式碼。repo 有 `docs/dia-spec.md`、`dia-feature-parity.md`，是對 Dia 行為的規格整理；內容是否涉及商標或介面素材我沒有查，未見他人提出質疑。
- 【證】與 Brave、Vivaldi：官網與文件沒有宣稱承襲；我沒有找到關聯。
- 【證】README 的分類「Arc 的側邊欄、Dia 的精緻」直接以其他產品命名，屬行銷用語。
- 注意：在 0.2.40-nightly.5 之前引擎並非 Helium 基礎（0.2.31 稱純 Chromium、早期為 ungoogled 系列與 CEF patch），意味著隱私與安全補丁的基準在最近一週內才換；這個變動尚未經過時間檢驗。【推】

## 6. 風險訊號與正面訊號

風險訊號
- 單人主導，無公司、無資金說明、無聯絡安全問題的管道（repo 根目錄 API 查不到 `SECURITY.md`，.github 目錄也不存在）。來源：GitHub contents API
- 專案年資極短，且公開 commit 歷史只有約 1 個月；4 個月內改名、換引擎兩次。來源：releases、release notes
- 發版與 nightly 過快，每天多版；commit 全數由 AI 協作，審查深度未知。來源：commits API
- 成長導向行銷（docs/growth.md、官網 8 倍宣稱、「Touch grass」風格文案），並有網站分析資料收集；App 內遙測有揭露（Settings › What's Sent，崩潰回報選擇加入，另有每次啟動讀取 `ardia.dev/switches.json` 的 kill-switch 請求，文件稱無 cookie、無 ID）。這是自述，需以程式碼審查驗證（由另一個 session 負責）。來源：docs/kill-switches.md、README
- 8 倍效能宣稱只限冷啟動、自測。來源：ardia.dev
- 我查不到維護者的職歷；個人網站與 X 暱稱是玩笑風格，這本身不是問題，但無法佐證專業信譽。
- 外部貢獻者的 PR 數量在最後幾天暴增，其中有機器人帳號 `posthog-eu[bot]` 開的 PR（來源：issues API）。【推】可能是自動化流程；仍應留意供應鏈（誰能合併、是否有雙人審查）。

正面訊號
- GPL-3.0 與 NOTICE 完整，且在 10/22 才補上；會承認上游（Helium、ungoogled、CEF、uBlock），並在官網揭露 Helium 在某些項目比自己快。
- 原始碼公開、release 附原始碼說明（NOTICE 稱每個 release 連結對應的 tag 與引擎 patch 系列）、Apple 公證。
- 安全修補有跡可循：0.2.37 將已儲存密碼放在 Touch ID 之後，並預設關閉 AppleScript 執行頁面 JS；0.2.39 封鎖 8 張外洩的 eMudhra 中繼憑證；CRLSet 更新說明為無 install ID、無 cookie。來源：release notes
- 有真實外部使用者與貢獻者在 issue/PR 活動；有 Discord；維護者在 PR 與 issue 上活躍。
- 作者有不少其他公開作品與多年的 GitHub 歷史（2021 起），不是剛建的空帳號。

## 查不到或未驗證

- 維護者真實職歷、雇主、與 Orchid/Hexclave 的實際關係。
- 公開歷史早於 2026-09-25 的 commit（repo 建立日為 6/19）。
- Hacker News、Reddit、X、Discord 的實際討論內容與規模。
- 8 倍宣稱的獨立重現。
- 是否有第三方安全審計、漏洞通報紀錄。
- 「Netnyahoo」改名的原因（搜尋與 release notes 都未說明）。
