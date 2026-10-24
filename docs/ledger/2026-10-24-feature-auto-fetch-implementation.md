# 自動 fetch（feature/auto-fetch-implementation）

## Situation

Preferences → General 的 `autoFetchEnabled` / `autoFetchMinutes`（預設 10）存得起來、畫得出來，
但沒有任何讀取端（`[DRIFT-auto-fetch-unwired]`，#102）。Spec P11 item 9：只抓目前 repo、切換
repo 時計時器重置、純 fetch、背景低優先度、失敗不彈窗（status bar + log）、有前景作業或
conflict 時跳過該次。

使用者同時問：push / delete remote 前後要不要 fetch。回答是不要——git 自己會和 remote 比對，
並更新它碰到的 tracking ref；`OperationRunner` 是每個 repo 一條的 FIFO，app 內的 fetch 與
push 不會互相競爭。

## Task

使用者裁定（2026-10-23/24）：

1. 開啟 repo 時的 fetch 跟開關綁定。
2. push / 刪除 remote 分支前後不加 fetch。
3. ~~push 加 `--force-if-includes`~~ —— 第 1 個 commit 開工時發現它會拒絕 Force Push dialog 的
   每一次 push（那個 dialog 只在 behind > 0 時出現，本地 reflog 從沒包含要覆蓋的 commit），
   也會讓 `GitIntegrationTest.cpp:4469-4473` 變紅。停下來問，裁定 **「開 dialog 時都不能做
   背景 fetch」**；push 保持只用 `--force-with-lease`，commit 1 取消。
4. 前景操作送出時，只取消**還在排隊**的背景 fetch；正在跑的讓它跑完（保留 2026-10-15 的
   「會產生 gitlock 的動作都不能取消」，`killableMidFlight` 維持 false）。
5. 背景 fetch 後只在 ref 有變時才跑 history walk 與 prune preview。history graph **不做局部
   拼接**——`algorithm-chooser`：rows 是 `--date-order`（`HistoryProvider.cpp:47`），抓到一個
   committer date 很舊的 commit 會插在中間，下面每條 lane / RowId 都要移；checkpoint 要
   0.5–25 MB（預算 64 MB）。使用者接受。
6. Auth / HostKey 失敗 → 暫停自動 fetch 直到手動 fetch 成功（「status bar + log 說明」）；
   網路失敗照 spec 下次排程重試。
7. Submodule 維持 git 預設（on-demand）。
8. 計量網路暫停：**這輪不做，記成 drift**（使用者裁定）。
9. 執行模式 AUTO，授權本地 commit；不 push、不開 PR。

## Action

### 量測（commit 5 前，Stop 條件）

200k fixture（`docs/PERFORMANCE.md`）、540 refs、git 2.56.0、macOS：

| 量的東西 | 結果 |
|---|---|
| (a) 完整 walk（`gbm_graph_check`，rev-list + GraphBuilder，第一個 chunk 137 ms） | 344 ms |
| (b) 兩次 `for-each-ref` snapshot，10 次中位數 | 133 ms（128–152） |

(b)/(a) = 39%，超過 10% 的門檻 → 停下來問。**裁定：「前值用上次 refresh 的 snapshot」**——
`FetchRequest.refsBefore = Session::currentRefs()`，fetch 後只讀一次 `RefStore::load()`，以
`RefStore::sameRefTips` 比較；沒有前值或讀取失敗一律當成「有變」（安全方向）。
~~walk 時帶 `AutoFetchResync`~~：`Session.cpp:342` 對合併後的 origin 是 `(void)takePending()`，
接上去只會多一個沒人讀的 producer（[CULT-orphan-wiring]），所以整個效果就是「沒變就不呼叫
`refreshHistory()`」。

**這輪沒做**：把 fetch 後讀到的 refs 直接當成下一次 refresh 的 refs（已向使用者報告）。

### Commits（各自可單獨 revert，倒序）

