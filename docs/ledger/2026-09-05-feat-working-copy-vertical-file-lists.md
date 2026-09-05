# 2026-09-05 · feat/working-copy-vertical-file-lists — 檔案清單改成左側垂直，順手挖出六個介面共有的樹狀缺陷

使用者的原話：

> working copy頁，目前左右不好看檔案內容，幫我把水平unstaged-staged file list改成
> 左側垂直，unstaged一樣在上，file line view 在右側 commit message位置不變

「不好看**檔案內容**」是這句話的重點所在。兩個檔案清單並排在上半部，把整個視窗的
寬度吃掉之後，diff 只剩下半部；而 diff 才是這一頁存在的理由。

```
現況                                    目標
┌──────────────┬──────────────┐        ┌────────┬──────────────────────┐
│ Unstaged · 2 │ Staged · 1   │        │Unstaged│ a.dart  [2file│unified]│
│  a.dart      │  c.dart      │        │ a.dart │  @@ -12,7 +12,9 @@   │
│  b.dart      │              │        │ b.dart │  -  old line         │
├──────────────┴──────────────┤        ├────────┤  +  new line         │
│ diff  (2 file / unified)    │        │Staged·1│                      │
│ @@ -1,4 +1,5 @@             │        │ c.dart │                      │
├─────────────────────────────┤        ├────────┴──────────────────────┤
│ commit message      [Commit]│        │ commit message        [Commit]│
└─────────────────────────────┘        └───────────────────────────────┘
   wc.diff   垂直 46/54                  wc.files  水平 extent 260
   wc.columns 水平 1:1                   wc.stack  垂直 1:1
                                         commit box 一個字都沒動
```

## Phase A — 先寫 spec 再動程式碼

使用者對寬度那題沒有選項，只回了一句：「一樣先更新 html spec 給我看過」。所以這一輪
的第一個交付是 `docs/claude-design-demo/working-copy-layout-spec.html`，沿用上一輪
worktree-dialogs-spec 的骨架，Before/After 兩組活的 mockup（1280 與 1920 兩種寬度，
因為左欄固定寬 vs 比例寬只有在兩個寬度並排時才看得出差別），每個數字旁邊註明出處。

spec-auditor 的判定是 9 個 drawn value：**符合 2**（`[1,1]` 比例、drop hint 的現有
字串）、**不符 3**（兩條分隔線的方向、垂直 min 96 vs spec 的 200px）、**無出處 4**
（extent 260、min 180、96 的 repo 先例、drop hint 的替代字）。

這裡最重要的一件事，是稽核**把偏離的形狀說清楚了**。spec 第 09 頁的 `SPLITTERS` 表
兩列都在，而且跟當時的程式碼逐字相符：

```
{ id: 'wc.columns', where: 'Unstaged ↔ Staged', dir: '垂直', def: '1 : 1',   min: '200px' }
{ id: 'wc.diff',    where: '檔案區 ↔ Diff',      dir: '水平', def: '46 / 54', min: '150px' }
```

`dir` 講的是**分隔線本身**的方向。所以這一輪不是「內部改個 storage 名字」，是**兩列
spec 明文被推翻**——照 [SPEC-absent-not-faked] 記成使用者裁定的偏離，與
[STRUCT-working-copy] 記的「拿掉 checkbox」同一類。

使用者三次裁定：

1. 寬度 → **方案 A**，固定寬度 `GbmSplitterSpec.extent`（260 / min 180）
2. diff 預設 → **改成 `unified`**（右側 pane 再切成左右兩欄，等於把抱怨原封不動搬過去）
3. drop hint → **C1**「拖曳檔案到下欄 = stage」

第三次的追加裁定把範圍擴大了：

> A、C1、tree 一起修，目前的 line stage/unstage code section 樣式你也要看一下，
> 這部分之前只有 code 修改，沒有設計在 spec 上

## 換軸就是換 key，這是義務不是選項

[FLU-splitpane-axis-change] 寫得很直白：只有 ratio 模式撐得過換軸；extent 模式存的是
原始像素數。這一輪兩條線都換軸，兩個既存值都失去意義：

| 舊 | 舊語意 | 新 | 為什麼不能沿用 |
|---|---|---|---|
| `wc.diff` flex[46,54] min150 | 垂直：board ↑ / diff ↓ | `wc.files` extent 260 min 180 | 46/54 是**高度**比例，套到寬度上讓檔案清單佔掉近一半，正是要解決的問題 |
| `wc.columns` flex[1,1] min200 | 水平：Unstaged ← / Staged → | `wc.stack` flex[1,1] min 96 | min 200 是**寬度**下限；當成高度下限，兩欄要 400px 才畫得下 |

