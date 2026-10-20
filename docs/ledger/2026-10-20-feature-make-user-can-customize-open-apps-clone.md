# Clone 改成背景作業、askpass 修好、憑證遮罩、歡迎畫面照 P15 A

同一個分支的第二段（epoch 4–5）。第一段是
[ledger: worktree 自訂開啟方式](2026-10-18-feature-make-user-can-customize-open-apps.md)。

## Situation

第一段收尾時，Clone 仍是同步的 `gbm_repo_clone`：

- 執行期間畫面卡住。
- 沒有進度，也不能取消。
- 不寫 Log，失敗只在 footer 顯示紅字或重開對話框（Q4、Q5、Q8）。

使用者接著提出的裁定（2026-10-19、2026-10-20）：

- R1：「憑證也是使用者的，沒有資安疑慮」，Clone 失敗要寫進 Log。
- R4：「動作應該是跟 ui 分開的，log一定跟動作強綁定，每個動作都要有log」。
- R6、R7：在來源處遮罩憑證，Log 和日後的 OTel 共用同一份已遮的內容。
- R10–R14：
  - 成功就轉到新 repo。
  - 不跳錯誤彈窗，R5 撤銷。
  - 成功時記錄搬到新 repo 的 Log，失敗或取消時留在發起的視窗。
  - 歡迎畫面也有自己的 Log。
  - 撤掉 Q5、Q8。
- R15–R18：
  - TASKS 的兩段進度，以及「取消刪除未完成資料夾」。
  - 歡迎畫面照 P15 A 重做。
  - repository 列不顯示進度。
  - Clone 對話框補上兩個勾選。

## Task

依 plan 的 epoch 5.3，各 slice 依序如下：

| Slice | 內容 |
| --- | --- |
| S0a | F10 |
| A0 | askpass 修復 |
| S1 | 動作 wrapper、遮罩 |
| S1b | 遮罩的套用點 |
| S5 | 拖曳關閉 Log 時清掉底色 |
| S2、S3a | 動作改走 runner |
| C1 | 進度解析 |
| C2 | capi clone job |
| W0 | 設計稿 |
| W1a | 歡迎畫面 |
| C3 | Dart clone job |
| C4 | 刪除 `gbm_repo_clone` |
| S6 | 規則 |
| S7 | 本檔 |

## Action

### 預審

- **Epoch 4**：
  - security-reviewer 提出 11 項，都在 P3 以下。
  - plan-verifier 第一次 REVISE，3 個 blocker：sink 綁定、取消契約、停止條件。修正後 READY。
- **Epoch 5**：
  - security-reviewer 提出 1 個 P1、4 個 P2、6 個 P3。
  - plan-verifier 前兩次 REVISE，closing review READY。
  - 使用者批准，並裁定 ASK-3 (a)、ASK-4 ok。

### 最大的發現：askpass 在 Flutter 版從來沒有接上（P1-A）

```text
git 需要憑證 ──► GIT_ASKPASS = app 執行檔
                   └─ 三個 runner 都沒在 main 最前面攔截 GBM_ASKPASS_MODE
                        → 開出第二個 GUI，git 等 60 s idle 逾時
```

- 這是既有缺陷，fetch、pull、push 也受影響。平常被 credential helper 或 ssh-agent 擋掉，所以沒人發現。
- 依 standing rule 1，在本輪修好：
  - runner 只有在 `GBM_ASKPASS_MODE=1` 時才 dlopen gbm_capi，取得 `gbm_askpass_main` 後呼叫。
  - 一般啟動完全不碰 dylib。
  - 三個 runner 都改：macOS 新增 `main.swift`，Windows `wWinMain`，Linux `main`。
- 一起修的 askpass 問題：
  - 請求目錄改成 mkdtemp、0700，回應檔 0600 原子寫入（P2-B）。
  - 目錄消失時 client 結束（J1）。
  - prompt 開著時暫停 idle 逾時（J2）。
  - SSH passphrase 預設遮蔽（K）。
  - 帳號之後緊接著問密碼時，第二個提示漏接的 race（97145961）。

### 動作 wrapper 與遮罩

- `AppActionRunner.run(action, sink:, token:)`：
  - 呼叫 `run()` 當下就取得 sink，widget 卸載後仍會寫入。
  - 只接 `on Exception`；`Error` 照樣往外丟，不寫 log。
  - 不可取消的 body 拿到的是 `AppActionCancelToken.none`（F8）。
- `redactUrlCredentials` 套用在三個地方：
  1. `OperationRecord.fromJson`：commandLine 由已遮的 argv 重新組出（`joinCommandLine`）。
  2. `GitError.fromJson`。
  3. runner 的 message 與 outcome。