| # | commit | 內容 | mutation（跑 / 變紅） |
|---|---|---|---|
| 2 | 945fa67e | `askpass::wireRefusing`；背景 fetch 加 `--no-auto-maintenance --no-write-fetch-head` | 6 / 6 |
| 3 | b11b71d2 | `gbm_remote_fetch(..., background)`，C 與 Dart binding 同一個 commit；背景路徑不呼叫 begin/endAskpass | 2 / 2 |
| 4 | 232b4f12 | 非背景的 submit 取消排隊中的背景 unit；跑著的不動 | 4 / 4 |
| 5 | e310cc77 | `refsMoved`；ref 沒變不跑 walk | 9 / 9（第 7 個先 build fail，改寫後重跑） |
| 6 | a3b2ee2f | Dart：背景 fetch 失敗不進 `lastError`；`refsMoved == false` 不跑 prune preview | 7 / 7（原本 6 / 7，補 controller 層測試） |
| 7 | 50223d15 | `decideAutoFetch` 純函式 | 6 / 6 |
| 8 | f8ae1f2c | `AutoFetchScheduler` + factory（注入 periodic timer） | 15 / 15 |
| 9a | f62d477f | `DialogOpenObserver` 註冊在 GoRouter | 6 / 6；router 註冊測試先紅後綠 |
| 9b | 7c350c3b | `RepoSessionController.fetchFinished` | 4 / 4 |
| 9c | 38e9bf75 | `AutoFetchHost` 掛進 `WorkspaceScreen`；暫停寫一行 error log | 12 / 12（一個寫錯的 mutation `false ? null : X` 沒有改到任何東西，改寫後重跑才算） |
| 10 | 313efeb4 | Preferences 文案；間隔只存正整數 | 3 / 3 |

計畫的 commit 9 拆成 9a/9b/9c，三個都能各自 revert。

### 跑出來才知道的事

- **F3 重現**：一個 session 只有一個 askpass poller，背景 fetch 的 `endAskpass` 會把排在
  後面的 push 的認證提示一起收掉。用假 ssh（`GIT_SSH_COMMAND` 指向腳本）寫成確定性的
  capi 測試 `PushQueuedBehindABackgroundFetchStillRaisesItsPrompt`，先紅，再修。
- **`refs/remotes/origin/HEAD`**：git 2.48+ 的 `remote.<name>.followRemoteHEAD` 讓第一次
  fetch 建立 `origin/HEAD`，「安靜的 remote」測試因此看到 `refsMoved:true`。是 fixture 的
  形狀問題，不是 code：`settleInitialRefresh` 先 `git fetch` 一次。
- **routed dialog 不是 `PopupRoute`**：計畫寫「數 `PopupRoute`」，實際上 `dialogRoute` 的
  `CustomTransitionPage` 是非 opaque 的 `PageRoute`，數 `PopupRoute` 會漏掉所有 routed
  dialog，還會把 context menu 算進去。改成 `RawDialogRoute || (PageRoute && !opaque)`
  （[FLU-routed-dialog-is-a-page-route]）。
- **取消的背景 fetch 一樣會發 outcome**：`OperationRunner.cpp:193-203` 對被取消的排隊 unit
  仍呼叫 `onDone`（`Cancelled`），所以 scheduler 的 in-flight 旗標會被清掉，不會卡住。
- **沒讀取端的 getter**：scheduler 的 public `paused` 只有測試在讀，刪掉，測試改驗行為
  （tick 被跳過 / 會跑）。

### G1（spec-auditor）

- 暫停 log 行：0 不符、2 無出處。依審查把原因依錯誤碼寫出（`HostKey` 不會被寫成「認證
  失敗」），裁定原文引在 `AppLogEvents.autoFetchPaused` 的註解；level 用 error，因為 P10
  item 3 只有未讀的 error 會進 status bar 摘要，而裁定要求 status bar。
- Preferences 文案：1 不符、2 無出處。「下方的分鐘數」在開關關閉時指向不存在的欄位；
  舊文案（沿用）把失敗寫成反映在 ahead/behind，ERRCASES 是「Status bar + log … 下次排程
  自動重試」。兩處都照 spec 改寫。

## Result

- 自動 fetch 會在開啟 repo 時跑一次，之後每 `autoFetchMinutes` 分鐘跑一次，只抓目前的
  repo，切換 repo 時重新計時。遇到以下情況跳過該次：dialog 開著、等待認證輸入、conflict、
  前景 git 作業、上一輪還沒跑完。Auth/HostKey 失敗時暫停，status bar 會顯示一行 error，
  手動 Fetch 成功後恢復。
