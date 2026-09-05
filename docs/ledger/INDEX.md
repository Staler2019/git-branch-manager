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
- 2026-09-04 — [fix/prune-stale-comment-and-recovery-choice-copy](2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md) — 刪掉 Prune remote branches 描述成現在式的過期例外註解；OperationChoice 的 wire 精簡到只剩 kind+destructive，文案改 Dart 端依 kind 組，順手補上 Retry／Remove index.lock 兩個死按鈕（含新增 capi）；G1 剩餘 17 個對話框全部改中文，Checkout／Rebase onto 兩個 mock 落差關閉（後者補上 rebaseMerges/autosquash capi 旗標）
- 2026-09-05 — [feat/worktree-dialogs-shell-redesign](2026-09-05-feat-worktree-dialogs-shell-redesign.md) — worktree-dialogs-spec.html 的 G2–G8：對話框欄位標籤統一 P6 樣式、`.gbm-input` 30px/r6、GbmDialogShell 拿掉 ✕ 改靠 Escape（先補測試釘住）、標題列/動作列照 P6 全尺寸 mock（GbmButtonSizeScope 讓 34 個呼叫點的按鈕一次變小）、新增 GbmDialogReadOnlyField/GbmDialogWarnField 並修掉它在真對話框 Column 底下炸高度的缺陷
- 2026-09-05 — [fix/partial-branch-delete-no-refresh](2026-09-05-fix-partial-branch-delete-no-refresh.md) — 多選刪除分支後側邊欄不刷新：`git branch -d` 部分成功仍 exit 1，而 refs 刷新掛在 `succeeded` 之後；核心早就用 before/after 探測算出真的刪掉了哪些，只是那個知識只走進訊息字串。新增 `OperationOutcome::mutatedRefs`（刻意不序列化）
- 2026-09-05 — [fix/benign-exit-not-logged-as-error](2026-09-05-fix-benign-exit-not-logged-as-error.md) — 每次 refresh 都在 log 寫兩列紅字：`config --get` 讀不到 key 的 exit 1 是答案不是拒絕，但紀錄層沒有任何欄位能說出這件事。新增 `GitCommand::benignExitCodes`（一組 code，因為 `--unset` 是 5 不是 1）與 `OperationRecord::benignExit`；順帶修掉 sink 提早收工也被記成 ERROR；追加一段：那個 sink 測試是 repo 裡第一個讓 `LineSink` 回傳 false 的，於是踩出 Windows `terminate()` 只殺一個行程不殺整棵樹、`stderrThread.join()` 永久卡住的老缺陷（CI 一顆 job 卡 81 分鐘），連帶補上 ctest 與 job 兩層逾時；追加二：使用者裁定順手把 stdout 那半邊也做掉——`GitCommand::timeout` 原來兩個平台都沒有任何測試，Windows 卡在同步 `ReadFile` 時 deadline 根本驗不到，改用一條 deadline watchdog 從外面 `CancelSynchronousIo`；追加三：上面宣稱的「job object 慢 33%」是錯的，第三次跑同一個 job object 回到 1.02×，錯在對照組是 175 個不 spawn、平均 34ms 的測試，對機器快慢不敏感，就地劃掉並改寫；追加四：使用者裁定「動作的逾時要可預期，而量測要當成修改的依據」——查證後發現那 28 個 `timeout = 0` 的動作註解裡依賴的 cancel **從來沒有人可以呼叫**（`Handle` 在 ~40 個呼叫點全被丟掉）。新增 `GitCommand::idleTimeout`（閒置而非總時長）與 `gbm_cancel_operation`（依裁定 Dart/UI 先不接，另開 issue）；常數由普查決定而不是猜——**git 只在 stderr 是 tty 時才畫進度條**，所以那 28 個指令對 pipe 一個位元組都不吐，閒置逾時對它們退化成總時長上限；並把追加三欠的量測工具建起來（A/A null 手臂定解析度、注入已知延遲當儀器自我檢查、比值 gate 先關著因為數字還沒收集到）
