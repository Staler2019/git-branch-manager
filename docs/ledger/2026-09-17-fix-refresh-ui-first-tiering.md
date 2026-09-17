# 2026-09-17 · fix/refresh-ui-first-tiering — 刷新分層：UI 先到，其餘後同步

使用者回報兩件事：整體刷新太慢，畫面要用的東西（目前分支、working copy）應該先到，其餘
（stash、worktree、remote、submodule、bisect、lfs、identity）晚點背景同步；以及停在
Working Copy 頁時把視窗切回來，刷新期間讀不到檔案內容。

## 三段因果鏈

查下去，第二個症狀是一條完整的因果鏈，兩段各自成立、疊在一起才造成「讀不到」：

```
視窗取得焦點
  └─ refreshRepoStatus() 依序 post 十支（FIFO 佇列，池子只有 2–6 執行緒）
       #1 history(refs 7ms → REFS_UPDATED，接著 rev-list 走訪)
       #2 workingCopy(status 32ms)
       #3 stashes 12ms   #4 worktrees 5ms   #5 remotes 5ms
       #6 submodules 79ms   #7 bisect 5ms   #8 lfs 11ms   #9/#10 identity 各 5ms
                 │
         #2 回來 → WORKING_COPY_STATUS_UPDATED
                 │
                 ├─(A) _readWorkingCopyStatus() 把 workingCopyDiffs 整份清空
                 │        → unstagedLoading 變 true → 整個 diff pane 變轉圈圈
                 │
                 └─(B) working_copy_view 的 ref.listen 重發兩支 diff 請求
                          → post() 進佇列尾端，排在 #3..#10 後面（含 submodule 79ms）
                 │
         (C) 兩支 diff 回來 → 畫面才恢復
```

(A) 與 (B) 是兩個獨立缺陷；(C) 是分層要解的那一半。

## 使用者裁定

1. 不新增 refs-only capi；`gbm_history_refresh` 在走訪前就送 `REFS_UPDATED`，沿用現有呼叫。
2. tier 2 等 tier 1 的事件到齊再發，另加 fallback timer。
3. app 內加計時埋點，量「切回視窗 → diff 可讀」，before/after 各 5 次取中位數。
4. Preferences 加 Developer 分頁，本輪行為做成 feature flag 方便實機對照。

## 實作（八個可各自 revert 的 commit）

- **C1**（`9dfa034`）Developer 分頁骨架 + `RefreshTimings` 計時埋點（`focusAt`/`refsAt`/
  `statusAt`/`firstDiffAt`/`backgroundDoneAt`），狀態列顯示 + `debugPrint`。
- **C2a**（`2f3a94a`）未追蹤檔案的 `untrackedSize`/`untrackedMtimeTicks` 帶過 wire —— core
  早就用 `(size, last_write_time)` 當 `UntrackedLineCountCache` 的 key，只是沒送出來。
- **C2b**（`209a4a8`）狀態刷新不再整份清空 `workingCopyDiffs`；改成逐側指紋比對，指紋不變才
  留著，並把上界從「清空即上界」收緊成 `kMaxCachedWorkingCopyDiffs = 4`。
- **C3**（`9992a18`）`requestWorkingCopyDiff`/`requestWorkingTreeContent` 從 `post()` 改
  `postFront()`，比照既有的 blame/commit meta/commit files。
- **C4**（`91a2c50`）`refreshRepoStatus()` 分兩批：tier 1（`refreshRepoState`/
  `refreshHasCommitGraph`/`refreshHistory`/`refreshWorkingCopy`）立即發；tier 2（其餘八支）
  等 `WORKING_COPY_STATUS_UPDATED`（含 fallback timer）再發，且用 `Timer(Duration.zero)`
  延後——**不是** `scheduleMicrotask`，因為 Riverpod 的 listener 通知本身可能走微任務佇列，
  兩個微任務誰先誰後要靠推理；`Timer.zero` 排進事件佇列，保證整條微任務佇列（含
  `working_copy_view` 的 `ref.listen` 同步重發的兩支 diff 請求）都清空之後才輪到它，順序
  因此是佇列順序本身，不是賭贏一場微任務競賽。
- 一支 lint 漂移修正（`c79e6db`）。
- **C5**（`874bd3d`）`real_repo_harness.dart` 的 `flatKeysToClear` 補上三個新扁平 key。

被排除的選項（連同理由，不只是暗示）：

- **等 graph 走訪完再發 tier 2** —— 大 repo 上可能好幾秒，且被新刷新取消時根本不送
  `complete:true`，會讓 tier 2 永遠不發。使用者看的是 working copy，就以它為準。
- **用 `WorkingCopyStatus` 相等性直接抑制重發請求** —— 會讓「換掉一行、numstat 不變」的
  原地編輯永遠停在編輯前的 diff；今天的「無條件重發」正是它為什麼是對的。
- **只靠 C++ 降優先權、不在 Dart 延後** —— `postFront` 跳得過佇列但搶不下已經在跑的工作，
  這正是 tier 2 要延後而不只是降優先權的理由。
