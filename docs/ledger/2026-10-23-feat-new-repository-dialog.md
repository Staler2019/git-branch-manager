# New repository 對話框、Clone 的「瀏覽…」

## Situation

File → New repository… 開的是 `promptText`：一個 `AlertDialog`，只有「Path for the new
repository」一欄。spec DLGS 的 New repository 是名稱／位置／預設分支名，外加兩個勾選。這是
Round A（[fix/worktree-and-working-copy-refresh](2026-10-21-fix-worktree-and-working-copy-refresh.md)）
回報清單上的問題 6，獨立成一輪。

## Task

先做 G1 設計稿，裁定後再實作。裁定（2026-10-23，詳見
`docs/claude-design-demo/new-repository-spec.html` 的裁定表）：

| # | 裁定 |
|---|---|
| N-D1 | 「拿掉這個勾選」：不做「建立 .gitignore（從全域範本）」，git 沒有全域 .gitignore 範本 |
| N-D2 | 目標已是 repository → 停用＋warn；存在且非空 → 可建＋warn；空目錄照常 |
| N-D3 | core 先跑 `git check-ref-format --branch` |
| N-D4 | 「不要新建commit」，確認為「對，拿掉空 commit 勾選」 |
| N-D5 | 按下就關，成敗只進 Log |
| N-D6 | 分支名預設 `main` |
| N-D7 | 「沿用現有 shell」：`GbmDialogShell` 不動 |
| C-D1 | Clone 的「瀏覽…」「選的是上層」 |

另一個要求：「clone、新增repo需要改畫面，資料夾輸入改成可以瀏覽資料夾」。

## Action

可逆的 commit 結構，依序：

```
47da7e35 chore  設計稿定稿；spec DLGS 兩處修訂＋P16 REVISIONS 兩列；matrix 的 Clone 列原處更正
a4364241 feat   core：InitRepoRequest.initialBranch，先 check-ref-format 再 init -b
8e8dfdd8 feat   capi：gbm_repo_init(path, initial_branch)＋Dart binding＋兩個測試 fake
9d04fc7c refactor  probeTargetDirectory（missing/empty/nonEmpty/gitRepository），Add worktree 改用
b15a33a7 feat   NewRepositoryDialogContent（/dialogs/new-repository?origin=）取代 promptText
a248af55 feat   cloneDestinationPath＋Clone 的「瀏覽…」
74e12d5d test   device：New repository 走真的 gbm_capi
```

git 行為都是在 git 2.56.0、暫存目錄實測的結果，設計稿的流程表有完整數字。決定設計的有兩點：

- `git init -b a..b x` 會 exit 128，**但 `x/` 已經被建出來**。所以由 core 先檢查分支名（N-D3），
  不然使用者會看到失敗，磁碟上卻多了一個空目錄。
- 對已經是 repository 的目錄跑 `init -b other`，exit 0，並印
  `warning: re-init: ignored --initial-branch=other`。git 不報錯，但分支名不會生效，所以對話框直接停用（N-D2）。

實作中發現並修正的問題：

- **C1：** 原本 timeout 或取消的分支名檢查也會回報成「分支名不合法」。補了一個 red test
  （`ATimedOutBranchCheckIsNotReportedAsAnInvalidName`），只有 git 自己回答「不合法」才算 InvalidArgument。
- **C3b：** 按下 Create 後 dialog 已經 pop，State 也沒了，所以 router、runner、bindings、sink 都在 pop
  之前取好（`appLogSinkFor(ref, originWorkDir)`，沿用 R4／R13）。init 流程從 `repo_switcher_popover.dart`
  移進 dialog；`promptNewRepository` 只剩推送路由，簽名改成和 `promptCloneRepository` 一樣。
- **C4：** 在 Clone 按「瀏覽…」後，`_destEdited` 會重設為 false，目標路徑交回給 URL 自動更新，直到使用者再手改。

設計稿列的「plan 寫三個入口（含 repo switcher）」不對：switcher footer 只有 Open／Clone，實際入口是
workspace 的 File 選單和歡迎畫面。

## Result

**測試：** core 667、capi 247、Flutter 3993 全綠，analyzer 0。device 測試
`new_repository_flow_test` 2/2、`worktree_add_refresh` 2/2。

**Mutation**（mutations-run／tests-reddened 分開記）：

| commit | 跑 | 作廢 | 有效 | 各自轉紅的測試數 |
|---|---|---|---|---|
| C1 core | 4 | 0 | 4 | 2/1/1/3 |
| C2 capi | 4 | 2（`-Werror` unused parameter，改寫後重跑） | 2 | 2/2 |
| C3a probe | 5 | 0 | 5 | 2/1/2/1/2 |
| C3b dialog | 12 | 0 | 12 | 1×11、2×1 |
| C4 clone | 9 | 2（`String?` 傳給 `String` 編譯失敗，改寫後重跑） | 7 | 2/2/2/1/1/2/1 |
| device | 1 | 0 | 1 | 2（C 端忽略 `initial_branch`，2/2 轉紅） |

**跨語言邊界：** `lookupFunction` 只比對符號名稱（[TEST-ffi-matches-symbol-only]），widget 層的 fake
也驗不出 C 端有沒有真的收到分支名。所以補了 device 測試，並做了 C 端 mutation 證明它咬得到。

**既有缺陷（不是這輪造成的）：** 從歡迎畫面轉進任何 workspace，都會觸發 Flutter 的
「More than one active PlatformMenuBar」debug 斷言。用既有的 Open 路徑做最小重現，同樣是紅的。
`WelcomeScreen` 與 `WorkspaceScreen` 各自掛一個 `PlatformMenuBarHost`，新頁面的 `initState` 比舊頁面的
`dispose` 早執行。Flutter 的 `_PlatformMenuBarState.dispose` 會呼叫 `clearMenus()`，所以推測 release
build 轉場後系統選單會被清空，要等下一次 rebuild 重送才恢復。**這個推測沒有量測。**
device 測試的成功案例因此改從 repository 視窗開始。這個缺陷要不要修、要不要開 issue，交給使用者裁示。

**Verifier：** 新開 context 的 `verifier` 對 HEAD `74e12d5d` 回 **CONFIRMED**：core／capi／Flutter 全套件與
device 測試都重跑過。三個 advisory 依 P3／P4 預設處理，都延後，未更動已 CONFIRMED 的實作：

- **P3（延後，待使用者裁示）：** `@{-N}` 形式的分支名。`check-ref-format --branch` 沒有指定 `repoDir`，
  會在 process 的 cwd 執行。cwd 在某個 repo 內時，`@{-1}` 會被展開成前一個分支而通過檢查；接著
  `init -b '@{-1}'` 失敗，並留下空目錄。verifier 在本 repo 內實測 rc=0，在非 repo 目錄實測 rc=128。
  錯誤訊息仍會正確進 Log，只是 N-D3 「不建目錄」的保證在這個條件下不成立。從 Finder 啟動時 cwd 通常是 `/`。
- **P4（延後）：** 除了 Timeout／Cancelled，檢查本身起不來（例如 spawn 失敗）也會被報成「不是有效的分支名」。
- **P4（延後）：** 在 Clone 選了上層之後，若 URL 改成帶不出資料夾名，目標路徑會保留舊值，不會退回成上層本身。
