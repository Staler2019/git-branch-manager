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

- ~~閘門 2 假設「Prune 對話框同時只有一個」，這由它是 route 保證；若哪天改成可並存的面板
  分頁，`_remoteShownByPruneDialog` 要從單一欄位改成集合。~~ **就地更正（後驗審查指出）：
  「由它是 route 保證」不成立，而風險不在未來的面板改版，在今天。** `remotePruneRemoteBranches`
  的 handler 是無條件的 `context.push(...)`，沒有「已經開著」的防護；`dialogRoute()` 的 barrier
  會擋住非 macOS 的 in-window `MenuBarRow` 第二次點擊，但 macOS 的原生 `PlatformMenuBar` 在
  Flutter 的 hit-testing 之外，barrier 擋不到它。所以在 macOS 上快速點兩次同一個選單項，可以在
  第一個 dispose 之前推出**同一個 remote** 的第二個實例；此時第一個的 `dispose()` 會呼叫
  `endPruneDialogPreview(remote)`，而守衛是比對 **remote 名稱**而非對話框實例，於是閘門在第二個
  實例眼前被打開、sweep 照跑——正好重現這個修正要防的「使用者自己的 Prune 按鈕撞 not found」。
  未實際重現（需要真實 macOS 原生選單與 Flutter overlay 的競態，腳本測試搆不到），評為 P3：
  有界、無資料損失、機率低，且該錯誤在自動 prune 路徑上本來就被抑制。**依 CLAUDE.md 的處置
  規則，P3 預設 defer/report，不為它改動已 CONFIRMED 的候選**——要修的話是把閘門從 remote 名稱
  改成對話框實例的 token，並重跑驗收與一次新的 verifier。
- **沒有針對 microtask-before-dispose 守衛的回歸測試**（P4）。後驗審查嘗試用
  `router.push` 緊接 `router.pop` 逼出那個競態，但 `pumpWidget`/`push` 內部本來就會讓出
  microtask queue，構造不出窗口；守衛本身以程式碼檢視確認正確。

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

---

# 第二片：P3／P4 不 defer，並把決策搬出 session

第一片的 verifier 回 CONFIRMED 但附兩個 advisory（P3 閘門以 remote 名稱當 key、P4 沒有
regression 測試），我依 CLAUDE.md 的 P3/P4 處置規則 defer 了。**使用者推翻：「p3 p4 都應該要
做，你的有問題、有疑慮，就應該確認事實＋寫測試確保它。不可 defer」**，並額外裁定 already-open
防護要加到**全部對話框**；隨後在被問到依賴反轉時裁定 **B：連延後表與 sweep 一起搬出
controller**，理由是「後續最好維護，而且職責乾淨」，並要求先構思**如何用整合測試確保內部邏輯
不會因為 refactor 而壞掉**。

本片送出的 `plan-verifier` 被使用者中止，**所以本片沒有任何審查裁決**。不當作 READY，也不假裝
有審查過。

## 先問對的問題：搬家的網子要建在哪個縫上

「怎麼確保 refactor 沒弄壞」的答案不是多寫測試，而是**把測試放在搬家動不到的縫上，並且證明
它在搬家之前就是綠的**。第一次我建錯了：那些測試直接建構 `FakeRepoSessionController` 並斷言
它的 `commandLog`，於是 controller 是測試的**主體** —— 決策一搬走，controller 不再派工，整份
測試會全紅，網子反而被搬家摧毀。

對的縫是 `ProviderContainer`：

```
  IN : controller.debugRecordFetch() / debugHandleEvent(FFI 事件)
       controller.publishRefs(snapshot)
       audience.register / declare / release
  OUT: commandLog 裡的 pruneRemote（次數、refs、automatic）
       整合層：側邊欄那一列在不在
       ▲ 決策在 controller 還是在 notifier，這兩個縫都看不出來
```

所以順序被拆成 C7（換閘門來源，決策仍在 controller）→ C7b（測試改由 container 驅動，跑綠）
→ C8（搬家）。C7b 是多出來的一步，也是整個保證的支點。

**結果**：C8 之後特徵測試 19 顆全綠，而那個檔案的 diff 只有三處、全在 `setUp`
（一個 import、一個已不存在的建構參數、一行掛載新 provider），**斷言與 fixture 一個位元都沒
動**；`test/integration/workspace_stale_remote_ref_after_delete_test.dart` **完全未被改動**且
維持綠。後者是最強的證據 —— 它跑真實 `WorkspaceScreen`，從頭到尾沒有點到延後表。

## 事實先於設計：查出來三件事推翻了原本的做法

| 查到的事實 | 推翻了什麼 |
|---|---|
| `RepoSessionController` **不持有 `Ref`**，`data/` 層沒有任何 repository 持有；建構子注入是唯一慣例 | 「session 讀一個 dialog registry provider」逆著慣例。注入 port 才順，而 `ClosableRepoSession`／`OpenRepoSessions` 就是現成寫法 |
| named optional 參數**只動 1 個生產呼叫點**（`FakeRepoSessionController` 用 `super.x` 轉發，~88 個 fake 建構點自動繼承） | 反轉的建構成本幾乎是零，不需要為了省成本妥協形狀 |
| preview 的 provenance（`_autoPrunePreviewsInFlight`）是 controller 私有，`RepoSessionState` 沒有對應欄位 | 搬出去的 notifier 分不出 fetch-preview 與對話框 preview，也就是分不出閘門 1 —— B 的關鍵難點 |

