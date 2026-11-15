# fix/stuck-waits-dead-threads — stuck-waits 後續：死掉的 helper 執行緒、繞過 funnel 的兩處交出、callback 註冊失敗、自動 worktree prune 配對

## Situation

[ledger: stuck-waits 已知缺口 2、1](2026-11-12-fix-stuck-waits-threads-and-pre-post.md) 留下的缺口清單，使用者逐項裁定：「缺口 3 =>修」、「Windows 的 deadline 執行緒、CatFileBatch 的 watchdog 執行緒死掉時沒有處理 => 要處理，不要做一半」、「refresh 交出 pool 一直失敗，可能反覆重試 -> 測一下」；funnel 那項解釋過後裁定「A4照做」。其他匯出在交出前失敗會讓畫面一直轉，裁定為「34 個 read 都加失敗狀態」，因牽動 UI 要過 G1，另開一輪（R-B），不在本輪。盤點時另外發現兩個既有的 Dart bug，裁定「兩個bug併進R-A」。

## Task

- A1：core 的 guardedThread 測試開關（可指定名字讓那條執行緒在 body 前丟例外）。
- A2：Windows stdin pump／deadline 執行緒死掉時，run 以該例外結束。
- A3：CatFileBatch watchdog 死掉時 kill 子程序，請求立刻失敗、下一個請求換新子程序。
- A4：maybeRefreshIndex 與 writeCommitGraph 經 submitToRunner。
- A5：gbm_register_callback 回報是否註冊成功；量測 refresh 持續交出失敗的重試次數。
- A6：自動 worktree prune 的配對（併入）。
- A7：dispose 時未回覆的 branch deletion probe 以錯誤完成（併入）。

計畫：A1–A5 經 plan-verifier 兩次 REVISE（CatFileBatch 失敗後會重新生成、macOS 的 capi-only preset 開著 GBM_BUILD_TESTS、register 的 C++ 半邊沒有測試、CatFileBatch 寫入已死子程序會 SIGPIPE）後收尾審查 READY；A6/A7 一次 REVISE（測試假 controller 跑不到真的 dispatch、回 0 的測試分不出修正與突變）後 READY。修訂紀錄在計畫檔。使用者核准、選 AUTO。

## Action

1. `e7d8dac2` A1：GBM_BUILD_TESTS 開啟時 gbm_core 以 PUBLIC 定義 GBM_TEST_FAULT_HOOKS（template 在 header，每個 TU 必須同值）；failNextThreadForTest(name) compare-and-clear。macOS app 的 dylib 以 capi-only 建置，帶著這個開關（未 arm 無作用）；`-DGBM_BUILD_TESTS=OFF` 建出的 libgbm_capi.dylib 以 nm 查無任何開關符號（capi-only 建置的正向對照查到 7 個）。
2. `611ae989` A2：stderr pump 的 stderrFailure 改為三條 helper 共用、加鎖的 firstFailure；第一個死掉的存例外並 terminate()，join 後 rethrow。兩個 _WIN32 測試加 8 秒 backstop cancel，讓未修版本是紅燈而非 ctest timeout；本機把區塊改成 `#if 1` 編譯通過（POSIX 上執行會紅，因為沒有這兩條執行緒，正好證明 backstop 生效）。
3. `126f4a39` A3：watchdog 的 onException 在 watchMutex_ 下 killChild()；請求以 Io 失敗並 poison，下一個 read() 照既有路徑換新子程序。ignoreSigPipeOnce 移到 base/PosixPipe，CatFileBatch 的 spawnPosix 也呼叫。只加 kill、未忽略 SIGPIPE 時，「先死再寫入」的測試行程以 exit 141（SIGPIPE）結束——這正是 plan-verifier 的預測。兩個測試以 ctest --repeat until-fail:20 重跑全綠。
4. `63bfdad1` A4：兩處改經 submitToRunner；maybeRefreshIndex 交出失敗時還原 lastIndexRefresh_；writeCommitGraph 交出失敗時送 {"succeeded":false}。之後 src/capi 只剩 submitToRunner 呼叫 runner.submit。index 測試第一版在修正前也綠（第一次 refresh 排入的 update-index 非同步地在弄髒之後才跑），加 500 ms 等待後才在修正前變紅。
5. `98a0754b` A5：gbm_register_callback 改回傳 int32_t（catch 用 reportNativeException 回 0）；Dart 的 GbmSessionEvents.registered 為 false 時，讀出錯誤、關閉 session、不啟動任何讀取。測試開關 gbm_test_fail_register 與 read 開關的 sticky:<where>。函式 body 太短被 clang-format 壓成一行時 check-native-exception-guards.py 認不出 try block，加一行註解保持多行。
6. `0ea04926` A6：見下方「發現」。PruneWorktreesOperation 標 kind "prune-worktrees"；gbm_worktree_prune 回傳 int32_t；Dart 的計數改為 FIFO，由唯一的 dispatch pruneWorktrees({automatic}) 推入、回 0 撤回，WC outcome 依 kind 取出前端；刪除失效的 _isSuppressedAutoPruneWorktreesError；抑制／順序／回 0 測試改用真的 RepoSessionController。
7. `d4cdc8a8` A7：dispose() 關閉 session 後，仍在等的 probe 以 codeName Cancelled 的 error 完成。

