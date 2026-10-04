---
paths:
  - "app_flutter/lib/features/context_menus/**"
  - "app_flutter/lib/features/dialogs/restore_file/**"
  - "app_flutter/lib/features/dialogs/keyboard_shortcuts/**"
  - "app_flutter/lib/features/dialogs/preferences/**"
  - "app_flutter/lib/features/workspace/widgets/action_toolbar.dart"
  - "app_flutter/lib/data/repositories/app_preferences_repository.dart"
  - "app_flutter/lib/data/repositories/file_list_view_mode_repository.dart"
  - "app_flutter/lib/data/services/update_*.dart"
  - "app_flutter/lib/data/ffi/gbm_bindings.dart"
  - "app_flutter/lib/widgets/file_*.dart"
  - "src/capi/**"
  - "tests/capi/CancelOperationApiTest.cpp"
  - "docs/reports/spec-conformance-matrix.md"
---

# Current known drift

Pin prefix `DRIFT-`. Format: [README.md](../../docs/rules/README.md). Open spec gaps a future session must not "fix back" or mistake for a bug. `gh issue list` is authoritative for issue state; closed drift lives in the ledger.

## [DRIFT-context-menu-catalog] The context-menu catalog has no importer

- **Rule**: `features/context_menus/gbm_context_menus.dart` declares spec page 05's 11 groups as `context_menu_parity_test.dart`'s baseline; nothing under `lib/` imports it, so each render site hand-writes its list (**#71**).
- **Do**: keep extracting pure `*_menu_items.dart` functions checked against it; 05-A, 05-C, 05-K keep private builders (reasons in their matrix rows).

## [DRIFT-auto-fetch-unwired] Preferences → General AUTOMATIC FETCH has nothing behind it

- **Rule**: `autoFetchEnabled` / `autoFetchMinutes` are stored and drawn (`_GeneralSection`) and read by no timer, so P11 item 9's 「預設每 10 分鐘一次」 has no implementation (**#102**; `autoFetchPrune` was deleted, see [REF-fetch-auto-prunes]).

## [DRIFT-no-pull-dialog] No pull dialog route exists

- **Rule**: P17's 「選單的 Pull… 或 Alt + 點工具列才開」 has nothing to open; `ActionToolbar`'s Pull runs `pullChanges()` with the configured default (**#109**).
- **Do**: `DLGS`'s "Pull blocked" entry has no dialog either; why its choices were deleted: [ACT-recovery-choice-wire].

## [DRIFT-updater-windows-untested] The updater script's Windows half is parsed, never executed

- **Rule**: `update_installer_script_test.dart` executes the `sh` half; PowerShell is only syntax-checked on `windows-latest` ([CI-powershell-golden-parse]). The device test stops at `readyToInstall`, so no tier runs the real install-and-restart.
- **Do**: diagnose from `<systemTemp>/gbm-update.log` (`updateLogPath()`); the app truncates it (`update_log_test.dart`), both scripts append.
- **Evidence**: [ledger: Install and restart 卡在 Installing…](../../docs/ledger/2026-09-01-claude-windows-app-update-install-irloo0.md)

## [DRIFT-restore-before-this-state-missing] "Restore file to before this state" has no dialog and no menu entry

- **Rule**: spec `DLGS` has two Restore-file entries; only "…to this state" is built. The second (parent-oid content, disabled on merge/root, a third `ro` row with expandable diff) and its 05-K sibling item are absent. The built half also lacks the `chk` 「還原前先 stash 目前的變更」 and the `warn`'s real line count.
- **Do**: not a copy-only change (new dialog, route, menu item, parent lookup, stash sequencing); it needs a ruling first.
- **Evidence**: [ledger: G1f](../../docs/ledger/2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md)

## [DRIFT-shortcuts-copy-excluded] The Shortcuts surfaces stay English

- **Rule**: `keyboard_shortcuts_dialog.dart` and `preferences_dialog.dart`'s `_ShortcutsSection` draw every row from `gbmMenus`; translating them means translating `gbmMenus`, which cascades into `MenuBarRow`, the native macOS `PlatformMenuBarHost` and every shortcut label.
- **Do**: leave both English until a menu-bar localisation ruling; `dialog_copy_test.dart`'s 'Preferences' group pins the English header.
- **Evidence**: [ledger: G1i](../../docs/ledger/2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md)

## [DRIFT-cancel-capi-unwired] `gbm_cancel_operation` exists with no Dart caller, by decision

- **Rule**: 使用者裁定「開 capi cancellation token 然後先不接線」: capi + C++ registration only (`Session::cancelOperations`, `CancelOperationApiTest.cpp`); no `CancelOperationDart`, no UI. `~Session()`'s own `cancelOperations(0)` is C++-internal and does not close this.
- **Consequence**: a git command still making progress has no user-reachable stop; `GitCommand::kHangCeiling` is only a floor.
- **Do**: closing needs a typedef, a Dart-side in-flight id (`GBM_EVENT_OPERATION_FINISHED` carries none), a UI entry, and cancel not drawn as an error (P10 `LOGRULES`). ~~Only a device test crosses the seam~~ `gbm_capi_signature_parity_test.dart` checks the new typedef's count and types and is red until `gbm_cancel_operation` leaves its `_unboundAllowlist`; order and meaning still need a device test ([TEST-ffi-matches-symbol-only]), and `integration_test/` reaches neither cancel nor `gbm_rebase_start`'s 6 parameters (three same-type `int32_t` flags the parity test cannot tell apart).
- **Evidence**: **#139**; [ledger: 追加四](../../docs/ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [DRIFT-list-tree-mode-scope-undecided] P03 item 10 contradicts itself on whether List/Tree mode is per-list or shared

- **Rule**: its own `note` says 「模式各清單獨立記憶」 and then 「同一個設定套用到…」; the code is shared (`fileListViewModeProvider`, five call sites) and the matrix ratified that; collapse state is per-list (`FileTreeList._expandedFolders`).
- **Do**: nothing is broken; do not switch to per-list or call it a bug. It needs a ruling, since [SPEC-mockup-is-not-prose]'s prose-wins tiebreak cannot settle a prose-vs-prose tie.
- **Evidence**: [ledger: Working Copy 檔案清單改成左側垂直](../../docs/ledger/2026-09-05-feat-working-copy-vertical-file-lists.md)
