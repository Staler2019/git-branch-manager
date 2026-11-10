# fix/autoscroll-stack-overflow — 拖曳選取的 autoscroll 在放開時 stack overflow

## Situation

Windows 本機跑裝置層時，`full_file_stage_flow_test.dart` 的 'an autoscrolling drag past unbuilt rows stages from its start row to its end row' 偶發失敗，`main` 上也一樣。看到的失敗有三種：

- `no pinned one-shot head`（一次）
- 測試本體已跑完，結果卻是 「did not complete」，沒有任何訊息
- `'dart:async/stream_impl.dart': Failed assertion: line 378`（`_sendData` 的 `assert(!_inCallback)`）

## Task

使用者裁定「autoscroll 偶發中斷 => 查完修完」：找到根因，修好。

## Action

### 找根因：被推翻的假說

- ~~listener 例外經 zone handler 再丟，`_STATE_IN_CALLBACK` 殘留~~：在 test zone 與 `main` 外層各包一層 handler，失敗時兩層都沒有印出任何東西。
- ~~`stream_impl.dart:378` 是原始失敗~~：這個失敗形狀只在我加了 DIAG 儀器之後出現。那份儀器的 `runZonedGuarded` handler 寫了 `throw e`，而 handler 丟例外本身就會讓 `_STATE_IN_CALLBACK` 殘留，所以它是儀器造成的第二現場。
- 也懷疑過 teardown 時 session 還開著、NativeCallable 的關閉順序，都沒有證據支持。

### 根因

把 handler 改成不再丟例外、同步寫檔（`writeAsStringSync(..., flush: true)`）。第一次失敗就抓到：`PlatformDispatcher.onError` 收到 `StackOverflowError`，stack 共 8023 層，全是 `Future._completeWithValue → _propagateToListeners → StackZoneSpecification._run` 這一組重複。

來源是 Flutter 的 `EdgeDraggingAutoScroller._scroll()`（`scrollable_helpers.dart:237-319`）。每捲一步（至多 20 px）就 `await _scroll()` 遞迴一層。拖曳放開時，整條 future 鏈在同一個 microtask 裡一次收尾。Flutter master 也還是這樣寫（2026-11-10 用 `curl` 查 raw 原始碼確認）。

`flutter test` 一律帶 `--chain-stack-traces`（`flutter_tools/lib/src/test/runner.dart:91`，無條件），每層因此撐成 8 個 frame。測試拖了約 900 步，剛好卡在上限附近，所以是偶發。

### 正式版也會中嗎：量測

用 `flutter drive --profile` 跑暫時的 probe（AOT，不帶 chain），4900 行的全檔視圖，按住後到指定深度再放開：

| 深度（約） | 捲動距離 | 經過時間 | 結果 |
|---|---|---|---|
| 500 | 10,009 px | 32 s | 正常 |
| 1501 | 30,019 px | 95 s | `StackOverflowError` ×2 |
| 2700 | 54,010 px | 172 s | `StackOverflowError` ×2 |

probe 前兩次沒量到東西，原因各一：12000 行超過 `fullFileViewMaxLines`（預設 5000），全檔視圖沒開；拖曳起點不在文字上，選取沒有開始。結論：這是 app 的 bug，不只是測試的問題。

### 修法（使用者在三個選項中選「App 自己捲」）

新增 `lib/widgets/selection_edge_scroll.dart` 的 `SelectionEdgeScroll`，由 `GbmCodeHScroll` 包在垂直 list 外面。四處 `SelectionArea` 都經過 `GbmCodeHScroll`（Working Copy、`diff_page.dart`、`side_by_side_diff_view.dart`、`panel_diff_text.dart`），所以一起修到。做法：

- 選取拖曳點的垂直座標夾回框內，框架永遠不會啟動垂直 autoscroll。
- 指標在框外時，用 Ticker 迴圈捲動 controller（不是遞迴），並重送夾回的拖曳點。
- 水平座標不動，水平 autoscroll 仍由框架處理，深度只有一行的寬度。

速度：框架宣告每秒 30 步（`_kDefaultSelectToScrollVelocityScalar`）。但每步 33 ms 的動畫結束在幀邊界，下一步又晚一幀才開始；widget 層實測 2 秒捲了 829.7 px，約 415 px/s。我起初照宣告值寫成 600 px/s，會比原本快 1.45 倍，所以改成每秒 20 步。改後舊程式也能通過速度測試，表示手感沒變。

### 過程中寫錯、已更正的

