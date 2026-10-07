# fix/slow-machine-log-and-timeouts — Windows 慢機器：中文路徑、失敗看不見、逾時一律有限

## Situation

使用者在一台 Windows 公司電腦（兩個資安掃描程式、很卡）上，對 .NET 專案做了 MVC→分層搬移
（約 1500 個檔案搬移＋namespace 改寫）。之後 merge 衝突不顯示、worktree 面板是空的（資料夾卻
已建立），而且底部 Log 抽屜看不到失敗的指令。使用者的判斷是逾時太短。repo、branch、worktree
名稱含中文；commit message 是 git 預設。

讀碼確認的缺口：

- ~100 處寫死的讀取逾時（status 120 s、numstat 120 s×2、worktree list 30 s），量測基準全是
  macOS。
- App 層錯誤（`GBM_EVENT_ERROR_OCCURRED`）只寫 `lastError`，不進 Log。
- 衝突清單只來自 status＋numstat 這一次讀取，任一失敗整個失敗。
- 讀取還沒結束就沒有任何 Log 列。
- Windows 上 narrow `std::filesystem::path` 用系統代碼頁，UTF-8 中文的續位元組不是合法 Big5
  trail，轉換有損。
- 28 處 `timeout = 0` 的指令靠 10 分鐘閒置上限，8 處 stash 是 600 秒，三處（`reset --hard`、
  `push --delete`、`rebase --continue`）完全沒有上限，`CatFileBatch` 的每次請求也沒有。

「完全沒看到失敗列」不能直接推論為逾時：H1 逾時、H2 讀取尚未結束（最壞 6 分鐘以上才有紀錄）、
H3 非 git 錯誤（今天不進 Log）、H4 Log 被清空。本輪沒有在使用者的機器上重現，所以哪個假說是
真因**仍未驗證**，見 Result 的回報清單。

## Task

使用者的裁定（原文見計畫檔，這裡只留結論）：

1. 錯誤必須在 Log 看得見、逾時拉長；先修看不見的失敗指令。
2. numstat 逾時不得拖垮衝突清單；讀取進行中也要有 Log 列；worktree 建立／列出指令要進 Log。
3. 「無時限的改為有時限，以後沒有沒時限的東西」；網路指令「沒有作用或超過 1 分鐘沒有資料傳輸
   就卡掉」，本地動作「使用者的耐心最多就 5 分鐘」；`CatFileBatch` 一併改。
4. 介面用時限**倍率**（不是統一秒數）：拖拉四段＋右側自由輸入；不顯示秒數，但 debug 時要知道每個
   指令的實際時限。
5. C3：Working Copy 內一行提示。D3：新增 RUNNING 字樣、最後面不寫「執行中」；時限欄與欄名列各是
   Developer 裡的獨立開關；Developer 分組依畫面區域命名，不帶 branch 名。
6. CI 可用，但不得併回 main：draft PR #177 `[DO NOT MERGE]`，不 merge、不 mark ready。

## Action

分支 `fix/slow-machine-log-and-timeouts`，每顆 commit 可單獨 revert（`git log origin/main..HEAD`
為準）。

- **F（路徑）**：`FsUtil` 新增 `utf8FromPath`；路徑進出 C++ 一律走 UTF-8（含 `canonicalKey`）；
  `scripts/check-narrow-path-conversions.py` 進 CI。F-a 只有測試、Windows capi job **紅**；F-c
  之後轉綠。紅在哪一個斷言沒有在這份記錄裡重抄——以 PR #177 的 run 歷史為準。
- **A（看得見）**：App 層錯誤寫進操作紀錄；紀錄以正規化路徑與 linked worktree 認領，空
  `repoDir`（clone／init，argv 可能帶 token）不派給任何 session。
- **B（倍率）**：process-wide 倍率（`setTimeoutMultiplier`）、capi、偏好在 `sessionOpen` 之前推送。
- **C（numstat）**：status 成功而 numstat 非取消地失敗時仍發佈檔案與衝突清單，
  `lineCountsUnavailable = true`；Cancelled 仍整個失敗。C3 在 Working Copy 看板上方一行提示。
- **D（running）**：core 在 spawn 後記 `running` 紀錄，結束時同 id 再記；Dart 以 id 原地取代、找不到
  （已被筆數上限修剪）就 append；`operationLogRevision` 取代 append／取代都 +1，未讀改比 revision。
- **E（解碼）**：事件資料解碼失敗寫進操作紀錄而非靜默丟棄；E1（U+FFFD 替換）經 plan-verifier 撤回，
  因為替換過的字串會經 Dart 回寫進 repo。
- **逾時一律有限**：`effectiveDeadlines()` 是唯一出處。本地＝`min(宣告或 300 秒, 300 秒)×倍率`；網路＝
  無總時限、閒置 60 秒×倍率。網路指令加 `--progress`（lfs 用 `GIT_LFS_FORCE_PROGRESS=1`），stderr
  的 `\r` 重繪只留最後狀態。`CatFileBatch` 每次請求 30 秒×倍率，watchdog 殺子行程、回 Timeout、
  寫一筆 TIMEOUT 紀錄、下次自動重開。
- **介面**：Preferences 倍率（四段拖拉＋自由輸入）；Log 抽屜 RUNNING 列（accent、旋轉 loader、
  減少動態不轉）、固定欄寬（耗時 72 靠右、exit 44、時限 84）、欄名列與時限欄各一個開關（預設關）；
  匯出一律帶時限。每個值的出處：`docs/claude-design-demo/slow-machine-timeouts-spec.html`。

