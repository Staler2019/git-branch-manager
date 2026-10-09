# feature/worktree-checkout — worktree 新增後清單不更新、Open in terminal 位置、Windows Switch to 白屏

## Situation

使用者回報三件事：

1. macOS：Add worktree… 之後清單沒有出現新的 worktree。
2. Windows：worktree 面板選一個 worktree 按 Switch to，視窗全白並顯示「沒有回應」；macOS 沒有。
3. 「open in terminal is relative to a worktree function, so might be put on same line with
   "switch to" button」，並且「can you add a terminal icon」。

讀碼時 bug 1 的整條鏈（`Session::addWorktree` 的 onSuccess → `refreshWorktrees` →
`WORKTREES_UPDATED` → `_readWorktrees` → 面板 `.select`）每一段都有接上，所以不是少了呼叫。
當時列為頭號候選的是 `requestWorktreePendingCounts` 無條件發布、可能以舊清單蓋掉新清單——
**這個假說最後沒有成立，也沒有修**。

## Task

- Bug 3：使用者裁定蓋過 P19 PANELSPEC 的工具列「Add、Prune、Open、Remove」；spec-auditor 先稽核。
- Bug 1：先在 macOS 重現再修，不修猜測。
- Bug 2：沒有 Windows 機器，需要使用者提供卡住時的主執行緒 stack。
- 後續裁定：「Windows 的 handle 繼承問題修掉，然後開pr直接檢查ci」。

## Action

**Bug 3**（`b1f117c`）：按鈕移到明細列 Switch to 之後，ghost、`LucideIcon('terminal', 12)`，顏色比照
`action_toolbar.dart`。glyph 名稱出自規格的 `icTerminal`；`assets/icons/terminal.svg` 取自
lucide-static 1.53.0，照既有資產格式。mutation 2 次：拿掉 icon 紅 1；放回工具列紅 4（重複標籤讓
`panelButton` 歧義，紅得比該紅的寬）。

**Bug 1 的重現沒有成功，線索來自使用者**：裝置測試 `worktree_add_refresh_test.dart` 走真的
對話框，「建立新分支」與使用者說的「checkout 既有分支」兩條都綠（8 秒內出現）。使用者接著指出
「log drawer 那列一直是 running，但動作其實已經完成」。這把問題從 Dart 移到 core：操作沒有結束，
onSuccess 就不會刷新。

在使用者正開著的 app 上量：`git worktree add` 已不在行程表，但兩個 `git fsmonitor--daemon`
（使用者全域 `core.fsmonitor=true`，ppid 已是 1）與 app 握著同一批 pipe 物件（`lsof` 的 pipe
位址相同）。`ProcessRunner.cpp`／`CatFileBatch.cpp` 用裸 `pipe()`，`posix_spawn` 的 `adddup2`
把寫入端接上 1/2，但原 fd 號碼在子程序裡也還開著；daemon 把自己的 0/1/2 指向 /dev/null，卻保有
那個號碼。poll 永遠等不到 EOF。

一個沒成立的嘗試：在 scratch repo 用 shell 管線跑 `git worktree add … | cat`，0 秒結束——shell
自己會關掉多餘的 fd，所以 shell 重現不出這個漏洞；裝置測試也沒重現（daemon 是否起來取決於環境，
本輪沒追）。

修法（`10971fa`）：`base/PosixPipe` 的 `makeCloexecPipe`（Linux `pipe2`，其他 `pipe`+`fcntl`）
與 `initSpawnAttr`（Apple 加 `POSIX_SPAWN_CLOEXEC_DEFAULT`）。測試：`hang_forever
--detach-grandchild` 生出一個 0/1/2 指向 /dev/null、睡 5 秒的孫程序後立刻結束。修前 3001 ms 撞
逾時、修後 221 ms。mutation 3 次紅 1 次：兩道同時拿掉才紅；macOS 上任一道都能單獨擋住，Linux 只有
CLOEXEC 那道。

**Windows 同族缺陷**（`80457df`）：寫入端可繼承、`CreateProcessW` 沒有 handle list，同時 spawn
的子程序會拿走彼此的寫入端。`base/WinHandleList` 的 `InheritList` 以
`PROC_THREAD_ATTRIBUTE_HANDLE_LIST` 限定，建不出就拒絕 spawn；無 stdin 時改用可繼承的 `NUL`
（`GetStdHandle` 在 GUI 行程可能為空）。競態本身無法在測試裡定時，所以測試斷言機制：
`--probe-handle` 讓子程序回報一個未列入的可繼承 event 是否到得了它。只在 Windows 編譯，本機沒跑過。

格式：本機 clang-format 是 23 版、CI 是 18 版，23 版重排了無關程式碼；改在 scratchpad 裝 18.1.8，
只格式化 `src/`（CI 只檢查 `check-path: 'src'`），測試檔維持手寫。

## Result

- Bug 3 完成。Bug 1 根因確認並修正，待使用者實機確認 log 列會結束、清單會刷新。
- macOS core ctest 745 個通過（2 個 lfs 照舊 skip）；Windows 的新測試待 CI。
- **Bug 2 仍開著**：Windows handle 繼承是同族缺陷，但沒有找到 UI 執行緒上同步跑 git 的地方，所以
  它解釋不了「沒有回應」，只是候選。仍需要 Windows 卡住時的主執行緒 stack
  （`flutter run -d windows` 後 DevTools Pause，或 Visual Studio「附加至處理序 → 全部中斷」）。
- 未處理：P19 mockup 把 worktree 按鈕畫成 `gbm-btn-sm`，程式明細列是 normal（既有偏差，非本輪引入）。
