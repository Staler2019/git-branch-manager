# fix/worktree-and-working-copy-refresh — worktree 刷新、working copy、刪除分支

## Situation

使用者一次回報六個問題（第六個 New repository dialog 另開 Round B，`feat/new-repository-dialog`）：

```
1a  在目前 worktree checkout 後，worktree 清單的分支沒更新
1b  Add worktree 仍鎖住已切走的分支
2   切換 worktree 後 working copy 沒刷新
3   F5 時檔案清單延遲更新
4   移除 worktree 後，它的分支仍刪不掉
5   刪除分支時 unmerged 檢查應只在確認前警告一次，確認後不能再擋
```

回合中追加兩項：worktree 操作要在 status bar 顯示為執行中工作；remove worktree 預設接著 prune。

## Task

每個問題先找到根因再修，一個 slice 一組可逆 commit，每個 commit 先紅後綠並做 mutation check。
使用者裁示：

- 1b：根因是過期清單，**不加 `--force`**。
- A8：Adding / Removing worktree 前景顯示（比照 Checkout），Pruning worktrees 與 lock/unlock 摺疊（比照 Prune）。
- A5：「先 normal，有目錄才展開」。
- A6（問題 5）：有 upstream 就跟 upstream 比；沒有 upstream 或 upstream 已 gone 就不比，提示「沒有 upstream（或已 gone），無法確認是否已同步」後以 `-D` 刪。批次 dialog 在範圍內，`delete_remote_branch_dialog` 不在。
- 資料夾選單「Delete merged branches…」整個移除，spec 一併修訂（A9）。
- A6 的重試 tip 採 (b)：forceDiscard 重試一律用 C1 查詢回傳的 tip，不新增 capi outcome 欄位，C5 不提前。
- A6 的 plan 經五次 plan-verifier 皆 REVISE、blocker 均 FIX；使用者裁示「那就交給dedicate verify去之後驗收這段吧」，實作後由 verifier 驗收。

## Action

### 問題 2：兩個根因，第一個推論是錯的

~~`RepoIdentity.forWorkDir` 把 gitDir 設成 `<wt>/.git`，linked worktree 的 `.git` 是檔案，`RepoState::watchTargets` 監看不存在的路徑 → 檔案變動永遠不觸發。~~
實作開始後查證：`watchTargets` 在 `src/` 與 `lib/` 都沒有呼叫端，這個推論不成立。真正的根因：

1. `repoSessionProvider` 不是 `autoDispose`，A→B→A 切回時沿用 A 的舊 session，而 `WorkspaceScreen.didUpdateWidget` 在 identity 改變時不刷新（45533a19，改為呼叫 `refreshRepoStatus`，與 focus regain 同一入口、不經節流）。
2. go_router 以 route 而非 repoId 當 page key，`WorkingCopyView` 跨 identity 沿用同一個 State，commit box 帶著上一個 repository 的 draft（8535325a）。

gitDir 指向指標檔仍是真缺陷：linked worktree 內 `RepoState` 查不到 `MERGE_HEAD`、`rebase-merge`、`index.lock`，合併中仍回報 clean。`Session::open` 改以 `RepoClassifier::resolveGitDirFile` / `resolveCommonDir` 解析（fde0824e）。

### 問題 1a / 1b：checkout 之後沒有重發 worktree 清單

`Session::checkout` 成功路徑沒有 `onSuccess`。補上 `refreshWorktrees()`（0cbd70ca）。Add worktree dialog 的「已在 <dir>」判斷讀同一份清單，所以 1b 一起好了。同形狀的漏洞還有 `createBranch(checkoutAfter)` 與 `renameBranch`（b6c26bf7）。

### 問題 4：git 本來就放行，擋住的是 Dart

先重現：兩個情境的 capi 測試（一般 remove、目錄已被外部刪除再 remove）在修正前就是綠的，git 在 remove 後即允許刪除分支。擋住的是 sidebar 批次 gone 選取：它排除 `RefInfo.worktreePath` 非空的分支，而 worktree 操作從不重讀 refs。add / remove / prune 的 `onSuccess` 加上 `refreshHistory`（2d1f5ca8）。

