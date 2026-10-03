# chore/s3-arch-state-machine — 第二片：退役 arch-state-machine.md

## Situation

上一片後 L0 是 61,591 字元。`docs/rules/arch-state-machine.md`（21,281 字元、9 條 pin）以兩張大表為主：
`RepoSessionState` 的欄位表與 FFI 事件表。

## Task

依 `memory-steward` 處置表退役此檔；被引用的 pin 要全數改指，且不新增無來源的內容。

## Action

- 處置（使用者裁定「做吧」）：DELETE 4（兩張表、lifecycle、credential-recovery）、ENCODE 4（graph span index、
  unfiltered row indices、deferred prune、refresh entry point）、L1 1（never-guess → `.claude/rules/refresh-gating.md`，
  沿用 pin）。沒有使用者裁定，被刪內容的敘事已在 ledger，所以不新增 record。
- 抽查屬實：事件常數已到 `commitFileCountsReady = 35`（表寫 0–33）；欄位表缺 `lastFileAtRevisionExport`、
  `commitFileCountCache`、`refreshTimings`；操作紀錄上限是 `maxOperationLogEntries`（表寫 500）。
  `workspace_screen.dart` 的 mount 註解自述「實測刪掉這行只紅 workspace_stale_remote_ref_after_delete_test」。
- C1：程式與測試註解 12 處改指 symbol（只改註解），其中 `checkout_recovery_dialog.dart` 原本把 preflight 的說法
  誤引成 refresh-entry-point，改指 `OperationRunner.cpp` 的 `preflight()`。
- `dart format` 報 `worktrees_panel_test.dart` 有 1 處差異：在第 471 行的程式碼、不在本輪改的註解，HEAD 版本即如此，
  是本機 Dart 3.13.3 與 CI 版本不同（[CI-formatter-version-drift]），未動。
- C2：規則檔 7 處、紀錄 2 處改指；刪檔；README 前綴表就地劃掉。

## Result

- L0 **61,591 → 40,442** 字元，上限同步調低；pin 197 → 189，懸空 0；連結 broken 0。
- ENCODE 依賴的 6 個測試檔 +56 全過；`flutter analyze` 0 issue。
- 未做：L0 仍高於 30,000；剩 `ops-repo-culture.md`（14,028）、`arch-actions.md`（8,746）、README、CLAUDE.md、`ops-ux-rubric.md`。
