# Working Copy 全檔檢視（feat/wc-full-file-view）

## Situation

使用者回報 Working Copy 的 diff 只看得到每個 change 前後 3 行，看不到整個檔案、更長的上下文，也看不出
change 在檔案裡的位置。要一顆按鈕切到「全檔檢視」，`2 file` 與 `unified` 都要能用。

Spec 沒畫過全檔檢視（bundle 搜「整個檔案／全檔／full file／whole file／expand」皆 0 筆相關），所以這是
spec 外的新功能，G1 設計稿的每個值只能引 KIT 或既有 widget。

同一輪使用者另外回報 unified 模式下同一行出現兩次，排成第一個 slice（A），不依賴全檔功能。

## Task

使用者裁定（2026-10-24，AskUserQuestion）：

1. 全檔 = 直接全部攤開：卡片與 Stage/Unstage/Discard 照舊，卡片之間補上整份檔案的未變更行，畫法同 `_GapBlock`
   （dashed 左線，不淡化）。
2. 變更定位 = 捲軸旁的 overview ruler，可點擊跳轉；不做 ↑↓ 按鈕。
3. 開關 = 全域偏好（`AppPreferences`，同 soft wrap）。
4. Slice A：兩張卡片都包住同一個未變更行 →「卡片在這裡切開」；對側純插入／純刪除落在卡片範圍中間 →「卡片在那個位置切開」。
5. G1（設計稿 `docs/claude-design-demo/wc-full-file-view-spec.html`）：`Icons.expand`；tooltip 與 View 選單 `Full file`，
   不綁快捷鍵；上限 tooltip `File too large for full view`；全檔模式不畫 `@@`；ruler 方向色（未暫存 `accent`、已暫存
   `success`）、寬 10、距 well 右緣 4、上下對齊 well padding 8、底軌 `surface-sunken` r999、標記內縮 1／最小高 4／r2、
   well 右 padding 8 → 22；與 spec 不同處改回 spec（diff 列 padding 12 → 10、icon hover `textPrimary`）；Unstage 環色
   維持 `borderStrong`（修 spec）。
6. 超時一律走 `gitTimeoutMultiplier`，不新增寫死的 deadline。
7. Slice L（step 5 量測後）：片段與全檔共用同一條 lazy 路徑；soft wrap 開啟時以「字數 ÷ 每行容納字數」估高，跳轉後修正。
8. Slice L 的選取：捲動過的拖曳改用 ①「端點幾何」；填空列「每列 1 item，虛線接續」；「關掉 keep-alive，繼續 L3」。
9. AUTO 模式：本分支可 commit；不 push、不開 PR、不 merge、不安裝、不刪除、不做外部動作。

## Action

### 關鍵約束

`StageOps.cpp` 的 stage/unstage/discard lines 在 core 用預設 `DiffOptions`（-U3）**重算** diff，再以
`hunkIndex + lineIndices` 定位。畫面若改用 -U∞ 的 diff，索引會對到別的 hunk。所以 -U3 diff 仍是唯一的動作依據，
全檔 diff 只提供填空的未變更行（row key `'f:$source:$line'`，結構上解析不成 hunk 列），對任何 payload 貢獻為零。

### Slice A：unified 去重與排序（acbd3ca5 … ca8ad300）

- barrier 由「對側變更的 index 行」改成對側**每一個**變更列的 `(line, offset, rank)`（unstaged rank 0），scope 不能
  嚴格跨過任一個；推論：任兩張不同側卡片的 key 範圍不重疊，裁定 ① ② 由同一條規則滿足。
- 剩下的重複只會是 context 對 context，用隱藏處理（`hiddenContextLines`）：gap 對 gap 留 unstaged；卡片內的 context
  對 gap，gap 讓出。
- `orderedDiffBlocks`（抽成純函式）在 merged 模式下把 gap 拆成單行排序後再合併；不變式：繪製列 `(line, offset, rank)`
  非遞減，`2 file` 序列不變（U6）。
- 修正前紅：barrier 3 個、隱藏 3 個、排序 2 個。

### 全檔資料路徑（eb2c7368 … d66ae3f0）