使用者追加的「remove 預設 prune」（d1d206e3）：plan 原寫「remove 失敗但目錄已不存在時也 prune」，實測目錄已不存在時 `git worktree remove` 本身就成功（`RemovingAWorktreeWhoseDirectoryIsAlreadyGoneFreesItsBranch`），這個分支不需要。prune 是盡力而為，失敗只進 operation log。

### A8：status bar 看不到 worktree 操作

`running_git_tasks.dart` 的 `_taskKind` 白名單沒有 `worktree`（f22e462a）。plan 原寫的次因「worktree 操作沒登記 `inFlight_`，Cancel 找不到它」~~成立~~ 不成立：指定 id 的 Cancel 走 `operations_->cancel(id)`，不經 `inFlight_`，C++ 不需改。

### 問題 3：量出來不是排隊

plan 原本的假設是 `refreshWorkingCopy` 排在 history walk 後面（FIFO），打算改 `postFront`；但 [CPP-interactive-reads-go-to-the-front] 刻意把它留在 `post()`，所以先量。在 microsoft/vscode 上：並行 walk 只多 0–110 ms；真正的成本是 `git status --untracked-files=all` 本身 450–710 ms。

改為 `=normal`，只在出現 `? dir/` 記錄時跑一次 `git ls-files --others --exclude-standard -z -- :(literal)<dir/>...` 展開（3f173de0）。各 10 次中位數：

| 情境 | `=all` | `=normal` + 展開 |
|---|---|---|
| 無未追蹤目錄 | 473 ms | 31 ms |
| 一個含 200 檔的未追蹤目錄 | 464 ms | 54 ms |

`RealRepoTest.WorkingCopyUntrackedListMatchesUntrackedFilesAll` 逐筆比對兩種模式（nested repo、ignored、空白與 unicode 路徑、glob 形狀的目錄名 `g[1]`）。mutation 4 個有效、轉紅 1/2/1/10；另 2 個因 `-Werror`（未使用函式）沒編過、結果作廢後改寫重跑。

### A9：「Delete merged branches…」

標籤帶 `…` 卻不開 dialog，直接對整個資料夾送 `-d`（[UX-ellipsis-promises-a-dialog]）。spec 先修（a9e20cb8：05-J 移除該項與前面的分隔線，P16 REVISIONS 加一列；plan 原寫 05-C，05-C 其實是 Remote-only/gone branch），再刪碼（ac52718d），orphan grep 兩向 0。

### 問題 5（A6）：確認前警告，確認後直接刪

舊流程：dialog 送 `-d` → git 拒絕 → 事後才跳 Delete Blocked；勾「同時刪遠端」時遠端結果覆寫 `_lastFailedDeleteBranchRequest`，重試變成無動作。

```
開 dialog ──► BranchStore::probeDeletion（一次 for-each-ref；rev-list --count <tipOid> ^<upstream>）
               │ counted 0           → -d（git 也拿同一個 upstream 比，不會拒絕）
               │ counted >0 / noRef  → 警告 → -D，expectedTipOid = 查詢的 tipOid
               ▼
core: tip 比對（live 過濾之後）── 不符 → StaleBranchTip ／空 tip → MissingBranchTip，整個請求不刪
               ▼
controller: 拒絕一到就重查 → Delete Blocked 顯示新數字；Delete anyway 送這次查詢的 tip，按下時不再查
               ▼
本地成功後才送遠端刪除（thenDeleteRemote）
```

commit：C1 414941c8（`BranchStore::probeDeletion`）、C2 63c994b8（逐名 entries、tip 比對）、C3 95aa51e9（capi 事件 40、Dart 接線）、C4 1f622311（遠端延後、拒絕時查詢）、C4b 97fc2f41（Delete Blocked 顯示數字）、C5 e9530f7d（單一 dialog）、C6 8e288ee8（批次 dialog）。

偏離 plan 的地方：

