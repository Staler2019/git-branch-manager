# fix/diff-auto-refresh-takes-index-lock — #194 的 `index.lock` 持有者與四條路徑

## Situation

#194：stage 一個 hunk 之後立刻 unstage，偶發 `LockHeld`（`argv:[]`，代表擋在 preflight，git 還沒跑）。
TSan job 上也出現過同一個紅燈。`GitCommand.h` 寫著持有者「never identified」，並用
`worktreeReadFlags()` 蓋住 fsmonitor 機器上的 9/12 失敗。

使用者的公司 repo 是大 repo：日常約 20 檔變更，即將有約 3000 檔的 MVC 轉六角重構。
只修鎖、讓大 repo 變慢不被接受：「我在意大repo情境」、「請務必提出可以解決這種bug的解法，避免修一半」。

## Task

找到持有者，把所有會拿鎖的路徑都處理掉，效能退步要有數字也要補回來。
使用者裁決（「照建議」）：A–E 全做；刷新在每次成功寫入後與視窗焦點時觸發，最多每 30 秒一次；
lock 等待上限 2 秒；測試暫存路徑也改成每個 process 獨立。

## Action

持有者是 `git diff` 結束時的 auto-refresh（`diff.autoRefreshIndex`）。遇到內容沒變、stat 已舊的 entry
就更新 index 並拿鎖，`--no-optional-locks` 擋不住。`git apply --cached` 留下的正是這種 entry，所以 stage
之後的背景 `diff --numstat` 會和下一次 unstage 的 preflight 相撞。

量測（git 2.56，global config 中性化）：

| 指令 | index 被改寫 |
|---|---|
| `--no-optional-locks diff --numstat` | 5/5 |
| 加 `-c diff.autoRefreshIndex=false` | 0/5 |
| `diff --cached`、`status` | 0/3 |

```
會拿 index.lock 的來源                    處理
1. app 的背景 diff                   →  A  globalFlags 關 auto-refresh
2. app 的寫入                        →  已由 OperationRunner 序列化（查過，全部走 operation）
3. 外部程序（IDE、終端機）            →  B  preflight 最多等 2 秒
                                        C  git 自己回報拿不到鎖時，冪等的 index 操作重跑
4. A 造成的效能缺口                  →  D  背景 update-index -q --refresh，最多每 30 秒一次
```

**D 的行為**：`Operation::isHousekeeping()`，不記 undo、不寫 Starting log、遇到鎖立刻放棄不等待。
`isBackground()` 為真，使用者操作進來會取消還在排隊的刷新；已在跑的跑完，因為殺掉 git 可能留下鎖。
入口是 `Session::refreshWorkingCopy()`，寫入成功與焦點刷新都經過這裡。時間戳在送出時記錄，
所以被取消的那次要等下一個超過 30 秒後的觸發才補上。

**E 的量測**（`core.fsmonitor=true`，`UnstageHunkReversesAFullyStagedSingleHunkFile`，每格 30 次，
B 的等待、C 的重試、D 全部關閉）：

| | `worktreeReadFlags` 開 | 關 |
|---|---|---|
| `autoRefreshIndex=true` | 0/30 | 27/30 |
| `autoRefreshIndex=false` | 0/30 | 0/30 |

第一輪矩陣沒有關 D，四格都是 0/30，連對照組（旗標關、autoRefresh 開）也沒重現。D 會掩蓋這個競態，
這一輪無法判讀，關掉 D 重跑才得到上表。候選組合（旗標關、autoRefresh 關、D 開，B 和 C 關）再跑 100 次是 0/100。
單獨關掉 auto-refresh 就讓 27/30 歸零，由此判斷 fsmonitor 上的 9/12 和 #194 是同一個來源；git 內部的路徑沒有另外追。

10 萬檔 repo（fsmonitor daemon 運作中，7 次中位數，`diff.autoRefreshIndex=false`）：

| | 帶旗標 | 走 daemon |
|---|---|---|
| `diff --numstat`，乾淨工作目錄 | 90 ms | 110 ms |
| `diff --numstat`，20 檔已改 | 95 ms | 105 ms |

`worktreeReadFlags()` 因此保留：鎖安全已不靠它，但刪掉不會更快。這是速度上的選擇，紀錄已就地改寫。

`globalFlags()` 註解裡的 734 / 1065 / 11 ms 來自另一個探針（小 repo，5000 個 stat-dirty、約 200 行）：
關掉 auto-refresh 後每次 diff 734 ms；開著時第一次 1065 ms，之後 11 ms。

**D 的效能依據**（10 萬檔 synthetic repo，5000 個 stat-dirty、約 40 行，index 7827 KiB，global config 中性化）：

| | status | diff --numstat | update-index --refresh |
|---|---|---|---|
| 乾淨 | 223 ms | 104 ms | 106 ms |
| 從不刷新 | 3597 ms | 1573 ms（autoRefresh=false） | 第一次 604 ms |
| 刷新之後 | 205 ms | 102 ms | |

沒有 D 的情況下，3000 個同內容檔案線性估算 status 約 2.2 s、diff 約 1 s；這是估算，不是量測。

**測試暫存目錄**：fixture repo 只用測試名稱命名，平行 process 會互相刪除。8 個平行、5 輪，同一個測試：
共用 37/40 失敗，獨立 0/40。改在 `TestMain` 設定一次，不動約 60 個 `temp_directory_path()` 呼叫點，
新 fixture 也就不會忘記。

**Mutation**（跑的次數與變紅的測試數分開記）：

