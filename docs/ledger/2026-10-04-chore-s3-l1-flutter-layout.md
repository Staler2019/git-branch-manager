# chore/s3-l1-flutter-layout — L1 第一片：fn-flutter-layout.md 21 條縮為 1 條，另拆兩份窄路徑 L1

## Situation

L0 在上一片降到 28,705 後，接著處理 path-scoped 的 L1 檔，每份預算 6k。`.claude/rules/fn-flutter-layout.md`
是最大的一份：36,133 字元、21 條，`paths: app_flutter/**`，所以碰任何一個 Flutter 檔都會整份載入。

## Task

依 `memory-steward` 處置表縮減（使用者：「ok照你處置表做」），並加一個條件：
`fn-flutter-split-pane.md` 的 paths 不含 `tokens.dart`，避免為了一個 token 檔把整份規則帶進來。

## Action

- **處置**：L1 留 3 條，分到三份檔：
  - `fn-flutter-layout.md`：renderflex，paths `app_flutter/lib/**`。
  - `fn-flutter-layout-test.md`：finder-proves-existence-not-position、paint-color-quantises，paths `app_flutter/test/**`、`integration_test/**`。
  - `fn-flutter-split-pane.md`：splitpane-axis-change，paths 只含 `split_pane.dart` 與其測試。
- **ENCODE 16 條**：這些條目都已有測試釘住。15 個測試檔跑 +269 全綠。**這一片沒有另做 mutation**，依據是那些測試在原本各輪都已做過 mutation check。
- **L2 1 條 + 新紀錄 2 份**：`no-twodimensional-viewport` 改寫成 record，並新增 merged-diff-region-order、log-drawer-collapsed-by-default 兩份 ruling record（C1）。
- **C2，只改註解**：
  - 程式與測試裡 7 處退役 pin 引用改成白話或 records 路徑。
  - 使用者裁定 B／U1 與 log drawer 的裁定補上 records 指向。
  - 順修兩處早就過時的文字：
    - `gbm_code_hscroll.dart` 指向一個不存在的測試檔，改為 `diff_page_scrollbar_placement_test.dart`。
    - `split_pane_min_extent_test.dart` 的 reason 還寫「explicit collapse」，那個說法在 collapsed-drawer 那輪已被推翻。
  - `flutter analyze` 0；兩個 split_pane 測試檔 +27 全綠。
- **C3，規則重寫與改指**：`arch-testing.md` 第 13–15 列、`ops-spec-reading.md`，以及四份 records 裡的退役 pin 引用，都改成白話或 record 連結。改寫前先到程式碼核對每句新說法：
  - `GbmDialogWarnField` 的 `IntrinsicHeight` 在 `gbm_dialog_field_kinds.dart:111`。
  - `gbmInputDecoration()` 沒有 `labelText`、`isDense: false` 的理由在它自己的註解裡。
  - `_orderedBlocks` 在 `scoped_diff_view.dart`。
- **migration-loss 檢查**，逐條跑；hay 是新規則檔、records、ledger 與相關 lib/test 目錄：
  - 7 條缺 0。
  - 其餘 14 條缺的多半是 Evidence 欄裡 ledger 檔的**路徑字串**。那些檔案本身都在，屬於 false positive。
  - 有幾個是寫法不同但事實還在：
    - `y: 14.9` 對應程式裡的 `y=14.9`。
    - `labelRect.bottom <= fieldRect.top` 寫成 `lessThanOrEqualTo` 斷言。
    - `GbmSplitPane.initState`、`_GbmSplitPaneState.initState` 就是 `split_pane.dart` 的 `initState`。
    - `maxHeight: double.infinity` 在 `scoped_diff_view.dart` 寫成 `maxHeight: infinity`。
    - `GbmButton(...)` 只是示意。
  - **接受的真實遺失**：`floating-label` 那條附帶的量測，即 `errorText` 在同一個固定高的框內畫在 `y: 33–50`、本身沒有缺陷，以及 `helperText` 與它同屬一類。這兩項現在只留在 git 歷史（`HEAD~1:.claude/rules/fn-flutter-layout.md`）。它們描述的是「不需要修的東西」，留到 L1 也不會改變任何人的動作。
- **其他檢查**：
  - `check-rule-pins.py`：163 條、96 個引用，懸空 0。
  - 連結檢查 broken 1，是 `docs/rules/README.md` 範本裡原本就有的 `<date>-<branch>` 佔位字串，不是這輪造成的。

## Result

- `fn-flutter-layout.md` 36,133 → 557 字元，另兩份新檔 972 與 649，三份都低於 6k。
- 碰 `app_flutter/lib/**` 的檔，載入量從 36k 降到 557。split-pane 那份只有碰到 `split_pane.dart` 本身或它的測試才會載入。
- L0 不變，維持 28,705。
- 還超過 6k 的 L1 有十份，留給後續的片：fn-git-commands、arch-testing、fn-cpp-core、drift-open、ops-toolchain-ci、fn-refs-branches、ops-spec-reading、fn-flutter-input、fn-flutter-state、arch-testing-device。