換 key 讓舊的 `panelLayout.wc.diff` / `panelLayout.wc.columns` 變孤兒——讀取 miss、
落回預設值，**不會讀到錯的數字**，是 [FLU-storage-id-not-tab-id] 記過的同一個取捨。

### 96 是量出來的，不是挑的

垂直 `minExtent` 的純常數部分算得出來：header `rowHeightCompact` 26 + drop hint 外距
`space2` 8 + 內距與框線 (8+1+8+1) 18 = 52px chrome，加一列檔案 26 = **78px**。剩下的
是一行 11px 文字的行高，`TextStyle` 沒設 `height:`，是 `TextPainter` 的活數字。

所以沒有用算的，用**二分**：拿 `working_copy_board_test.dart` 自己的 overflow 斷言當
判準，把 `splitterWcStack.minExtent` 往下調——

```
85 → 紅        86 → 綠        78 → overflow by exactly 8.0px
```

真正的下限是 **86**，採用的 96 帶 10px 餘裕。這一步同時解決了「這個測試一寫出來就是
綠的」這個問題：一個到手就綠的測試不能證明自己不是空的，而二分出來的 85/86 邊界可以。

順帶一提，`GbmSplitPane` 的 flex `minExtent` 是**兩個 pane 共用一個底線**，而 drop
hint 只有 Unstaged 欄有（`if (!fromStaged)`），所以 Staged 自己只需要 52px 卻被同一個
數字綁住。這是取捨，不是缺陷，寫進 `tokens.dart` 的 doc comment 裡。

## 真正的收穫在 tree 模式，而且它不在 Working Copy

使用者說「tree 一起修」時，指的是 Working Copy 樹狀模式下葉節點畫的是完整路徑，資料
夾列已經寫過的前綴又寫一次。查下去發現這件事**不在 Working Copy**，在共用的
`FileListModeSwitcher`——所以**六個介面同時中獎**：Working Copy 兩欄、History 的
Changed files、Compare 的 Files、Conflict 視窗、`panel_file_diff_detail`。

```
壞掉的樣子                        修好之後
▾ lib/features/                   ▾ lib/features/
    lib/features/a.dart               a.dart          ← node.name
    lib/features/b.dart               b.dart
```

原因是 `leafBuilder(context, item)` 沒有第三個參數，每個 call site 只好自己從 item 掏
完整路徑，於是 list 與 tree 兩個模式畫出**完全一樣的字**。P03 item 10 的原文是「平鋪
完整路徑，或依資料夾摺成樹狀」——完整路徑是 **list** 模式的事。

修法是把契約改在 switcher：`leafBuilder(context, item, label)`，list 傳 `pathOf(item)`，
tree 傳 `node.name`。六個 call site 各自決定葉節點的字，就是六次分歧的機會
（[CULT-single-source-of-truth]）；加一個參數之後，漏掉是**編譯錯誤**。

### 同一個 note 裡還藏著第二個缺陷

`FileTree._collapseIfSingleChild` 收合單子項鏈時，**檔案**那一支做的是
`leafPath!.split('/').last`，把整段前綴丟掉了。資料夾那一支本來就是對的——所以任何
「收合鏈結尾是資料夾」的 fixture 都看不出問題。

而 P03 item 10 自己的例子就是這件事：

> 樹狀模式下只有一個子項的資料夾會自動串接成 **`lib/app/views`** 一列，不會逐層縮排
> 浪費寬度

`lib/app/views` 就是串接後的完整前綴。spec 舉的例子正是被丟掉的那個東西。

### 為什麼 conformance matrix 沒抓到

matrix 的 P03 item 10 那一列判 **符合**，證據是五個 `ref.watch(fileListViewModeProvider)`
的 call site。但那一列的標題寫的是「ONE shared preference across …」，那是 item 10 的
**最後一句**；前面兩句從來不在稽核單位裡。

這同時是兩條規則：[SPEC-cell-names-capability]（cell 拿能力當證據，而不是畫它的
widget）與 [SPEC-audit-unit-is-not-the-page]（標題宣告的範圍之外的散文沒被讀過）。
判定已就地更正，契約釘成 [STRUCT-leaf-label-from-switcher]。

**另外撿到一個要裁定的**：item 10 自己前後兩句對「模式」講反了——「收合狀態與**模式**
各清單獨立記憶」對上「**同一個設定**套用到 …」四個介面。程式碼實作的是後者，matrix
也一直是照後者判的；收合狀態確實是各清單獨立（`FileTreeList` 自己的 `_expandedFolders`）。
兩邊都是散文，[SPEC-mockup-is-not-prose] 的「散文勝過圖」在這裡幫不上忙，所以**記錄
但不決定**，開成 [DRIFT-list-tree-mode-scope-undecided]。