- **C3 不做 feature flag** —— 要能開關需要新增 capi setter,
  而 `dart:ffi`'s `lookupFunction` 只認符號名不認簽章，只有 device 層測得到那條縫，為了一個
  除錯開關付這個代價不划算。

## C6 —— 量測

### 方法上的一次繞路，以及為什麼放棄

原計畫用 `osascript` 驅動真正的 macOS 視窗 activate/deactivate，對著一顆真正在跑的
`.app` 做。這條路連撞三個層層堆疊的真實環境陷阱，每一個都要直接動到開發者自己那台機器上
真正在用的 `~/Library/Preferences/dev.gitbranchmanager.gbmFlutter.plist`：

1. `defaults` CLI 對這個 bundle id 悄悄轉去讀寫
   `~/Library/Containers/dev.gitbranchmanager.gbmFlutter/Data/Library/Preferences/...`
   的一份**副本**——即使實際跑的是未沙盒化的 Debug binary，從不讀那個路徑。跑出來的
   `defaults read` 因此看起來正確，卻不是 app 實際讀到的東西。
2. 用 `/usr/libexec/PlistBuddy -c "Set :key value"` 寫一段 JSON 字串進 plist 時，它把字串
   裡的雙引號整個吃掉——用 `python3 -c` 搭 `plistlib`/`json.loads` 直接解那份真實 plist 才
   抓到：`jsonDecode` 因此在 `RecentsRepository.read()` 內部炸掉，而它的合約是「missing 或
   malformed data 一律回傳空陣列」——`WelcomeScreen` 因此持續顯示「沒有開啟的 repo」，不是
   任何一行 app 程式碼的錯，是自動化腳本自己把資料寫壞了。
3. 兩次事故都只能靠直接位元組比對真實偏好設定檔才診斷得出來——這是持續在拿一份陌生開發者
   機器上「正在用」的檔案冒險，只為了量一次性的數字。

在把真實偏好設定檔還原成事故前備份（byte-identical，`diff` 驗證過）、確認沒有殘留的 rig
行程之後，向使用者提出四個選項，使用者選擇「改用 `integration_test` harness 量測」——
這正是 `workspace_focus_refresh_test.dart` 已經在用、也是 `[STATE-refresh-entry-point]`
自己的「not verified on real hardware」注記所承認的同一種模擬：`tester.binding.
handleAppLifecycleStateChanged(AppLifecycleState.inactive/resumed)` 證明的是**接線**，
不是「macOS 真的會在視窗取得焦點時送出這兩個事件」。這一輪的兩支量測檔案用同一招，對著
`real_repo_harness.dart` 建的拋棄式 repo（`shared_preferences` 範圍內、從不碰真實 plist）。

### 第一次量測是拿 A 的尺量 B，就地更正

第一次跑出來的數字（分支中位數 136ms、`main` 中位數 338ms）是拿兩把不同的尺量出來的，
advisor 這一輪的審閱點出來的：分支那個 136ms 是 `RefreshTimings.firstDiffAt − focusAt`
（controller 內部事件落地的時刻）；`main` 那個 338ms 是測試端 wall clock，從
`_leaveAndReturn` 之前到用 20ms 顆粒度輪詢「marker 文字真的畫出來」為止——多算了兩次
lifecycle 派送、兩次真實 frame 的 pump、widget rebuild + paint、以及輪詢顆粒度，而且全部
只加在 `main` 那一側。**這是同一組規則裡
`[CPP-windows-terminate-hangs-join]` 記過三次的「拿 A 的尺量 B」，這一輪自己也犯了一次**，
就地劃掉不引用那兩個數字。

修法：分支這一側也量同一種**代理**（wall clock：`_leaveAndReturn` 之前到 marker 真正畫出來
為止），與 `main` 的量法完全一致，才是可以直接比較的頭條數字；內部四個時間戳（`refs`/
`status`/`diff`/`bg`）留著當分支自己的內部分解，**不可以**拿去跟 `main` 的代理數字相減。

同時修掉一個結構性的 poll race：舊版輪詢只看「`firstDiffAt != null`」，如果第一次輪詢就
搶在 `resumed` handler 重設 `RefreshTimings` 之前執行，會讀到上一輪殘留的戳記而誤判——
這一輪剛好贏了那場賽跑（五個 delta 都和逐輪 `debugPrint` 對得上），但那是運氣不是構造。
改成先記錄 `before = timings`，輪詢先等 `focusAt != before.focusAt`（新一輪已經開始）才
開始等 `firstDiffAt`。

另外照 C6 步驟 4 補回被漏掉的**畫面空白區間長度**量測（reply 從缺席到回來的時間）——這是
和「新 diff 多快到」不同的一件事，C2 應該把它壓到 0。方法：種一個已知的 sentinel 行，不做
任何內容變更就觸發一次 focus-regain，輪詢 sentinel 文字消失又出現之間的時間差；一直沒消失
就記 0。

### 最終數字（matched-instrument，5 次 focus-regain，取中位數）