- `DiffOptions::fullFile()`：`contextLines = 2147483647`（git 以 int 解析 `-U`）。git 2.56.0 實測：50 行、第 5／45 行
  變更的檔案回一個 `@@ -1,50 +1,50 @@` hunk。
- capi `gbm_working_copy_full_diff` + 事件 41；走 `sharedReadPool().post()`，不搶 -U3 的 `postFront`。超時沿用
  `workingTreeDiff` 的 180 s，經 `effectiveDeadlines()` 乘倍率；倍率 3 時 operation record 的 `timeoutMs` = 540000。
- 一致性：`fullDiffAgreesWith` 比對兩份 diff 的變更行；不一致時每個 `(path, side, fingerprint)` 最多重抓一次（-U3 與全檔一起）。
- `fullFileFillRows`：只出兩側 -U3 hunk 都沒畫到的 index 行，5k 行 3 ms，不快取（pane 只在輸入變時 rebuild）。
- 上限 `kFullFileViewMaxLines = 5000`（見量測）；超過時按鈕 disabled、不 active、tooltip 說明。
- 途中修掉一個既有 bug（9f1b64fe）：`_reportScope` 只在有↔無切換時發布 submitter，Shift+↓ 擴大範圍後 Ctrl/Cmd+Alt+S
  仍只送出第一列。

### 量測（macOS，profile build，`integration_test/perf/`）

| 結構 | 行數 | 開啟 | 捲動 p90 |
|---|---|---|---|
| eager `Column`（step 5 原版） | 5k | 963–1488 ms | 35–41 ms |
| 純 `Text` eager | 5k | 259 ms | — |
| lazy `ListView.builder`（L2，4f9fcbf5） | 5k | 80 ms | 15.5 ms |
| lazy | 20k | 539 ms | 45 ms |
| lazy + 填空接上（aba0e02d） | 5k | 72–77 ms | 15–16 ms |
| lazy + 填空接上 | 20k | 530 ms | 47–57 ms |

預算為開啟 ≤ 100 ms、捲動每幀 ≤ 16 ms：5k 通過，20k 不通過，上限因此定在 5,000（使用者的預期是 5k）。

### Slice L：lazy list（eaf385f7 … 3d1be912）

- `DiffListModel`：item = 卡片／gap／hunk 標題／每列 fill／leading；prefix offsets + 二分搜尋。
- 外框由 `_FrameSegment` 逐 item 畫切片，`scoped_diff_view_lazy_test` 以 eager 版的每列 rect 為對照組。
- **keep-alive 被否決的根因**：kept-alive 而未 paint 的列，`applyPaintTransform` 是 `setZero()`，`paragraph.dart` 的
  edge 判斷變成 NaN，`_compareScreenOrder` 又用 `getTransformTo(null)` 排順序；實作時另見 kept-alive 的畫面外 item
  重建時註冊未 layout 的 selectable，丟出 `RenderBox was not laid out`。所以 `addAutomaticKeepAlives: false`，捲動過的
  拖曳改由兩個端點決定範圍（sticky `_gestureScrolled`；手勢中途 diff 被換掉時不產生範圍）。
- **IgnorePointer 根因**：放開時 autoscroll 的 `DrivenScrollActivity` 仍在跑，Scrollable 的 `RenderIgnorePointer` 吃掉
  所有 hit，終點落到列表尾端。hit test 改從 `RenderViewport` 進入。
- 端點只看 y：探針 x 取 `GbmCodeHScroll` 不橫捲的 box 上的 gutter 位置。
- L4：Shift+方向鍵移動端點時，以 vertical `ScrollPosition.ensureVisible` 對上下兩緣各做一次。

### Step 8：overview ruler（c0dec44e）

- ruler 疊在 well 的 `Listener` 外面（按標記不是拖曳起點）；標記位置 = 卡片在繪製列中的比例，卡片 head 算一列。
- `_jumpToCard`：卡片已建出就 `ensureVisible`；未建出時量畫面頂端 item 的真實位置，跳「估計距離」，下一幀再修正，
  最多 6 次。這取代了計畫裡「TextPainter 量真實列高」的作法。
