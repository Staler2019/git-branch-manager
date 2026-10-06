# fix/conflict-rail-title-continue-label — 衝突視窗：檔案列標題與底部動作列照 P8

## Situation

#172 收尾時回報了兩處不符，使用者指示「開issue，兩個都照規格修」，開了 #175：

- **檔案列標題**：程式顯示「x of y resolved」；P8 的窗格標題是 `.mklbl`「Conflicted files」。
- **Continue 標籤**：P8 mockup 寫 `Continue rebase`，內文寫 `Continue`。

## Task

依 G1，先派 spec-auditor 稽核標題與整條底部動作列，再把規格本身沒有單一答案的點交使用者裁定，最後照可逆的 commit 結構逐一 TDD。

## Action

- **spec-auditor**：共 40 個值，11 符合、22 不符、7 無出處，0 個裁定。底部動作列的相鄰不符有：
  - 標籤 `Next conflict`、`Mark resolved`（小寫 r）；
  - Abort 用 danger、Continue 用 primary，五顆都是 sm；
  - 按鈕間距 9px、padding 8/11、頂線；
  - 狀態文字；
  - prose「全綠時 Continue 才可按」，程式卻只依作業種類判斷。

  我自己抽查了決定用的事實：`.mklbl` 的 CSS、底列的 DOM、`GbmButtonSize.sm` 存在、`canContinue` 只看作業種類。
- **使用者裁定（2026-10-06）**：
  1. Continue 照內文維持 `Continue`（`[SPEC-mockup-is-not-prose]`）。
  2. 標題照 `.mklbl` 原樣，不比照 CHANGED FILES 的寫法。
  3. 留下 List/Tree 切換鈕（P03 第 10 項），拿掉「x of y resolved」。
  4. 底列相鄰不符全部本輪修，包含 Continue 的啟用條件。
  5. 狀態文字比照 banner 用英文：`<檔名> — N conflict(s), M resolved`。
- **commits**：

  | commit | 內容 | mutation |
  |---|---|---|
  | `29ecad2` | `_RailTitle`：10px、uppercase、letter-spacing 0.6、textTertiary、padding 6/10、底線；切換鈕在右側，間距 6 | 7 個；紅 1×6，拿掉切換鈕那一個紅 2 |
  | `ab02ed3` | 底列標籤、kind、sm、間距 9、padding 11、頂線、底色 | 9 個；紅 3／2／1×7，多紅的是以標籤找按鈕的既有測試 |
  | `b45226f` | 底列狀態文字（10.5px、textTertiary、flex:1），拿掉無出處的水平捲動 | 5 個；紅 1／1／2／1／1 |
  | `2abd007` | Continue 需 `canContinue && _batch.allResolved` | 2 個，各紅 1 |

- **過程中的修正**：
  - C2 第一次用 Python 錨定 `return Container(` 時，命中的是更前面某個類別裡長得一樣的程式碼。賦值前的 assert 擋下了，檔案沒有被寫壞。改成從 `class _ConflictActionBar` 之後開始找，並 assert 切出的區段裡沒有其他 `class`。
  - 舊的「bottom action bar renders with expected buttons」只用 `findsWidgets` 驗按鈕存在（`[TEST-fixture-cannot-disagree]` 第 8 型），已換成規格測試。
  - 新的 Continue 閘讓三支既有測試轉紅：cherry-pick、rebase，以及 integration 的 Take Ours → Continue 流程。它們原本在檔案仍是衝突時就按 Continue；現在先把檔案標為已解再按。

## Result

- G3：full suite 3197 綠（~1 skip）；analyze 0；device `conflict_flow_test.dart` 在 macOS 1/1 綠。
- **刻意留下、沒有規格出處的程式行為**：
  - Abort／Continue 只在有 sequencer 作業時才出現；
  - revert 不能 Abort；
  - Previous／Next 在只有一段時停用；
  - 兩個 tooltip 文字。這些都源自既有程式的實際限制，tooltip 文字沒有測試釘住。