- `[DRIFT-auto-fetch-unwired]` 縮小成只剩「計量網路暫停」。
- 新規則：[GIT-background-fetch-refuses-prompts]、[FLU-routed-dialog-is-a-page-route]。

### 殘留風險（記錄，不修）

- Push 按下時（`confirmForcePush` 關閉）若已有一個**正在跑**的自動 fetch，它會在排隊的 push 前
  更新 `origin/X`——裁定 4 讓跑著的 fetch 跑完。
- 鎖住的 keychain、第三方 credential helper：拒絕提示的設定擋不住不經 askpass 的 helper。
- 既有 P3：兩個排隊的前景 askpass 作業本來就會互踩 poller（本輪沒有新增，也沒修）。
- 惡意 repo config（F10）、取消延遲（F9）：見計畫的 security dispositions。

### ~~發現但需要裁定~~ 已裁定（spec P11 item 9）

- 「只在 status bar 的 +N task 內顯示」：~~背景 fetch 目前以完整的「Fetching …」task 出現，
  沒有摺進 +N。~~ 使用者裁定「可折」，spec-auditor 審過後再裁定：**單獨時當主項目**（同 Prune，
  spec 沒寫只有摺疊作業時 zone 2 畫什麼）、標籤 **Auto fetch**（背景 fetch 是 `--all`，拿不到
  remote 名）、執行中被拒的 Cancel **「拒絕訊息只進 log」**（warning，不設 `lastError`）。
  ae720efa（`OperationRecord.isAutoFetch` 以 argv 判斷，mutation 6 / 6）、9984ef4f（mutation
  5 / 5，第 5 個靠補上的測試才變紅）。
- 「有新變化時 status bar 的分支區短暫高亮一次，不跳通知」：使用者裁定**「這個不需要」**。
- verifier A1（在 Preferences 裡打開開關不立刻 fetch）：使用者裁定不補抓——「只要關掉應該就不能
  auto fetch」，維持現狀。

### verifier（fresh context）：CONFIRMED

C++ 940/940、flutter `+4054 ~8`、analyze / format 乾淨；probe 另外確認：被取消的排隊背景 fetch
會清掉 in-flight、token 不會進暫停那行、`showDialog` 從 shell 子頁開也算 dialog。兩個 advisory：

- **A1（P3）**：在 Preferences 裡打開開關不會立刻 fetch——Preferences 本身是 dialog，開啟那次
  tick 被 `dialogOpen` 擋掉，第一次 fetch 要等一個間隔。合乎裁定「開 dialog 時都不能做背景
  fetch」與「跳過該次」；但 scheduler 的註解寫 ~~fetches at once~~，已原地更正。是否要在
  Preferences 關閉後補抓一次，待使用者裁定。
- **A2（P4）**：repo switcher popover 與 graph columns selector 用 `showGeneralDialog`，也會讓
  該次跳過；偏保守，沒有正確性風險。

## Preferences 說明與四個孤兒開關（同一個 branch，第二段）

### Situation

使用者回報「preference 頁下面註解太多了，使用者完全不需要知道」，並更正範圍：「我說的是preference頁的選項說明喔」。
G1 的 spec-auditor 同時找出四個存得下、畫得出、沒有任何讀取端的設定（#102 的形狀）：
`recordManualOpens`、`autoScanEnabled`/`autoScanMinutes`、`globalGitignoreEnabled`/`Path`/`Source`、
`cherryPickAddsSourceLine`（`CherryPickOps.cpp` 從沒加 `-x`）。

### Task

使用者裁定（2026-10-24）：

1. 範圍「整個 Preferences 頁」；處理方式「只留影響，不留來源、原因考量還是什麼其他種種」。
2. 「記住手動開啟的 repository」、「在背景重新掃描基礎資料夾」、「使用全域 gitignore 檔案」→「移除開關」。
3. 「cherry-pick 時加上 (cherry picked from commit …)」→「接上」。

### Action