第三點的解法是**跨界線傳事實而不是命令**：controller 把延後項發布成 `RepoSessionState` 的一個
欄位。sink port 那條路會讓 notifier 的 `pruneRemote` 回呼 controller，provider 圖成環而
Riverpod 在 build 時就拒絕。記在 [STATE-deferred-prune-flow]。

## Riverpod 的一個限制改掉了 P4 的做法

P4 原本要「在 `initState` 同步 register，把 race 從構造上消掉」。第一版 `PruneAudience` 寫成
`StateNotifier<Set<String>>`，**對話框測試全紅**：

> Tried to modify a provider while the widget tree was building.

Riverpod 禁止在任何 widget life-cycle（含 `initState`）改動 provider。所以改成 **plain class +
純 `Provider`**，也就是 `OpenRepoSessions` 的同一個形狀。這不是偏好而是限制，而且回頭看，
`StateNotifier` 本來就是錯的工具：沒有任何 widget 需要 watch 它，卻換來那個限制。

同一輪還學到第二件事：**接線放在 provider body 是不夠的**。訂閱原本寫在 `repoSessionProvider`
的 body，而覆寫 `repoSessionProvider` 的測試**繞過那段組裝**，於是拿到閘門卻沒有開啟閘門的路
—— 半個行為，靜悄悄的。閘門與它的釋放是同一個行為，所以 `addReleaseListener` 進了 port、訂閱
進了 controller 建構子。

P4 的鑑別測試因此不必贏任何 race：`register` 與 `declare` 分開之後，「已釋放的 token 遲到宣告
不成立」是一顆確定性的測試，而那正是原本 `mounted` 守衛在擋的東西。

## 保真度檢查：mutation 換一個用途

一般 mutation check 是問「新測試的紅夠不夠窄」。搬家時它還有第二個用途：**把第一片的每條
mutation 搬到新實作的對應位置，必須紅到同一顆測試** —— 這是唯一能抓到「行為消失、測試也跟著
改、所以全綠」的機制。

| mutation | 紅 | 應紅的那顆 |
|---|---|---|
| 拿掉 audience 閘門 | 1 | 有 UI 正在列這個 remote 時暫緩 |
| 拿掉「仍在 remoteBranches」 | 1 | ref 已經不在 remoteBranches 裡就不送 |
| 拿掉「仍在 gonePendingByRemote」 | 1 | ref 又回到 remote 上就不送 |
| 拿掉「沒試過」 | 1 | 只試一次 |
| claimed 視為終局 | 4 | 中間一次無關的 refresh 不會讓延後項失效（＋三顆同形狀） |
| provenance 閘門拿掉 | 4 | 對話框來源的 preview 不會餵進延後表（＋三顆同形狀） |
| **`_dispatched` 的清除規則拿掉** | **0** | ← 搬家新增的規則，沒有測試釘住 |

**跑了 7 個、紅了 12 顆、1 個無紅。** 那個無紅的就是 B 帶進來的新複雜度：remove-before-dispatch
原本是「派工前從表裡移掉」，而表現在是 controller 的 state、notifier 寫不到，所以「已試過」改
由 notifier 的 `_dispatched` 持有，並多出一條規則 —— 某 remote 的延後集合被新 preview 整片替換
時要清掉該 remote 的 `_dispatched`。

**補那顆測試立刻抓到一個真缺陷**：`_autoPruneUnclaimedRefs` 對空 preview 提早 return，所以延後
表根本不會被清。搬家前這是條件 3 順手處理的（表在 controller 手上，不符合就**移除**）；搬家
後 notifier 只能跳過不能寫表，清除必須發生在 controller 那一端。後果具體：ref 回到 remote 上、
後來又被刪掉，會以一筆**全新的**延後項到達，而 notifier 仍記著上一次已經試過，於是第二次消失
永遠 prune 不掉。

### 一次假的綠，和一次假的紅

兩個都記下來，因為兩個都是照著規則才發現的：

- **假的綠**：第一次做「claimed 視為終局」那條 mutation 時我把它插在 `if (due.isEmpty) return;`
  **之後**，而那個 fixture 在那一刻 `due` 正好是空的 —— mutation 在到不了的路徑上，回報全綠。
  依 [TEST-mutation-check-every-test] 的 Note，沒真正套用的 mutation 不算證據；移到 early
  return 之前重做，紅 4。
- **假的紅**：跑 mutation 時用 `flutter test $T`（`T` 帶兩個路徑）被當成**單一引數**，四個
  mutation 全部回報 `+0 -1` —— 那是 loading 失敗不是真的紅。路徑寫死重跑，才拿到 2/3/1/1。

## P3b：already-open 防護，48 個呼叫點