- **補接一個漏掉的裁定**：裁定 7 的 soft wrap 估高從 L1/L2 起一直沒接上——view 永遠傳 `charsPerLine: 0`。soft wrap
  長行時 model 估總高 66k、實際約 410k，修正迴圈每次只走估計距離，6 次走不到。現在版面完成後依 list 寬度與
  `kDiffCodeTextStyle` 字寬算出，有變才 `setState`。

### Step 9：device 層（91ff012b）與它找出的 staging 錯行（028e0338）

`full_file_stage_flow_test.dart` 第一次跑就紅：從 `INSERTED_ONE` 拖到 `INSERTED_TWO`，`git diff --cached` 裡是 ONE 與
**THREE**。片段模式重現相同結果——是既有 bug，不是全檔模式造成的：

```
_submitTemporary 依 hunk 由小到大送出；core 每次以 -U3 重算
stage(h0)  →  剩下 [TWO=h0, THREE=h1]
stage(h1)  →  對到 THREE
```

修法：由最大的 hunk index 開始送出；stage 後面的 hunk 不改變前面 hunk 的 index 與行號。widget 層的 fake 不會重算 diff，
表達不出這個錯（[TEST-fixture-cannot-disagree] 第 11 型），四個既有測試甚至把「依檔案順序」寫成期望值，皆已改並註明。

另兩個 device 層的發現：

- autoscroll 之後一次性 block 的 head（含 Stage 按鈕）畫在範圍最上方，已捲出且未建出——範圍存在，但只剩快捷鍵可送出。
  這是 UX 觀察，沒有改。
- 一次 autoscroll 案例 staged diff 為空；debug 重跑時通過。推測是 [TEST-no-dart-process-while-core-runs-git]（core 仍在
  stage／重抓 1000 行全檔 diff 時測試就 `runGit`），沒有證實。讀 git 前改成先等 board 把檔案列在兩欄。
- 第一次整檔 run 共 37 分 19 秒，其中 autoscroll 案例約 36 分鐘；instrument 後同一案例 101 秒到達、整案 3 分鐘內。
  36 分鐘的原因**沒有找到**。

### G3：device 層逐檔重跑找出的回歸（bdbafd87）與 hover（915c4922）

逐檔重跑 ~~28~~ 24 個 device 檔：~~27~~ 23 綠，`context_menu_flows_test.dart` 5/5 紅（05-G 右鍵 Discard 後 framework 例外
`identical(childRenderObject, parentRenderObject)` 與 `Cannot get renderObject of inactive element`，其餘 4 個是連鎖）。

- worktree 二分：`c3e6ee7a`（lazy 前）綠、`4f9fcbf5`（L2）綠、`f53626b3`（L3）紅。**L3 提交時沒有跑 device 層**，
  這是本輪的 G3 漏網。
- 對照實驗：開回 keep-alive → 仍紅；拿掉 step 8 的卡片 GlobalKey → 仍紅；拿掉「無內容時直接回傳 list」的 early
  return → 綠。
- 根因：L3 為端點幾何在 ListView 掛了 `_listKey`。refetch 期間來源短暫沒有內容，`build` 把 list 回傳在
  `SelectionArea` 之外；帶 GlobalKey 的列被**搬出再搬回**，region 對 inactive 的 `SelectionListener` 排序。
  L3 之前沒有 key，空狀態是重建，所以沒事。
- 修法：`_listKey` 只在有內容時掛上。`_hScrollKey` 一律掛上不會紅（內層 key 一變列就重建），所以不加條件。
- hover sweep：ruler 標記可點但沒有 click cursor，補上。
- 兩個修正後再逐檔重跑：24/24 檔全綠。

### 移除 orphan（c81011da）

`GbmCodeScrollWell` 在 slice L 後於 `lib/` 無 reader，doc comment 的論點（列不能 unmount）也已不成立；原樣搬進
`diff_row_cost_perf_test.dart` 當 eager 基準，量測結構不變。

## Result

### 測試與 mutation

- `flutter test` 4224 通過（~8 skip）；analyzer 0；format 通過；ctest 950/950（eb2c7368 時）。
- 每個 commit 的 mutations-run / tests-reddened 記在各自的 commit message。等價 mutation：81b9c24f 的 high-inclusive
  （barrier 一定來自另一側、rank 不同）；30fef443 的 M10（拿掉 sort）；33abb9e0 的 shouldRepaint；4f9fcbf5 的 K8
  （ListView padding）；f53626b3 的 N8（hit test 從 viewport 進入，local 即內容座標）；cb89afd8 的「關閉時也觸發」。
  66d0d73a 的 M8（binding 呼叫錯成 `workingCopyDiff`）在 fake 層走不到，改由 device 層覆蓋。

