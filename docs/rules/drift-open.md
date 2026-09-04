# Current known drift, and open issues

Pin prefix `DRIFT-`. Format: [README.md](README.md).

`gh issue list` is authoritative for issue state; entries here and in the ledger are
historical the moment they are written.

## [DRIFT-context-menu-catalog] The context-menu catalog has no importer

- **Rule**: `features/context_menus/gbm_context_menus.dart` declares all 11 of spec page
  05's groups and is the parity test's acceptance baseline, but no file under `lib/`
  imports it — each render site hand-writes its list.
- **Consequence**: the catalog itself can drift from the spec, which the per-render-site
  audit method cannot detect (**#71**).
- **Do**: all 11 groups are checked against the catalog with no `skip`. Eight are pure
  `*_menu_items.dart` functions — that extraction is the template to follow; 05-A, 05-C
  and 05-K keep private render-site builders for reasons in their matrix rows.

## [DRIFT-05c-is-remote-only] 05-C applies to a remote-only row only

- **Rule**: a *local* branch whose upstream is gone is **05-B**, not 05-C.
- **Consequence**: the code dispatched on `_gone` and got this backwards for rounds,
  leaving a branch that still exists on disk with no Checkout, Merge or Delete.
- **Note**: 05-C is a **user-ratified deviation** from the catalog now, not a drift —
  `Prune this ref` is deleted and `Delete on remote…` is `Delete remote branch…`, both
  recorded in the catalog file's own doc comment.

## [DRIFT-absent-for-no-capi] Absent for lack of a capi entry point

- **Rule**: per-object transfer counts for fetch/pull/push, `git init` / clone, removing a
  *scanned* repository from the switcher, squashing N commits, per-remote Pull/Push, and
  six `PANELSPEC` detail fields (最後 fetch, 預期 commit, 大小, 剩餘步數,
  自訂測試指令, 欄位選擇器).
- **Note**: **待提交數 is closed** — it has a capi entry point now
  ([GIT-worktree-status-is-per-path]). 建立於 is closed for linked worktrees and absent for the
  current one, a bare repo and an expired reflog, each caveat recorded rather than guessed.
- **Evidence**: all tracked on **#76**;
  [ledger: 十二個管理面板照 P19 樣板統一](../ledger/2026-09-02-feat-p19-panel-template-conformance.md).

## [DRIFT-auto-fetch-unwired] Preferences → General 的 AUTOMATIC FETCH 整段沒有實作在後面

- **Rule**: `autoFetchEnabled` and `autoFetchMinutes` are stored, drawn and **read by
  nothing** — no timer anywhere issues that fetch.
- **Consequence**: P11 item 9's 「預設每 10 分鐘一次…切換 repo 時重置計時」 has no
  implementation to check against.
- **Note**: two of #102's three `autoFetch*` orphans. The third, `autoFetchPrune`, was
  **deleted** rather than wired — see [REF-fetch-auto-prunes]. An earlier record put this
  row in Preferences → **Git**; it is `_GeneralSection`.

## [DRIFT-lfs-match-approximate] `lfs_pattern_match.dart` is an approximation

- **Rule**: it approximates gitattributes matching; it is not a port of `wildmatch()`.
- **Consequence**: a pattern it cannot parse matches nothing, so a group reads 0 rather
  than a wrong number.

## [DRIFT-no-pull-dialog] No pull dialog route exists

- **Rule**: P17's 「選單的 Pull… 或 Alt + 點工具列才開」 has nothing to open.
- **Consequence**: `ActionToolbar`'s Pull only runs `pullChanges()` with the configured
  default (**#109**).
- **Consequence**: this reaches the recovery-choices layer too. `DLGS` has a "Pull
  blocked" entry (three buttons, danger second, the same shape as "Checkout blocked"),
  and `RemoteOps.cpp`'s pull path used to push `StashAndRetry`/`Abort`
  `OperationChoice`s for exactly that dirty-work-tree refusal — but
  `RepoSessionController._handleOperationOutcome`'s switch has arms only for
  `checkout`/`deleteBranch` ([CULT-orphan-wiring]), so nothing ever read a
  `pull`-kind outcome's choices. Deleted rather than left orphaned, in the same
  round that narrowed `OperationChoice` to `kind`+`destructive` — `outcome.summary`/
  `error` still carry the failure message through the ordinary `lastError` path, so
  nothing the user could actually see is lost.

## [DRIFT-updater-windows-untested] The updater script's Windows half is parsed, never executed

- **Rule**: the `sh` half is genuinely *executed* by `update_installer_script_test.dart`;
  PowerShell cannot be, and PR CI compiles no Windows at all (**#69**). **Superseding the
  earlier 「text-asserted only」 wording**: it is now also syntax-checked on a real
  `windows-latest` runner ([CI-powershell-golden-parse]) — which catches a parse error, and
  still nothing about behaviour.
- **Consequence**: the real install-and-restart has no automated coverage on any platform —
  the device-tier test deliberately stops at `readyToInstall`.
- **Note**: two failures have now reached users through this gap from opposite directions —
  「關掉了沒回來」(inherited CWD, BOM) and 「沒關掉、卡在 Installing…」(an unbounded synchronous
  `gbm_session_close`). Both were invisible to every tier here.
- **Do**: read `<systemTemp>/gbm-update.log` (`updateLogPath()`) — every arm of both
  scripts writes its exit code there, and every failure path reached after the app has
  exited relaunches, so the next failure is diagnosable rather than a vanished window.
  **The app now writes its own half of that file too** ([CULT-log-both-sides-of-a-handover]),
  so a handover that fails *before* the script starts is diagnosable as well; the app owns
  truncation and both scripts append.
- **Evidence**: ledger: 更新流程的三個缺陷

## [DRIFT-checkout-dialog-mock-delta] Checkout dialog draws neither `DLGS`'s 目前 row nor its two radios — **closed**

- **Rule (superseded)**: `DLGS`'s Checkout mock has a read-only `ro` row (目前 branch +
  pending-change count) and a `radio-on`/`radio` pair (帶著變更切過去 / 先 stash，切完不自動
  還原). `checkout_dialog.dart` used to have neither — one "stash uncommitted changes
  first" checkbox stood in for the radio pair, and there was no 目前 row at all.
- **Closed**: both are now drawn, quoted verbatim from `DLGS`'s Checkout entry
  (`spec_logic.js`'s `DLGS` array, `grp: 'C', name: 'Checkout'`): the 目前 row reads
  「目前 $head」 on a clean tree and appends 「 · 有$N 項未提交變更」 once dirty (the
  spec's own punctuation, no space after 有); the radio pair reads 「帶著變更切過去」
  (radio-on, `stashFirst: false`, the default) and 「先 stash，切完不自動還原」
  (`stashFirst: true`), gated on the same `isDirty` the removed checkbox was. The pair
  maps onto the `_stashFirst` bool `checkout(stashFirst:)` already took, so no capi or
  controller change was needed — this one was presentation-only, unlike
  [DRIFT-rebase-onto-missing-capi-flags] below.
- **Rule**: the mock's `warn` field (「兩邊都改到的檔案會阻止 checkout；屆時列出檔名並提供
  「stash 後重試」。」) is deliberately **not** drawn. It was never part of what this pin
  recorded as the gap, and it describes a failure this dialog cannot predict ahead of the
  attempt — that is exactly what `checkoutChoices` and the checkout-recovery dialog
  ([STATE-credential-recovery]) already handle once git actually refuses.
- **Do**: this was a UI-structure change, closed directly on the user's explicit ruling
  (「兩個落差也修掉」) rather than a fresh spec-auditor pass, since every drawn value here
  was already spec-auditor-quoted in the G1d citation table.
- **Evidence**: [ledger: G1d](../ledger/2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md);
  closed in the same round's follow-up commit.

## [DRIFT-rebase-onto-missing-capi-flags] Rebase onto is missing two `DLGS` checkboxes and a warn banner, and the checkboxes are capi-shaped — **closed**

- **Rule (superseded)**: `DLGS`'s Rebase onto mock has `chk-on`「保留 merge commit
  （--rebase-merges）」, `chk`「自動 squash 標記過的 fixup commit」, and a `warn` for an
  already-pushed branch needing a force push after rebase. `rebase_onto_dialog.dart` used
  to have none of the three, and the two checkboxes could not be added to the dialog alone
  — `startRebase(target, stashFirst:)` carried no flags for either, and
  `gbm_rebase_start`'s capi signature had no parameters to carry them either.
- **Closed**: the full chain is wired now, bottom-up. Core: `RebaseRequest` gained
  `rebaseMerges`/`autosquash` bool fields and `RebaseOperation::run()` appends
  `--rebase-merges`/`--autosquash` to the `git rebase` argv when set — both measured
  directly (scratch repo, git 2.55.0) to work on a **plain, non-interactive** `git rebase`
  with no `-i` of the app's own; git's own docs confirm `--autosquash` "uses the
  --interactive machinery internally, but it can be run without an explicit --interactive".
  Capi: `gbm_rebase_start` gained two more `int32_t` parameters. Dart:
  `RepoSessionController.startRebase()` gained `rebaseMerges`/`autosquash` named bools,
  forwarded through the FFI binding. UI: `rebase_onto_dialog.dart` draws both checkboxes
  quoted verbatim from `DLGS` — chk-on defaults on, chk defaults off — plus the warn
  banner, gated on [REF-remote-side-not-upstream]'s `remoteCounterpartOf()` (the same
  single source `delete_branch_dialog.dart`'s own doc comment names traps for), not
  re-derived from `hasTrackingInfo` or `upstream` alone.
- **Do**: `gbm_rebase_start`'s fifth parameter (`autosquash`) is exactly the shape
  [TEST-ffi-matches-symbol-only] warns about — `dart:ffi`'s `lookupFunction` matches by
  symbol name only, never by signature, so a dropped or mis-ordered parameter compiles and
  analyzes clean on both sides and only breaks at runtime. `RebaseApiTest.cpp`'s
  `PlainRebaseWithAutosquashFoldsAFixupCommit`/`PlainRebaseWithRebaseMergesPreservesAMergeCommit`
  prove the *C++* side — `gbm_rebase_start` really does thread both flags into
  `RebaseRequest` and into `git rebase`'s argv — and `GitIntegrationTest.cpp`'s
  `RealRepoTest` cases of the same names test the git behaviour itself, one layer down.
  **Corrected**: an earlier version of this line claimed the capi test "is the one tier
  that actually crosses that boundary" — wrong, per [TEST-ffi-matches-symbol-only]'s own
  wording ("only a device-tier test crosses that seam"). `RebaseApiTest.cpp` calls
  `gbm_rebase_start` directly from C++; it never goes through `dart:ffi`'s
  `RebaseStartDart` typedef or `lookupFunction`, so it cannot see a dropped or
  mis-ordered parameter on *that* side.
- **Note**: **the `dart:ffi` seam itself is unverified.** `integration_test/` has no file
  that reaches rebase at all (grepped for `startRebase`/`rebaseStart`/`RebaseStartDart` and
  for `rebase`/`Rebase`, both empty) — [TEST-device-tier-not-in-ci] applies, and this is
  additionally a case with **no existing device test to extend**, not just one that needs
  rerunning. Recorded per [SPEC-absent-not-faked] rather than left implied by the corrected
  sentence above: nothing today would catch `gbm_bindings.dart`'s `RebaseStartDart`
  typedef silently drifting from `gbm_capi.h`'s six-parameter signature. Writing that
  device test is unscoped work, not part of this pin's closure.
- **Evidence**: [ledger: G1d](../ledger/2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md);
  closed in the same round's follow-up commits.

## [DRIFT-restore-before-this-state-missing] "Restore file to before this state" has no dialog and no menu entry

- **Rule**: `DLGS`'s array has *two* Restore-file entries (`spec_logic.js`), and only the
  first is built. Quoted in full since the earlier G1f plan flagged its own spec-auditor
  read as truncated at 250 characters:
  - **"Restore file to this state"** (built, `restore_file_dialog.dart`): `danger: true,
    primary: 'Restore file'`, `ro`「檔案」`v: 'lib/graph/lane_allocator.dart'`, `ro`
    「還原成」`v: 'a1b2c3d · 2026-08-14 11:20 · Fix lane allocator overflow'`, `warn`
    「此檔目前有未提交的 42 行變更，會被覆蓋且無法復原。」, `chk`「還原前先 stash 目前的
    變更」, `note`「與下一張成對：本張取 commit 本身的內容（a1b2c3d 之後）。」
  - **"Restore file to before this state"** (absent): same shell, `ro`「檔案」same value,
    `ro`「還原成」`v: '4b8f01c（a1b2c3d 的前一筆）· 2026-08-14 09:02'`, `hint`「等於抵消
    a1b2c3d 對這一檔做的改動，不碰其他檔案」, a *third* `ro`「將抵消的改動」
    `v: '+18 −7（可展開看 diff）'`, the same `warn` and `chk` as above, `note`「入口在
    commit 明細的檔案右鍵，與上一張相鄰並列，標題是兩張唯一的區別 — 所以「還原成」那一
    行必須寫出實際 hash 與日期，不能只寫「前一版」。merge commit 或首筆 commit 沒有單一
    父節點時此項 disabled。不建 revert commit，只改工作區。」 `DIALOGS`'s shorter note for
    the same name: 「還原成父 commit 的內容，等於抵消該 commit 對這一檔的改動。不建
    revert commit；merge 或首筆 commit 時 disabled。」 The 05-K submenu (`spec_logic.js`'s
    context-menu data) lists both as sibling items.
- **Note**: **not a fresh discovery** — `gbm_context_menus.dart`'s own doc comment on
  `_historyCommitFile` already names the missing submenu item as a pre-existing, deliberate
  gap predating Tier 4, left alone because that catalog is the context-menu parity test's
  acceptance baseline. This pin adds the full `DLGS` field-level citation, which was not
  previously recorded anywhere under `docs/rules/`.
- **Consequence**: even the *built* half is short two things from its own `DLGS` entry —
  the `chk`「還原前先 stash 目前的變更」checkbox (a stash-then-restore sequencing decision,
  not addressed by `restorePaths()` alone) and the `warn`'s exact wording, which names a
  real line count the dialog has no data for (it only computes a bool, `_hasUncommittedChanges`).
- **Do**: closing this needs (a) a new `RestoreFileBeforeDialogContent` plus route plus
  05-K submenu item, (b) a parent-oid lookup with the disabled-on-merge-or-root case the
  note calls for, (c) an expandable-diff affordance for the third `ro` row, and (d) a
  stash-first checkbox wired to whatever sequencing `restorePaths`/`stashChanges` support —
  none of which is a text translation, so none of it belongs in a G1 copy-only pass. This
  joins [DRIFT-checkout-dialog-mock-delta] and [DRIFT-rebase-onto-missing-capi-flags] in
  shape (a mock the app only partially draws) but, unlike those two, was **not** among the
  「兩個落差」the user named for closure this round — it stays open pending a ruling.
- **Evidence**: [ledger: G1f](../ledger/2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md).

## [DRIFT-open-issues] Open issues

- **Open**: **#62** (TabRow overflow menu), **#68**–**#71**, **#76**, **#84**–**#89**
  (Tier 6 spec blockers), **#92**–**#95** (capi with no spec entry point), **#99**,
  **#101**, **#102**, **#109**, **#119** (side-by-side pins neither gutter — awaiting a
  real-hardware check by the user).
- **Closed**: **#74** (fix/branch-prune-and-gone-marking — its text was corrected first,
  the same function had two further defects the issue never mentioned, per
  [CULT-correct-the-record]); **#75** (all four 260820 `REVISIONS` shortcut gaps landed in
  feat/p03-working-copy-redesign); **#67** (macOS `CFBundleName` is the literal
  `git-branch-manager`, candidate fix 1, in fix/macos-about-dialog-parity).