使用者裁定「全部 26 個對話框都加」。實際掃出來是 **48 個呼叫點、14 個檔案**（單行 26、多行
22，所以只用單行 grep 會少數一半）。

`pushDialogRoute` 放在 `lib/routing/dialog_route.dart` —— 「這個對話框已經開著了嗎」是 **router**
的事實，與 session 無關，所以它完全獨立於上面的反轉。三個量到的事實各否決一個看起來合理的
寫法：

- `currentConfiguration.uri` **停在 base location**，不反映被 push 的對話框 → 不能用
  `GoRouterState.of(context).uri`。
- 被 push 的是 `ImperativeRouteMatch`，只有它的 `matches.uri` 留著 query；`matchedLocation`
  丟掉 → 不能用後者，否則 `?remote=origin` 與 `?remote=upstream` 會被當成同一個對話框。
- pop／barrier 點擊／`Navigator.pop` 三條關閉路徑都清掉那筆 match → 防護不會永久擋住重開，
  這是它能成立的前提。

**又一次「測試證明不了它看起來在證明的事」**：我先寫的「query 不同要都能開」在
`matchedLocation` 版本下**照樣全綠** —— `/first` 與 `/first?remote=origin` 本來就不等，閘門
根本不觸發，兩個都開，斷言成立。真正會被弄壞的是**帶 query 的同一個 URI 推兩次不去重**，補
了那一顆才紅。[TEST-fixture-cannot-disagree] 的原形。

規則用 `dialog_push_single_source_test.dart` 機械化：掃 `lib/` 底下 `.push(` 接
`RoutePaths.…Dialog…` 的形狀（`dotAll`，所以多行也吃到），必須 0 命中。沒有這顆，第 49 個呼叫
點會靜靜繞過去，而症狀只在使用者連點時出現。

`app.dart` 的啟動更新檢查沒有 `BuildContext`（它拿的是 `ref.read(appRouterProvider)`），所以
另有一個 `pushDialogRouteOn(GoRouter, String)` 入口，`pushDialogRoute` 是它的 `BuildContext`
便利版。

## 驗收

`pushDialogRoute` 動到每一個對話框入口，所以裝置層 **十四檔全跑**（計畫寫十檔，實際數是
十四），一檔一次 `-d macos`，跑前 `build_capi.sh` 並 `pkill`：

| 檔 | 結果 | 檔 | 結果 |
|---|---|---|---|
| commit_file_counts | 2/2 | stage_lines_flow | 7/7 |
| commit_flow | 1/1 | untracked_unstage_flow | 1/1 |
| conflict_flow | 1/1 | update_check_flow | 2/2 |
| context_menu_flows | 5/5 | working_copy_line_counts | 1/1 |
| history_filter | 2/2 | worktree_pending_counts | 1/1 |
| multi_push_flow | 2/2 | operation_log_benign_exit | 1/1 |
| rename_branch_flow | 2/2 | repo_lifecycle | 1/1 |

`update_check_flow` 是 `pushDialogRouteOn(GoRouter, …)` 那條沒有 `BuildContext` 的路徑，
其餘十三檔涵蓋的是 `pushDialogRoute` 的一般路徑。

其餘閘門：全套 `flutter test` **+2989 ~1 -12**，12 顆紅全是既有的
`gbm_widgets_golden_test.dart`（本機 Flutter 3.47.5 對 CI 3.44.9），本輪沒有新增任何紅；
`flutter analyze` 零；`check-rule-pins.py` 209 條規則／172 個交叉引用／懸空 0；
`dart format` 只格式化本輪碰到的檔案，另外 5 個既有漂移檔照
[CI-formatter-version-drift] 不動。

Orphan-wiring 雙向 grep 全部有生產者也有讀者：`goneRefsDeferredByClaim`（controller 寫、
notifier 讀）、`withGoneRefsDeferredFor`、`PruneAudience`／`holdsRemote`／
`addReleaseListener`（port 有實作也有呼叫端）、`deferredPruneProvider`（`WorkspaceScreen`
那一行 watch 是它的掛載點）、`claimedRemoteCounterparts`（三個讀者）、`heldRemotes`
（`@visibleForTesting`，四處斷言）。`lib/` 底下唯一剩下的裸 `.push(` 在
`pushDialogRouteOn` 自己裡面。

## 還沒做的，以及為什麼

- **推送與 PR #145 敘述更正**：PR 敘述現在仍寫著 P3／P4 是 deferred residual，那已經是假的，
  依標準規則 4 要就地更正。但這一片的 commit 還沒推，先改敘述會變成描述 PR 裡沒有的東西，
  所以順序是先推再改，而推送要等指示。
- **真機手測四條**（原始回報流程；fetch → F5 → 刪分支；Prune 對話框開著時於外部刪掉占用分支，
  列表不被抽掉、關窗才消失；同一選單項連點兩次只開一個對話框）需要使用者的機器與眼睛。
- **本片沒有任何審查裁決**（送出的 `plan-verifier` 被使用者中止），第一片 blocker 3 的修正
  也沒有 fresh reviewer。不當作 READY。
