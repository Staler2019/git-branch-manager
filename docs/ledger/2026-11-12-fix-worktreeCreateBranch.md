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

**追加（使用者第二次裁定）**：三件事。

1. 「`autoSetupMerge=always` 加測試，要驗環境」。新 fixture `BranchTrackingTest::useAutoSetupMerge(value, controlStart, controlUpstream)`：設定後讀回確認，再跑一個不帶 flag 的 `git branch env-control <controlStart>`，斷言它**確實**得到 `controlUpstream`——設定在此環境沒生效時測試紅在這一步，不會假綠。New branch 與 worktree 各補一條 `always`（本地起點，git 以 remote "." 追蹤 `main`）；既有 inherit 測試改走同一個驗證。commit `9fd198ab`。
2. 「`CreateBranchRequest` 為什麼沒用到，是因為都用 checkout -b 嗎」。不是：New branch 對話框每次都走 `CreateBranchOperation`；沒有呼叫者的只是 `setUpstream`/`upstream` 兩個欄位，因為對話框設 upstream 是另送 `push -u`（新分支第一次 push 前沒有遠端 ref 可追蹤）。`git switch --create` 只用在 checkout 遠端成本地。
3. 「Checkout 遠端分支成本地，要加測試，商業邏輯要保住」。實測 `git -c branch.autoSetupMerge=false switch --create s1 origin/develop` 沒有 upstream，加 `--track` 則有——`CheckoutOp` 原本沒帶 flag，這條商業邏輯在 `false` 下是破的。`CheckoutOp` 建立分支時改為明示 `--track`。不需改 capi：這個 op 建立分支的呼叫端（Checkout 對話框 `_createsLocalBranch` 只在選遠端時、側邊欄 `checkoutRemoteAsNewLocal`）都傳 remote-tracking ref；「stash 後重試」沿用同一個 request，也帶得到。commit `14c3b151`。

**一個假紅**：C5 的 `false` 測試第一次紅在環境驗證那步，不是主斷言：對照組用了 `origin/main`，但 fixture 只 push 了 `main:topic`。改成 `origin/topic` 後才是真紅（`upstreamOf("topic")` 為空）。環境驗證本身攔下了一個寫錯的 fixture。

C7 `9949e1ad`：移除 `CreateBranchRequest.setUpstream/upstream`、`gbm_branch_create` 的兩個參數、Dart binding、`RepoSessionController.createBranch` 與 fake 的對應參數；`CreateBranchOperation` 一律送 `--no-track`。`CreateBranchRequest` 本身仍被 New branch dialog 使用（`new_branch_dialog.dart` → `createBranch`），不是因為改用 `checkout -b` 而沒用到；沒有呼叫者的只有這兩個參數。新分支的 upstream 仍只由 `pushChanges(setUpstream: true)` 設定。C8 `29d414b9`：依 verifier 回報更正 `CheckoutOp.h` 的註解——git 拒絕 `--track` 的是 raw commit id、tag、以及沒有 remote fetch refspec 對應的 `refs/remotes/` ref；`HEAD` 這類符號 ref 會被接受。

C10：使用者裁定「time limit 移除，目前這limit太極限了」。PR #221 的 `Flutter UI - macOS (arm64)` 每一步都成功（`flutter test` 4612 通過、`flutter build macos` 成功），但 job 跑 25 分 04 秒，被 `timeout-minutes: 25` 取消；`fix/crash-filter-stack-overflow-log`、`fix/stuck-waits-threads-and-pre-post` 近期也有相同的 cancelled。移除 `ci.yml` 6 個、`cq.yml` 4 個 job 的 `timeout-minutes` 與其說明註解，並就地改寫 [CI-no-ctest-timeout]：測試的期限只剩 `CMakePresets.json` 的 `tbase.execution.timeout`（300 秒／測試），ctest 以外的卡死會跑到 GitHub 的 6 小時上限。

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

**留給使用者裁定的觀察（未開 issue）**：`CreateBranchRequest.setUpstream=true` 送的是 `git branch <n> <start> --track <upstream>`，而 `--track` 的選擇性參數只吃 `=` 形式，`<upstream>` 會被當成第三個位置參數。~~目前 `lib/` 沒有任何呼叫者傳 `setUpstream: true`（[CULT-orphan-wiring] 的形狀），所以沒有使用者看得到的影響。~~ 使用者裁定「沒人用 => 移除」，兩個參數已在 C7 移除，見下方追加段。~~`CheckoutOp` 的「checkout 遠端成本地會追蹤」也沒有測試釘住（memory-steward 指出），本輪未動。~~ `CheckoutOp` 的「checkout 遠端成本地會追蹤」也沒有測試釘住（memory-steward 指出）。使用者裁定要保住，見下方追加段：它在 `autoSetupMerge=false` 下其實不追蹤，已修。

~~不在範圍：`git checkout -b`／checkout 遠端成本地（`checkout_dialog.dart`、`checkoutRemoteAsNewLocal`）：那是「把遠端分支拿到本地」，追蹤是預期。~~ checkout 遠端成本地（`checkout_dialog.dart`、`checkoutRemoteAsNewLocal`）追蹤是預期行為；原本以為它不受影響而列為範圍外，實測 `autoSetupMerge=false` 下不追蹤，見下方追加段。

**追加段的 mutation**：

| # | Mutation | 跑的範圍 | 紅的測試數 | 是哪幾條 |
|---|---|---|---|---|
| M7 | BranchOps 拿掉 `--no-track` | 分支追蹤相關 11 條 | 3 | always 新測試、兩條既有 New branch |
| M8 | WorktreeOps 拿掉 flag | 同上 | 3 | worktree 的 remote 起點、inherit、always |
| M9 | 環境驗證改成設 `false`、不讀回 | 同上 | 3 | 三條用 `useAutoSetupMerge` 的測試，全紅在對照組 |
| M10 | CheckoutOp 拿掉 `--track` | `gbm_core_tests` 全部 787 | 2 | `false` 下的短名稱與完整 ref 兩條 |

`ctest --preset capi-only` 1097/1097。沒有改 Dart，`flutter test` 未重跑。device tier 沒有走 checkout 遠端成本地的測試；真實 git 行為由 core 整合測試覆蓋，Dart 端「選遠端時送 `createBranch: true`」由 checkout dialog 的 widget 測試覆蓋。

C7 為移除，沒有先紅的測試；以 M11（只在 header 還原兩個參數）驗證 `gbm_capi_signature_parity_test.dart`：只紅 `gbm_branch_create` 一項，已還原。全套：ctest 1096/1096、flutter test 4612 通過 / 19 skipped、`flutter analyze` 0。第二次 verifier（C4–C7）CONFIRMED，附兩條 P4：(a) 不對應任何 remote fetch refspec 的孤兒 `refs/remotes/<x>/<b>`，checkout 成本地現在因 `--track` 報「cannot set up tracking information」而非建立不追蹤的本地分支——罕見、走一般失敗路徑顯示、不遺失資料，defer；(b) `CheckoutOp.h` 註解範圍過廣——已於 C8 更正。
