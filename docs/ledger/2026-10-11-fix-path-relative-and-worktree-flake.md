# fix/path-relative-and-worktree-flake — PATH 相對路徑、worktree_add_refresh 的崩潰；dart:io 回收子行程那輪取消

## Situation

- 前一輪（`feature/prepared-message-followups`）留下三件事：
  - dart:io 的 `wait()` 會回收 core 起的 git，exit code 變成 -1（`[TEST-no-dart-process-while-core-runs-git]`）。
  - 計畫資安審查的 F9：`GitExecutable` 會採用 PATH 裡的相對路徑項目。
  - 裝置測試 `worktree_add_refresh_test.dart` 不穩，之前在 `879eba2` 綠 1／4、在 `d59a3be` 綠 1／3。
- 三件原本併成一輪處理（分支 `fix/dartio-child-reaping`），計畫經 plan-verifier READY（epoch 3），使用者核准。

## Task

- 讓 git 子行程不受宿主 `wait()` 影響。使用者裁定：分平台、不加行程。
- F9：略過 PATH 的相對路徑。
- 找出 `worktree_add_refresh` 不穩的根因；有根因才修。

## Action

### dart:io 回收子行程：已取消，改開 issue #184

- 重現測試 `ProcessRunnerReapTest`：用一條執行緒模擬 dart:io，一直呼叫 `wait()`。
  - 修正前 macOS 有 73/100 和 71/100 次 exit code 錯。
  - Linux 在 Docker 裡測，100 次中有 13 次 exit 128 被回報錯。
- macOS：`POSIX_SPAWN_START_SUSPENDED`，先註冊 kqueue `NOTE_EXIT|NOTE_EXITSTATUS` 再 `SIGCONT`，結束狀態從 kevent 取。這個做法可行：修正後 0 錯，core 全套 793/793 綠。
  - 提交在 `fix/dartio-child-reaping` 的 `93ef4430`，沒有推送，保留作參考。
  - mutation 跑了 7 個。
    - 紅的：M1、M2、M4（補了 `--probe-fd` 測試之後）。
    - M3 卡住，等同紅。
    - M5 是機率性的紅：1000 次一批，10 批中 4 批紅。
    - M6、M7 存活。M6 存活，是因為 `terminate()` 回收後會把 `pid_` 設成 -1，`wait()` 根本不會去等 kevent。計畫預測它會紅，預測錯了。
- Linux：計畫用 glibc `__clone(CLONE_VM|CLONE_VFORK)`、exit signal 0，靠 `__WCLONE` 讓 `wait()` 看不到子行程。**這個前提被實測推翻。**
  - 探測程式 `cloneexec.c`，Linux 7.0.14：
    - exec 前：只有 `__WCLONE` 看得到這個 child。
    - **execve 之後**：普通 `waitid` 看得到它，`__WCLONE` 反而看不到。exec 把 exit signal 重設回 SIGCHLD。
  - 不加行程的話，Linux 沒有辦法修。
- 使用者裁定（2026-10-11）：「這次dart.io修正都取消，開issue說明。因為只能修mac可能要從流程下手，而不是一直去突破自己寫架構」。
  - 已開 **#184**，內容包括量測、兩個平台的結果、往流程方向的候選做法。
  - Linux 那份未完成的實作沒有提交。
- 執行中另外量到的事實：
  - macOS 上 `posix_spawn` 執行檔不存在時，會有一個子行程短暫可見：`waitpid(WNOHANG)` 先回 0，隨後消失、不需要回收。plain、CLOEXEC_DEFAULT、START_SUSPENDED 三種 flag 都一樣。
  - Docker Ubuntu 22.04 的 git 是 2.34.1。`RealRepoTest.RebaseAutosquashFoldsFixupCommitsWhenEnabled` 在那裡紅，推論是 git 版本太舊（非互動 rebase 的 `--autosquash` 要 2.44 才生效）。沒有在 base 上重跑確認。

### F9：PATH 相對路徑（`1d625590`）

- `fromEnvironmentPath()` 只採用絕對路徑的項目。空項目代表 "."，一併略過。
- 新測試 `SearchPathSkipsARelativePathEntry`：PATH 設成「相對目錄:絕對目錄」，兩邊都放一個 `git`，cwd 指向相對目錄的上層。
- mutation 2 次（拿掉檢查、反轉檢查），各紅 1 條。

### worktree_add_refresh：dispose 順序造成崩潰（`e1347dde`）

- 在 HEAD 上跑 3 次，綠 1 次。紅的 2 次都在 5 秒時「did not complete」，同時各產生一份 crash report。
- 本機 6 份 `gbm_flutter-2026-10-11-*.ips`（包括前一輪的 4 份）全部一樣：
  - `SIGABRT`
  - `dart::Assert::Fail` ← `DLRT_GetFfiCallbackMetadata`
  - ← `Session::requestWorktreePendingCounts()` ~~的 emit（`Session.cpp:1065`／`1079`）~~ 裡的 callback 呼叫（更正，verifier P4）：
    - 1079 是 `emitEmpty(WORKTREES_UPDATED)`。
    - ~~1065 是 `if (!result)`，不是 emit。~~ 1065 是 `worktreeStore_->list(...)`，不是 emit（再次更正，第二輪 verifier F1：上一句差一行）。這一幀直接接 Dart trampoline，中間是被內聯的呼叫，而這個範圍內唯一的 callback 呼叫是 ~~1066~~ 1067 的 `emit(ERROR_OCCURRED)`。推論：`~Session` 先 cancel `readCancel_`，`list()` 因此失敗，送出錯誤事件。
    - Session.cpp 從 12:05（`4c60e76e`）之後沒改過，6 份 crash 都在那之後，所以行號對得上現在的原始碼。
