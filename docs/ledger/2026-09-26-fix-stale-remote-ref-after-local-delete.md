# 刪掉本機分支後殘留的 remote-tracking ref（fix/stale-remote-ref-after-local-delete）

## 回報

「why sometime i delete local branch in app, and the branch shows as still a
remote branch there」，並附上步驟：

1. Fetch
2. 刪掉一個 remote 上已經被刪掉的本機分支
3. 對話框確認刪除
4. 這個分支又以 remote 分支的樣子留在側邊欄
5. Refresh（F5）沒有變化
6. 再 fetch 一次，那一列才消失

## 根本原因

單一缺陷，不是兩個疊在一起。

`[REF-fetch-auto-prunes]` 的自動 prune 只在 **fetch 觸發**的 preview 上執行，而且
使用者裁定「僅限無本機分支者」——有本機分支占用的 ref 保留 cloud-off 標記，因為使用者
還能 repush。`_autoPruneUnclaimedRefs()` 算出 `claimed` 之後，把被占用的那半
**放掉就不再回頭看**。

```
步驟        origin/x 在磁碟   gonePending 有它   本機 x 占用它   側邊欄畫出
--------------------------------------------------------------------------
1 fetch          ✔                 ✔                ✔          x（本機列，標 gone）
                                                               ↑ 被占用 → 不 prune（正確）
2-3 刪本機 x     ✔                 ✔                ✘          origin/x（remote-only 列）
                 ↑ 占用消失了，但沒有任何路徑會重新評估它 ← 缺陷
5 F5             ✔                 ✔                ✘          同上（ref 真的還在磁碟上）
6 再 fetch       ✘                 —                ✘          （消失）
                 ↑ 新的 fetch-preview → 這次 unclaimed → 自動 prune
```

F5 幫不上忙，因為它只是重讀 refs，而那個 ref 確實還存在。第二次 fetch 之所以有效，
是因為它產生了一次新的 fetch-preview。

### 查過但不是成因的三件事

- 刪除對話框的「同時刪 remote」**正確被抑制**：`delete_branch_dialog.dart` 的
  `remoteAlreadyGone` 讀 `isEffectivelyGone`，所以不會發出注定失敗的
  `git push --delete`。
- 步驟 4 那一列**是有 gone 標記的**：`sidebar_panel.dart` 對 remote-only 列也算
  `isEffectivelyGone`，而 `gone_marking.dart` 對 `RefKind.remoteBranch` 比對
  `fullName`。所以不是「標記掉了」的第二個缺陷。
- `pruneRemote()` 走 `git branch --delete --remotes`（`RemoteOps.cpp:227`），
  **純本機、不連網**——所以補救不需要任何網路成本，這是整個修法能成立的前提。

## 修法

`_goneRefsDeferredByClaim`（remote → full ref 名稱集合）記下「fetch-preview 說 gone，
但只因為被占用而放過」的 ref。`_pruneDeferredGoneRefsNowUnclaimed()` 掛在
`publishRefs()` 的 state 寫入之後重算。

掛 refs 而不是掛 `deleteBranch` 的完成分支，是因為後者那一刻 refs 還沒重讀，
`state.refs.localBranches` 仍含著剛刪掉的分支，占用判斷會答錯。掛 refs 另外讓它
自我維護：單筆刪、批次刪、終端機外部刪、`git branch -m` 之後 `--unset-upstream`，
全部同一條路。

### 兩道彼此獨立的閘門

```
             ┌─ 閘門 1（出處）：只有 fetch 觸發的 preview 能把 ref 放進延後表
preview 回覆 ┤
             └─ gonePendingByRemote 無論來源都會被寫（現有行為，不動）
                        │
publishRefs ────────────┴─▶ sweep ─┬─ 閘門 2（時機）：這個 remote 的 Prune 對話框
                                   │   正開著 → 跳過，且不從延後表移除
                                   └─ 否則 → 派工
```

閘門 2 是 `plan-verifier` 第一次審查挑出來的，而它挑對了：**我第一版只有閘門 1，而
閘門 1 管的是「哪個 preview 可以餵延後表」，sweep 的觸發是另一條獨立的路。** 對話框
開著、占用的本機分支在外部被刪掉時，sweep 照樣會把對話框正在列的 ref 刪掉，使用者
接著按 Prune 就撞 `not found`——正是我引用來當基礎的那條規則的 Do 要防的事。

閘門 2 用**對話框自己宣告**的訊號（`beginPruneDialogPreview`/
`endPruneDialogPreview`），不用「最近有沒有 manual preview」的時間推測：
`lastRemotePrunePreview` 是 last-write-wins 且從不清空，拿它當條件會在使用者開過一次
對話框之後**永久**關掉 sweep。關窗時順便再跑一次 sweep，所以被暫緩的 prune 在關窗時
就做掉，而不是等下一次 fetch。

### 移除與保留的分界，以及第二個被審查抓到的錯

| 哪個條件不成立 | 延後表 | 為什麼 |
|---|---|---|
| 還被占用 | **保留** | 這是刪除之前的**常態**，不是終局 |
| ref 已不在 `remoteBranches` | 移除 | 結構上是終局；送過去只會拿到 `not found` |
| 已退出 `gonePendingByRemote` | 移除 | 它又回到 remote 上了 |
| Prune 對話框開著 | **保留** | 暫緩，等關窗那次 sweep |