| commit | 內容 | mutation（跑 / 變紅） |
|---|---|---|
| ab18565b | 六個分頁的說明改寫成只講影響；刪主題 token 說明 | 8 / 8 |
| c144cd9a | 移除 `recordManualOpens`（開啟的 repo 一律記錄，行為不變） | 1 / 1 |
| 750dbc90 | 移除 `autoScan*`（Rescan now 與新增資料夾時的掃描不變） | 1 / 1 |
| c85dc9a1 | 移除 `globalGitignore*`、路徑欄位與「從 .gitconfig 匯入」標籤 | 1 / 1 |
| 0fbd5e09 | core：`CherryPickRequest.recordOrigin` → `-x` | 2 / 2 |
| b94cf6ec | capi `gbm_cherry_pick(..., recordOrigin)`，C 與 Dart binding 同一個 commit | 3 / 3（capi 那個先寫成 unused-parameter build fail，改 `(void)` 後重跑） |
| 11acf007 | `repoSessionProvider` 把 `cherryPickAddsSourceLine` 推進 `cherryPickRecordsOrigin`（開啟時 + `ref.listen`） | 2 / 2 |

- `git cherry-pick -n -x` 一樣會把來源行寫進 MERGE_MSG（shell probe 確認），所以 `--no-commit` 搭 `-x` 不衝突。
- ~~已存在使用者 SharedPreferences 裡的三組舊 key 沒有清掉：沒有讀取端，留著不影響行為。~~ 使用者裁定「留著沒有意義」，58d72c0c 會清掉（見下方〈補測試與清舊值〉）。

### Result

- Preferences 說明只剩影響；三個開關不再出現；cherry-pick 依開關加上來源行（預設開）。
- spec-conformance-matrix P11 第 4、6、8 列與 MSGS 列原地更正；orphan 記錄補第 16–19 個；
  [CULT-orphan-wiring] 的次數改為 19。
- #102 本身沒有更新（GitHub 是外部動作，這輪只授權本地 commit）。

### verifier（fresh context，cherry-pick `-x`）：CONFIRMED

逐 commit 檢查 C/Dart arity（0fbd5e09 6 個、b94cf6ec 起 7 個，parity test 都綠），ctest 942/942、flutter
`+4072 ~8`。真 git 2.56.0 probe：`--no-commit -x` 與衝突時的 MERGE_MSG 都帶來源行；編輯後 continue 不會重複加，
刪掉後也不會被補回；多 commit 序列裡衝突之後的 commit 仍帶 `-x`。兩個 P4 advisory，~~不修~~（第二個已由 3e1d5da1 補測試）：b94cf6ec 單獨出貨時
開關還沒接上（預設值相同）；「`-x` + 衝突 + 編輯後 continue」只有手動 probe，沒有自動測試。

### 補測試與清舊值（使用者要求）

使用者：「cherry pick 以及 開關測試補上」、「-x 那個要測試」、「移除開關的舊值要移除，留著沒有意義」、「issue更新掉」。
上面 verifier 的兩個 P4 因此不再是「不修」（第二個由 3e1d5da1 補上；第一個是 commit 單獨出貨的情況，不需要測試）：

| commit | 內容 | mutation（跑 / 變紅） |
|---|---|---|
| 3e1d5da1 | capi：`-x` + 衝突的預填訊息、編輯後 continue（保留只出現一次、刪掉不補回）、衝突後排隊的 commit 仍帶 `-x` | 2 / 2，三個新測試都至少紅一次 |
| 58d72c0c | `removeRetiredKeys`：Preferences 載入時刪掉六個已移除設定的 key，加上更早的 `autoFetchPrune` | 3 / 3 |
| 4bd7690b | device：History 右鍵 Cherry-pick，預設帶來源行；Preferences → Git 關掉後不帶；harness 清 `appPrefs.cherryPickAddsSourceLine` | 2 / 2 |

- 第一版 `removeRetiredKeys` 在迴圈裡 `await`，只有第一個 key 會在建構當下從 cache 拿掉；改成 `Future.wait`。
- device 測試第一版用 `git rev-parse` 輪詢 HEAD，違反 [TEST-no-dart-process-while-core-runs-git]；改讀
  `.git/refs/heads/main`。
- #102 已留言更新。