- 重送夾回的點時會再進 `_noteEdge`，把框內點當成指標回來了而停掉；加了 `_resending` 防護。
- 程式碼比畫面寬時，一整組既有拖曳測試變紅。我起初判斷 ~~放在最外層（橫向 scroller 外）會讓 sideways handler 拿不到內容、整個選取失效~~。
  - 真正原因：selection container 多一層後巢狀四層（region、橫向 scroller、`SelectionEdgeScroll`、list），最深一層要到掛載後下一幀才註冊（SDK 3.47.4 `selectable_region.dart` 的 `_scheduleSelectableUpdate`：從 microtask 排的 post-frame callback 落在下一幀）。
  - 在掛載當幀就按下，整個拖曳收不到事件。
  - 補一幀後，最外層、最內層兩種放法都 11/11 綠（放置位置的 mutation 存活）。
  - 程式碼註解已照實改寫。實測掛載後 `hasScheduledFrame == true`，下一幀由框架自己排；我加過的 `ensureVisualUpdate()` 沒有任何測試能證明需要，已刪。
- `scoped_diff_view_scrolled_drag_test.dart` 與 `diff_pane_drag_stage_test.dart` 的掛載輔助函式各補 `await tester.pump()`，旁邊寫明原因。

## Result

- `test/widgets/selection_edge_scroll_test.dart`：11 個測試，`code that fits` 與 `code wider than the view` 各跑一輪。
  - 每組 5 個：2000 步不溢位、速度、往上捲、回框內或放開就停、選取跟著內容延伸。
  - 另加 1 個：寬版的水平 autoscroll 仍由框架處理。
- 先紅：改之前的 `gbm_code_hscroll.dart` 上，2000 步測試 `Stack Overflow` → `did not complete`，與裝置層症狀相同。
- Mutation（最終版程式）：執行 5 次，變紅的測試數分別為 9、8、4、2、6。
  - 項目：不夾座標、拿掉重送防護、每秒 30 步、放開不停、每步 40 px。
  - 第一輪另有「回框內不停」這個 mutation 存活：`_tick` 本身算到 overshoot 為 0 就會停，那個分支是多餘的，已刪掉。
- `flutter test` 全套：4583 通過、27 略過、0 失敗。`dart analyze` 0 issue，`dart format` 0 changed。
- 裝置層（Windows ARM64）：
  - commit / empty_side_preview / stage_lines / sync_scroll 全綠。
  - autoscroll 測試連跑 10 次 10 綠；修之前 6～10 次內各輪都抓到 1 次失敗。
  - `full_file_stage_flow_test.dart` 整檔 6/7。紅的是「discard 後換行是 CRLF」，已由 PR #215（`fix/clone-askpass-test-race`）修正，這個分支從 `main` 開，還沒有那個修正。
- profile probe 加上修正後重跑（同一份 4900 行全檔視圖）：

  | 深度（約） | 捲動距離 | 經過時間 | 結果 |
  |---|---|---|---|
  | 500 | 10,006 px | 26 s | 正常 |
  | 1500 | 30,004 px | 76 s | 正常 |
  | 2700 | 54,006 px | 136 s | 正常 |

  - 速度：舊版在實機約 313～316 px/s，新版約 385～395 px/s，快約 1.25 倍。widget 層的假時鐘固定每幀 16 ms，量到的舊版速度是 415 px/s，與實機不同。
  - 舊框架的速度是「33 ms 動畫，再加上等到下一幀」，本來就隨實際幀率變動，所以沒有單一的「原本速度」可以對齊。~~沒有改參數，只記下這筆數字，留給使用者決定。~~ 使用者裁定「維持看機器設定 這部分不改」：保持每秒 20 步。新程式依實際經過時間計算步長，速度不隨幀率變動。
- 改用架構測試、不寫成規則：memory-steward 判定 `[FLU-selection-autoscroll-recurses]` 的兩行都是 ENCODE。
  - Rule 那一行：`selection_edge_scroll.dart` 的 doc comment 加上 2000 步的測試已經涵蓋。
  - Do 那一行（「新的可選取區要經過 `GbmCodeHScroll`」）：新增 `test/architecture/selection_area_scroll_test.dart`。`lib/` 裡凡是出現 `SelectionArea(` 或 `SelectableRegion(` 的檔案，都必須也出現 `GbmCodeHScroll(`，而且至少要掃到 4 個檔，避免空掃描也算通過。
  - Mutation：執行 2 次，變紅的測試數分別為 1、1。拿掉 `panel_diff_text.dart` 的配對，測試點名該檔；把 pattern 改成永遠比對不到，測試報 `Actual: []`。
- memory-steward 提出的疑點：`SelectableText` 會不會走同一條遞迴。結論是不會。SDK 3.47.4 裡用到 `EdgeDraggingAutoScroller` 的只有 `scrollable.dart`、`scrollable_helpers.dart` 和兩個 `reorderable_list.dart`；`SelectableText` 是 `EditableText`（`selectable_text.dart:759`）。app 裡唯一的 `ReorderableListView` 是 graph 欄位選擇器，只有幾列，拖曳撐不到上千步。
- 沒有開 issue。暫時的 probe 檔（`integration_test/perf/zz_autoscroll_depth_probe_test.dart`）不進 commit。
