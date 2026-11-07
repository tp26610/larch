# 開發工作流程

CLAUDE.md 放架構與決策；這裡放「怎麼做事」。開工前不必全讀，遇到對應情境再看。

## 驗證 UI / 行為改動
- 改完功能先跑 `scripts/smoke.sh`。跑之前確認沒有已安裝的 Larch 在執行（`pgrep -fl Larch`），有就 `osascript -e 'tell application "Larch" to quit'`；它會跟 smoke 搶 key window，造成偶發失敗（見 CLAUDE.md 第 24 點）。
- 會影響畫面或候選列內容的改動（包含排序、比對規則，不只樣式），要重新安裝真實 app 才算驗證：`scripts/install.sh`，再 `open -a /Applications/Larch.app`。只跑 build 與 smoke 時，已安裝的舊版仍帶著舊行為。
- 實測有問題時先看 Larch 自己顯示的畫面（錯誤頁、截圖），再判斷是網站還是 Larch 的問題。
- `install.sh` 預設用鑰匙圈裡的 Developer ID 簽章（身分固定，不會每次重新詢問 keychain 存取）；找不到憑證才退回 ad-hoc，此時每次重建簽章都會變，macOS 可能重新詢問，是已知現象不是 bug。

## 網頁行為「沒反應」的除錯
不要憑印象猜網頁怎麼觸發，先看實際事件。2026-11-02 的 Slack 登入交接就是前兩次改錯路徑：真正的觸發點是隱藏 iframe（`main=false`）載入 `slack://`。
1. 暫時在 `Tab.decidePolicyFor`、`createWebViewWith` 記下每個事件（URL、是否主框架、`navigationType`），**含子框架**。
2. 紀錄寫到 `/tmp/larchdbg.log`（用 `FileHandle` 追加）。**`NSLog` 在 `log show` 裡抓不到**，別用。
3. 安裝除錯版，實際操作一次再讀紀錄。
4. 查完 `git checkout` 還原除錯碼，再做正式修正。

## 可行性 PoC
- 在拋棄式分支做；結論（驗證了什麼、用了哪些私有 API、哪些假設成立）寫進 `BACKLOG.md` 該項目下並標日期，程式碼分支刪掉。
- 任何除錯用的命令列旗標都要同時加 `--smoke`，否則會讀寫真實的 `~/Library/Application Support/Larch/`（macOS app 忽略 `HOME`，沒有別的隔離方式）。同時確認 `AppDelegate` 的「命令列網址」迴圈不會把旗標參數當成網址開成 Tab（參考 `--open-palette` 的略過寫法）。

## BACKLOG 估點
Story point 只用 1 / 2 / 3 / 5 / 8 / 13 / 21 / 40 / `?`。例外：Epic 拆成子項目時，每個子項目仍須在刻度內，Epic 總計可以是子項目的原始加總（如 25）。

## 發版
- repo：`tp26610/larch`（公開）。標籤用純 semver：`v0.1.0`、`v0.1.1`…，與 `VERSION` 一致。
- 版本號由作者（或 Claude）直接決定：修正與小功能升 patch，明顯的大功能才升 minor；發版摘要寫出選的版本與一句理由。
- 流程：改 `VERSION` → `scripts/dmg.sh` → commit → 打同名 tag → push main 與 tag → `gh release create <tag> --title "..." --notes-file <檔案>`，附上 dmg。
- Release notes 用繁體中文、結果先行：一行說明，接 `##` 分段（新增 / 修正；首發版用「核心功能 / 已知限制」），每點寫使用者看得到的行為變化，不要貼 commit 清單。patch 版結尾可附 compare 連結 `https://github.com/tp26610/larch/compare/vX...vY`。
