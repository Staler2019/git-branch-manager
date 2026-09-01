# Rounds

One line per round, newest last. Older rounds are in
[../ledger.md](../ledger.md) — see [README.md](README.md) for why they stayed.

`merge=union`: two parallel branches appending here merge automatically. If a
union merge ever leaves the list out of order, re-sort by date; nothing reads
this file positionally.

- 2026-08-13 — [feat/flutter-design-restore](2026-08-13-feat-flutter-design-restore.md) — UX3 評分第一輪（由 CLAUDE.md 移入，內文未改）
- 2026-08-31 — [docs/split-rules-for-parallel-rounds](2026-08-31-docs-split-rules-for-parallel-rounds.md) — CLAUDE.md 拆成 rules 檔、ledger 改一輪一檔，讓平行分支不再撞車
- 2026-09-01 — [fix/history-graph-commit-date-order](2026-09-01-fix-history-graph-commit-date-order.md) — 列序改照 commit 時間、lane 0 真的保留給 HEAD 的分支、History 最上方多一列未提交變更
- 2026-09-01 — [claude/windows-app-update-install-irloo0](2026-09-01-claude-windows-app-update-install-irloo0.md) — Install and restart 卡在 Installing…：關 session 的同步 FFI 沒有逾時，交接過程也沒有任何紀錄
