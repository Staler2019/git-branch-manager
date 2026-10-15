# 狀態列顯示執行中的 git 動作，Cancel 交給 core 依 unit 判斷

## Situation

使用者回報：除了 `Reading history`，fetch / pull / push 等動作在右下角都沒有進度條，只能開 log 看 RUNNING 列。

查到三件事：

- `WorkspaceScreen._backgroundTasks()` 只產生 history scan 與停在衝突的 sequencer 兩種任務；`BackgroundTask.fetch/pull/push/checkout/merge/rebase` 六個 factory 有單元測試、沒有任何 caller（孤兒第 14 例）。
- 總數未知的任務畫 `value: 0.0` 的靜止空條與 `N/0`，看不出有沒有在跑。
- `gbm_cancel_operation` 依先前裁定沒有 Dart caller（`[DRIFT-cancel-capi-unwired]`）；`Operation::killableMidFlight()` 有覆寫、`src/` 沒有讀者（孤兒第 15 例）。

## Task

使用者裁定（2026-10-15，原文）：

1. 「這輪先不取消，但是需要檢查，capi 中有 gitlock 會產生的動作都不能取消。如果發生 io 意外或是動作意外需要 rollback。」
2. 「看 capi 怎麼包這個 unit 動作，如果包一起就不可以取消。」
3. 「rollback只做capi 的單個 unit動作，capi 處理、照樣拋錯到 flutter、但不損壞 git 為前提，需要考量各種可能 edge case，做穩定。」（S3，另輪）
4. 「實作不是用 cancellable 喔。維持之前決策，吃cancellationToken 如果capi吃的到cancellationToken。如果真的 cancel 了，capi不行cancel 會拋錯。=> 因為cancellation目前包含，timeout 處理、stack cancel 傳遞等等。」— 推翻了本輪第一版 commit 2（UI 旗標 `cancellable`），該版未 commit，檔案留在 scratchpad。
5. 「對，S2 的 capi 提前到這輪」
6. G1：Checkout／Merge／Rebase 的 Cancel 可按，由 core 拋錯；總數未知的計數「改spec，沒有計畫」；標籤照列；`+N more` 改 `+N task`。

## Action

```
Cancel(task) ─ queuedOperationId ─▶ gbm_cancel_operation ─▶ Session::cancelOperation(id)
                                                              └▶ OperationRunner::cancel(id)
   queued            → trip，什麼都沒跑         Cancelled
   running+killable  → trip                     Cancelled
   running+!killable → 不 trip、ERROR_OCCURRED  NotCancellable
   找不到             →                          NotFound
```

| commit | 內容 | mutations-run / tests-reddened |
|---|---|---|
| `0f8d218` | 不定進度條、`N` 不畫 `/0`、linger 畫滿格、`stoppedSequencer` 靜止條；原地更正 `[TEST-no-pumpandsettle-with-spinner]` | — |
| `6181866` | `OperationRunner::cancel(id)` → `Cancelled/NotCancellable/NotFound`，讀 `killableMidFlight()` | 4 / 1,1,1,1 |
| `ced72b4` | 全程序唯一的 queued id、`QueuedOperationScope`、`OperationRecord::queuedOperationId`、JsonCodec 輸出 | 6 / 1,2,1,1,1,1 |
| `9f418b6` | style：測試行超過 100 欄 | — |
| `4887c9e` | capi `cancelOperation(id)`、`GitError::Code::NotCancellable`、log 依接收 session 決定是否帶 id | 5 / 1,1,2,1,1 |
| `9b3774e` | Dart 綁定、`OperationRecord.queuedOperationId`（缺欄＝0）、`cancelOperation(int)` | 4 / 1,1,2,1 |
| `1fb8558` | `running_git_tasks.dart`、`BackgroundTask.gitCommand` 取代六個孤兒 factory、`+N task` | 10 / 1,20,1,1,1,1,3,1,1,3 |
| `a127b5a` | 使用者取消不寫 `lastError`；NotCancellable 照常顯示 | 3 / 1,1,1 |
| `8d0aec6` | device：`status_bar_cancel_flow_test.dart`（pre-receive hook 卡住 push），Windows 1/1 | 2 / 1,1 |

偏離計畫，照實記：

- 欄位名從計畫的 `operationId` 改為 `queuedOperationId`：record 已有 `id`（log record id），兩個 id 並存時 `operationId` 讀不出是哪一個。
- 其他 session（linked worktree）的操作不出現在本 session 狀態列：接收 session 的 record id 為 0，無從取消，也就不畫。
- 排隊中、尚未 spawn git 的 op 沒有 running record，狀態列看不到也無從按 Cancel；排隊取消只在 `OperationRunnerCancelTest` 驗證，capi 層無法穩定讓 op 停在 queue（已在測試檔註明）。曾告知使用者「排隊中的任務在 log 也看不到」，待使用者決定是否處理。
- 計數不畫：spec 頁 10 的 `199,960 / 199,960 objects` 依裁定 6 以 [record](../records/2026-10-15-status-bar-no-object-counts.md) 修訂，spec HTML 本身不改。

靠「跑」而非「讀」發現的：

- `0f8d218` 讓 18 個衝突測試 `pumpAndSettle` 逾時 — sequencer 任務原本 `total 0` 也變成不定條；改為 `waitingOnUser` 靜止條。
- MSVC 建置在非 UTF-8 codepage 下 ninja 記不到 `/showIncludes` 相依，舊 object 未重編，測試以 0xc0000409 崩潰；`chcp 65001` 後正常。

## Result

- ctest 792/792；`flutter analyze` 0；`flutter test` 3525 全綠（`a127b5a`）。
- Device tier（Windows，逐檔跑 21 檔）：20 綠、`update_check_flow_test.dart` 紅 1 —「downloads the real asset…」在 `canSelfInstall` 斷言失敗，原因字串 「This copy was not installed with the installer, so it cannot update itself.」。本分支沒有改動任何 updater 檔（`git diff main...HEAD` 對 update 相關路徑為空）；這是 [feat/release-msi-installer](2026-10-14-feat-release-msi-installer.md) 改成「只有 MSI 安裝的副本能自我更新」後，debug build 必然不符合的測試前提，與本輪無關，處置交使用者決定。
- 範圍外發現，交 S3（裁定 3 的 rollback 輪），本輪未改：`ProcessRunner::execute` 對任何命令都把 token 接到 kill，與 `terminate()` 的註解「mutating git process is never killed mid-flight」不符；逾時（`effectiveDeadlines`）與 `~Session` 的 `cancelOperations(0)` 都可能在 merge／rebase／checkout 中途砍掉 git。
- 規則：`[DRIFT-cancel-capi-unwired]` 原地改寫為已接線；`[CULT-orphan-wiring]` 計數 13 → 15，[record](../records/2026-10-04-orphan-wiring-instances.md) 加第 14、15 例。
