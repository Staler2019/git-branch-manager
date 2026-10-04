# chore/s3-l1-git-commands — L1 第二片：fn-git-commands.md 19 條縮為 2 條，paths 收窄

## Situation

`.claude/rules/fn-git-commands.md`：30,362 字元、19 條，`paths: src/**, tests/**`，碰到任何一個 C++ 檔都會整份載入。L1 每份預算 6k。

## Task

依 `memory-steward` 處置表縮減。使用者裁定「照你建議做」，內容如下：

- 兩條 keeper 留在 L1。
- remove-locked 另寫一份 record。
- worktree prune 的裁定不另寫 record，因為 ledger、測試和註解都已經有。

## Action

- **處置**：
  - 留 L1 2 條：`output-format-single-slot`（併入 `diff-tree-ignores-first-parent`）與 `worktree-reads-need-fsmonitor-off`。
    - 留下的理由：**新的**呼叫點沒有測試會抓到漏掉的 flag，CI 也沒有 fsmonitor。
  - ENCODE 16 條：steward 逐條列出了測試名與行號。
  - DELETE 1 條：`push-without-refspec`。
- **抽查 steward 的三點**，都和程式碼一致：
  - 原 `GIT-worktree-status-is-per-path` 寫「fsmonitor-off 規則 applies verbatim」，**這句是錯的**。`WorktreeOps.cpp` 刻意不帶 flag，`WorktreeReadFlagsTest` 的 `PerWorktreePendingCountStatusDoesNotPayForThemEither` 也釘住了。新的 keeper 明寫「never to `git status` (including the per-worktree pending count)」。
  - `RemoteOps.h` 的 `PushRequest` 註解「Empty pushes the current branch」不準，沒有 upstream 時 git 會拒絕。已在 C1 更正，用的是和測試註解一致的說法。
  - `ProcessRunner.cpp` 已對每個 git 子程序強制 `LC_ALL=C`，所以「不解析 stderr 是因為 gettext 在地化」這個理由比原文寫的弱。不解析 stderr 的做法本身仍然正確，程式碼這一輪沒動。
- **C1，只改註解**：
  - 13 處 GIT- pin 引用改指 symbol。
  - `BranchOps.cpp` 補 `Ruling:`：遠端刪除不做 probe。
  - `working_copy_status.dart` 的過時路徑改掉。
  - `flutter analyze` 0，`test/data` 加兩個 worktree dialog 測試 +716 全綠。
  - 本機 `build/dev` 指向 repo 的舊路徑，C++ **沒在本機編譯**，留給 CI。C++ 這邊只動註解，行長都在 100 以內；clang-format 的差異在原檔就有（本機 v23 對 CI v18），不是這輪造成的。
  - `dart format` 順手改了兩個沒碰的測試檔，是本機格式化器版本和 CI 不同造成的，已用 scratchpad 的 patch 還原。
- **C2**：新增 `docs/records/2026-10-04-remove-locked-worktree-has-no-force.md`，記下這個決定的狀態是「實作者在授權範圍內的判斷，非使用者裁定」。`remove_worktree_dialog.dart` 補上 `Ruling:` 指向。
- **C3**：
  - 改寫規則檔，paths 收窄為 diff、status、worktree 那幾個檔加 `WorktreeReadFlagsTest.cpp`。
  - `fn-flutter-state`、`drift-open`、`fn-refs-branches`、`ops-toolchain-ci` 各有引用改指，`orphan-wiring` 那份 record 也改了一處。
- **migration-loss 檢查**，逐條跑：
  - 大多數缺項是示意用的佔位字串（`… feat/x`、`2 …`、`@@ -0,0 +1,N @@`）、行號（`WorkingCopyStatus.cpp:271-288`），或在程式碼裡換了寫法（`kind == Added`、`"worktree", "prune", "--verbose"`、`isPrimary: true` 的 fixture）。
  - **接受的真實遺失**：使用者回報 Add Worktree 時附的 `exit 255` 這個細節。它只是症狀，行為本身已由 `add_worktree_dialog_test.dart` 的 remote-pick 案例釘住。
  - steward 另外列出的遺失：「grep 鄰近的雙胞胎」這條教訓（原 primary-not-current-worktree），以及 Windows `/dev/null` 的 `diff-no-index.c` 原始碼判讀。兩者都只留在 `500a67a:.claude/rules/fn-git-commands.md` 和原 ledger。
- **就地更正**：`2026-09-05-fix-partial-branch-delete-no-refresh.md` 那句「就地記進 [GIT-branch-d-partially-succeeds]」劃掉並改寫，因為 pin 已經退役。
- **其他檢查**：`check-rule-pins.py` 146 條、65 個引用，懸空 0；budget 檢查通過。

## Result

- `fn-git-commands.md` 從 30,362 降到 1,613 字元，載入範圍從整個 `src/**`、`tests/**` 縮到 6 個檔。
- L0 不變，維持 28,705。
- 還超過 6k 的 L1 剩 9 份：arch-testing、fn-cpp-core、drift-open、ops-toolchain-ci、fn-refs-branches、ops-spec-reading、fn-flutter-input、fn-flutter-state、arch-testing-device。
