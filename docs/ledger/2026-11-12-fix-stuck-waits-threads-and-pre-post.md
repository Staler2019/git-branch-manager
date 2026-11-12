# fix/stuck-waits-threads-and-pre-post — stuck-waits 已知缺口 2、1：死掉的執行緒與交出前的例外

## Situation

[ledger: feat/stuck-waits](2026-11-09-feat-stuck-waits.md) 的已知缺口列了四項。使用者裁定「ok照你說2,1 然後34紀錄」：修 2（不在 read pool 上、死了不回覆的執行緒）與 1（交出工作之前就丟例外），3（`CallbackRegistry::emit` 丟事件）與 4（drain 丟掉的 read 不回覆）只記錄。

盤點時發現缺口 2 的清單有一半已經不成立：`CloneJob` 與 `Scanner` 早已處理，`DelayTimer::run()` 本來就接住 `onFire_`。真正會讓人等下去的是 `AskpassPoller` 的執行緒與 `ProcessRunner` 的 progress sink；缺口 1 落在 `postRead` 交給 pool 的那一步，以及 operation funnel 交給 `OperationRunner::submit` 的那一步。

## Task

- S1：poller 執行緒死掉時，等待中的 askpass client 立刻失敗，`isPromptPending` 不再擋住 idle deadline。
- S2：`onProgress` 丟例外時 `run()` 以該例外結束（Windows stderr pump 與 POSIX 一致）。
- S3：`postRead` 交出失敗仍回覆，`onAlways` 照跑。
- S4：operation 交不進 runner 時不送 outcome（會插到已排隊的同類 operation 前面，破壞 Dart 依序配對），改由匯出同步回報；Dart 撤回剛記的 pending。
- S5：本紀錄，並在 stuck-waits ledger 原地更正缺口清單。

計畫經 plan-verifier 兩次 REVISE 後收斂（r0→r2，修訂紀錄在計畫檔）；使用者選 AUTO。

## Action

1. `b107d684` S1：`AskpassPoller` 的 `guardedThread` 加 onException，呼叫 `cancelPrompt()`。測試：`onPrompt` 丟例外，5 秒內 client 結束、exit 1、`isPromptPending` 為 false。
2. `e300610d` S2：`execute()` 接住 `pump` 的例外，`terminate()`、`wait()`、補記 Log 紀錄後重新丟出；Windows stderr pump 存 `std::current_exception()`、終止子程序，join 後 rethrow。**偏離計畫**：原計畫認為 POSIX 已正確；寫測試時實測 POSIX 也有兩個缺陷：`hang_forever` 子程序沒被收掉（手動依 PID kill），Log 那一列停在 RUNNING。一併修掉。
3. `1447ff4d` S3：`postRead` 先把 `onFailure`／`onAlways` 放進 `shared_ptr`，`run` 與 `postRead` 各持一份；交出步驟 `handToReadPool` 以值接 `std::function`，失敗時在呼叫端執行緒記錄、回覆、跑 `onAlways`（包 try，不用 `ScopeExit`：解構子丟例外會結束程式）。動手前逐一檢查 36 個 `postRead` 呼叫點，沒有一個持有回呼會拿的鎖（唯一命中是立即執行的 lambda 內的鎖，已釋放；`DelayTimer` 呼叫 `onFire_` 前已解鎖）。測試開關 `gbm_test_fail_read("post:<where>")`。**偏離計畫**：計畫寫 blame 當 keyed reply 案例，但 blame 的失敗是 `ERROR_OCCURRED`，改用 branch deletion probe（`requestId`）。`check-read-pool-posts.py` 的白名單加入 `handToReadPool`，併入同一 commit，否則 CI 會擋。
4. `899e16b8` S4：三個 funnel 經 `submitToRunner` 交出並回傳 bool；`false` 只代表交出那一步丟例外。`submitOperation` 的 `inFlight_` 記帳另包 try，丟了只少一個 cancel-by-id，仍回 true；例外與保留的 `onAlways` 都在 `inFlightMutex_` 放開後處理（`endAskpass()` 會 join）。四個匯出改回傳 `int32_t`，catch 用 `reportNativeException` 回 0（比照 `gbm_history_refresh`，登記於 `check-native-exception-guards.py`）。Dart 照舊先記錄，回 0 時 `dropLast*`。測試開關 `gbm_test_fail_submit`，`after:` 前綴在 `submit()` 回來後才丟。

