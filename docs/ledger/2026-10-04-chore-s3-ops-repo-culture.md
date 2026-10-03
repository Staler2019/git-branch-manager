# chore/s3-ops-repo-culture — 第三片：ops-repo-culture.md 縮為 5 條，L0 首次低於 30k

## Situation

上一片後 L0 是 40,442 字元。`docs/rules/ops-repo-culture.md`（14,028 字元、14 條）是流程原則，
其中幾條與使用者全域 `~/.claude/CLAUDE.md` 的 Standing rules 幾乎逐字重複，且 `orphan-wiring`、
`single-source-of-truth` 被程式碼大量引用（16、22 處）。

## Task

依 `memory-steward` 處置表縮減，保留被大量引用的 pin 名稱，不遺失事實。

## Action

- 處置：留 L0 4 條（縮短，`remeasure-when-upstream-moves` 併入 `scrutinise-the-comment`）；全域已有的 4 條刪除；
  ENCODE 2；L2 3。
- **使用者裁定 B**：steward 建議把與全域重複的 standing rules 也刪掉，但這個 repo 是 public 且有 cloud session
  （`session-start.sh` 只在 `CLAUDE_CODE_REMOTE=true` 時執行），雲端讀不到 `~/.claude`。所以 standing rules
  縮成兩行留在 L0（讀 spec 修 issue、不自己縮 scope、開 issue 要問、stage by file），其餘三條照刪。
- **steward 的兩處錯誤**：說 `check-instruction-budget.py` 裡也有上限值要改（上限只在 CLAUDE.md）；說
  orphan-wiring 的案例都已在 ledger —— `check-doc-migration-loss.py` 報 orphan-wiring 缺 5、reference-impl 缺 1，
  補寫 `docs/records/2026-10-04-orphan-wiring-instances.md` 後缺 0。`do-not-derive` 缺的兩項
  （`SideBySideSide.left => oldLine`、`oldStart != newStart`）在 `side_by_side_diff_view.dart:217` 與其測試第 196 行，
  由 ENCODE 承載，接受。
- **ENCODE 驗證**：`log-both-sides` 原本只有 grep 層級的證據，做 1 個 mutation（`UpdateLog._put` 直接 return）：
  `update_log_test` + `update_installer_test` +54 −7，還原後乾淨。
- C1 程式／測試註解 5 處改白話或改指併入的 pin（只改註解，analyze 0）；C2 規則檔 4 處、紀錄 1 處改指。

## Result

- L0 **40,442 → 28,705** 字元，**首次低於 30,000 目標**；開場總量約 73.3k（含 `~/.claude` 44.6k）。上限調為 28,705。
- pin 189 → 180，懸空 0；連結 broken 0。
- 未做：L1 檔仍大多超過每檔 6,000（S3 後續片）；註解精簡（§4）尚未開始。