- 原因：`RepoSessionController.dispose()` 先 `_events?.dispose()`（`NativeCallable.close()`），再 `closeNativeSession()`。
  - core 要到 `~Session` 才 drain，這段期間仍在跑的 pending counts（每個 worktree 跑一次 git）會 emit。
  - 這時事件打到已經 close 的 callable，Dart VM abort。
  - `GbmSessionEvents.dispose` 的註解寫「必須在 session close 之前」，順序剛好講反了。已在原處更正。
- 修法：對調順序。session 關閉之後就不會再有事件。
- 測試 `repo_session_dispose_order_test.dart`：在假 `sessionClose` 裡呼叫已註冊的 callback，模擬 drain 中的 emit。
  - 修正前紅，訊息正是 app 崩潰的那一行：`Callback invoked after it has been deleted`。
  - mutation 2 次（順序反轉、拿掉 session close），各紅 1 條。

## Result

- `flutter test` +3462 ~1、analyze 0、format 0。
- core ctest：第一次 `-j8` 跑的時候~~有一條紅~~有兩條紅（更正：只讀了畫面最後一行，漏了一條；`LastTestsFailed.log` 列了兩條）：`ProcessRunnerTimeout.ProgressOnStderrAloneKeepsAChildAlive` 與 `ProcessRunnerTimeout.AChildStillDrippingOutputOutlivesTheIdleDeadline`。當時裝置測試正在編譯，第一個 drip 沒在 500 ms 的閒置期限內到。前者單獨重跑 5/5 綠，與本輪改動無關。
- 推送前在空閒的機器上重跑：core ctest 787/787、capi ctest 787/787，0 失敗。
- 裝置層 `worktree_add_refresh`，修正後共 8 次：
  - 7 次直接綠（約 35 秒）。
  - 1 次停了約 4 分 48 秒，最後通過。卡住期間：
    - core 全部閒置（只剩常駐的 `cat-file --batch` 在等輸入）。
    - 主執行緒在 run loop 閒置。
    - 用 `osascript` 把 app 叫到前景後，幾秒內就完成。
  - 假設：視窗不在前景時沒有 frame，`tester.pump` 一直等。只有這一個樣本：之後 6 次都在 90 秒前結束，沒用上前景喚醒。所以**未證實**，也沒有做任何 workaround。
  - 修正後沒有新的 crash report。
- 已在原處補註 2026-10-09 ledger 對這個 flake「不認定原因」的那段。
- 新 pin：`[FLU-close-session-before-callable]`。

## 追加：verifier 的三條 P4（使用者 2026-10-11：「p4修完」）

- **PATH 測試在 Windows 不跑**：`SearchPathSkipsARelativePathEntry` 拿掉 `#ifndef _WIN32`。
  - 改用 `setEnv`（Windows 用 `_putenv_s`），分隔符與執行檔名依平台決定。
  - Windows 上 registry 找到的 Git for Windows 會排在最前面，所以那裡改成斷言「真正的 git 有被列入」，並且「每個候選都是絕對路徑」。
  - macOS 上 mutation 1 次（拿掉檢查），紅 1。
  - 本機沒有 Windows 工具鏈，Windows 的編譯與執行要等 PR 的 base 是 `main` 時的 CI。
- **close 時排隊中的事件 payload 沒被釋放**：先量。新測試在 `sessionClose` 裡送一個帶 payload 的事件，dispose 後等事件迴圈跑完再計數，結果釋放 0/1。這證實了：listener 關閉時，佇列裡的訊息會被丟掉。
  - 修法：`GbmSessionEvents.dispose()` 不立刻 close，改成經由自己的 callable 送出哨兵（eventType -1）。listener 的訊息依序送達，哨兵抵達時前面的事件都已經收到、payload 也已釋放，`_onEvent` 這時才 close。
  - 新增 `@visibleForTesting isNativeCallbackClosed` 與 `test/data/ffi/event_dispatcher_test.dart`。原因：「永遠不關」這個 mutation 第一次沒有被任何測試擋下，而沒關的 listener 會讓 isolate 一直活著。
  - mutation 3 次（立刻 close、永遠不關、不送哨兵），各紅 1。
- **ledger 行號**：見上方 Action 的原處更正。第一次更正自己又差一行（第二輪 verifier REFUTED，F1），已再更正。
- 第二輪 verifier 另提 P4：新加的 typedef 插在 `GbmSessionEvents` 的 doc comment 與 class 之間，已移到 doc comment 上方。


## 追加：PR #185 的 CI（2026-10-11～12）

- #182 合入後，#185 的 base 自動改成 `main`，完整 CI 第一次跑。13 項中 12 項綠，包括 Windows：`SearchPathSkipsARelativePathEntry` 在 MSVC `/WX` 下編譯通過，也跑過。
- 紅 1 項：Sanitizers (asan+ubsan) 的 `WorkingCopyApiTest.UnstageHunkReversesAFullyStagedSingleHunkFile`。第二個操作 `unstage_hunk` 在 preflight 時看到 `.git/index.lock` 存在，回報 `LockHeld`（run 38126494972）。
  - 本 PR 的 C++ 改動只有 `GitExecutable` 的 PATH 判斷，這條測試走不到。main 最近的 CI 都是綠的。
  - `gh run rerun --failed` 重跑後 13/13 綠。
  - 這與 `GitCommand.h` 的 `worktreeReadFlags()` doc 記錄的「`index.lock` 偶發，holder 從未找到」同形。不同的是這次發生在**沒有 fsmonitor 的 CI 機器、ASan build** 上，以前的紀錄都是開了 fsmonitor 的本機。
  - 本輪沒有追 holder，也沒有開 issue。