### Verifier（HEAD 915c4922）：CONFIRMED

六項主張皆通過。除了重跑 unit（420）與 `full_file_stage_flow_test`（6/6），另有兩個獨立探針：真 git 產生
HEAD／index／worktree 的 fuzz（1200 情境、22,580 次隨機範圍的 payload 比對，failures 0），以及照 `StageOps.cpp`
每次重讀 -U3 的送出順序模擬（164 情境：由大到小 164/164 正確，由小到大 72 個出錯）。兩個 P4，記錄不修：

- unstage 方向跨多個 staged hunk 的一次性 scope，device 層沒有覆蓋（只有模擬證據）。
- 超過上限時 titlebar 按鈕 disabled，關掉偏好只能走 View → Full file。
- fuzz 的 parser 不處理 `\ No newline at end of file`，檔尾無換行沒有被 fuzz 到。

### 這一輪自己的失誤（照實記）

1. **aba0e02d 提交時全套是紅的**：fake 的 `refetchDisagreeingDiffs` override 蓋掉了被測的真實方法，3 個測試紅；
   當時只看了輸出的最後一行。f31551de 修正。之後一律 grep `All tests passed|Some tests failed|[E]`。
2. **step 8 第一次 mutation 漏算**：腳本 regex 把測試名限制在 60 字元，長名稱的紅被當成存活（R6 誤報）。修正解析後重跑；
   R7/R8/R11 是真的存活（測試字型下估計值太準），補了兩個會讓估計值漂移的測試。
3. **soft wrap 估高沒接上**（見 step 8），直到 ruler 的跳轉測試才被發現。
4. **L3 沒跑 device 層就提交**，`context_menu_flows_test` 因此紅了 L3 之後的每一個 commit，直到 G3 才發現（見上）。
5. **staging 錯行**是本輪以前就存在的 bug，但本輪 L3 的 30 個捲動拖曳測試都只用單一 hunk 的 fixture，也沒看出來；
   是 device 層第一次用三個 hunk 才抓到。

### 與計畫的差異

- 端點命中：計畫寫「每個子區塊各包 `MetaData`」，實作改成等價的幾何規則（item 內以列的 rect 判斷）。
- hit test 從 `RenderViewport` 進入，不是 ListView 的 box（IgnorePointer 根因）。
- 捲到卡片的跳轉由 L4 移到 step 8（L4 時沒有呼叫端）。
- TextPainter 量列高 → 跳轉時以畫面上 item 的真實位置做迭代修正。
- 選單切換的整合測試是新檔 `workspace_full_file_toggle_test.dart`，沒有擴充 parity test。
- View 選單位置（`File list as tree` 之後）是我選的，spec 沒有規定。

### 未做／待決

- `algorithm-chooser` 在 ruler 的比例換算與跳轉修正前沒有派出（換算是單純比例，修正是逐次逼近，判斷不需要）。
- ~~一次性 block 的 head 在長距離拖曳後不在畫面上（上方 UX 觀察），沒有改，待使用者決定。~~ **使用者裁定「長距離拖曳後 => 改」**，選 sticky head，已實作，見最後一節。
- ~~規則提煉：新增 `[FLU-stage-last-hunk-first]`、`[FLU-lazy-scrolled-drag-geometry]` 與 `[TEST-mutation-check-every-test]`
  的一條 Do，使兩個 L1 檔超過 6,000 字元報告門檻（`fn-flutter-input.md` 7,532、`arch-testing.md` 6,218）。
  `memory-steward` 建議：兩條 FLU 已由 site comment 與測試承載，移除；TEST 那條縮短；另列既有條目的 trim 候選。
  依 CLAUDE.md，待使用者裁定後套用，裁定前不提交規則檔。~~ **使用者裁定（2026-10-25）「照 memory agent 做」**，已套用，見下節。
