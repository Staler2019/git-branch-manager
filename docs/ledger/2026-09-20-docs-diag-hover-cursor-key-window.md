# 拖動邊界 hover 游標異常，無法重現（docs/diag-hover-cursor-key-window）

## 回報

使用者：「拖一首是在hover不會正常運作了，有2:1. hover不會有可拖圖示，但是拖動還是可以
運作，且拖動時才變圖示 2. 拖動完移開可拖區域，圖示仍然是可拖動圖示」。追問後確認受影響
的是 History 的欄位寬度調整邊界（`_ColumnResizeStrip`）與分支側邊欄／log 面板的
`GbmSplitPane` 分隔線；欄位選取器的排序握把（`_GripHandle`，`.grab` 游標）「沒問題」——但
這句是在症狀已經自我恢復之後測的，見下方，不能當作「只有 resize 邊界受影響」的證據。
使用者另外澄清：「這次改之後才發生的。不過現在，程式放一陣子之後，現在hover又正常」。

## 已排除的假說

- **App 自身程式碼改動**：三個游標相關檔案裡，只有 `split_pane.dart` 最近有改動
  （`d4d14bb` 等 4 個 commit），但只動了 `_currentFlexes[0]` 的數值運算與
  `onDragStart`/`onDragEnd`/`onDragCancel`，完全沒有碰過 `cursor:`/`MouseRegion`。
  `commit_graph_view.dart`（History 欄位邊界）完全沒有被近期任何 commit 動過，卻同樣受
  影響——兩者唯一共同點是活在同一個 Flutter 視窗底下，只有「視窗層級」的成因能同時解釋
  兩者。
- **Flutter SDK／macOS 版本飄移**：本機 Flutter SDK 最後一次 commit 是 2026-09-10
  （10 天前）；`softwareupdate --history` 顯示最後一次系統更新是 2026-09-01（19 天前）。
  兩者都沒有在「這次改」附近移動過。
- **殘留的舊 build 行程**：`ps aux | grep gbm_flutter` 只有一個行程（這次 `flutter run`
  debug session），沒有 `/Applications/gbm_flutter.app` 同時在跑造成的混淆
  （`[TEST-stale-process-blocks-tier]`）。
- **「這次改」是時間上的巧合，不是因果**：這個 session 本身是 terminal-heavy 的工作流程
  （Task A 的大量 git／build 指令），焦點在 app 視窗與終端機之間頻繁切換——這正是下面主
  假說會預期出現症狀的操作模式。

## 主假說（已用 Flutter engine 原始碼確認機制存在，未經現場測試證實）

`FlutterViewController` 的滑鼠追蹤預設是 `kFlutterMouseTrackingModeInKeyWindow`
（`FlutterViewController.mm`）：`mouseMoved`／hover 事件只在視窗是 **key window** 時才會
送進 Flutter；`mouseDragged` 不受此限制，只要該 view 收過 `mouseDown` 就會持續收到。
`app_flutter/macos/Runner/AppDelegate.swift`／`MainFlutterWindow.swift` 都沒有覆寫這個
設定，兩者都是最小 `FlutterAppDelegate` 子類別。新增規則
`[FLU-mouse-tracking-key-window-only]` 記錄這個事實。

- 症狀 1（hover 沒圖示、拖曳時才變圖示）由此機制直接推出：視窗不是 key 時純 hover 移動
  不會送到 Flutter 的 `MouseTracker`；按下滑鼠開始拖曳讓視窗成為 key 之後，
  `mouseDragged` 才開始送達，游標才第一次被正確設定。
- 症狀 2（拖完卡住）在同一假說下成立的條件是：放開滑鼠、移出邊界之前或當下，視窗又失去
  了 key 狀態——這需要現場驗證，不是自動成立。
- 已用 `FlutterMouseCursorPlugin.mm` 原始碼確認：native 端每次呼叫
  `activateSystemCursor:` 都無條件 `[cursorObject set]`，沒有 native 端快取造成「決定要
  換游標卻沒真的換」——問題出在「Flutter 有沒有收到 hover 事件」，不是 native 呼叫本身。

## 次要假說（僅在主假說被推翻時才追，未驗證）

`WorkspaceScreen` 監看的欄位（`[FLU-watch-a-record-not-the-state]`）包含
`isRefreshing`，而 `PlatformMenuBarHost` 每次 `isRefreshing` 翻轉都重建一份真正的 macOS
`NSMenu`。這解釋了「頻繁、不定期觸發」的部分，但**尚未確認** NSMenu 重建是否真的會動到
NSCursor 或 Flutter 的 `MouseCursorManager._lastSession` 快取，且它本身無法單獨解釋症狀 2。

## 現狀：無法重現

使用者回報「現在都沒問題」——距離症狀最後一次出現已經過了一段時間，且沒有機會在症狀仍在
發生時執行下面的判別測試。依 CLAUDE.md 標準規則 #1（遇到問題要先讀 spec／決定紀錄再修，
而不是停在原地），既然目前抓不到穩定重現步驟，就把整份診斷（已排除的假說、engine 層級的
確認、下面的測試協定）存查在這裡，等下次症狀出現時直接照著做，不用重新從頭推理一次。

## 下次症狀出現時的測試協定

1. **判別測試（主假說的完整性）**：先點一下 app 視窗的標題列（確保視窗是 key，且這個
   點擊本身不構成拖曳）。拖動一個邊界（分支側邊欄或 log 面板的分隔線）、放開、把指標移
   開，過程中不要點擊或切換到任何其他視窗。
   - 游標恢復正常箭頭 → 主假說完整成立。
   - 游標仍然卡住 → 主假說不完整，轉第二個測試。
2. **次要假說的相關性測試**（僅在測試 1 卡住時才做）：按一次 F5，觀察 hover 是否立刻恢復
   正常，或立刻惡化。
3. **順手記錄**：`flutter --version` 的 commit／`sw_vers`、正在跑的是哪個 build
   （`ps aux | grep gbm_flutter` + 對應 PID 的啟動路徑）、視窗在症狀出現前 5 秒內是否是
   key（前一個動作是點了 app 視窗還是切到別的 app/終端機）。

## 下一步

若主假說被測試 1 證實，是否要把 `MainFlutterWindow.swift` 的 `mouseTrackingMode` 改成
`.inActiveApp` 留給使用者裁定——這是產品層級的取捨（改變游標追蹤的語意範圍），不是單純
bug 修復，且任何 `macos/Runner/*.swift` 的改動要到 release tag 建置時才會被編譯到
（`[CI-linux-only]`）。依標準規則 #3，是否開 issue 追蹤本輪詢問使用者，本輪未開。

## 新增／更新的規則

- 新增 `[FLU-mouse-tracking-key-window-only]`（`fn-flutter-input.md`）。
- 新增 `[DRIFT-hover-cursor-not-reproduced]`（`drift-open.md`）。
