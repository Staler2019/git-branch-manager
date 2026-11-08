# feat/next-launch-recovery — 上次開啟途中結束，下次啟動就不自動重開

## Situation

#207：Windows 繁中（ACP 950）上，最近開啟的 repo 若是路徑含 CJK 的 linked worktree，`gbm_capi.dll` 在開啟時丟出
`std::system_error`，行程直接結束。app 每次啟動都重開最近的 repo，所以每次都 crash，使用者只能手改
`shared_preferences.json`。#207 建議的第 4 點就是「上次開啟失敗就跳過」。A（錯誤通道）、B（crash filter）已合併，
這是 A → B → C 的 C。

## Task

使用者裁定：

- PR 切分：「C：開 repo 前留標記、成功後清除；若上次沒成功，就不自動重開，進 Welcome 並顯示原因」。
- 顯示：「Welcome 上的紅字加 Log 抽屜那一列，寫明『上次開啟某 repo 時 app 結束，已跳過自動開啟』，且只跳過一次，使用者手動再開就照常」。
- 標記範圍（2026-11-08，AskUserQuestion）：「開啟完成就清」，不是整個執行期間都立著。
- plan review 經過五個版本（REVISE ×5），使用者在第四、五版都選擇再審一次，第五版選「核准，AUTO 模式」。

G1：spec-auditor 稽核 12 個值，6 符合、2 不符、3 無出處、1 屬裁定。改掉的兩處不符：產品名寫成 `Git Branch Manager`
（app 內一律是 `git-branch-manager`），原因句比裁定寬；另外自創的 `Crash log:` 改回既有的 `(details: …)`，切換彈窗的頁碼更正為 P02 #15。
規格沒有任何關於啟動時重開上次 repo 的規則；列的去處依 P15 B「只是通知結果的留在 log 抽屜與狀態列」。

## Action

```
bootstrapApp（runApp 之前）
  decideStartupTarget(marker, recents)
  ├─ OpenRecent(workDir) ─► await marker.set(workDir) ─► override pendingAutoReopenProvider
  │                                                      │
  │      AutoReopenHost（router 之上）listenManual(repoSessionProvider(workDir), fireImmediately)
  │                         isFirstLoadSettled: lastError != null || (isOpen && !isRefreshing)
  │                         └─► marker.clear()
  └─ Welcome(skipped) ──► await marker.clear() ─► override skippedAutoReopenProvider
                            AutoReopenHost: Future.microtask ─► windowLogProvider 寫一列 error
                            "Skipped reopening <workDir>: git-branch-manager quit while opening it
                             last time. Open it again from File → Switch repository… (details: <log>)"
appRouterProvider 讀 startupTargetProvider（預設 = 原本「開最近的 repo」，不讀標記）
gbm_native_error_log_path_json() ─► readNativeErrorLogPath() 給 (details: …)
```

Commits：

1. `336f1060` capi 匯出 log 路徑與 Dart binding。
2. `cf3aa122` 標記、`AutoReopenHost`、`AppLogEvents.autoReopenSkipped`；兩個 provider 預設 null，這個 commit 不生效。
3. `f99b8404` `StartupTarget`、bootstrap 寫入／清除、router、改正兩處 doc。
4. `2212e432` 正常結束也清標記（使用者 2026-11-08 「開啟完成就清 要加」）：`AppExitSessionCleanup` 在 `closeAll()` 之後
   await 清除，更新的交接 `_closeSessions()` 同樣清除。
5. `c2eaa785` 補測試（使用者「test 沒涵蓋要補」）：GbmApp 層的 skipped 列與結束清除、「開啟完成」只看 history、兩個 app 同時執行。

### Mutation

| Commit | 跑了 | 變紅 | 說明 |
|---|---|---|---|
| 1（C++） | 2 | 2 | JSON key、路徑換成 temp dir；都只紅 `TheLogPathIsStagedAsJson` |
| 1（Dart） | 3 | 3 | 忽略回傳值、拿掉型別檢查、讀錯 key；各紅一個 |
| 2 | 8 | 8 | 第一次跑時 zsh 把三個測試檔併成一個參數，8 個都是「載入失敗」，不算；改 `${=T}` 重跑才是這裡的數字 |
| 3 | 7 | 7 | 另有 2 個把 collection-if 的元素刪成空行，編不過，不計；改成 override 為 null 後重跑 |
| 4 | 3 | 3 | 拿掉結束時的清除、清除移到 `closeAll()` 之前、拿掉更新交接的清除；各只紅對應的一個測試 |
| 5 | 4 | 4 | `app.dart` 不掛 `AutoReopenHost`（紅 GbmApp 的 skipped 列 1 個）；`isFirstLoadSettled` 改成也等 working copy（紅 5 個）；第二個 app 啟動時不清標記（紅 2 個）；拿掉結束清除（紅 GbmApp 的結束測試 1 個）。第一次跑 `app.dart` 那個時錨點沒對上（dart format 把呼叫併成一行），斷言失敗、檔案沒動，修好錨點重跑才是這裡的數字 |

