# 關閉 app 時 SIGSEGV（fix/quit-crash-session-shutdown）

## 回報

使用者提供一份完整的 macOS crash report（`gbm_flutter` 0.48.1 build 77，
`EXC_BAD_ACCESS` / `SIGSEGV`，位址落在一段未映射記憶體，緊接在 `App.framework`
的映射範圍之後）。回報步驟：「開一個 repo，把 history 捲到底；再開另一個 repo，
也捲到底；然後關閉 app —— app 關不掉，強制關閉後拿到這份報告」。

## 根本原因

三個查證過的事實疊在一起：

1. **`repoSessionProvider` 不是 `autoDispose`。** 讀
   `repo_session_repository.dart:4248-4258`，型別是
   `StateNotifierProvider.family`，不是 `.autoDispose.family`。Grep 全部
   ~150 個呼叫點確認沒有任何一處 `ref.invalidate`/移除這個 family 的
   entry。一個 `RepoIdentity` 一旦被開啟，它的 session 就在整個 app
   生命週期內永遠不會被自動 dispose——開 repo A 再開 repo B，A 沒有關閉，
   只是失去 watcher。crash report 本身印證了這點：thread dump 有 3 個
   `OperationRunner::workerLoop`、3 個 `DelayTimer::run`（每個 session
   各自一份），即回報當下至少 3 個 session 同時活著。
2. **正常關閉 app 從未呼叫任何 session 的關閉路徑。** Cmd+Q / 關視窗 /
   File → Exit 都不經過 Flutter route pop，`RepoSessionController.dispose()`
   （因此 `sessionClose()`）從未被觸發。專案裡已有的
   `OpenRepoSessions`/`openRepoSessionsProvider.closeAll()`（為自我更新流程
   而建、已有完整測試）在正常關閉 app 這條路徑上完全沒被用到。
3. **`Session::~Session()` 只會被動等待，不會主動取消。** 既有順序
   `operations_->drain()` → `refreshTimer_.stop()` →
   `sharedReadPool().cancelQueuedAndDrain()` 兩段等待都只是「清空 queue
   後等目前正在跑的那個工作自然做完」。`Session.cpp` 裡全部 31 處 post 到
   `sharedReadPool()` 的背景讀取，一律傳入一個空的、預設建構的
   `CancellationToken{}`——其 `state_` 是 `nullptr`，`onCancel()` 對它是
   徹底的 no-op，這些讀取先前完全無法被取消。

完整因果鏈：`-[NSApplication terminate:]` 送出
`NSApplicationWillTerminateNotification` → FlutterEngine 開始關掉 Dart
VM／isolate（讓 event callback 對應的 `NativeCallable` trampoline 失效）→
`exit()` → process-wide 的 `sharedReadPool()`（function-local `static
ThreadPool`）解構 → `shutdown()` → 主執行緒 `join()` 卡住等還在跑的
worker。某個 worker 的背景讀取這時候才做完，回呼
`Session::dispatchOperationLogRecord` → `publishOperationLogRecord` →
`callbacks_.emit(...)`，呼到一個已經被 Dart 引擎關閉回收的 trampoline。

## advisor 的關鍵修正

在動手設計修法前呼叫 `advisor()`，拿到三個修正：

1. **Explore agent 誤讀了 provider 型別**——原本以為 `repoSessionProvider`
   是 `autoDispose`（「disposal is automatic」是舊版 `[STATE-lifecycle]`
   自己寫的），advisor 指出 crash report 的 thread dump（3 組
   `OperationRunner`/`DelayTimer`）與這個宣稱矛盾，逼著回頭直接讀原始碼——
   結果證實 agent 錯了，`[STATE-lifecycle]` 也錯了，兩者都在本輪就地訂正。
2. **不必去猜兩個候選 crash 機制（Session 存活 vs. Dart trampoline 先被
   回收）哪一個才是真的**——兩者的修法完全一樣：在 Dart engine 開始
   teardown 之前，把每個 session 的背景執行緒徹底清空。
3. **測試邊界**：`OpenRepoSessions`/`closeAll()` 已有完整測試，新增的只是
   「退出時接線」；這條 wiring 本身可測，但 macOS 真的退出時序 race
   不能被任何自動化層重現（[TEST-fixture-cannot-disagree] shape 11）。

## 使用者裁定：不要 watchdog，改用既有的 cancellation token

規劃時原本考慮「仿 Windows 自我更新那套：獨立 isolate + 逾時強制
`exit()`」，讓 `closeAll()`（同步呼叫，理論上最壞可能卡到
`kHangCeiling` 10 分鐘）有個時限。使用者否決：「watchdog 記得之前否決過
了，用 cancellationToken 去決定時間限制」。

查證後發現：`Session::cancelOperations(0)` 早就存在、是 public method，
`gbm_cancel_operation` capi 早就把它接到 FFI 層——但使用者先前已經裁定
「開 capi cancellation token 然後先不接線」（[DRIFT-cancel-capi-unwired]，
`#139`），所以它從未被真正呼叫過。而全部 31 個 `sharedReadPool()` 背景
讀取，一律傳入一個死的 `CancellationToken{}`。兩者合起來，就是
`~Session()` 完全沒有辦法「叫」一個還在跑的背景工作停下來，只能等。

## 修法（含測量／測試）

**C++（`fix/quit-crash-session-shutdown` 第 1、2 個 commit）**：

- `Session.h` 新增 per-session 的 `CancellationSource readCancel_`
  （跟既有 `historyCancel_` 同一個模式，不需要額外的 mutex：不像
  `historyCancel_` 會被 cancel-then-replace，`readCancel_` 一個 session
  只有一份，只 cancel 一次）。