- 改走 runner 的動作：terminal、自訂應用、匯出、Save Log、New repository。被取代的 `record*Failed` 已刪除。

### Clone job（C1–C3）

```text
Dart CloneJobController ──gbm_clone_start──► capi CloneJob（專屬 thread、askpass、可取消）
     ▲  ◄── 12 OPERATION_LOG_RECORD（排他路由到這個 job）
     │  ◄── 11 CREDENTIAL_REQUESTED → CloneCredentialDialog（CloneJobListener 推）
     │  ◄── CLONE_PROGRESS {phase,current,total} → 狀態列 + Log running row 的 phase
     │  ◄── CLONE_FINISHED {ok,error,removedPath}
     ▼
ok   → origin 收回 → 新 repo session 的 Log 追加 → opened stream → CloneJobListener.go(新 repo)
fail → 留在 origin；Removed <path>（warning）／Could not remove <path>: <reason>（error）
```

- 取消時刪除：
  - 只刪 `ownsDest` 的資料夾，也就是開始時路徑不存在或是空資料夾。
  - 刪除前比對 FileId，並拒絕 symlink。
  - 原本就存在的空資料夾只清內容，保留最上層。
- `ProcessRunner.cpp` 那段「a mutating git process is never killed mid-flight」的錯誤註解，已就地更正。
- 版本門檻（W-D5）：git 低於 2.50.1 時，submodule 預設不勾，並顯示 CVE-2025-48384 的提示；不認 backport。版本由 `gbm_git_version_json` 回報。
- 資料夾名由 `cloneFolderNameFromUrl` 推出。父目錄是第一個已啟用的 base folder，沒有就不自動填。這一點是推測值。
- 分層：`lib/data` 不 import `routing` 或 `features`，已 grep 驗證。後來改由測試鎖住（ec6e8f02，`test/architecture/data_layer_imports_test.dart`，相對路徑也會解析）：注入四種違規 import 都轉紅，import theme 的對照組維持綠燈。轉頁經由 `CloneJobController.opened` Stream，由 app 層的 `CloneJobListener` 執行。

### 歡迎畫面（W0、W1a）

- 設計稿：`welcome-and-clone-spec.html`。
  - spec-auditor 第一輪：100 個值中 72 個符合、12 個不符、6 個沒有出處，大多是我畫錯，已修正。
  - 前例頁 `worktree-dialogs-spec.html` 的陰影 `.28` 已就地更正。
- 使用者刪除了 W1b（Recent 清單）：「recent就不用做了」。
- 實作時才發現的兩項更正，已在設計稿上就地劃掉改寫：
  - **W-D9**：鍵盤和選單讀同一張 handler map（[ACT-one-handler-map]），快捷鍵能用，View → Log 就必須是可用的。所以 View 選單只留 Log 可用。
  - **W-D11**：core 已在每個 base folder 存了 `last_scan_ms`。改成加總已啟用資料夾的值，不另外用 Stopwatch 量（[CULT-single-source-of-truth]）。
- 掃描錯誤改寫進視窗的 Log（推測值，依據是 P15 B 與 R11）。原本的錯誤 banner 隨著 AppBar 一起移除。
- About 改由 Help → About 進入。7 個檔案裡寫著「welcome screen has no menu bar」的註解，已就地更正。
- 修了一個既有 bug（5a8778bb）：在清單上按 Edit → Select all，也會送出 text 的 select-all，因為判斷「清單是否處理了」的條件從來沒成立過。新測試先紅後綠。

## Result

### Verifier

| 次 | 範圍 | 結論 | 證據 |
| --- | --- | --- | --- |
| 1 | A0 + S0a，8 項主張 | CONFIRMED | ctest 828/828；flutter +3659 ~8；macOS runner 以本地 Basic-auth HTTP server 端對端驗證；Windows、Linux 只讀程式 |
| 2 | C1 + C2，8 項主張 | CONFIRMED，2 個 P4 | ctest 872/872；沒有殘留的 fake-ssh process；另寫探測程式：目標路徑本身是指向外部的 symlink 時，取消後外部資料夾還在 |
| 3 | C3，8 項主張 | CONFIRMED，2 個 P4 | flutter +3859 ~8；`CloneJobApiTest`、`InitCloneApiTest` 24 個通過；確認原生 payload 與 `GbmEventType` 38、39 一致，`"Cancelled"` 字串與 `Error.cpp:126` 相符 |

第 3 次的兩個 P4，處置為 DEFER：

