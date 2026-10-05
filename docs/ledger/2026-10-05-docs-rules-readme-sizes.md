# docs/rules-readme-sizes — 更正 rules README 的過時數字，且不讓 L0 長大

## Situation

L1 整理（#165、#166、#168）把每個 `.claude/rules/` 檔都縮到 6k 字元內。之後 `docs/rules/README.md` 有幾處說法沒跟上：

- 檔案行數仍寫 210、167、153。
- 仍說 `arch-testing.md`「dominated by one table」，實際已經沒有表。
- imported half 仍寫 ~89k、含 `~/.claude` ~133k。

另外量測時還發現兩處：

- 前綴表的 `FLU-` 列漏了 `fn-flutter-layout-test.md`、`fn-flutter-split-pane.md`。
- CLAUDE.md 寫「the twelve path-scoped ones」，實際是 15 個。

## Task

使用者裁定「照建議更新」：就地劃掉錯的說法並改寫成正確的。

限制：README 與 CLAUDE.md 都屬於 L0，`check-instruction-budget.py` 是 ratchet，L0 不能超過 28,705。

## Action

- **量測**（2026-10-05）：
  - `arch-actions.md` 143 行、`arch-testing.md` 63、`ops-spec-reading.md` 62、`ops-repo-culture.md` 29。
  - L0 為 28,705。`measure.py`：啟動時載入的總量 73,330，其中 `~/.claude` 44,625。
- **改寫**：
  - 錯的句子以 `~~` 劃掉，正確的寫在原位。
  - FLU- 補上兩個檔。
  - CLAUDE.md 直接拿掉計數：表本身就是清單，重述它的數量正是這次過時的原因。
- **預算**：第一版 L0 變成 28,885，超出 180。只刪「重述別處」的文字，不刪事實：
  - 「`TEST-` and `FLU-` each span more than one file already」：表上就看得出來。
  - ledger.md 前言的引文「Grep the heading text there」：原文仍在 `docs/ledger.md`。
  - 「Path-scoped rules trigger on Read/Write/Edit only, never on a search」：開頭已經寫了 read or edited，只把「never on a search」併入開頭。

  最後 L0 為 28,705，剛好等於 ceiling。

## Result

- README 的數字與清單都與現況一致；CLAUDE.md 不再含會過時的計數。
- `check-instruction-budget.py` 與 `check-rule-pins.py` 都通過。
- 剩下的漂移風險：README 裡的行數與字元數仍是快照，日後要以這兩支 script 的輸出為準。
