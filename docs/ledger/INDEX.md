# Rounds

One line per round, newest last. Older rounds are in
[../ledger.md](../ledger.md) — see [README.md](README.md) for why they stayed.

`merge=union`: two parallel branches appending here merge automatically. If a
union merge ever leaves the list out of order, re-sort by date; nothing reads
this file positionally.

- 2026-08-13 — [feat/flutter-design-restore](2026-08-13-feat-flutter-design-restore.md) — UX3 評分第一輪（由 CLAUDE.md 移入，內文未改）
- 2026-08-31 — [docs/split-rules-for-parallel-rounds](2026-08-31-docs-split-rules-for-parallel-rounds.md) — CLAUDE.md 拆成 rules 檔、ledger 改一輪一檔，讓平行分支不再撞車
- 2026-09-01 — [fix/history-graph-commit-date-order](2026-09-01-fix-history-graph-commit-date-order.md) — 列序改照 commit 時間、lane 0 真的保留給 HEAD 的分支、History 最上方多一列未提交變更
- 2026-09-01 — [claude/working-copy-untracked-files-qq2gnc](2026-09-01-claude-working-copy-untracked-files-qq2gnc.md) — 未追蹤檔案終於看得到 diff、也 stage/discard 得動；太大的 diff 改成明講拒絕而不是默默只畫一半
- 2026-09-01 — [claude/windows-app-update-install-irloo0](2026-09-01-claude-windows-app-update-install-irloo0.md) — Install and restart 卡在 Installing…：關 session 的同步 FFI 沒有逾時，交接過程也沒有任何紀錄
- 2026-09-01 — [claude/windows-uncommitted-changes-5z40sr](2026-09-01-claude-windows-uncommitted-changes-5z40sr.md) — 修 Windows 上未提交列連不到 HEAD：trunkTip 的 TOCTOU race、readHead() 把失敗誤判為空 repo
- 2026-09-01 — [claude/sidebar-stash-styling-date-3dvzmu](2026-09-01-claude-sidebar-stash-styling-date-3dvzmu.md) — 側邊欄 STASH 列改用 GbmRow 補上 hover/選取/⋯ 選單按鈕，並修掉 timestamp 少乘 1000 造成的「20676d ago」
- 2026-09-02 — [feat/p19-panel-template-conformance](2026-09-02-feat-p19-panel-template-conformance.md) — P19 六條樣板規則從沒被逐條稽核過：十二個面板統一成四段式工具列（八個 danger 按鈕移出工具列）、補上 filter／清單標題／狀態列／面板內 banner、分頁各自記住捲動與 splitter，worktrees 補上待提交數與建立於
- 2026-09-03 — [feat/p19-panel-template-conformance（第二輪）](2026-09-03-feat-p19-panel-template-conformance-review.md) — 使用者實際用過之後回報五件事，查證又掉出三個：Remove worktree 完全沒有確認、側邊欄的 New branch 繞過了 spec 的 dialog、一句過期註解替缺陷擋了子彈；Worktrees 成為常駐分頁
- 2026-09-04 — [fix/prune-stale-comment-and-recovery-choice-copy](2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md) — 刪掉 Prune remote branches 描述成現在式的過期例外註解；OperationChoice 的 wire 精簡到只剩 kind+destructive，文案改 Dart 端依 kind 組，順手補上 Retry／Remove index.lock 兩個死按鈕（含新增 capi）