Mutation（執行次數與變紅次數分開記）：

| 片 | 突變 | 執行 | 變紅 |
|---|---|---|---|
| S1 | 不呼叫 `cancelPrompt`（第一個寫法因 `-Wunused-lambda-capture` 編不過，不計） | 1 | 1 |
| S2 | 略過 terminate／wait／record | 1 | 1 |
| S3 | (a) 失敗路徑用已移走（空）的 onFailure | 1 | 4，全為新測試 |
| S3 | (b) 失敗路徑不跑 onAlways | 1 | 2，refresh 與單元案例 |
| S3 | 檢查腳本白名單拿掉 `handToReadPool` | 1 | 3 |
| S4 | (a) 交出失敗改送 outcome 並回 1 | 1 | 3 |
| S4 | (b) 不跑保留的 onAlways | 1 | 1，askpass 案例 |
| S4 | (d) 拿掉 post-submit catch | 1 | 1 |
| S4 | (c) 拿掉 `dropLast*`，四個呼叫點各一次 | 4 | 各 1 |

S4 (c) 第一輪 delete、prune 兩個呼叫點沒有變紅（沒有 controller 測試覆蓋），補兩個測試後重跑才各紅 1。S4 的 C++ 先以「匯出呼叫後 `return 1`、catch `return 0`」的天真版本跑：6 個新案例紅 2（askpass、post-submit）；其餘 4 個在天真版本下也綠，它們守的是 mutation (a) 的設計。

## Result

- macOS：ctest 1100/1100；TSan 版 ReadFailureApiTest／PostRead 23 個、0 個警告；Flutter 4620 過、19 skip；`dart format`、`flutter analyze`、clang-format 22（`src/`）、GCC 16 `-Werror` 語法檢查、`check-*.py` 全過。
- S2 的 Windows 半邊只有 Windows CI 能證明（[CPP-windows-terminate-hangs-join]）；結果記在本檔追加。
- `[CPP-read-throw-still-replies]` 沒有改：規則說的「`postRead` 記錄後呼叫 `onFailure`」不變，交出失敗只是多一條同樣回覆的路徑；計畫的條件（S3 改變規則內容時才改）不成立。

### 已知缺口

- 缺口 3：`CallbackRegistry::emit` 在沒有 callback 或 malloc 失敗時丟掉事件。未處理。
- 缺口 4：session 關閉時 `cancelQueuedAndDrain` 丟掉的 read 不回覆。未處理。
- 交出之前的配置失敗：除了四個 tracked 匯出（回 0），其他匯出在呼叫 Session 前丟例外（例如 `toOidVector`）仍只寫 log。
- Windows 的 deadline 執行緒、`CatFileBatch` 的 watchdog 執行緒死掉時沒有處理。
- `maybeRefreshIndex`（null callback，沒人等）與 `writeCommitGraph`（`COMMIT_GRAPH_WRITE_FINISHED`，Dart 沒有請求在等）仍直接呼叫 `operations_->submit`，不經 funnel。
- 四個匯出的 catch 經 `reportNativeException` 寫 staging buffer，沒有人讀；與 `gbm_history_refresh` 同樣接受。

- Windows CI 證據（PR #220，run 43229568624，job `capi (FFI) - Windows`）：暫時 commit `3169ae58` 把 Windows stderr pump 的 onException 改成什麼都不做。1097 個測試只紅 1 個，正是 `ProcessRunnerTimeout.AProgressSinkThatThrowsEndsTheRunWithItsException`：`threw` 為 false（「the run did not end with the sink's exception」），耗時 10.22 s，等到 idle deadline 才結束。讀完後以 force-push 移除該 commit；修正版的 Windows 綠燈見 PR 最終 head 的 CI。
- fresh verifier 對最終 candidate `f16a1a70` 的六項主張回 CONFIRMED（`gbm_capi_tests` 320/320、`gbm_core_tests` 777/777、無殘留 `hang_forever`、去掉 `GBM_CAPI_TEST_EXPORTS` 後測試開關不留符號）。兩則 P4 提醒都延後：Windows 半邊由上面的 CI 證據補上；若交出 refresh 在正式環境持續失敗（例如反覆 `bad_alloc`），內聯的 `finishRefresh` 會在有待處理請求時以 0 ms 重新排程，每次重試都再記一筆 log。這是推測，沒有重現，也不處理。