### 發現：自動 worktree prune 的抑制從未在正式環境生效

`_isSuppressedAutoPruneWorktreesError` 只在 operationFinished 的處理裡被呼叫，但 `Session::pruneWorktrees` 走 submitWorkingCopyOperation，送的是 WORKING_COPY_OPERATION_FINISHED，那邊直接寫 lastError。所以自動 prune 失敗照樣跳 banner，in-flight 計數在任何路徑都不會遞減。舊測試假造了 operationFinished——真實 library 對這個操作不會送的事件——所以一直是綠的（[TEST-fixture-cannot-disagree] 第 9 型：跨語言欄位由測試手動設定，正式環境從不設定）。

### 量測：refresh 持續交出失敗

sticky 地讓 `post:Session::dispatchRefresh` 每次都失敗：

| 請求間隔 | 請求數 | 交出失敗次數 | 之後 1 秒內增加 |
|---|---|---|---|
| 30 ms | 20 | 1 | 0 |
| 200 ms | 20 | 20 | 0 |

30 ms 時被 RefreshCoalescer 的 150 ms debounce 合併成一次。失敗在 timer 執行緒上同步發生，「執行中又收到請求」的窗口幾乎為零，所以 finishRefresh 的 `again` 不會自己反覆觸發。上一輪 verifier 的推測（反覆 bad_alloc 時以 0 ms 不斷重排）不成立：重試以請求數為上限。

Mutation（執行次數與變紅次數分開記）：

| 片 | 突變 | 執行 | 變紅 |
|---|---|---|---|
| A1 | 拿掉 header 的 hook 呼叫 | 1 | 1 |
| A1 | 名字比對改成任何名字都中（第一版 `-Werror` 編不過，不計） | 1 | 1 |
| A2 | Windows CI 暫時 revert（見追加） | — | — |
| A3 | (a) 不 kill（＝修正前狀態，兩測試 hang 被 backstop 判紅） | 1 | 2 |
| A3 | (b) 不忽略 SIGPIPE（＝實作中間狀態，exit 141） | 1 | 1 |
| A4 | 失敗時不還原時間戳 | 1 | 1 |
| A4 | 失敗時不送事件 | 1 | 1 |
| A5 | C++ catch 回 1 | 1 | 1 |
| A5 | Dart 忽略 0 | 1 | 1 |
| A6 | 成功時不取出 | 1 | 1 |
| A6 | 回 0 時不撤回 | 1 | 1 |
| A6 | C++ 不標 kind | 1 | 1 |
| A6 | C++ export 永遠回 1 | 1 | 1 |
| A7 | 不完成 probe（＝修正前狀態，逾時） | 1 | 1 |

A3 (a)(b) 與 A7 不是事後另做的突變，而是修正前／實作中間的狀態，照實記錄。

## Result

- 本機（macOS）：ctest 1109/1109；TSan（build/tsan）這輪動到的 51 個測試 0 個 ThreadSanitizer 警告；flutter test 全套 4626 過、19 skip；flutter analyze、dart format、clang-format、check-*.py 皆通過。
- 逐 commit：7 個 commit 各自在乾淨 worktree 建置並跑完整 ctest（1102、1102、1104、1106、1108、1109、1109，全過）與 `flutter test test/data`（1421 到 1427，全過）。第一次的逐 commit 腳本 grep 也比對到名字含 Exception 的測試，`head -8` 切掉了 ctest 總結行，那次的 ctest 結果不算，修正 grep 後重跑才得到上面的數字。
- fresh verifier 對 A1–A7 回 CONFIRMED（A2 只讀程式碼，Windows 半邊見追加的 CI 證據）。五則 P4 提醒的處置：
  1. `update_controller_test.dart` 一次目錄執行中紅一次、單獨與重跑皆綠；本輪沒動該檔，記為無關 flake，不處理。
  2. A6：若 `submitToRunner` 在 `runner.submit` 已排入之後才丟例外，Dart 會撤回一個其實已排入的項目，FIFO 錯位。正式版在 submit 之後只有 Handle 建構或 `bad_alloc` 會丟，沒有重現，延後。
  3. A7 只涵蓋 `dispose()`；自我安裝流程單獨呼叫 `closeNativeSession()` 時，未回覆的 probe 要等到 dispose 才完成。不在本輪主張內，延後。
  4. 計畫檔寫的名字是 `GBM_CORE_TEST_HOOKS`／`failThreadForTest`，程式碼是 `GBM_TEST_FAULT_HOOKS`／`failNextThreadForTest`；本紀錄以程式碼為準。
  5. 計畫要求 `AWatchdogThatDiesDuringARequestEndsItPromptly` 也驗第二個請求在 1.5 s 後回 Timeout，實作只驗第一個請求 900 ms 內結束。計畫列出、未實作；換新子程序由 `ADeadWatchdogKillsTheChildAndTheNextChildIsHealthy` 涵蓋。
- A4 的偏離：`AWriteThatCannotBeQueuedFinishesAsFailed` 只驗事件，沒有驗 native error 的回報。
- 未處理、留給 R-B：其他匯出在交出前配置失敗（34 個 read 的失敗狀態，需 G1）；缺口 3、4 照舊。