- 二分用的 worktree（scratchpad 內，detached `f53626b3`）未刪除（AUTO 模式不做刪除）。

### 規則精簡（使用者裁定「照 memory agent 做」）

- `[FLU-stage-last-hunk-first]`、`[FLU-lazy-scrolled-drag-geometry]` 不新增：`scoped_diff_view.dart` 的 site comment 與
  測試已承載；`fn-flutter-input.md` 開頭「site comment 與測試已承載的規則」清單補上這兩項。
- `[TEST-mutation-check-every-test]` 新的 Do 縮短；第一條 Do 拿掉 `JsonCodec.cpp` 的例子。
- `[FLU-clear-selection-before-dispatch]` 的 Note 縮成一行（site comment 已有完整歷史）。
- `[TEST-no-pumpandsettle-with-spinner]` 的 Do 拿掉刪除線歷史。依 standing rule 4 不默默刪掉，原文保存在此：

  > - **Do**: find the sites with `grep -rnE '(Circular|Linear)ProgressIndicator\(' app_flutter/lib` (`commit_graph_view.dart` while `isRefreshing`, ~~`welcome_screen.dart` while scanning~~ (no indicator, 2026-10-23)); ~~`StatusBar`'s bars take `value: task.progress`, a non-null `double`, so they settle.~~ `StatusBar`'s bars are indeterminate while a task's `total <= 0` (`_barValue`, `status_bar.dart`), so they too never settle while one runs — a static empty track was the reported 「不知道有沒有在跑」 (2026-10-15).

- 結果：`arch-testing.md` 5,801、`fn-flutter-input.md` 5,616，皆在 6,000 以內；L0 24,456 不變。

### 使用者四項裁定之後（7ad8ad05 … ）

裁定原文：「照memory agent做」「長距離拖曳後 => 改」「P4,跨多個 staged hunk測試=>加」「P4,案超過 5,000 行時 titlebar 按鈕是 disabled => 自動暫停這個檔案的全檔檢視，但不影響全局設定」。

- **跨 staged hunk 的 unstage（100e5896）**：device 測試，三段插入全部 stage、拖曳框住前兩張 staged 卡片後 Unstage，第三段仍在 staged。
  綠；mutation（`_submitTemporary` 改為由前往後）→ 紅。mutations-run 1、tests-reddened 1。
- **超過上限（7a2ebc59）**：讀碼後確認既有行為已符合裁定（按鈕 disabled、tooltip、片段模式、`onToggleFullFile` 不被呼叫，判斷每次 build 依檔案重算）。
  追問後使用者選「Disabled + 說明」。補一個守衛測試：同一個 pane 先大檔後小檔，小檔重新填空、偏好未被切換。
  這個測試一開始就是綠的，沒有先紅；mutation（`_overCap` 觸發後保持 true）→ 紅。mutations-run 1、tests-reddened 1。
- **sticky head 設計（0c31ee24）**：`docs/claude-design-demo/wc-sticky-temp-head-spec.html`。
  spec-auditor 第一輪 15 不符／5 無出處，最嚴重的是我把置頂 head 的位置算成左 12／右 24，少算 well 外側 8px（正確 20／32，片段模式右 18）。
  第二輪 150 個值中 2 不符／2 無出處，另有 2 處文字與 CSS 矛盾，都在發佈前改正。
  使用者裁定：「可以照著實作，但是 跨 2 個 hunk 這文字不需要顯示出來」，追問後「兩處都拿掉」；陰影「不加」；對比度「開issue,說明影響範圍」→ **#200**。
- **拿掉「跨 N 個 hunk」（84514066）**：`hunkCount`／`temporaryHunkCount` 只供這段文字使用，一併移除（[CULT-orphan-wiring]）。
- **sticky head（c335eeb8）**：條件是「head 上緣在 viewport 之上，而且 block 最後一列仍在 viewport 上緣之下」。
  head 已建出時量它的 GlobalKey；沒建出時比較它所在的 card item 與頂端的 item。block 尾端用既有的 `_endpointAt` 編碼判斷。
  head 內容抽成 `_TemporaryHead`，兩處共用。`ScopedDiffView` 改成一律回傳 `Stack`，避免 head 出現或消失時 well 跟著重建。
  判斷在 layout 之後做，所以置頂版比 block 晚一個 frame。
  5 個 widget 測試、7 個 mutation，每個 mutation 都有指名的測試變紅：mutations-run 7、tests-reddened 5。
  device 測試（自動捲動拖曳）改按置頂版的按鈕：7/7 綠；mutation（按鈕無作用）→ 紅。