- A1（信心 medium，只讀程式）：如果 `CLONE_FINISHED` 在對話框 push 之後、第一次 build 之前到達，或者 `?job=` 無法解析，prompt 在 build 時就已經是 null，`ref.listen` 不會觸發，對話框會留在畫面上直到使用者關掉。時間窗很窄，也可以恢復。`app_router.dart` 裡寫著「closes itself as a stale one would」的註解對這種情況是錯的，~~已就地更正~~ 更正：寫下這行時還沒改，480be293 才劃掉並改寫。
- A2（信心 low）：成功後轉頁用的是使用者輸入的路徑，capi 端會正規化，例如去掉結尾的 `/`。結尾帶 `/` 時，identity 會和正規化後的路徑不一致。本輪沒有觀察到錯誤。

第 2 次的兩個 P4，處置為 DEFER，記錄在此：

- 持有全域 mutex 時呼叫 callback。callback 若會阻塞就可能 deadlock；Dart 的 listener 不會阻塞，所以沒有重現。
- 上層目錄兩次都讀不到 FileId 時，會被當成「沒變」。

### Mutation（mutations-run / tests-reddened）

| Slice | 結果 | 備註 |
| --- | --- | --- |
| S0a | 4 / 4 | |
| A0-1 | 5 / 4 | 一個前提太弱（`O_TRUNC`），補測試後轉紅 |
| A0-4 | 3 / 3 | |
| S1-1 遮罩 | 11 / 11 | |
| S1b | 15 / 15 | |
| S5 | 4 / 4 | |
| S2 | 8 / 8 | |
| S3a | 6/6、7/7、5/5 | |
| C1 | 8 / 8 | M2、M4 起初存活，補了兩個案例 |
| C2a | 7 / 7 | |
| C2b | 26 個 mutant | M20、M23 起初的紅燈不窄，加 guard 後重驗 |
| W1a 歡迎畫面 | 12 / 12 | 一個先編譯失敗；一個因測試字型太寬分不出置中而存活。兩個都改寫後轉紅 |
| C3 P1、P2 | 8/8、7/7 | |
| C3 Controller | 17 / 17 | |
| C3 status bar | 11 / 11 | T5 起初存活，補強測試後轉紅 |
| clone_url | 7 / 6 | U3 存活，那個分支多餘，已刪除；先紅後綠**沒有被觀察到**，測試與實作同時寫，改由 stub 讓 11 個測試轉紅來補證 |
| Clone 對話框與接線 | 15 + 5，全紅 | D10 是編譯錯誤，改寫成 D10b 後轉紅 |
| status bar 接線 | 4 / 4 | |
| Credential 重構 | 6 | F4、G1 原本沒有覆蓋，新測試補上後轉紅 |
| Credential dialog 與 listener | 9 / 7 | CD5（`_asking`）存活，判定多餘，已刪除；L3 存活，因為 `pushDialogRouteOn` 本身已去重 |

### 裝置測試（macOS，C3 完成時）

8 個檔案，全綠：

| 檔案 | 測試數 |
| --- | --- |
| merge_squash_flow | 2 |
| operation_log_benign_exit | 1 |
| prepared_message_flow | 5 |
| repo_lifecycle | 1 |
| status_bar_cancel_flow | 1 |
| update_check_flow | 2 |
| worktree_add_refresh | 2 |
| worktree_pending_counts | 1 |

`update_check_flow` 原本從舊標題列的 About 按鈕進入，已改成 Help → About。

### 與 spec 的差異（使用者的決定）

- R17：TASKS 寫 Clone 進度要顯示在「該 repository 列 + status bar」，本輪只做 status bar 與 Log。正在 clone 的 repo 要完成後才會出現在清單裡。
- W1b（Recent）刪除。
- S4a、S4b（錯誤彈窗）刪除（R11）。

### 已知但未查清

- ctest 的總數：C1 時是 841，前一次是 828，新增 16 個應該是 844，實際差 13，沒有對帳。沒有任何測試失敗或遺漏。
- Windows 與 Linux 的 runner askpass 攔截只確認了編譯，沒有在本機執行。
- 殘留風險（P3）：
  - 開始檢查到 git mkdir 之間有一個窗口。
  - 逾時時不刪除資料夾。
  - 機密在記憶體中沒有清零（P4）。
  - 繼承的 `GIT_TRACE2*` 不覆蓋，以免關掉企業遙測。
  - Remotes 面板直接顯示 fetchUrl 原文：那是畫面，不是 Log，不在 R6 的範圍內。