### 計畫與實際的差異（更正）

- ~~`OperationLogApiTest` 的 identity 測試不受 running 紀錄影響~~ 受影響，也要只數 `!running`。
- ~~普查：28 處 `timeout=0` 都帶 10 分鐘閒置上限~~ 另有三處完全無上限（`reset --hard`、
  `push --delete`、`rebase --continue`），已補。
- 計畫寫「`GitCommand` 加 `bool network`，呼叫點宣告」；實際改成從 argv **集中分類**
  （`isNetworkCommand`）。理由：28 個呼叫點逐一宣告會漏，漏掉就變成本地 300 秒——對一次大 fetch
  是錯的。代價：新增網路指令要記得進這一份清單。
- 計畫的網路清單含 `ls-remote`；實際移除。app 沒有呼叫點，且它不接受 `--progress`——全套第一次跑時
  3 個 `RemoteRepoTest` push 測試因 fixture 的 `ls-remote` 被加上 `--progress` 而紅。
- 偏離 spec：RUNNING 是第四個層級字（LOGRULES 只有三級；篩選時算 Info）；C3 與 P10 第 5 項
  「背景作業失敗僅留在 status bar 與 log」相左，依使用者裁定顯示。
- cat-file 的 `kRequestDeadline` 30 秒是**提案數字，不是量測**。

### 已知殘留

- verifier（CONFIRMED）的 P3：`collapseCarriageReturns` 在 `\r` 當下清行，進度列在 `\r` 後被砍斷時
  最後狀態整段消失（本輪引入）。已修，見 `fix: 進度列在 \r 後被砍斷時保留最後狀態`。
- verifier 的 P4：倍率只在建立 session 時推給 core，歡迎畫面（還沒開任何 repo）的 clone 跑在 ×1；
  session 未開時改倍率也不會推。~~**未修，待使用者決定。**~~ 使用者裁定「just fix it here」：
  改由 `gitTimeoutMultiplierSyncProvider`（GbmApp watch、session 開啟前 read）推送，見
  `fix: 逾時倍率由 app 推給 core，不再只在開 repo 時推`。
- verifier 的 P4：push/pull hook 靜默超過 60 秒×倍率會被砍（原本 10 分鐘）。符合裁定「超過1分鐘沒
  有資料傳輸就卡掉」，記錄行為變化，不改。

- `CatFileBatch` 逾時後「不 poison」的 mutation 存活：死掉的 pipe 在 `exchangeLocked` 內已經 poison，
  該行只涵蓋「回答與 kill 同時到達」的競態，無法穩定製造；註解已說明。
- C3 出現時看板高度門檻上移 26px（2×96+5+26）。`working_copy_view` 本來就沒有替看板保證高度下限，
  小視窗下早已會溢出；本輪未改。
- `GIT_LFS_FORCE_PROGRESS` 的行為**未實測**~~（本機沒有 git-lfs，兩個 lfs 測試 SKIPPED）~~。
  **更正**：CI 的 runner 映像裡有 git-lfs，兩個 lfs 測試在 CI 五個 job 都真的跑過；但它們只測
  track/untrack/add，沒有任何測試透過 pipe 跑 `git lfs fetch/pull/push` 看進度輸出，所以仍未實測。追蹤於 **#178**。

## Result

- 本機：core 557 passed（2 skipped＝lfs）、capi 181 passed、Flutter 3241 passed、`flutter analyze`
  0、格式乾淨、`check-narrow-path-conversions` 乾淨。
- Mutation（每顆 commit 各記「跑了幾個／幾個測試紅」）：numstat 2/2、running 6＋2、逾時倍率與有效時限
  4、本地 300 秒 4、網路 5×1、cat-file 5 有效（含 1 存活）、C3 4、RUNNING 列 7、revision 6、欄與欄名列 7、
  LOG 開關 7（M2 第一次存活，補測試後重跑變紅）。
- CI：~~**Windows 的進度測試結果以 PR #177 該次 run 為準**（`ProgressOnStderrAloneKeepsAChildAlive`、
  `AFetchReportsProgressThroughThePipe`）；本檔寫成時尚未看到，不在此宣稱 Windows 可用。~~
  **更正**：run 37639308439（HEAD bd8b57e）的 `capi (FFI) - Windows` 736/736 通過，兩個進度測試與
  兩個 `CatFileBatchDeadline` 測試都是 `Passed`（ctest 對 gtest skip 會印 `***Skipped`，所以是真的
  跑了）。這證明 Windows 的 stderr 執行緒把進度算進閒置時限；使用者機器上的真因仍未驗證。
- **使用者的機器上哪個假說（H1–H4）是真因，仍未驗證。** 裝新版後請在 Windows 上：重現一次、等
  ≥7 分鐘、Log「Save as…」匯出；回報 status／`diff --numstat`／`worktree list` 各列是 TIMEOUT、
  ERROR 還是不存在及其耗時；有沒有 App 層 error 列與「資料無法解碼」列；期間是否重開過 repo。再以
  倍率 2×／4× 各試一次，數字回填這裡並決定預設倍率。打開 Developer → LOG 的兩個開關可直接讀到每個
  指令的時限。