## scope 卡片：之前只有 code，沒有設計

使用者指出 line stage/unstage 的卡片樣式「之前只有 code 修改，沒有設計在 spec 上」。
設計來源找到了——`Diff Scope Studies` 是使用者自己的 artifact，變體 B。照
[SPEC-demo-dom-is-the-spec] 用 WebFetch 取回完整 CSS **與 DOM**（CSS 說長什麼樣，只有
DOM 說放在哪裡，而放在哪裡正是之前做錯的那一半）。

逐項比對之後分三類：S1/S2 符合、S12–S14 不是本輪的題目、S3–S11 待裁定歸成六題各附
建議。使用者回「照建議」——六題全部照建議採納。其中兩題的建議是「維持現狀」（S6 的
badge、S7 的 `(N changed)`），它們因此**從實作者判斷升格為使用者裁定**，
[STRUCT-working-copy] 裡那句「that last half is an implementation judgement, not the
user's verdict」就地劃掉。

實作分三個 commit：虛線與框線（W11）、兩個 chip（W12）、hover（W13）。過程裡的三件事：

- **兩個虛線實作**。我一開始 grep 沒找到既有的虛線 helper，寫了一個新的；後來發現
  `gbm_tag_chip.dart` 裡早就有 `_DashedRRectPainter`，還帶著一句「no other caller needs
  one yet (YAGNI)」的註解。grep 沒找到是因為我從 repo 根跑、路徑寫錯又加了
  `2>/dev/null`，把「目錄不存在」的警告一起吞掉了。統一成 3/2（既有的、有出處的值，
  不是我發明的 3/3），`GbmTagChip` 改用共用的，私有 painter 刪掉。
- **`_GapBlock` 的無限高度**。`Row(CrossAxisAlignment.stretch)` 放進 `Column` 之後炸
  `BoxConstraints forces an infinite height`——正是 [FLU-column-nonflex-unbounded-height]，
  用 `IntrinsicHeight` 收掉。
- **W12 的 11px overflow 是真的**。欄頭的計數 chip 是非 flex child，`Expanded(title)`
  救不了它（[FLU-renderflex-non-flex-first]）。它之所以看得見，是因為 W3 把那個測試的
  畫布從 200 收到 140——[TEST-canvas-is-800x600] 的反面：畫布比真實情境大的時候，版面
  缺陷是隱形的。

## 裝置層：六個檔案裡有一個紅的

[TEST-device-tier-not-in-ci] 說得很清楚，這一層沒有任何 CI 在跑，一次 UI 改版可以讓它
壞好幾輪而其他層全綠。而且 [TEST-grep-misses-intent-driven-device-tests] 提醒 grep 字串
會漏掉用 `GbmActionId` 進場的測試，所以除了 widget 名也 grep 了 action id
（只有 `worktree_pending_counts_test.dart` 是那種，用 `toolsWorktrees`，與本輪無關）。

跑之前：`pkill -f gbm_flutter`、`scripts/build_capi.sh`（[TEST-stale-dylib-is-silent]），
並先在**父 commit `4dd822a`** 跑一次對照組（[TEST-foreground-line-is-not-a-failure] 那
一條記的教訓——那句 `Failed to foreground app; open returned 1` 在全綠的跑次也會印）。

```
                          對照組(4dd822a)   分支尖端
stage_lines_flow              7/7 ✓          7/7 ✓
working_copy_line_counts        —            1/1 ✓
commit_flow                     —            0/1 ✗   ← 唯一的紅
commit_file_counts              —            2/2 ✓
conflict_flow                   —            1/1 ✓
context_menu_flows              —            5/5 ✓
```

`commit_flow` 的紅是 `Found 0 widgets with text "Staged · 1"`：

```dart
final Offset to = Offset(board.right - board.width * 0.25, from.dy);
//                       ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                       「另一欄在右邊」被寫成了算式
```

board 轉成上下堆疊之後，這個點落回 Unstaged 欄裡，檔案根本沒過去。改成
`board.bottom - board.height * 0.25` 就綠了（1/1）。

**這件事在裝置層以下完全看不到**：widget 層的拖曳是抓另一「列」的文字當終點
（`getCenter(find.text('pubspec.yaml'))`），與軸無關，整輪都是綠的。只有這個檔案自己
算幾何點——因為它的 fixture 是「一個什麼都還沒 stage 的 repo」，Staged 欄裡沒有任何一
列可以瞄準。釘成 [TEST-geometric-drop-point-is-axis-bound]。