- C2：tip 不符時 plan 原寫「該名不刪」，實作改為**整個請求都不刪**，避免部分刪除的中間狀態；recovery dialog 會重查全部名字。plan 已原處更正。
- C5 / C6 的「snapshot 與查詢 tip 不一致 → 停用並重查」解讀為「查詢之後 snapshot 的 tip 變了就重查」，而不是「查詢 tip 必須等於 snapshot tip」：後者在 refs 刷新落後時會無限停用。
- C6 的 `canDelete` 原本另外檢查「查詢已到且無錯誤」，兩個 mutation 存活，查證後是等價：查詢中或失敗時 entries 本來就是空的。改成只看 `entries.isNotEmpty`。批次 dialog 保留「失敗的查詢即使帶 probes 也不採信」的守門，並以一個合成 fixture 釘住（core 不會送出這種回覆）。
- C5 的「較舊查詢晚到時捨棄」測試是在實作後才補的（mutation「不比對 seq」存活才發現沒測），它的紅只來自 mutation。

**G1。** 草稿逐字列出三個 dialog 的 31 個字串，spec-auditor 結果：符合 9、不符 6、無出處 16。草稿本身的引用錯誤在此更正：Delete branch 的 note 屬 `DIALOGS` 不屬 `DLGS`；「同時刪除遠端分支」在 spec 沒有原文；plan 的 `delete_branch_dialog.dart:263` 實為 `:270`。使用者裁示：

1. 數字措辭「N 個 commit 尚未同步到 origin/x」（upstream 短名），不用 DIALOGS 的「未合併」或 P13 的「未 push」。
2. spec mock 的「刪除後只能透過 reflog 找回」不成立：`-D` 會刪掉分支自己的 reflog。單一 dialog 不補說明，Delete anyway 的說明整句拿掉，「都不寫」。
3. 批次 dialog 加總警告「其中 K 個分支會直接刪除，不再檢查是否已合併。」
4. 單一 dialog 對齊 mock：標題 `Delete branch`、「刪除本機分支 x。」、「同時刪除遠端 origin/x」。

spec 的「Deleted branch recovery」（刪除後 30 秒內從 status bar 以 Restore branch 撤銷）目前沒有實作，也不在 A6 範圍；已告知使用者，未裁示。

**mutation 合計（A6）。** C1 4 個（轉紅 2/1/2/1）；C2 5 個有效（1/2/2/1/1），另 1 個沒編過、作廢重跑；C3 capi 3、Dart 5；C4 5 個（StaleBranchTip 測試為既有行為守門，無 mutation）；C4b 10 個，其中 7 個第一次因 zsh 不拆 `$T` 參數、整檔載入失敗而作廢，改以分開的參數重跑；C5 12 個有效（1 個錨點因 `dart format` 重排沒對上、作廢重跑）；C6 15 個，2 個存活為等價 mutation（見上）。

## Result

- Flutter 全套 3947 passed、8 skipped（C6 時）；analyzer 0。C++ core / capi 於 C2 時 664 / 237 全綠。
- 問題 1a、1b、2、3、4、5 都已修，加上兩項追加需求。
- post-implementation verifier（A6）：**CONFIRMED**。core 664/664、capi 240/240、Flutter 3947 passed；另在暫存 repo 以 git 2.55 實測「已在 upstream、未併入 HEAD 的分支 `-d` 成功；ahead 的分支 `-d` 被拒」，count 0 送 `-d` 的前提成立。三個非阻擋 advisory，皆非本回合引入，等使用者裁示：
  - P3：core 的 `-d` 拒絕 summary（`BranchOps.cpp`）仍寫 "reachable only through the reflog"，只會在「count 0 送 `-d` 期間分支被移動」的 fallback 出現在 Delete Blocked，與 G1 ② 相抵。
  - P3：upstream 是本地分支（`refs/heads/main`）時，`shortRemoteRefName` 不剝前綴，顯示全名。
  - P4：Delete anyway 重查後全部是 notFound 時 entries 為空，保留的遠端刪除被靜默丟掉（程式推論，未重現）。
- G3 待做：device-tier 測試（使用者已同意執行）、orphan grep、push 與開 PR 前先問使用者。
- 未決：spec「Deleted branch recovery」未實作（見上）。