固定情境：1 個既有 commit、`notes.txt` 一個檔案（half-staged：已暫存 `line1\nline2\n`，
未暫存再加一行），每輪額外附加一行當 marker；零 submodule / 零 stash / 零 remote（
`git submodule status` 79ms 的固定成本仍然存在，只是這個 fixture 量不出它，一個更大的真實
repo 的 status/diff 本身也會更大——這裡量的是分層省下的**排隊**時間，不是 git 本身變快）。

| | `main`（未分層） | 本分支（分層 + C2b/C3） |
|---|---|---|
| focus→diff 可讀（wall clock，5 次） | `[300, 314, 322, 353, 356]` 中位數 **322ms** | `[179, 192, 194, 208, 267]` 中位數 **194ms** |
| 空白區間（無內容變更時） | vanished=true，**46ms** | vanished=false，**0ms** |

**focus→diff 可讀縮短約 128ms（40%）。空白區間從 46ms 壓到 0（C2b 的直接證據——舊 diff
在整段刷新期間從未消失過）。**

分支這一側額外量到的內部分解（`RefreshTimings`，五輪，`focusAt` 為 0 點，單位 ms）：

| cycle | refs | status | diff | bg |
|---|---|---|---|---|
| 0 | 187 | 92 | 186 | 97 |
| 1 | 199 | 61 | 126 | 65 |
| 2 | 182 | 67 | 122 | 67 |
| 3 | 179 | 66 | 115 | 70 |
| 4 | 171 | 61 | 113 | 61 |

`bg ≈ status + 1~6ms`，五輪一致——這是 C4 設計的「tier 2 在 `WORKING_COPY_STATUS_UPDATED`
之後、`Timer(Duration.zero)` 一輪事件迴圈就發」確實照設計運作的直接證據。

**`refs` 反而是四個戳記裡最晚落地的一個，五輪一致（171–199ms，晚於 status 的 61–92ms，
也晚於 diff 的 113–186ms）。** 這和使用者裁定 1 的前提（「目前分支本來就是最早落地的東西
之一，沿用現有呼叫」）字面上矛盾——原因**未查證**，只記錄觀察、不編因果故事。列出但未驗證
過的猜測：`refreshHistory()`/`refreshWorkingCopy()` 都 post 到同一個共用讀取池，`for-each-
ref` 的 process spawn 成本、或是 Dart 端單執行緒事件迴圈處理 FFI 事件時的排隊，都可能是
候選，但這裡沒有量到任何一個。**留給使用者裁定這是否要緊**——如果 UI 上「目前分支」真的
要最先更新，refs 落後 diff 60–70ms 就是一個要修的缺陷，而不只是一個有趣的數字。

### C2a 的實機證據——尚未自動化

計畫的驗收步驟 3b（未追蹤檔案原地改一行、行數不變，確認只有 `untrackedMtimeTicks` 變才會
重抓）不在這兩支測試的覆蓋範圍內——兩支都用一個已追蹤的 half-staged 檔案。這個 harness
的寫法（種 sentinel、輪詢消失/出現）可以直接搬過去量，但這一輪沒有做；留在人工驗收清單裡。

### 就地更正：`workingCopyDiffs` 舊 doc comment 那句「清空是 map 的上界」

`_readWorkingCopyStatus()` 原本的 doc comment 說整份清空「也是 map 的上界」——這句話本來
就漏了一個洞：兩次狀態更新之間，使用者可以點開 500 個檔案累積出遠超過合理大小的 map，清空
只在**下一次刷新**才會發生，不是任何時候的上界。新的上界（`kMaxCachedWorkingCopyDiffs = 4`）
比它更緊，不是更鬆——C2b 已經把這句改掉，這裡記一筆讓 ledger 和程式碼對得上。

## 這一輪自己走錯的兩步（最有價值的部分）

**第一步**：C2b 原本要寫成「路徑還在 `WorkingCopyStatus` 裡就留著」。而
`_readWorkingCopyStatus()` 現有的 doc comment 逐字防的正是這個——stage 掉一個 hunk 之後
路徑兩側都還在，舊 diff 會繼續被畫**而且繼續可以按**，行號卻已經指向別的行
（doc comment 原文：「the next "Stage 3 lines" would stage three other lines」）。改成
「每側指紋是否不變」才對。

**第二步**：改成指紋之後，plan-verifier 抓到第二層——未追蹤側的 `unstagedAdded` 不是 diff，
是**整檔行數**（`unstagedRemoved` 恆為 0），指紋比對對它完全無效：原地改一行、行數不變，
`unstagedAdded` 兩次一樣，指紋判定「沒變」，舊 diff 被留著且永遠不重抓——比原本的整份清空
還糟。C2a 補上 `untrackedSize`/`untrackedMtimeTicks` 才堵住。

兩次都是同一個形狀——**拿一個近似訊號去回答一個需要精確訊號的問題**，正是
`[STATE-never-guess-what-git-would-say]` 記的那件事換一個位置發生。**這一輪自己的 C6 量測
又踩了第三次**——用兩把不同的尺量兩側的同一段時間，見上面「第一次量測是拿 A 的尺量 B」。