- **全套**：`flutter test` 4233 通過、8 skipped；analyzer 0；format 乾淨。
- **device 層逐檔重跑（G3）**：`full_file_stage_flow_test.dart` 7/7、`stage_lines_flow_test.dart` 9/9、`context_menu_flows_test.dart` 5/5（上一輪改了 view 的樹結構後紅過，這次 view 一律包 `Stack`，所以也跑）。
  `integration_test/perf/` 的兩個量測檔沒有重跑；它們量的是列的成本，不驗證正確性。

- **Verifier（HEAD 7ab5e32d）：REFUTED**，F1（P2）：已有一次性 scope、置頂 head 正在畫面上時開始新的拖曳，
  置頂 head 和綁著舊 scope 的按鈕會留到放開才消失。原因是 `_onTouchChanged` 在拖曳中不 rebuild。主張的其餘 4 點都確認無誤
  （payload、幾何、不重建 well、拿掉 hunk 文字）。
- **F1 修正（137556fa）**：pointer down 時收起置頂 head。先寫的兩個測試（原地拖曳、向上自動捲動）先紅後綠；mutation（拿掉收起）→ 兩個都紅。
  另外在 `_stickyWanted` 加過一個 pointer-down guard，mutation 證明它多餘（放開前的 rebuild 沒有 settled scope，本來就不會畫出來），已拿掉。
  mutations-run 2、tests-reddened 2。全套 4235 綠；device `full_file_stage_flow_test.dart` 7/7。
- **Verifier（HEAD 137556fa，fresh）：CONFIRMED**，五點全部成立。原本讓 F1 成立的探測在兩個方向都通過；新拖曳放開後，置頂 head 綁的是新 scope。
  兩個 hunk 時，按置頂 head 與走鍵盤路徑送出的呼叫相同（最後一個 hunk 先送）；staged 側只送 Unstage；SelectionArea 的 State 從頭到尾是同一個物件。
  全套 4235 綠；device 7/7。
- ~~待查（P4，低信心，沒有修）：verifier 沒有驗證 diff 橫向捲動時的情況。真正的 head 會隨內容橫向移動，當它被頂端切掉一部分時，
  在置頂版左 20／右 18（或 32）的範圍外是否還會露出一條，沒有驗證。~~
  **已查（2026-10-25，使用者要求「橫向捲動時是否露出一條真正的 head查一下」）：會露出。** 內容比畫面寬時，block 隨內容延伸並橫向捲動；
  固定 20／18 的置頂版兩側，像素取樣在 x 0..20 與 482..500 取到真正 head 的底色 #0d2a4d。
  - 使用者裁定（AskUserQuestion）：「對齊 block 實際位置」。左右範圍取 block 與 view 的交集；block 邊緣在畫面外的那一側，不畫虛線，也不畫圓角。
  - 修正（313bb4cc）：橫向位移取自冒泡上來的 `ScrollNotification`／`ScrollMetricsNotification`，存在 `ValueNotifier`，所以橫向捲動只重建置頂版。
    置頂版移到 ruler 之下，否則延伸到右緣時會蓋住 ruler 的上段（hit test 證實）。
  - 新增 5 個測試：橫捲 0／60／700、ruler 在上、resize 夾住位移、不寬時兩側虛線都在。mutations-run 6、tests-reddened 5。
    哪一個沒有變紅，當時沒有記下來，這裡不補猜測。全套 4241 綠，analyzer 0。
    device `full_file_stage_flow_test.dart` 7/7（HEAD 313bb4cc）。`stage_lines_flow`、`context_menu_flows` 在這次修正之後沒有重跑。
  - 設計稿 INF-3 就地更正（f2e1b73f）。
  - ~~觀察，交給使用者決定：內容比畫面寬時，置頂版延伸到右緣，會蓋住垂直捲軸 thumb 最上面約 31px。~~
    **使用者裁定：「右緣留出捲軸的寬度」。** 修正（2f34808e）：置頂版的右側最多延伸到 view 右緣往內 10。
    10 = Material 桌面版 `Scrollbar` 的預設 thickness 8 + crossAxisMargin 2；`GbmCodeHScroll` 沒有設 theme。這個值出自 SDK，不出自 spec。
    block 右緣落在這 10 以內時，視同在畫面外，不畫虛線。
    測試：期望值 0 → 10；新增 dx 686（block 右緣落在捲軸區內）；新增 thumb 區的 hit test。
    mutations-run 3、tests-reddened 3／1／1。另外把 inset 斷言拿掉、只留 hit test，在 gutter 改成 0 的情況下 dx 0 與 dx 60 都變紅，證實修正前置頂版確實會攔下拖曳 thumb 的手勢。
    全套 4242 綠，analyzer 0；device `full_file_stage_flow_test.dart` 7/7（HEAD 05d09b68）。設計稿 INF-3 已補上（05d09b68）。
