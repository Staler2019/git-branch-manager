# 2026-09-01 · claude/sidebar-stash-styling-date-3dvzmu — 側邊欄 STASH 列補上 hover/選取/選單，修掉「20676d ago」

使用者的原話：

> sidebar stash has no hover color, select color, right click menu (can show
> like branches use dot icon as more). the lastly the wrong date of ... day
> ago (it shows 20676d ago, wtf), please look as the spec and show me how you
> would do

四件事，全部集中在同一個檔案：`app_flutter/lib/features/sidebar/widgets/sidebar_stash_section.dart`
的 `_StashRow`。

## 為什麼會這樣：這一列從一開始就沒有走共用的列元件

`_StashRow` 是手刻的 `GestureDetector` 包 `Container`，從沒改用
`lib/widgets/gbm_row.dart` 的 `GbmRow`——而側邊欄另外兩種列（分支、標籤，都是
`BranchTreeItem`）都是靠 `GbmRow` 才有 hover 色（`InkWell.hoverColor:
colors.surfaceHover`）跟選取底色（`selected ? colors.surfaceSelected : null`）。
這正是 [FLU-hand-rolled-inkwell-hover] 記錄過的同一種缺陷第三次出現——前兩次
（`FileTreeFolderRow`、`working_copy_view.dart` 裡的 `_MiniButton`）都是在 C18
「掃一遍這一輪改動檔案裡所有 `InkWell(`/`GestureDetector(`」時抓到的；這次沒有掃，
是使用者自己回報的。

`_StashRow` 原本完全沒有「選取」這個概念——`onTap` 從未接過，`SidebarStashSection`
也沒有任何欄位在記「目前選到哪一個 stash」。右鍵選單其實是接好的
（`_openContextMenu` → `showGbmContextMenu(..., stashMenuItems(...))`），只是
沒有像 `BranchTreeItem` 那樣一顆固定在列尾、恆定顯示的 `IconButton(Icons.more_vert)`
可以按——`gbm_context_menus.dart` 裡 05-H 那組甚至還留著「not yet wired」的過時
註解，這次一併訂正（[CULT-scrutinise-the-comment]／[CULT-correct-the-record]）。

## 「20676d ago」的根因

`StashEntry.timestamp`（`src/core/git/ops/StashOps.cpp` 用 `%at` 讀出來、
`JsonCodec.cpp` 原封不動序列化）是 unix **秒**，不是毫秒。`_StashRow` 舊版的
`_relativeTime()` 把這個秒數直接餵進 `DateTime.fromMillisecondsSinceEpoch()`，
沒有乘 1000，整整差了一千倍——換算下來落在 1970 年 1 月底附近，`DateTime.now()`
跟那個時間點的天數差就是「20676d」。

同一個 `StashEntry.timestamp` 欄位，`stashes_panel.dart`（P19 的 manage-stashes
分頁）、`reflog_panel.dart`、`commit_row.dart`、`line_history_panel.dart`、
`file_history_panel.dart` 全部都是先 `* 1000` 再丟進 `DateTime
.fromMillisecondsSinceEpoch`，然後用共用的 `formatGraphDate()`
（`features/history_graph/widgets/graph_date_format.dart`）格式化——側邊欄是
整個程式裡唯一漏掉這個轉換、還另外手刻一套「Xm/Xh/Xd ago」邏輯的地方。

## 修法

全部改在 `sidebar_stash_section.dart`：

1. `SidebarStashSection` 從 `ConsumerWidget` 改成
   `ConsumerStatefulWidget`／`ConsumerState`，比照 `StashesPanel` 自己的
   `int? _selectedIndex` 寫法，加上單一選取狀態（純視覺用途，這裡沒有像
   `StashesPanel` 那樣的細節面板要讀它）。选取 key 用 `index`，跟
   `StashesPanel` 既有的作法一致，不另外發明一套以 `oid` 為主的識別方式。
2. `_StashRow` 整個重寫成 `GbmRow` 包版面：`selected`／`onTap`／
   `onSecondaryTapDown` 都接上去，高度用 `PanelListRow` 已經量過、不會裁到
   第二行的 `rowHeightComfortable + space3`（46px）。多了一個固定寬度 32px
   的尾端欄位放 `IconButton(Icons.more_vert)`——寬度數字跟
   `BranchTreeItem._kActionsSlotWidth` 一樣，理由也一樣：讓整欄的 ⋯
   按鈕對齊。這顆按鈕跟右鍵共用同一個 `_openContextMenu`，只是簽名從
   `TapDownDetails` 改成 `Offset`，讓兩條路徑都能呼叫。
3. 刪掉 `_relativeTime()`，改叫 `formatGraphDate(DateTime
   .fromMillisecondsSinceEpoch(stash.timestamp * 1000), DateTime.now())`——
   跟其他五個消費同一欄位的地方統一寫法。
4. 順手把舊的雙重左內距（`Container` 的 `horizontal: space2` 加上 `Row`
   裡多一個 `SizedBox(width: space2)`，左邊變 16px、右邊只有 8px）收斂成
   `GbmRow` 單一個 `padding` 參數，兩邊對稱。

**沒有做的事，也是刻意的**：spec 的靜態 mockup 在 stash 列前面畫了
`{{ icStash }}` 這個型別小圖示，但真正的 `BranchTreeItem`
自己在分支列上也沒有畫對應的 `{{ icBranch }}`——也就是說 Flutter
這邊「分支列本身」就沒有實作那顆圖示。既然使用者的訴求是「跟分支列一樣」，
幫 stash 列加圖示反而會讓兩種列變得不一致，所以沒加。雙擊也沒有比照分支的
「雙擊 checkout」，因為 stash 沒有對應的動作——所有動作都留在選單裡。

## 驗證

- `flutter analyze`（整個 repo）：0 issue。
- `dart format --set-exit-if-changed`：改動的三個檔案全部通過。
- 新增 `test/features/sidebar/widgets/sidebar_stash_section_test.dart`
  三個案例：(1) 兩列都是 `GbmRow`，點擊會讓 `selected` 在兩列之間正確切換而
  不是疊加；(2) ⋯ 按鈕跟右鍵開出同一組 05-H 選單，Apply／Drop
  都確實派發到 `FakeRepoSessionController.commandLog`（用
  `hasLength(1)` 數次數，不是 `.any(...)`，比照
  [TEST-count-dont-any]）；(3) 針對「20676d ago」的回歸測試——取一個
  10 天前的固定時間點算出對應的 unix 秒數，斷言畫出來的字串等於
  `formatGraphDate(...)` 用同一個時間點算出的結果，並且明確斷言畫面上
  **沒有**出現「1970」字樣。三個都綠。
- 既有的 `test/features/sidebar/`、`test/features/context_menus/`、
  `test/integration/workspace_conflict_transition_test.dart`
  （總計 328 個案例）重新跑過，全部維持綠燈——沒有任何既有測試直接建構
  `_StashRow`／`SidebarStashSection`，所以這次的簽名變動沒有波及別的檔案。
- 沒有跑裝置層：這一輪只有 Linux 上的 widget test，[TEST-device-tier-not-in-ci]
  記過的那個缺口在這裡仍然成立，之後如果有人要驗證真的滑鼠 hover
  視覺效果，得另外挑一個裝置層批次補。
