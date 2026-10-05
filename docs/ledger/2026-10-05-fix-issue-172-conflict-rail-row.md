# fix/issue-172-conflict-rail-row — 衝突檔案列照 P8 改成單行，整檔動作移到編輯區

## Situation

#169 收尾時另議的一項：衝突視窗的檔案列是兩行，每列底下掛著 Take Ours／Take Theirs／Mark Resolved 三顆小按鈕。規格 P8 畫的是單行 `.gbm-row`（27px）：一顆狀態點、檔名、尾端剩餘段數，已解列淡化並加綠勾，沒有任何按鈕。此外 P8-1 列了 Ctrl/Cmd+↑↓ 切換檔案，程式裡沒有這組快捷鍵。

## Task

依 G1 先派 spec-auditor 稽核，再請使用者對三個規格沒答案的點裁定，然後照可逆的 commit 結構逐一 TDD。拿掉小按鈕前，要先替無法逐段解析的檔（binary、標記解析失敗）建好新入口，否則它們會沒有出路。

## Action

- **spec-auditor**：逐值引文。我自己抽查了決定用的事實：`GbmColors.success` 存在、`assets/icons/check.svg` 存在、原本的 `lineThrough` 沒有出處。稽核找出三處 prose 與 mock 的矛盾：
  - C1：mock 的段數與 prose「衝突 2 段，已解 1 段」對不上。依 `[SPEC-mockup-is-not-prose]` 以 prose 為準，數字代表剩餘段數。
  - C2：prose 寫「綠勾」，mock 畫的是 success 點加尾端 check。兩者不衝突，照 mock 畫。
  - C3：Continue 的標籤，mock 是 `Continue rebase`，prose 是 `Continue`。不在本輪範圍，只回報。
- **使用者裁定（2026-10-05）**：
  1. 無法解析的檔，整檔 Take Ours／Take Theirs 放「編輯區的提示處」；Mark Resolved 留在底列。
  2. 剩餘段數「已開過的檔才顯示」。沒開過的檔還沒解析，不顯示，也不猜。
  3. Ctrl/Cmd+↑↓ 移到「上／下一個檔，到頭停住」；Tree 模式略過資料夾列。
- **arch-suggester**：建議把走一步的函式 `adjacentConflictPath` 附加在 `conflict_resolve_logic.dart`，做成 top-level 純函式，不另開新檔。
- **commits**：

  | commit | 內容 | mutation |
  |---|---|---|
  | `fb81eca` | 編輯區 fallback 改放整檔 Take Ours／Take Theirs 兩顆 `GbmButton`，帶上 `oursBlobMissing`／`theirsBlobMissing` | 3 個，紅 2／1／2，都落在兩個新測試 |
  | `534f801` | 單行 `GbmRow`：27px；6px 點（danger／success）；檔名 10.5px，不設字重；已解列 `opacity .55` 加 12px `check`；清單 padding 6、列距 2；移除 `_MiniButton` | 11 個，各紅 1 |
  | `35f66cd` | `ConflictLineOrderState.unresolvedCount`；選中的檔即時讀數，離開時存入 `_remainingByPath`；列尾數字用 mono 9.5px、textTertiary | 8 個，紅 1／1／2／1／1／1／1／1 |
  | `e4f324f` | Ctrl/Cmd+↑↓：List 模式依 batch 順序，Tree 模式依 `FileTree` 的葉序；到頭時不重選 | 7 個，紅 1／1／2／1／3／2／1 |

- **過程中的修正**：
  - C1 的 K13 第一次寫成 `path == ""`，Dart 因此不再把 `path` 提升為非 null，整個檔案編譯失敗，所有測試載入就紅。這不是有效的 mutation。改成 `path != null && path.isEmpty` 重跑，紅 2。
  - C3 的 N8 把 `_allResolved` 的條件從 `== 0` 放寬成 `< 2`，結果全綠：原本沒有任何測試守住「只解完一部分」的情形。補了測試「the editable result waits for every region, not most」後重跑，紅 1。
  - #169 留下的「rail row hovers in surfaceHover」測試換成 C2 的四個列測試。hover 與 selected 的色值改由 `GbmRow` 自己負責；選中的底色畫在 ink 之上，所以 `.gbm-row.selected` 勝過 `:hover`。
  - device 測試 `conflict_flow_test.dart` 原本點的是 `find.text('Mark Resolved').first`（列上那顆），現在只剩底列那顆，流程裡也已先選了檔。改了寫法與註解。

## Result

- G3：full suite 3193 綠（~1 skip）；analyze 0；device `conflict_flow_test.dart` 1/1 綠（macOS）。
- 檔案列與 P8 一致，三顆小按鈕都移除。無法解析的檔改在編輯區用整檔按鈕處理。所有新測試都經過 mutation，紅的都落在測該條路徑的測試上。
- **已知限制**：Tree 模式的資料夾預設收合（`FileTreeList` 自己持有展開狀態，外部讀不到）。Ctrl/Cmd+↓ 可能選到收合資料夾裡看不見的檔：編輯區會打開它，但列表上看不到選中的那一列。
- **未處理、已回報**：
  - rail 標題目前是「x of y resolved」加上模式切換鈕，規格的 `.mklbl` 寫的是「Conflicted files」。
  - Continue 標籤的 prose 與 mock 矛盾（上面的 C3）。