| Slice | 跑 | 紅 | 備註 |
|---|---|---|---|
| A | 1 | 2 | |
| B | 4 有效，2 作廢 | 見右 | 前兩個 mutant 因 `-Werror` 編不過，作廢後用 `(void)` 重做。cancel 檢查的 mutant 只紅 `CancellingDuringTheWaitReportsCancelledNotLockHeld`。stale、等待中取消、`stopping_` 三個 mutant 在 `timeout 60` 內沒有 PASSED 摘要，是等滿 60 秒的 hang 紅，不是逐一測試的窄紅 |
| C | 3 | 1, 1, 1 | |
| D | 5 | 各 1 | `isHousekeeping` undo 分支、節流邊界、`isBackground`、Session 節流各紅 1 個；lock 等待是 60 秒逾時紅（`YieldsAtOnceToAHeldLockWithoutRunningGit`，該分支尚未實作時已看過同樣的紅）。未接線時 capi 兩個新測試都紅 |
| 暫存目錄 | 1 | 1 | |

**獨立驗證推翻了第一版 D 與 B（`verifier` 判定 REFUTED）**，全部測試當時是綠的：

| 問題 | 量測 | 處置 |
|---|---|---|
| stash pop 衝突後是 UU、沒有 `MERGE_HEAD`，`update-index` 回 1，status bar 冒出無從處理的紅色錯誤 | capi 實際走流程，record 是 `exitCode:1`、`benignExit:false` | `benignExitCodes = {1, 128}` |
| 寫入完成後讀 repo state 撞上 refresh 持鎖，status bar 留下假的 another Git process | 探針延遲 10 ms 讀取：小 repo 35/40、2 萬檔 repo 20/20；refresh 關閉對照 0/30 | `OperationRunner::state()` 比對 housekeeping 邊界，鎖是自己的就不回報；`Session::repoState` 改走它 |
| `submitWorkingCopyOperation` 不在 `inFlight_`，close 時 `cancelOperations(0)` 碰不到；持鎖時每個排隊操作等滿 2 秒 | 3 個排隊 6261 ms，修正後 195 ms | `OperationRunner::prepareForShutdown()`，並取消排隊與之後送入的背景工作 |

第一版把「silent: no event」寫得太滿。修正後 refresh 仍會發兩筆 `GBM_EVENT_OPERATION_LOG_RECORD`，Log 面板多一列。
這是刻意保留：Log 記錄的是實際跑過的每個 git 指令，藏掉一個會拿鎖的指令反而不誠實。status bar 不會顯示它
（`_taskKind` 對 `update-index` 回 null）。

## Result

全套測試：`capi-only` 996/996（721 core、274 capi、1 integration）。修正後重跑 `verifier` 的探針：延遲 0–20 ms 讀 repo state，`indexLocked` 各 0/40（修正前 10 ms 為 35/40）；持鎖 close 3 個排隊操作，探針只計 close 本身是 0 ms，上表的 195 ms 是整個測試的時間。第二輪 fresh `verifier` 判定 CONFIRMED，並另外在 TSan 下跑過相關測試，無警告；P3、P4 建議依規則不再改動行為，列在下面。`capi-only` 的 `LastTestsFailed.log` 可能留著舊內容（當時只建了 `gbm_capi_tests`，
`gbm_core_tests_NOT_BUILT` 顯示失敗），以 `LastTest.log` 的 Failed 數為準。沒有改動 Dart，因此未跑 Flutter 與 device tier。

**還沒解掉的部分**：

- 外部程序持鎖超過 2 秒，使用者仍會看到現有的 Retry 對話框，這是刻意的。
- 使用者寫入會排在執行中的 refresh 後面，大 repo 上最多延遲一次 refresh（106–604 ms），最多每 30 秒發生一次。
- refresh 持鎖期間，使用者在終端機跑的 `git add` 可能失敗；窗口同上。這一輪修掉的 `git diff` auto-refresh 窗口更頻繁，每次背景 diff 都可能遇到。
- 外部程序在 refresh 期間持鎖，`state()` 要到 refresh 結束後的第一次讀取才回報；stat-dirty 的 2 萬檔 repo 量到最多隱藏 517 ms。
- 關閉 session 時若外部程序短暫持鎖，排隊中的寫入會失敗而不是等待（持鎖 30、100、500 ms 都是如此）。`main` 本來就不等，所以不是回歸。
- `Session::repoState` 改走 `OperationRunner::state()` 這條接線沒有測試：改回 `RepoState::read` 時 274 個 capi 測試全綠，目前只有探針證明。
- exit 128 一律視為 benign，損毀的 index 不會由 refresh 回報；status 讀取是否回報沒有查。
- C 只涵蓋 stage、unstage、partial stage。其他寫入在 preflight 之後才失去鎖時仍回報 `LockHeld`，因為多步驟操作重跑不安全。
- `ProcessTempDir` 和 D 的 Windows 行為只有 Windows CI 看得到，本機沒有驗證。
- 100k repo 第一輪的 `diff`（auto-refresh 開啟）量到 10402 ms，只有一個樣本，原因沒查，沒有當成證據。

**過程中改正的錯誤**：Slice D 的 commit message 一開始寫錯 mutation 次數，push 前已 amend。
ledger 初版寫的 `core-only 985/985` 是當時那次 ctest 的輸出，`verifier` 在同一棵 build tree 量到 987（`GBM_BUILD_CAPI` 已是 ON），這裡改以最後一次為準。
`worktreeReadFlags()` 文件裡「git reads never create `.git/index.lock`」與 holder never identified 都已就地劃掉改寫。