- G3（HEAD 11a1529e）：device `stage_lines_flow_test.dart` 9/9、`context_menu_flows_test.dart` 5/5；本輪沒有新增執行期 timeout；orphan wiring 兩個方向都查過；hover sweep 只抓到 ruler 標記的 click 游標。
- **Verifier（HEAD 11a1529e，fresh）：CONFIRMED**，四點全部成立，沒有 P0–P2。
  scratchpad probe 的掃描範圍：excerpt 的 dx 0..700 共 18 個點，包含右緣落在 (490, 500] 的整段；ruler 加上寬 code 的 11 個點；`2 file` 右側 view 的 7 個點。
  每個點都比對了 head 的左右緣、真實 block 的 rect、虛線的側數，以及捲軸區的 hit test。橫向捲動之後，SelectionArea 的 State 仍是同一個物件。
  ~~P4（推測）：widget test 的 DPR 是 1，桌面上非整數 DPR 的情況沒有驗證。~~
  **已驗證（使用者要求「驗證一下」）：非整數 DPR 下沒有露出。** 測試的 DPR 分別設為 1.25、1.5、1.75、2.25、2.5，片段模式與 ruler 模式各跑一次，每次掃過 16 個帶小數的 dx，例如 0.3、19.6、333.33、671.7、686.4、691.9。
  - 每個 dx 都檢查兩件事。邏輯座標：置頂版與 block 的 rect 相同（容差 1e-6），虛線側數、捲軸區的 hit test 都正確。像素：用 `RenderRepaintBoundary.toImage(pixelRatio: dpr)` 取圖，在 head 的色帶上，置頂版左右外側超過 1 個 anti-aliasing physical pixel、捲軸區以外的地方，沒有任何一個 physical column 帶有 head 的底色。10 組全部通過。
  - oracle 的有效性：把置頂版改回不跟著橫向捲動（`scrolls = false`），拿掉邏輯座標的斷言，只留像素檢查。結果在 dpr 1.5 下，每個 dx 都抓到 11–40 個露出的 column。
  - 限制：小於 1 個 physical pixel 的露出，和 anti-aliasing 分不出來，這個 oracle 看不到。不過置頂版與 block 的邏輯座標完全相同，兩者的光柵化結果也相同。
  - probe 只放在 scratchpad，沒有進 repo，因為它檢查的事已經由邏輯座標的測試鎖住。
- 觀察（既有行為，本輪沒改）：verifier 的基準探測顯示，新的拖曳進行中，舊的 block 內一次性 block 也留在畫面上直到放開，原因相同。

這一段自己的失誤：
- 兩個 widget 測試的 fixture 寫錯，都在實作前就紅了，原因不在程式碼：row 9 在 300px 的 viewport 外沒被建出；`temporary-scope-card` 的 box 比 head 高出 4px 的 margin。改測試，不改程式碼。
- 第一版設計稿的出處註解有 15 處與 app 不符（見上），是只看 widget 名稱、沒逐一讀數字造成的。
- 這一段中途，auto mode 的 Bash 安全檢查服務連續 6 次沒有回應判定，工作暫停一次；服務恢復後照原步驟繼續，沒有略過任何步驟。