- F5（`wt.exe -d` 的 `;`）要不要開 issue，仍等使用者決定。
- ~~memory-steward 列出的 drift：有幾個地方直接呼叫 DesktopLauncher，沒有經過 AppActionRunner，違反 R4。處置見 S6 的 commit。~~ 更正：這在 R4 的範圍內，依 standing rule 1 本輪修好了，見下一節。

### R4 drift：直接呼叫 launcher 的地方

memory-steward 列出 6 處，實際 grep 共 12 處；它漏列的是 `submodules_panel`、`update_dialog` 和 `changed_files_panel:113` 的 openFile。

- 新增 `openFileAction`、`openInFileManagerAction`、`openUrlAction`（95dddc72）。mutation 7 / 7，每個紅 1–3 個測試。
- 11 處改走 runner。Log 的去處：workspace 內寫目前 repo 的 Log；歡迎畫面寫視窗的 Log（R13）；repo 切換清單依 `currentWorkDir` 決定。
  - 紅燈 −11，其中一個 popover 測試的紅燈混著 fixture 例外（windowLogProvider 需要 SharedPreferences），所以由 mutation 補證。
  - mutation 12 個有效、12 個轉紅，每個只紅 1 個測試。W7 原本的寫法是編譯錯誤，改寫成 W7a、W7b 後才算數。
- ~~`update_dialog` 的 Open releases page 還沒改：它由 About 或 Preferences 推入，不帶 origin，Log 該寫到哪個視窗沒有現成的答案，等使用者裁定。~~ 更正：使用者已裁定（2026-10-21），本輪已修，見下一節。

### Update 對話框帶 origin（2026-10-21）

使用者的裁定：

- 「a，照 Clone 對話框帶 origin」：Update 的 Open releases page 寫進發起視窗的 Log。origin 依 About → Update、Preferences → Update 兩條路往下傳。
- 「自動檢查更新也改用目前路由所在的 repo」：自動檢查推出的對話框，以 router 目前所在的 repo 作為 origin；在歡迎畫面上是 null，寫進視窗的 Log。

| Commit | 內容 | Mutation（run / reddened） |
| --- | --- | --- |
| dce6cdae | `appLogSinkFor(ref, workDir)`：依 workDir 選 session 或視窗的 Log | 2 / 2 |
| 0030494a | 三個對話框路徑帶 `?origin=`；`originWorkDirOf(router)` | 6 / 6 |
| f09b646c | route 的 repoId 不再重複解碼（見下） | 2 / 2 |
| 00c4a74f | 對話框接收 origin、Open releases page 走 runner、各呼叫點帶 origin、自動檢查用 `originWorkDirOf` | 11 / 11 |

- 00c4a74f 的先紅後綠：兩批各 −4，都是行為上的紅燈。O2（`updateDialogRoute` 解析 `?origin=`）第一次跑的紅燈數是空的：沒有任何測試掛上真的 route。補上「route 把 ?origin= 交給對話框」的測試；第一次重跑是 ('0','1')，那是測試檔漏了 import 的編譯錯誤，不算數；修正後是 27 綠 1 紅。
- 完整測試 +3898 ~8，analyze 0，format 0。

#### 順帶發現的既有缺陷：repoId 被解碼兩次

0030494a 的 mutation R5 存活，追下去才發現：go_router 交給 builder 和 redirect 的 `pathParameters` 已經解碼過（實測 `%2Fa%2F100%25` → `/a/100%`），而 `repoIdentityFromRouteParam` 又解碼一次。路徑含 `%` 的 repo 會開錯或直接丟 `Truncated URI`；workspace 的 redirect 還會組出 `/repo//…`。三種紅燈都在修之前重現過；f09b646c 修好。

### C4（38cedd7c）

- 刪除同步的 `gbm_repo_clone`（`InitClone.cpp`、`gbm_capi.h`）與 Dart binding（`repoClone`、`_RepoCloneNative`、`RepoCloneDart`）。
- 原本 `InitCloneApiTest` 的四個 clone 測試裡，有一案移植到 `CloneJobApiTest`，其餘三案已由 clone job 的測試涵蓋。capi 的 Clone/Init 測試從 24 變成 21（24 − 4 + 1）。
- ctest 870/870；binding parity 測試通過。mutation：把宣告加回去，「every header function is bound」轉紅 1 個。

### 本輪的註解更正

- `app_router.dart` 的 `cloneCredentialDialogRoute`：「closes itself as a stale one would」已劃掉並改寫（480be293，verifier A1）。A1 那一列原本寫「已就地更正」，寫的時候其實還沒改，已在那一列劃掉更正。