commit 3 的兩個 plan 指定 mutation：拿掉 pending override、override 成 `'$workDir/'`，都讓 `app_auto_reopen_test.dart`
「marks it until its first load settles」變紅。

## Result

- Flutter 全套 4590 通過（16 skip）；分析 0 issue。commit 4、5 之後重跑：4596 通過（16 skip），分析 0 issue，format 無變更。
- capi（`capi-only`）1069 個 100% 通過。第一次只看了 `tail -4`，沒有通過率那一行；`LastTestsFailed.log` 列著 NativeErrorApiTest，
  但檔案時間是 11-05，是舊的。重跑一次讀到「100% tests passed out of 1069」才算數。
- wiring-auditor：15 個符號全部有 producer 與 reader，`bootstrapApp` 的 `extraOverrides` 只有測試傳（刻意的測試接口）；
  `lib/` 裡沒有其他地方用 recents 決定初始路由，`main.dart` 的唯一 `runApp` 經過 `bootstrapApp`。
- device tier 的 `pumpRealAppOn` 不經過 `bootstrapApp`，拿到的是 `startupTargetProvider` 的預設值，所以 device tier 從來不走標記路徑；
  走真 `bootstrapApp` 的只有 `test/integration/app_auto_reopen_test.dart`。
- device tier（macOS）：`update_check_flow_test.dart` 2/2（Welcome）、`worktree_pending_counts_test.dart` 1/1（真 repo 的 workspace）。

### 和計畫不同的地方

- export 名稱是 `gbm_native_error_log_path_json`，不是計畫寫的 `gbm_native_error_log_path`：跟著同樣把 JSON 放進 staging buffer 的
  `gbm_git_version_json` 命名。
- 計畫狀態表的「prefs 寫入丟例外 → bootstrap 攔下」沒有做：`shared_preferences_windows` 2.4.1 的 `_writePreferences`
  自己 catch 並回傳 false（`lib/shared_preferences_windows.dart:374-399`），不會丟到 bootstrap；攔一個不會發生的例外也沒有測試能讓它變紅。
- 「skipped 列在 Welcome 重新掛載後仍只有一列」只測了 host 底下的子樹重建，沒有 mutation 涵蓋。

### 已知缺口

- 開啟完成之後才 crash 的，下次照常自動重開（裁定的範圍）。
- ~~兩個 app 同時執行時會搶同一個標記。~~ 行為已定並有測試（commit 5）：第二個 app 啟動時看到第一個還立著的標記，當成 crash，
  進 Welcome、寫一列 skipped、清除標記；第一個之後再清不會出錯。誤報一次，不會 crash loop。
- ~~macOS 的 `shared_preferences_foundation` 走 NSUserDefaults／cfprefsd，crash 前剛寫入的值能不能留下沒有驗證；#207 是 Windows。~~
  量過：2.5.6 的寫入是 `UserDefaults.standard.set(value, forKey:)`，不呼叫 `synchronize`（`SharedPreferencesPlugin.swift:40-41`）。
  用同一個呼叫寫入後立刻 `abort()` 的 Swift probe，延遲 0／100／1000 ms 各 20 次，`defaults read` 讀回 60/60（macOS 27.0.1）。
  不能做成自動測試：測試行程無法在自己 crash 之後讀回，device tier 也不在 CI。
- 「開啟完成」只看第一次 history 讀取；working copy 的第一次讀取還在跑時就清除了標記。這是定義，commit 5 用
  `isFirstLoadSettled` 的「working copy 未讀仍算完成」釘住。

### verifier 的結果

fresh `verifier` 對 `dea43750` 判定 **CONFIRMED**。它重跑了 Flutter 全套（4590）、analyze、capi 1069、real-library 測試，
並把 commit 1、2 的樹各自抽出來跑全套（4568、4583，analyze 0）；commit 3 與 HEAD 在程式碼上相同。另外寫了 real-library 端到端 probe
（真 `GbmBindings`、真 `RepoSessionController`、真 git repo，經過 `bootstrapApp`）：讀取中標記保留，第一次讀取結束後清除；
不存在的 work dir 以 `ProcessFailed` 結束，標記同樣清除。10 種 work dir 拼法（結尾 `/`、`%20`、`#`、`C:\…`、CJK）經 route 解回的
`RepoIdentity` 都和 host 用的相等。

advisories（未修，依 P3/P4 預設 defer）：

- ~~P3：第一次讀取還沒結束時使用者就正常關閉 app，標記會留下，下次啟動會被跳過一次，訊息寫「quit while opening it」。
  在「開啟完成就清」的裁定範圍內；要不要在正常結束時也清標記，留給使用者決定。~~ 使用者決定「要加」，commit 4 修正。
- P4：讀取期間任何一個讀取的 `errorOccurred` 設了 `lastError` 就算「完成」，比 doc comment 寫的寬；working copy 的第一次讀取可能還在跑（已在已知缺口）。
- P4：`readNativeErrorLogPath` 在 microtask 裡沒有 try/catch，binding 丟例外時這一列不會寫出；這是刻意的（fake 少成員就該當場失敗），正式版 library 一定帶這個匯出。