第一版我寫「前三個任一不成立就移除」，理由是「那個決定已經沒有意義了」。**那句話對後
兩個成立，對第一個完全不成立**，而這是第二次審查的 blocker：`publishRefs()` 的頻率遠
高於「使用者剛刪掉這個分支」——`refreshHistory()` 是 `refreshRepoStatus()` 的 Tier 1
成員，而 `Session::onRefreshTimerFired()` 在每次 coalesced refresh 之後**無條件**
`emitEmpty(GBM_EVENT_REFS_UPDATED)`（`src/capi/Session.cpp:373`，親自核對，沒有
「有沒有變」的閘門）。所以 fetch 之後、刪除之前只要按過一次 F5，延後項就被永久逐出，
**要修的 bug 原封不動回來**。唯一還看得到修好的情境是「fetch 與刪除之間零次 refresh」。

它也與我自己在同一份計畫裡寫的不變式矛盾（「閘門是『這個 ref 還沒試過』，不是『這個
ref 可以 prune』」）——對話框那一條拿到了那個待遇，占用那一條沒有。

保留的代價是一個**有界**殘留：一個永遠不會被刪掉的本機分支，延後項會留到 session 關閉
或下一次 preview 換掉整片 slice。上界是 preview 的大小，而 `gonePendingByRemote` 本來
就以同樣方式常駐在 state 裡。

派工前先移除，所以每個 ref 最多派一次；prune 成功後自己的 refs 重讀是 no-op 而非迴圈
（`[GIT-worktree-prune-has-no-expire]` 的同一個形狀）。失敗只試一次，那一列保留 gone
標記，等下一次 fetch 重新 preview。

## 測試與 mutation

單元層十顆（延續 `repo_session_auto_prune_test.dart` 既有的 `debugHandleEvent` 慣例）、
對話框層一顆、integration 層一顆。全部用 `where().length` 計數而非 `any`。

兩個「fixture 分不出來」的地方值得記下：

- 「本機分支還在 → 0 次」只有**單次 observation**，「已逐出」與「留著還沒派工」在那一刻
  都是 0。要分開必須有第二次 `publishRefs`，這就是補上的那一顆。
- 「ref 已不在 `remoteBranches` → 0 次」的 fixture 光靠那一個條件就已經 0 次，所以
  它**擋不住**「拿掉 gonePendingByRemote 交集」這個 mutation。要另一顆讓 ref 留在
  `remoteBranches` 裡而退出 `gonePendingByRemote`。

**8 個 mutation，分別讓 3／4／1／1／3／1／1／1 顆測試轉紅**（兩個數字分開記）。
一個要特別寫下來：拿掉 sweep 呼叫的 anchor 在 C3 之後變成**兩個**呼叫點，
`assert count(old)==1` 擋下了寫入，那一次的「全綠」是 mutation 沒套用而不是測試空轉
（`[TEST-mutation-check-every-test]` 的 Note），改成唯一 anchor 後重跑才拿到 `+0 -1`。

M2（閘門 1 改成無條件）比預期寬：預測 1 顆，實際 4 顆——多出的三顆是既有測試，釘的是
同一條不變式，所以寬而不是錯。

全套 `flutter test` 2965 通過、12 顆 golden 紅。那 12 顆**在本輪之前就存在**：把
repository 檔案還原成 C2 之前的版本再跑 `test/goldens/`，兩邊都是 `+9 -12`，如實記錄
而不動它（本機 Flutter 3.47.5 對 CI 的 3.44.9）。

## 審查

兩次 fresh `plan-verifier`，兩次 REVISE，三個 blocker 全部 FIX：

| # | Blocker | 處置 |
|---|---|---|
| 1 | 出處閘門擋不住「Prune 對話框開著時把它正在列的 ref 刪掉」 | 加閘門 2 |
| 2 | 承諾的 mutation check（gonePendingByRemote 交集）沒有任何測試能紅 | 補一顆，並改成 mutation→測試對照表 |
| 3 | 「還被占用」時逐出延後項，一次 F5 就讓整個修正失效 | 改為保留；補一顆兩次 observation 的測試 |

審查次數達上限（closing review 不能重啟迴圈），**blocker 3 的修正沒有經過 fresh
reviewer**。依據（`Session.cpp:373` 無條件發事件）已親自核對原始碼。

## 已知殘留

- **真機未驗證。** 三條手測（原始步驟、對話框暫緩、F5 之後再刪）都還沒在真實硬體上跑過。

- 閘門 2 假設「Prune 對話框同時只有一個」，這由它是 route 保證；若哪天改成可並存的面板
  分頁，`_remoteShownByPruneDialog` 要從單一欄位改成集合。

## 裝置層

先踩到一個環境問題：`build/capi-only` 的 CMake cache 是從**舊路徑**
（`Code/PersonalProjects/git-branch-manager`）產生的——repo 搬過家——所以
`scripts/build_capi.sh` 直接 CMake Error（`CMakeCache.txt directory ... is different`）。
該目錄是 gitignore 的產物，清掉重建即可（99 個目標，exit 0）。寫下來是因為下一個在這台
機器上跑裝置層的人會再撞一次。

依 `[TEST-grep-misses-intent-driven-device-tests]`，grep 了
`prune`／`Prune`／`gone`／`Gone`／`branchDeleteBranch`／`manageRemotes`／`deleteBranch`，
命中四檔，**逐檔各跑一次** `-d macos`，全綠：

| 檔案 | 結果 |
|---|---|
| `conflict_flow_test.dart` | 1/1 |
| `untracked_unstage_flow_test.dart` | 1/1 |
| `context_menu_flows_test.dart` | 5/5 |
| `repo_lifecycle_test.dart` | 1/1 |

四次都印了 `Failed to foreground app; open returned 1`，而四次都在它後面接著印出計數——
`[TEST-foreground-line-is-not-a-failure]` 說的正是這件事，不要把那一行當成失敗訊號。