順帶把 kTouchSlop 那一步為什麼**仍然往橫的**寫進註解：`startGesture` 預設是
`PointerDeviceKind.touch`，它**在** `_kTouchLikeDeviceTypes` 裡
（[TEST-dragdevices-is-not-a-guard] 講的是 `mouse`，那個不在），所以第一步若直接往下，
清單自己的捲動器可能在 `Draggable` 贏得 arena 之前先把手勢認走。

## 收尾時撿到的兩個孤兒／過期紀錄

- **`GbmLayout.workingCopyLeftColumnWidth = 280`**：從被加進來的那個批次 commit 起就
  沒有任何 `lib/` caller，唯一的讀者是斷言它自己的值的那條測試——[CULT-orphan-wiring]
  的原型。轉軸讓它從無害的死常數變成**名字指錯東西**（左欄現在是檔案清單那一疊，寬度
  260）。那條測試的名字還寫著「matches spec (280)」，而 spec 全文搜 280 只有 3 個命中，
  兩個在 base64 區塊裡、一個是無關的 `max-width:280px`。真正有出處的 280 是
  `splitterPanelList.defaultExtent`。刪掉，理由寫在測試檔原處。
- **`_wellChildren` 的 doc comment**：寫著「臨時卡片固定佔住最上面的槽，沒有選取時是
  `SizedBox.shrink`」，而那個函式只吐 `_HunkHeading`／`_GapBlock`／`_ScopeCard` 三種
  child。一次性選取早就改成巢狀在卡片內了（正是變體 B 的 DOM 結構）。註解裡引的那個
  危險（inline 插入會位移下面每一列，而列上掛著 `SelectionListener`）本身沒錯，錯的是
  把它當成保留固定槽的理由——列都帶 `GlobalKey`，Flutter 是把 element 搬過去而不是重建。
  就地劃掉重寫。同一句話在 `arch-structure.md:216` 也有一份，一起改。

## 數字

**突變檢查**（[TEST-mutation-check-every-test]，兩個數字分開記）：

| commit | mutations-run | tests-reddened |
|---|---|---|
| W1 splitter specs | 3 | 3 |
| W2 外層換軸 | 2 | 3 與 2 |
| W3 兩欄堆疊 | 2 | 3 與 2 |
| W4 unified 預設 | 1 | 1（另有 3 個既有測試變紅，那就是這一步的突變檢查） |
| W6 drop hint | 1 | 1 |
| W10a `FileTree` | 1 | 2 |
| W10b `leafBuilder` | 1 | 2 |
| W11 虛線與框線 | 5 | 5 |
| W12 兩個 chip | 4 | 4 |
| W13 hover | 4 | 4 |
| **合計** | **24** | **32** |

W5 用的是二分而不是突變（85 紅／86 綠／78 差 8.0px），W8 的紅是裝置層真的跑出來的。

**測試與靜態檢查**：全套 `flutter test` 2866 passed / 1 skipped；`flutter analyze`
No issues found；裝置層六檔 17/17。

W13 的 M3 突變第一次沒對上，因為 `dart format` 把那個運算式重排過——照
[TEST-mutation-check-every-test] 的「anchor 匹配不到代表突變根本沒套用，REDS=0 不是
測試空洞的證據」重跑一次，也是 -1。

## 還沒做的

- **人工上機確認沒有跑**：拖檔案上下、拉兩條分隔線、把左欄拉到最窄、切 2 file/unified、
  重啟後版面記憶。這一項是使用者自己的，裝置層綠不等於這一項過了。跑之前記得
  `ps aux | grep gbm_flutter` 確認前景的是剛建的那個（[TEST-stale-process-blocks-tier]：
  `/Applications` 裡那個舊的會一起被 `osascript` 抓到）。
- **W10 的範圍**是我自己判的。使用者說的是 Working Copy 的 tree，我改的是共用 widget
  的契約，於是六個介面一起變。理由是標準規則 1（碰到相關問題就讀 spec 與紀錄然後修掉）
  加上 [CULT-single-source-of-truth]，但這是**擴大**而不是縮小，所以講明白：想收回只
  改 Working Copy 的話，`a4bcfd1` 可以單獨 revert。
- **PR #138 的 CI 是紅的**，那是另一條分支、與本輪無關（`capi (FFI) - Windows` 跑了
  1h29m 之後失敗，形狀像卡住；`Flutter UI` 因為 `needs: capi-build` 連跑都沒跑；其餘
  9 個 job 綠）。沒有動它。
