# fix/worktreeCreateBranch — 新分支不再隱性設定 upstream

## Situation

使用者回報：Add worktree 選「建立新分支」時，新分支被設了 upstream，「而且永遠是 develop」。

程式碼裡沒有任何寫死的 `develop`（`src`、`app_flutter/lib` 唯一命中是 `RefStore.cpp` 的 trunk seed 清單，與此無關）。`AddWorktreeOperation` 送的是 `git worktree add -b <new> <path> <start>`，`CreateBranchOperation` 送的是 `git branch <new> <start>`，兩者都沒有 `--track`/`--no-track`，新分支要不要 upstream 交給了使用者的 `branch.autoSetupMerge`。

## Task

- Add worktree「建立新分支」：不論起點、不論 `autoSetupMerge`，新分支都沒有 upstream。
- Add worktree「Checkout 既有」選只在遠端的 `origin/feat/x`：建立的 `feat/x` 仍追蹤 `origin/feat/x`（原本行為）。
- 使用者裁定同形缺陷一起修：New branch 對話框起點選 `origin/x` 時，新分支也不該有 upstream；upstream 只經由「同時 push 並設為 upstream」設定，這也是 `new_branch_dialog.dart` 自己 doc comment 的說法。

## Action

**先量，不猜。** scratch repo，git 2.56.0：

| 指令 | 起點 | autoSetupMerge | upstream |
|---|---|---|---|
| `worktree add -b` | `origin/develop` | true（預設） | `origin/develop` |
| `worktree add -b` | `develop`（本地，追蹤 `origin/develop`） | inherit | `origin/develop` |
| `worktree add -b` | `develop`（本地） | true | 無 |
| `worktree add --no-track -b` | 兩者皆試 | true / inherit / always | 無 |
| `worktree add --track -b` | `origin/develop` | true | `origin/develop` |
| `branch e origin/develop` | `origin/develop` | true | `origin/develop` |
| `branch p1 origin/develop --no-track` | `origin/develop` | true | 無 |

所以「永遠是 develop」有兩條路：使用者挑 `origin/develop` 當起點，或 repo 設了 `inherit` 且目前在 develop（Add worktree 的 createNew 預設起點是目前分支）。兩條都由明示 `--no-track` 消除。

`git worktree add --[no-]track` 的最低版本：`Documentation/git-worktree.txt` 在 tag `v2.15.0` 無此選項、`v2.16.0` 有（抓兩個 tag 的檔案比對）；app 已對低於 2.24 的 git 發警告，不需另外處理。

**C1 `174bcb30`**：`CreateBranchOperation` 非 `setUpstream` 時帶 `--no-track`。不改 capi。

**C2 `af2cd96b`**：`AddWorktreeRequest::track`，`-b` 一律帶 `--track` 或 `--no-track`；`gbm_worktree_add` 加 `int32_t track`（ABI 變更，C 與 Dart 同一個 commit）。對話框只在「Checkout 既有 + 遠端 + 本地不存在」傳 `track: true`，createNew 不傳。`track` 沒有 UI：它不是使用者選項，是對話框依模式決定的事實（使用者確認不加勾選框）。

**計畫漏掉、實作時補上的一條**：[TEST-ffi-matches-symbol-only] 要求意義改變的 capi 參數有 device tier 測試真的過 `dart:ffi`。計畫的 acceptance 只寫了「跑既有的 `worktree_add_refresh_test.dart`」，而那兩條既有測試都不看 upstream。補了兩條：createNew 在 `inherit` 下、remote-only checkout，各讀 `.git/config`（不在 app 開著時跑 git，[TEST-no-dart-process-while-core-runs-git]）。後者能抓到 Dart 端把 `track` 與 `force` 位置對調。

**一個自己寫錯的斷言**：C1 的整合測試第一版寫 `EXPECT_EQ(out, "\n")`，修好後仍紅：`IProcessRunner::run()` 會去掉最後的換行（[CPP-run-not-byte-exact]）。改前的紅是真紅（值為 `refs/remotes/origin/main`），只是斷言寫錯了空值的樣子。

