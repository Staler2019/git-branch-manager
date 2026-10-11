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
  - ← `Session::requestWorktreePendingCounts()` 的 emit（`Session.cpp:1065`／`1079`）
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
- core ctest：第一次 `-j8` 跑的時候有一條紅，`ProcessRunnerTimeout.ProgressOnStderrAloneKeepsAChildAlive`。當時裝置測試正在編譯，第一個 drip 沒在 500 ms 的閒置期限內到。單獨重跑 5/5 綠，與本輪改動無關。最後的全套結果見下方「推送前」。
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