- `Session.cpp` 全部 31 處 `CancellationToken{}` 換成
  `readCancel_.token()`（先用 awk 逐一確認每一處都真的在
  `sharedReadPool()` 的 lambda 裡，而不是同步路徑）。
- `~Session()` 新順序：`unregisterLiveSession` → **`cancelOperations(0)`**
  → `operations_->drain()` → `refreshTimer_.stop()` →
  `historyCancel_.cancel()` → **`readCancel_.cancel()`** →
  `sharedReadPool().cancelQueuedAndDrain()`。取消在前，等待在後——被取消
  的操作走失敗分支，不會觸發原本那條「`operations_->drain()` 必須先於
  read-pool drain」不變式所擔心的、鏈出新 `sharedReadPool()` post 的
  `onSuccess` 路徑，所以那個既有的 ASan-confirmed use-after-free 修法不受
  影響。
- 新測試 `CancelOperationApiTest.SessionCloseCancelsQueuedOperationsInsteadOfDraining`：
  提交 20 個 `gbm_reset_to`，立刻（不等完成）`gbm_session_close()`。
  沿用檔案裡既有的決定性手法（OperationRunner 是單一序列 worker、
  `onDone` 同步呼叫），不需要真的計時就能斷言「最多 1 個跑完，其餘
  ≥19 個被取消」。**修前紅燈**：20 個全部照跑完成，0 個取消。修後綠燈。
- `ctest --test-dir build/capi-only`：698 個測試全過（2 個既有、與本次
  無關的 LFS 測試因環境缺 `git-lfs` 跳過）。

**Dart（第 3、4 個 commit）**：

- 新增 `AppExitSessionCleanup`（`lib/features/app_lifecycle/`），接上
  `AppLifecycleListener(onExitRequested:)`，呼叫既有的
  `openRepoSessionsProvider.closeAll()` 後回傳 `AppExitResponse.exit`。
  跟 `AutoUpdateCheck`/`UpdateLeftoverSweep` 同一個組合模式疊進
  `app.dart`。`AppDelegate.swift` 已經是 `FlutterAppDelegate`，不需要動
  任何 Swift/Cocoa 程式碼。
- 新測試用 `tester.binding.handleRequestAppExit()` 驅動——這正是
  `WidgetsBinding` 在真實退出路徑上實際呼叫、並 fan-out 到每個
  `AppLifecycleListener` 的同一個入口，不是繞過真實分派邏輯的替代品。
  修前紅燈（widget 不存在，編譯失敗）；修後 3 個測試全綠。
- `flutter analyze`：零警告。`dart format`：4 個改動檔案格式化 0 變更。
- 全套 `flutter test`：2957 個測試通過。另有 9 個
  `goldens/gbm_widgets_golden_test.dart`（`GbmButton`/`GbmPanel`）的失敗，
  查證後是既有、與本次分支無關的 0.04% 像素差異（渲染環境漂移）——本次
  分支完全沒有碰過這兩個 widget 或任何主題/渲染程式碼，如實記錄而非
  隱藏。

## 已知殘留（誠實記錄，本輪不做）

`sharedReadPool()` 是所有 session 共用的一個池子。`closeAll()` 逐一
（sequential）關閉每個 session：session A 關閉的那一刻，若 session B
（還沒輪到關閉、token 還沒被取消）剛好有一個讀取正佔用某個 worker
執行緒，A 的 `cancelQueuedAndDrain()` 仍然要等那個（尚未取消的）B 的
讀取自然結束。這比修法前好得多（這些讀取本身多半有限定的 timeout，不是
那 28 個無期限的寫入指令），但不是理論上的最短等待。完全消除需要「先對
所有 session 取消，再逐一 drain」的兩階段關閉——規劃時明確寫出這個選項，
使用者在 `ExitPlanMode` 核准時沒有要求本輪一併做，故列為已知殘留，記在
`[CPP-read-pool-tasks-need-live-token]` 的 Note。

`repoSessionProvider` 仍然不是 `autoDispose`——本輪修的是「app 退出前」
這一刻，不是「使用者切換 repo 之後，舊的那個該不該被關掉」這個更大的
設計問題。目前仍然沒有任何 UI 動作可以在 app 繼續開著的情況下關閉單一
個 repository；每個開過的 repo 的 session 會一路累積到整個 app 退出為止。

## 手動裝置層驗證

未在本輪執行——需要使用者在真實 macOS 硬體上，依照回報的原始步驟
（開 repo A 捲到底、開 repo B 捲到底、分別用 Cmd+Q／視窗紅按鈕／
File → Exit 三種方式關閉，並測一次從 WelcomeScreen 直接關閉）重現一次，
確認 `~/Library/Logs/DiagnosticReports` 沒有新的 crash report、沒有殘留
的 `gbm_flutter`/`git` 行程或 `.git/index.lock`。C++/Dart 兩層的自動化
測試已經證明修法成立，但 OS 層級的關閉時序 race 本身不能被任何自動化層
重現（[TEST-fixture-cannot-disagree] shape 11），這是誠實記錄而非
遺漏——見 plan 檔案的驗證章節。

## 新增／更新的規則

- 就地訂正 `[STATE-lifecycle]`（`arch-state-machine.md`）：session
  disposal 不是自動的。
- 更新 `[CPP-session-dtor-order]`、新增 `[CPP-read-pool-tasks-need-live-token]`
  （`fn-cpp-core.md`）。
- `[DRIFT-cancel-capi-unwired]` 加一行：`cancelOperations()` 多了一個
  純 C++ 內部呼叫點，不算把這條 drift 關掉。
- 新增 `[FLU-app-exit-closes-every-session]`（`fn-flutter-state.md`）。