**一次格式疏漏**：C2 commit 前的 `git clang-format --diff --staged` 有輸出，但指令串接沒有在它非空時停下，commit 照樣落地。尚未 push，以 `--amend` 只加入那一處換行。本機 clang-format 是 23、CI 是 22；整檔的既有違規不是本輪造成，只檢查改動的行。

**不寫規則**：`memory-steward` 判 ENCODE。兩個點已由測試與 site comment 守住；「每個建立分支的指令都要明示」的通則與 `CheckoutOp.cpp` 的 `git switch --create`（checkout 遠端成本地，刻意追蹤）矛盾，寫成規則會誤導下一輪。

## Result

Mutation（每次先備份到 scratchpad、跑完從備份還原）：

| # | Mutation | 跑的範圍 | 紅的測試數 | 是哪幾條 |
|---|---|---|---|---|
| M1 | C1 拿掉 `--no-track` | `gbm_core_tests` 全部 779 | 2 | `RefusesImplicitTrackingWithoutAnUpstreamRequest`、`RemoteRepoTest.ANewBranchFromARemoteStartPointHasNoUpstream` |
| M2 | C2 core 拿掉 flag | `*Worktree*` 38 | 2 | `WorktreeTrackingTest` 的 remote 起點、inherit |
| M3 | C2 core 一律 `--no-track` | `*Worktree*` 38 | 1 | `CheckingOutARemoteOnlyBranchStillTracksIt` |
| M4 | 對話框 `track: true`→`false` | `add_worktree_dialog_test.dart` 37 | 1 | remote-only checkout |
| M5 | Dart 端永遠送 `track=0` | device tier 4 | 1 | remote-only checkout 仍追蹤 |
| M6 | C2 core 拿掉 flag | device tier 4 | 1 | 新分支不繼承 upstream |

Mutations run：6；tests reddened：2、2、1、1、1、1，每個都只紅預期的那幾條。

Suites：`ctest --preset capi-only` 1092/1092；`flutter test` 4613 passed / 19 skipped；`flutter analyze` 0；`dart format` clean；device tier `worktree_add_refresh_test.dart -d macos` 4/4。

Post-implementation `verifier`：**CONFIRMED**（`af2cd96b`）。它自己重跑 device tier 4/4、目標 gtest 9/9 與 `WorktreeApiTest` 16/16、dialog 與 `gbm_capi_signature_parity_test.dart` 202 passed，並在 scratch repo（git 2.56.1）以 true / always / inherit 三種設定、remote / 本地 / 無起點三種起點確認 `--no-track -b` 都沒有 upstream，舊 argv 則重現 `origin/develop`。兩條 P4 建議，皆 DEFER：A1 device tier 的建立新分支用的是 inherit + 本地起點，不是使用者原本的 `origin/develop` 起點（該輸入已由 core 測試 `ANewBranchFromARemoteStartPointHasNoUpstream` 與 dialog 測試 `track: false` 覆蓋）；A2 `autoSetupMerge=always` 只有手動驗證（修正靠明示 flag，不依賴設定值）。

**留給使用者裁定的觀察（未開 issue）**：`CreateBranchRequest.setUpstream=true` 送的是 `git branch <n> <start> --track <upstream>`，而 `--track` 的選擇性參數只吃 `=` 形式，`<upstream>` 會被當成第三個位置參數。目前 `lib/` 沒有任何呼叫者傳 `setUpstream: true`（[CULT-orphan-wiring] 的形狀），所以沒有使用者看得到的影響。`CheckoutOp` 的「checkout 遠端成本地會追蹤」也沒有測試釘住（memory-steward 指出），本輪未動。

不在範圍：`git checkout -b`／checkout 遠端成本地（`checkout_dialog.dart`、`checkoutRemoteAsNewLocal`）：那是「把遠端分支拿到本地」，追蹤是預期。
