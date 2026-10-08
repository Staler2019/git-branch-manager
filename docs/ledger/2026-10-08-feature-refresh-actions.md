# feature/refresh-actions — refresh 不再跑 LFS、submodule、bisect 與 identity 讀取

## Situation

使用者回報兩件事：每次 refresh 都會跑 LFS（本機根本沒裝 git-lfs）；每次 refresh 都會去問
`user.name`/`user.email`，「它不是網路工作，也不是寫入或編輯 config 的指令」。

`RepoSessionController.refreshRepoStatus()`（focus 回來、F5、View → Refresh 共用）的 tier 2
（`_callTier2Members`）原本有八個成員，規則是「每個無參數的 `refresh*` 都在 sweep 裡」：

```
refreshStashes / Worktrees / Remotes / Submodules / BisectStatus
refreshLfs / refreshLocalIdentity / refreshEffectiveIdentity
```

## Task

先查每個成員的狀態到底被誰讀（`grep` 全 `app_flutter/lib`）：

| 狀態 | 讀者 | 處置 |
|---|---|---|
| `lfs*` | 只有 `lfs_panel.dart` | 移出 sweep，面板開著時跟 sweep 重讀 |
| `submodules` | 只有 `submodules_panel.dart` | 同上 |
| `bisectStatus` | 只有 `bisect_panel.dart`（bisect 進行中的 banner 走同步的 `repoState`） | 同上 |
| `localIdentity` | 只有 Repository Settings 對話框（開啟時自己會讀） | 移出 sweep |
| `effectiveIdentity` | 對話框＋`commit_graph_view.dart` 的「我的 commit」email | 移出 sweep，改在開 repo 時讀一次 |
| `stashes`/`worktrees`/`remotes` | sidebar、compare、各對話框 | 留在 sweep |

使用者的裁定：

1. 「lfs會影響commit graph顯示嗎，如果不會應該限定在只有lfs面板開著」——LFS 只在面板開著時跑。
2. identity：「原來是我的commit判斷要用嗎，如果只有這個要用，那確實你這樣ok」——接受「在終端機改
   `git config user.email` 後，要重開 repo 或開設定對話框才會更新」。
3. 「submodulesm bisectstatus是不是也只有在他們的panel才有影響」——是，比照 LFS 處理。

原始請求是「app 啟動時偵測 LFS 是否安裝」。refresh 既然完全不碰 LFS，啟動偵測只會讓每次開 app
都多一個 `git lfs version`；改沿用 `Session::refreshLfs()` 既有的「每 session 首次才偵測並快取」，
而它現在只在 LFS 面板開啟時發生。這一點寫在計畫裡，計畫經使用者核准。

## Action

四個 commit，各自可 revert：

1. `aa89c62` identity 移出 sweep；`_open()` 讀兩者各一次。
2. `d640340` 新增 `features/panels/refresh_sweep_listener.dart` 的 `listenToRefreshSweep()`
   （位置由 arch-suggester 建議）：監聽 `refreshTimings.focusAt`，面板掛著時每個新 sweep 呼叫一次；
   LFS／Submodules／Bisect 三個面板在 `build()` 接上，`initState` 的首次讀取不變。
3. `0a736f8` LFS／submodules／bisect 移出 sweep。
4. 本 commit：ledger、`operation_log_benign_exit_test.dart`（device tier）更正。

```
之前: F5 ─► tier1 ─► tier2 [8 個]
之後: F5 ─► tier1 ─► tier2 [Stashes, Worktrees, Remotes]
      Lfs/Submodules/Bisect 面板掛著 ─► focusAt 換新 ─► 各自 refresh*()
      _open() ─► refreshLocalIdentity() + refreshEffectiveIdentity()
```

被本輪推翻、原地劃掉更正的紀錄：

- `refreshRepoStatus()` 的 membership 規則（加上例外清單），與「`git submodule status` 79ms 但
  照樣無條件跑」一段——移出是因為讀者只有面板，不是因為成本，也不是猜 repo 有沒有 submodule，
  所以 `STATE-never-guess-what-git-would-say` 仍成立，並補一行 Do。
- `operation_log_benign_exit_test.dart` 的前提「Session open does *not* read the local
  identity」。改為：identity 來自 open，並斷言 F5 不再新增任何 `user.name` 讀取——這正是使用者
  的回報。
- tier-2 成員數（eight／twelve）出現在 `app_preferences_repository.dart`、`refresh_timings.dart`
  與三個測試檔，全部改成不帶數字的描述。

## Result

- 紅→綠：C1 兩支（open 讀 0≠1；sweep「不在 sweep 內」1≠0）、C2 四支（三面板＋helper）、
  C3 一支。
- Mutation（runs / 紅的測試數）：C1 2 / 各 1；C2 5 有效 / 1、4、1、1、1（另一個 run 因型別
  不符而編譯失敗，不計）；C3 3 / 各 1。
- **沒被任何 mutation 弄紅的測試**：helper 的「unmount 後不呼叫」。`ref.listen` 隨 element 一起拆除
  是結構保證，沒有一個能編譯的 mutation 能違反它；這支測試保留作為行為說明。
- `flutter analyze` 0、format 乾淨、`check-rule-pins.py`／`check-instruction-budget.py` 通過。
- Flutter 全套：3252 passed、1 skipped。
- Device tier（`integration_test/operation_log_benign_exit_test.dart -d macos`）：綠。新斷言做了
  mutation：1 run / 1 紅（把 `refreshLocalIdentity()` 放回 tier 2 → `Expected: <2> Actual: <3>`）。
  其他 `integration_test/` 檔案沒有碰到 refreshLfs／Submodules／BisectStatus／identity 或 viewRefresh
  的入口（以 grep 確認），所以沒有跑。
