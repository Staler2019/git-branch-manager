# Engineering ledger

Round-by-round record of what changed in this repo, why, which premises did
not survive contact with the source, and which facts were found by *running*
rather than by reading. Moved here verbatim from `CLAUDE.md`, which had grown
to ~176KB and is auto-loaded into every session; this file is not.

Read [CLAUDE.md](../CLAUDE.md) first — it holds the current structure, the
session state machine, the testing tiers, and the distilled invariants and
traps. This file is the evidence behind them: when a distilled rule needs its
original measurement, its counter-example, or the issue number it came from,
it is in the section below that names the same branch.

Sections are in the order they were written and cross-reference each other
with "above"/"below". That ordering is preserved, so those resolve — with one
exception: a handful of "above"s name a section that *stayed* in CLAUDE.md
("Action availability state machine", "Testing tiers", the route tree, the
Intent / Action layer). Grep the heading text there. Nothing in the body below
was edited to fix them, deliberately: the block is byte-identical to what it
was in CLAUDE.md, and a record you can checksum is worth more than a corrected
cross-reference.

Source comments across `app_flutter/` cite these sections by name ("CLAUDE.md's
Tier 0c note", "Known gaps", "Tier 6c"); those names live here now, and the
pointer at the end of CLAUDE.md says so.

## Adding a round

Append a new `###` section at the end, named for its branch, in the shape the
sections below use. Length is free here — nothing auto-loads this file. Then
distil only what a future session must know *before* it starts into
CLAUDE.md's "Invariants and traps", anchored back to your section's name. Do
not append a round-shaped section to CLAUDE.md; that is what this file exists
to prevent.

## Rounds (chronological)

### Spec conformance pass

A later pass re-read the source spec (`Flutter Desktop Spec.dc.html`, the
same claude.ai design project `f6b7d1fd-…` that `docs/design/tokens-reference.md`
is drawn from) page by page and closed the gaps it found. What that changed,
so the next reader doesn't re-derive it:

- **~30 of 52 menu actions were wired to `null`** — the menus rendered, but
  clicking did nothing. All now resolve to a handler except the four routed
  through `MenuBarRow` params and those legitimately state-dependent
  (disabled with no unstaged files, on a detached HEAD, or mid-conflict per
  spec page 07).
- **History had no commit search** (spec page 02 item 3). Added
  `features/history_graph/commit_search.dart` + a filter field. The lane
  column is hidden while filtering, because `graph.edges` connect adjacent
  rows of the *unfiltered* snapshot. Known limitation documented there:
  message/author matching only sees commits whose `CommitMeta` has loaded;
  hash-prefix matching covers the whole snapshot.
- **Nine spec page 06 dialogs did not exist** — new-branch, checkout,
  delete-branch, rebase-onto, force-push, delete-remote-branch, restore-file,
  discard-changes, repository-settings.
- **Discard had no confirmation at all**: `WorkingCopyView._discardFile`
  called `restorePaths` straight from the context menu. It now goes through
  the discard-changes dialog.
- **`PlatformMenuBarHost` was a passthrough stub**; it now builds a real
  macOS `PlatformMenuBar`, and `MenuBarRow` is suppressed there so the menus
  don't render twice (spec page 01).
- The Keyboard shortcuts dialog was seven hardcoded strings matching neither
  the menu labels nor the real bindings; it now derives from `gbmMenus` +
  `gbmActionShortcuts`.

Toolchain note: this repo needs Flutter with Dart ≥ 3.12.2 (`pubspec.yaml`'s
`sdk: ^3.12.2`) — Flutter 3.44.x ships it. After that pass `flutter analyze`
is clean (exit 0) and `flutter test` is 631 passed / 21 skipped.

**`flutter analyze` must stay at zero issues.** CI's Flutter UI job runs it
with no tolerance flags, and the command exits non-zero on *info*-level
lints too — so an "only an info" diagnostic still fails the build. That job
also sits behind `needs: capi-build`, so it does not run at all while any
capi job is red; a green capi run can therefore surface Flutter problems
that were previously invisible rather than absent.

### Known gaps (flagged, not fixed this round)

- **B (−1 pt)**: route/entry-point reachability was audited exhaustively;
  whether each dialog's *internal* functionality is complete once opened was
  not re-verified per dialog.
- ~~**Route audit has drifted since Round 1**: a later `deleteRemoteBranchDialog`
  route (`route_paths.dart`) was registered in `app_router.dart` but never
  given a call site under `lib/features/`~~ — **Fixed**: `sidebar_panel.dart`
  now renders one merged branch tree instead of local branches only, per the
  source design (`Flutter Desktop Spec (standalone).html`, page 02 items
  4/12): `branch_tree_builder.dart` gained `mergeLocalAndRemoteBranches()`
  (local ∪ the subset of remote branches with no local branch tracking them,
  matched by a local branch's `RefInfo.upstream` — confirmed to be the
  tracked ref's *full* name, not `%(upstream:short)` — against a remote
  branch's `fullName`; a matched remote branch is dropped, an unmatched one
  keeps its ref but has its `shortName` stripped of the `<remote>/` prefix so
  it groups into the same folder a same-named local branch would) and
  `remoteBranchParts()` (the inverse split, recovering remote name + branch
  name from a remote ref's `fullName` for the actions below).
  `BranchTreeItem` renders a remote-only row per `BRANCH_STATES`: cloud icon
  (cloud-off for gone, new `assets/icons/cloud-off.svg`) at 0.62 opacity,
  single tap inert, double tap checks out as a new local branch, and its
  right-click menu swaps to the 05-C subset (Checkout as new local…/Copy
  branch name/Prune this ref/Delete on remote…, ~~"Fetch this branch" omitted
  — `gbm_remote_fetch()` has no per-ref fetch capability~~ — **stale**:
  `gbm_capi.h`'s `gbm_remote_fetch()` takes `refs`/`refCount` and restricts
  the fetch to exactly those refs, `BranchTreeItem`'s `onFetchRef` is wired
  to it, and 05-C's parity assertion passes with the item present).
  `sidebar_panel.dart`
  wires the three real actions: `checkout(target: fullName, createBranch:
  true, newBranchName: shortName)`, `pruneRemote(remoteName, [fullName])`,
  and `context.push(RoutePaths.deleteRemoteBranchDialogFor(...))` — the
  previously-orphaned route now has its call site. Covered by
  `branch_tree_builder_test.dart`, `branch_tree_item_test.dart`,
  `branch_context_menu_test.dart` (widget tier) and
  `sidebar_panel_remote_branch_test.dart` (drives the real
  `repoSessionProvider`/`GoRouter` seam via `FakeRepoSessionController`, not
  just `BranchTreeItem` in isolation — including a round-trip test that
  `emit()`s a conflicted state, asserts double-tap checkout no-ops, then
  `emit()`s clean and asserts it fires, per the "Rule" at the end of
  "Action availability state machine" above). Discovered along the way: a
  remote-only row's `InkWell.onDoubleTap` and its inner "more" `IconButton`'s
  tap recognizer sit in the same gesture arena, so a single click on that
  button has a real ~300ms hesitation before the menu opens
  (`kDoubleTapTimeout`) — a latency quirk, not fixed here (see
  `sidebar_panel_remote_branch_test.dart`'s `_openRemoteRowMenu` doc
  comment). ~~Still not addressed: a "gone" row (a local branch whose
  upstream vanished) still goes through the full 05-B local-branch menu
  instead of spec's narrower gone-row subset~~ — **Fixed**: `BranchTreeItem`
  gained `_buildGoneMenuItems()`, routed to whenever `ref.isGone` (checked
  after the `_isRemoteOnly` branch in `_buildMenuItems()`), per 05-C's own
  target note: "gone 的列只留 Prune 與 Copy，其餘停用" (a gone row keeps only
  Prune and Copy enabled; the rest disabled). "Checkout as new local…" and
  "Delete on remote…" render but permanently disabled (`enabled: false`,
  `onTap: null`) rather than omitted — matching the spec's "停用" wording,
  and confirmed via `_GbmMenuRow` that `enabled: false` overrides `danger`
  styling too (dimmed, not red). `SidebarPanel` gained `_pruneGoneUpstream()`
  and wires it to `onPruneRef` for a gone row (guarded on
  `ref.upstream.isNotEmpty`, defensive since `isGone` is only ever computed
  for a branch with a configured upstream) — it prunes `ref.upstream` (the
  vanished remote-tracking ref, e.g. `refs/remotes/origin/feature`), not
  `ref.fullName` (the still-live local branch), per BRANCH_STATES's note:
  "真正移除 remote-tracking ref 要執行 Prune". Covered by five new tests in
  `branch_context_menu_test.dart`'s "gone row (05-C subset)" group (item set,
  both disabled items no-op on tap, Prune dispatches, dimmed-not-red
  styling) and two in `sidebar_panel_remote_branch_test.dart`'s "gone-row
  menu wiring" group (`Prune this ref` reaches the real session with the
  upstream ref; the two disabled items reach neither `commandLog` nor the
  delete-remote-branch route — the latter assertion exists because that
  action dispatches by navigation, not by session command, so a
  `commandLog`-only check can't see a regression that re-wires it). And
  `gbm_context_menus.dart`'s other 8 unwired targets remain a separate,
  larger gap this doesn't touch.
- Some spec behaviour has no backing capi entry point and is therefore
  absent rather than faked: per-object transfer counts for fetch/pull/push
  (spec page 10's "12,480 / 31,206" progress figures, reported as
  indeterminate instead), `git init` / clone (File → New repository… and
  Clone repository… are disabled, as is the switcher popover's Clone
  footer — no entry point exists in `gbm_capi.h` or `src/core`), removing a
  *scanned* repository from the switcher list (05-A's "Remove from list" is
  live for manually-opened rows, which `RecentsRepository` owns, and
  disabled for scanned ones, which would only come back on the next scan).
  ~~and open-file-at-revision / save-this-revision in 05-K~~ — **Fixed**
  (Tier 4, see below): `gbm_export_file_at_revision` is the blob-read entry
  point that was missing. Settings whose effect this layer cannot yet honour
  are likewise not offered in Preferences — see `AppPreferences`' doc
  comment.
- ~~**`TabRow`'s Merge…/Cherry-pick…/Reset… buttons bypass the action
  availability state machine**~~ — **Fixed**: `TabRow` gained a
  `conflictActive` param (stays presentational/Riverpod-free, same as
  `BranchTreeItem`/`CommitGraphView`'s param of the same name);
  `WorkspaceScreen` computes it via
  `!isActionEnabled(GbmActionId.branchMergeIntoCurrent, session)` and wires
  it in. Cherry-pick and Reset still have no `GbmActionId` of their own, so
  they share Merge's gate rather than going ungated — all three would start
  a second sequencer operation mid-conflict, the same class spec page 07
  disables. Covered by `tab_row_test.dart` (widget tier) and the new
  `test/integration/workspace_tab_row_conflict_gate_test.dart` (integration
  tier, mirrors `workspace_conflict_transition_test.dart`'s pattern —
  clean/conflict/round-trip). `MergeDialogContent` itself still does not
  independently read `session.conflictActive` (only disables "Merge" when
  no target branch is selected) — not a live gap now that the dispatch
  path leading to it is gated, but worth knowing if a future direct-link
  entry point to that dialog is added.
- ~~**`dart format --set-exit-if-changed .` is not CI-enforced**~~ —
  **Fixed**: the pre-existing 27-file drift was formatted in one
  standalone commit, then a dedicated `dart-format` job ("Dart format")
  was added alongside the C++ side's standalone "Format and layering"
  (`lint`) job rather than living as a step inside `flutter-ci`
  ("Flutter UI") — a format failure now surfaces on its own check instead
  of aborting `flutter-ci` before `flutter analyze`/`flutter test`/
  `flutter build linux` get a chance to run, and it doesn't wait on
  `capi-build` since formatting needs no native library. Both jobs were
  later split out of `ci.yml` into their own `cq.yml` workflow (same
  `pull_request` trigger), since neither builds or tests anything — they
  are pure static checks. Caught along the way: `dart format`'s output is
  not stable across Dart SDK versions —
  `subosito/flutter-action@v2`'s `channel: stable` floats, so a local Dart
  3.12.2 and a CI run on a newer stable (Dart 3.13.0 shipped a formatter
  style change) can each accept the *other's* output as "needs
  reformatting", flapping a file between two valid-but-different
  formattings depending on who last touched it. No SDK version is pinned
  here yet — worth revisiting if this recurs.
- **D (−2 pt)**: History and Working Copy are still a tab switch, not a
  combined view. This matches an industry-standard pattern (Fork, GitKraken,
  Sourcetree all do the same) and isn't treated as a defect — but it's one
  more step than zero.
- **A (−1 pt)**: T2 evidence only — no moderated user testing behind any of
  these step counts.
- A `code-review` pass was run against the full branch diff (not just this
  round's changes) as part of the loop protocol. Two of its six findings
  were spot-checked and both were false positives against intentional,
  already-documented decisions already on this branch: `app.dart`'s
  single-`ThemeVariant` switcher deliberately replaces the old
  system-following `ThemeMode` (see `theme_mode_provider.dart`'s doc
  comment), and `commitMetaCache`'s `copyWith` already defaults to
  `this.commitMetaCache`, so omitting the parameter preserves rather than
  resets the cache. Of the remaining three: ~~unbounded `commitMetaCache`
  growth~~ is **fixed** — `RepoSessionState.withCommitMeta()` now caps it
  at `_kMaxCommitMetaCacheEntries` (5000), evicting oldest-inserted entries
  once over, mirroring `operationLog`'s `_kMaxOperationLogEntries` pattern;
  see `test/data/repositories/repo_session_commit_meta_cache_test.dart`.
  ~~Skeleton-width layout jank in `commit_row.dart` and a missing widget test
  for sidebar-toggle state were **not** independently verified — still
  unconfirmed leads for whoever picks them up next, not accepted facts.~~ —
  **Resolved** (2026-08 spec-conformance audit, see below): the skeleton-width
  lead was checked directly against `commit_row.dart` and found to be no
  defect (downgraded, not fixed — there was nothing to fix); the
  sidebar-toggle lead was found to already have three passing widget tests
  covering it. Both were stale entries in this list, not open work.

### Spec conformance audit (2026-08)

A full re-audit against `docs/claude-design-demo/Flutter Desktop Spec
(standalone).html` — every page, not a diff — done on branch
`docs/spec-conformance-audit`. Unlike the "Spec conformance pass" above
(which closed gaps directly), this round's user-approved scope was
**audit-only**: no `lib/` production code changed. Full detail lives in two
generated reports (regenerate the spec extraction via
`tools/extract_design_spec.py` if the source `.html` ever changes):

- `docs/reports/spec-conformance-matrix.md` — page-by-page conformance
  table, ~78 items checked against the 12 spec pages plus shortcuts/dialogs.
- `docs/reports/code-review-2026-08.md` — architectural review (not diff
  review) of `app_flutter/lib/`, 0 CRITICAL / 2 HIGH / 3 MEDIUM / 3 LOW.

**Root cause of most drift (H1)**: `lib/features/context_menus/gbm_context_menus.dart`
fully declares all 11 spec page-05 context-menu groups, labels matching the
spec verbatim — but no file under `lib/` imports it, only `test/` does. Each
render site hand-writes its own item list instead, so 5 of 11 have drifted:
05-B (missing Rebase-onto-here/Compare-with…), 05-E (missing Merge-into-
current/Compare-with…/the whole "More actions" submenu), 05-F (missing
Stage/Open-file/Show-in-file-manager/Open-terminal-here), 05-G (missing
Discard-N-lines…), 05-K (missing Compare-with-working-copy/Open-terminal-
here plus 3 submenu items). 05-A/C/D/H/I/J conform (05-D/H/I/J via a
dedicated `*_menu_items.dart` pure function each — the template to follow
when this eventually gets fixed). Not fixed this round; tracked as skipped
regression tests (below) so a future fix flips them green one at a time.

**H1 update (Tier 1, see below)**: 05-F and 05-G now follow that template
too (`working_copy_file_menu_items.dart`, `diff_line_menu_items.dart`), so
six of eleven groups are catalog-checked with no `skip`, and 05-K's two
wireable items landed. Note the audit's own 05-F and 05-G rows were
materially wrong — see the Tier 1 section for what they got wrong and why
it moved the fix.

**H1 update (Tier 4)**: 05-K is now catalog-checked with no `skip` too
(seven of eleven), so **05-B and 05-E are the only drifted groups left**.
05-K's render site is still a private `_buildMenuItems` inside
`changed_files_panel.dart` rather than a `*_menu_items.dart` pure function
— it stayed there because its items need the container's commit oid and its
two-step export state, which the pure-function template has nowhere to put.

~~**New defect found while writing test coverage, not from static reading
(H2)**: `working_copy_view.dart`'s Commit/Amend buttons do not reactively
enable while typing a commit summary — `_summaryController` has no listener
wired to `setState`, so `canCommit` only recomputes on some *unrelated*
rebuild (e.g. staging a file), not on the summary text itself changing. The
gate logic (`canCommit`) is correct in isolation — confirmed by pre-seeding
`workingCopyDraftProvider` before mount — the defect is specifically the
missing "text changed → rebuild" wiring. Both new test suites below had to
route around this (stage-after-type ordering, or a full tab-away-and-back)
rather than a plain `enterText` + assert. Not fixed this round.~~ — **Fixed**
(Tier 0, see below): `_summaryController` now carries a listener
(`..addListener(_onSummaryChanged)`, mirroring `_diffScrollController`'s
existing pattern) that calls `setState(() {})` on every keystroke, so
`canCommit` recomputes immediately instead of waiting for an unrelated
rebuild. `test/integration/workspace_states_table_test.dart` gained a test
that drives this with a real `tester.enterText()` instead of the
provider-override workaround the pre-existing test in that file still uses
(that one verifies gate *logic*; the new one verifies the typing → rebuild
wiring, which is what H2 was actually missing).

~~**Other confirmed gaps**: `branchRenameCurrentBranch` has no keyboard
shortcut bound despite F2 being unclaimed…~~ — **Fixed** (Tier 0c, see
below). The two *other* absent bindings named there (Find-in-files,
Stash-changes) were excused as spec-internal collisions — spec's own MENUS
table double-assigned their keys. **That excuse expired on 260820**: P16's
`REVISIONS` table reassigns Find-in-files to `Ctrl/Cmd+Shift+H` and Stash
changes to `Ctrl/Cmd+Shift+S`, so both are now ordinary unbound shortcuts
with no defence. Neither is fixed here (Tier 0c scoped itself to rename);
the matrix rows are corrected and each needs its own issue. Note the Stash
one is not a free slot: `Ctrl/Cmd+Shift+S` currently belongs to
`repositoryStageAll`, so honouring the revision means re-deciding that
binding too. Two more REVISIONS casualties in the same table, both found
after the first pass at these docs and both **not** fixed here:
`repositoryStageSelectedLines` is now spec'd at `Ctrl/Cmd+Alt+S` but bound
to `Ctrl/Cmd+Shift+Enter`, and `Edit → Select all` (`Ctrl/Cmd+A`) does not
exist in `gbmMenus` at all — the latter is deliberately **sequenced after**
the multi-select work (#54), since `Ctrl/Cmd+A` is also `MULTIKEYS`' "全選
當前清單" and binding it first would give it nothing to select.

~~`lib/features/workspace/widgets/tab_row.dart`'s 18-item `_MoreMenu`
overflow menu plus 3 standalone buttons is the sole non-conforming entry
surface in the app~~ — **Largely fixed** (Tier 6b, #62): spec page 14 turned
out to already answer the design question this was waiting on. The menu is
down to **2** items and the buttons to **1**; see "Tier 6b" below for what
moved where and why three of those remain. ~~Two competing Log implementations also still coexist~~ — **Fixed**
(Tier 6a, #61): P16's REVISIONS deleted the dialog from the spec by name
("只留抽屜；operation-log dialog 從規格中刪除") and P10's LOGRULES gained a
「只有一套」 row, so `operationLogDialog`, its route constant, its
`_MoreMenu` entry and `features/operation_log/` are all gone;
`features/log_drawer/` keeps the feature. See "Tier 6a" below.

New tests added this round: `test/features/context_menus/context_menu_parity_test.dart`
asserts all 11 groups against `gbmContextMenuGroups` — the 6 conforming
groups directly, the 5 drifted ones (`05-B/E/F/G/K`) with `skip: true`
pointing back to the matrix's corresponding row, so clearing a skip is the
signal a future fix landed.
`test/integration/workspace_states_table_test.dart` locks in the 3
previously-under-tested STATES-table rows (Working copy/Commit/Status bar)
and is what surfaced H2. `test/actions/gbm_shortcuts_test.dart` gained one
`skip: true` test for the F2 gap. `integration_test/` (new — see its own
README.md) adds real-`gbm_capi`/real-temp-repo device-tier coverage for
three flows (repo lifecycle, commit, merge-conflict resolution), run
individually per platform (`-d macos`/`-d linux`/`-d windows`) rather than
as a directory — running the whole directory in one `flutter test` command
was found to be unreliable on macOS specifically (each app launch after the
first fails to attach a debug connection), not a defect in the tests
themselves.

### Tier 0 fixes (fix/tier-0-spec-conformance-gaps)

The audit above turned into 8 GitHub issues (#43–#50), grouped into tiers by
dependency risk; Tier 0 was the "independent, no shared file" batch. Per
user decision, all 8 landed as 7 sequential commits on one branch (not
parallel worktrees, not squashed) rather than the 8th (#45) — see below.
Commit order: `0b → 0a → 0h → 0f → 0d → 0e → 0g`.

- **0a / #43** (`613f80c`) — H2 above, fixed.
- **0b / #44** (`2a60b47`) — `gbm_context_menus.dart`'s 05-C doc comment
  said "Not yet wired"; `branch_tree_item.dart`'s `_buildGoneMenuItems()`
  already implemented it (confirmed by this same audit, see 05-C in the H1
  paragraph above). Comment-only fix, no behavior change.
- **0d / #46** (`2307ef7`) — History's ref chips now merge a synced
  local+upstream pair into one chip with a cloud-icon suffix instead of
  drawing both separately, and draw a dashed chip at the commit the
  upstream actually points to when the two have diverged (spec page 02).
- **0e / #47** (`a928bd5`) — the List/Tree file-view preference
  (`fileListViewModeProvider`) is spec page 03 item 10's *one* shared
  setting, but History's Changed files panel, Compare's two file lists, and
  the conflict-resolution rail each drew their own hardcoded flat list with
  no toggle. All three now read the shared provider and render through the
  same `FileListModeSwitcher`/`FileTreeFolderRow` Working Copy already
  used — proved cross-page, not just per-view, via a new
  `test/integration/workspace_file_list_view_mode_test.dart`.
- **0f / #48** (`16626b2`) — the status bar's folded "+N task" label is now
  a tappable `showMenu` popover listing every background task with its own
  Cancel button (spec page 10), not inert text.
- **0g / #49** (`3e65208`) — see its own commit message for the five
  sub-items and the capi extension (`gbm_discovery_set_base_folder_depth`,
  `RepoIndexDb`'s schema-3 `lastScanSkipped` column) two of them needed.
- **0h / #50** (`503e326`) — `operationLog`'s cap was a hardcoded module
  constant whose doc comment incorrectly claimed it mirrored
  `OperationRunner::kMaxUndoEntries` (a different, unrelated 200-entry list
  for Undo Last); it now reads `AppPreferences.logMemoryLimit`, the field
  spec's LOGRULES table actually describes ("上限寫在 Preferences，不隱
  藏").
- **0c / #45 — deliberately not in this batch**, and shipped later on its
  own branch once the blocker cleared. See "Tier 0c" below.

Two premises in the original issues were corrected during planning, not
just during implementation — worth knowing before re-reading #49/#50's
issue text literally: #50 assumed the C++ `kMaxUndoEntries` constant needed
changing in lockstep with the Flutter cap; it doesn't; they were never
actually linked. #49 assumed all five Preferences sub-items were pure
Flutter-side wiring; two needed a real capi addition, which the user
explicitly approved doing as part of this round rather than splitting into
a separate capi-only issue.

### Tier 1 fixes (fix/tier-1-spec-conformance-gaps)

Issues #51–#53, the page-05 context-menu batch. Nine sequential commits on
one branch (six for the issues themselves, then the follow-up defect, its
docs, and the device-tier e2e), same as Tier 0. **All three issues' premises turned out to be
wrong in ways that moved the work**, so read this before re-reading their
issue text:

- **#51's named render site was dead code.** `changed_file_row.dart`'s
  `ChangedFileRow` was constructed by **nothing under `lib/`** — only by
  `test/`. `WorkingCopyBoard` (`39d6303`) had replaced it and `5581538` had
  moved the real 05-F menu into `working_copy_view.dart:576`, leaving the
  widget orphaned. Consequences: the live menu already had `Open terminal
  here` (so the gap was 2 items, not 3), and the parity test was pumping the
  dead widget, so "just remove the skip" per the issue would have gone green
  against code nobody runs. The orphan and its test file were deleted in
  their own commit; `working_copy_file_menu_items.dart` is the extraction the
  parity test now checks. **Deliberate reduction while doing it**:
  `Blame…`/`File History…`/`Line History…` left this menu, because 6 spec
  items + 3 beyond-spec extras is 9 and `showGbmContextMenu` asserts spec
  page 05's own 8-item cap. `GbmMenuItem.submenu`'s flyout was not
  implemented at the time (it is now — Tier 4), so nesting them was not an
  option then. They stay reachable from `tab_row.dart`'s overflow menu,
  minus the pre-filled path — a real, accepted convenience loss, and one
  that a follow-up could now revisit since the flyout exists.
- **#52 needed a new capi, and 05-G's drift was 4 items not 1.** Spec's own
  05-G block lists `Stage 12 lines` / `Stage hunk` / `Unstage hunk` /
  `Copy lines` / `Discard 12 lines…`; the code had `Stage line`, `Copy line`,
  and ternaried between the two hunk directions. All four now match: both
  hunk items always render, with the inapplicable one carrying `enabled:
  false` **and** `onTap: null` (`enabled` alone is a visual signal — see
  `gbm_menu.dart:28`). `gbm_discard_lines` is new: `gbm_stage_lines`/
  `gbm_unstage_lines` are `git apply --cached` and only move the index, so
  discarding work-tree lines needed `git apply --reverse` without
  `--cached`. `StageOps.cpp`'s `applyPatchToIndex` was split into a
  `cached`-parameterized `applyPatch` (the four existing callers pass true,
  behavior unchanged). The patch is built with `unstaging: true` — that flag
  means "will be reverse-applied, so check the new side", which is exactly
  what a work-tree reverse apply does, and it also keeps a rename's header
  pointed at the new path so the reversal discards content without undoing
  the rename. Offered only on the unstaged side, always through the
  discard-changes dialog's new line mode.
- **#53 landed as scoped**, its 2 top-level items wired; the parity skip
  stays per the issue, with regression coverage in a targeted
  `test/integration/history_commit_file_menu_test.dart` instead — both new
  items dispatch by navigation or by an injected service, so neither shows
  up in `FakeRepoSessionController.commandLog` and a `commandLog`-only test
  could not see them regress.

**A seventh commit closes a defect the first six introduced**, found while
writing coverage for the seam between them rather than by reading the diff:
`discardLinesDialogFor`'s URL → `app_router.dart`'s inline `hunk`/`line`
parsing → the dialog's line mode had no test at any tier (the menu end and
the `gbm_discard_lines` end each did). That inline parsing cross-nulled its
two outputs — `hunkIndex: lineIndices.isEmpty ? null : hunkIndex` and the
mirror image — so a URL carrying line indices with a missing or unparsable
`hunk` silently produced *whole-file* mode: the same danger button, asked
to discard two lines, would have discarded the entire file. Parsing now
lives in `features/dialogs/discard_changes/discard_changes_request.dart`
(`DiscardChangesRequest.fromQuery`, plus `wholeFiles`/`lines`/`malformed`
constructors), and anything that asked for line mode but cannot be honoured
is `isMalformed` — the dialog then renders a `Close` button and no
destructive one at all, rather than falling back. Covered by
`discard_changes_request_test.dart` (8 malformed URL shapes) and
`discard_changes_dialog_test.dart` (which of `discardLines` vs
`restorePaths` actually fires — the assertion that matters, given the
blast-radius difference). `FakeRepoSessionController` gained a
`discardLines` override for it. The line-mode copy also changed from "will
be removed from the working copy" to "will be reverted": a discarded `-`
line is one the working copy deleted, so discarding it restores the line.

**All three flows then got real device-tier coverage** rather than the
hand-check the plan had budgeted for:
`integration_test/context_menu_flows_test.dart` drives them against the real
`gbm_capi` and a real temp repo — 05-G asserts the bytes on disk (only the
selected line reverted, the neighbouring insertion untouched, `git status`
still ` M`), 05-F asserts the absolute path handed to the OS, 05-K asserts
the router really lands on `ComparePage` with `CommitGraphView` gone. Two
things about the harness came out of writing it, both now in
`integration_test/README.md`: `build/native/libgbm_capi.dylib` is a *copy*,
so a stale one loads happily and a new capi entry point appears to be a Dart
bug; and these tests share the machine's real `shared_preferences`, where a
`panelLayout.*` splitter ratio the developer once dragged made History's
Changed files panel overlap the commit graph by ~28px — enough that a
correct `tester.tap` silently missed its hit test. `pumpRealAppOn` now
clears those keys, so geometry depends only on the code under test.

Also noted while running the C++ suite:
`UndoApiTest.UndoRefusesAfterSwitchingBranches` is flaky (~2 in 5, a 10s
`waitForRefreshesToSettle` timeout) independently of this branch —
`MergeApiTest.ConflictingMergeReportsConflictThenResolveAndCommitFinishes`
and `UndoApiTest.UndoLastOperationRevertsTheCommit` fail the same way under
a loaded parallel `ctest` and pass on re-run. Not investigated here; worth
knowing before blaming a future branch for it. Tracked as **#70**, which
also records the untested hypothesis (a fixed 10s budget losing to parallel
load) and warns against raising the timeout before confirming it — that
would paper over a real refresh-coalescing bug if one exists.

**A second flake was isolated during Tier 0c's CI run and must not be
folded into #70** — `WorkingCopyApiTest.UnstageHunkReversesAFullyStagedSingleHunkFile`
failing with `LockHeld` ("Another Git process appears to be running in this
repository", the lock being its *own* temp repo's `.git/index.lock`). Unlike
#70's shape it was **not** a timeout and **not** load-dependent: run alone
with no parallel `ctest`, it failed 1 in 12 and again at iteration 30 of 40,
each time in ~0.36s, nowhere near any timeout budget. **Fixed** — #77, closed
by PR #78 (`3f6cfa1`).

Two things about it are worth keeping, because both are the kind of mistake
that is cheap to repeat:

- **It was a real product race, not a test artifact**, and the first
  diagnosis recorded here was wrong in an instructive way. This paragraph
  used to say "a working-copy operation is reported complete before git has
  released the index lock the next one needs" — blaming the *previous
  write*. That write's lock was long gone. The actual holder was the
  **background status/diff that follows it on `sharedReadPool()`**: a
  different pool from `OperationRunner`'s single serial worker, so reads and
  writes are not serialised against each other, and a plain `git status`
  rewrites the index (and takes `.git/index.lock`) whenever its stat cache
  has gone stale. Writes never collide with writes; only a background read
  can collide with a write. The fix is `--no-optional-locks` in
  `GitCommand::globalFlags()` — see its doc comment for why it is global
  rather than tagged onto the ~28 read call sites.
- **The end-to-end flake could not be reproduced on demand afterwards, in
  either direction.** After the fix the test passed 60/60 — but so did a
  control run with the fix removed, and 40/40 under parallel `ctest` load.
  Each test uses its own temp repository, so the race is intra-process
  thread scheduling, not inter-process contention, and that stress method
  cannot surface it. The evidence for the fix is the deterministic
  mechanism test (`RealRepoTest.StatusReadDoesNotRewriteTheIndex`, red
  before and green after) plus the causal chain above — not an A/B.

**#70 is still open**, and the triage advice stands: a red capi job may be
either shape, and they need different treatment — read the failure text
before assuming. A 10s `waitFor`/`waitForRefreshesToSettle` timeout under
load is #70; anything else is new.

### Tier 5 (fix/tier-5-native-window-title) — issue closed, not implemented

Issue #60 asked for a custom Windows/Linux title bar (a window package, two
platform-project changes, a new widget). **It should not be built**, and the
one thing worth carrying forward from this round is why, because the same
mistake is cheap to repeat.

Reading spec page 01's prose instead of its mockup shows the spec asks for
the *opposite*: 「三平台統一樣式，只有 menu bar 位置與**標題列跟隨系統**」
(intent line), and item 2 of its three-item platform-differences list is
「**標題列按鈕位置與號誌燈樣式沿用系統原生**」 — where the other two items in
that same list (macOS `PlatformMenuBar`, the system file picker) plainly mean
"use the OS's own facility". The facing panel scopes Flutter self-drawing to
「視窗**內**所有內容」, putting the title bar deliberately in the other list.
The page's three mockup cards illustrate what each OS's *native* decoration
looks like — the macOS card draws traffic lights with the same placeholder
technique the Windows/Linux cards use for minimize/square/close. Relying on
native decorations, which this app already did, **is** the conforming
behaviour. `spec-conformance-matrix.md`'s row read the illustration as a
requirement; that row is now corrected in place, and #60 is closed as
not-planned rather than fixed (same convention as #45: an issue whose premise
does not survive contact with the source is closed with the evidence, not
quietly retitled). **Generalisable rule: a mockup shows what the user sees,
not who draws it — a conformance verdict has to rest on the spec's prose.**

What *did* ship is a real page-01 gap the audit missed while chasing the
imaginary one: all three mockup cards title the window `git-branch-manager`,
but every platform still used Flutter's scaffold default `gbm_flutter`.
`lib/app.dart`'s `MaterialApp.title` does not reach the OS window title on
desktop, so this lives in native runner code only — `windows/runner/main.cpp`,
both branches of `linux/runner/my_application.cc` (GNOME header bar *and* the
X11 traditional title bar; changing one leaves half of Linux wrong), and on
macOS `MainFlutterWindow.swift` plus `MainMenu.xib`. `PRODUCT_NAME` /
`BINARY_NAME` were left alone on purpose: they are also the built artifact
names and `release.yml` hardcodes `gbm_flutter.app`/`.exe` paths.

That leaves macOS's *application* name — the Apple menu, About panel, Quit
item and Dock tooltip, all of which read `CFBundleName`, i.e.
`$(PRODUCT_NAME)`, i.e. still `gbm_flutter`. Setting `NSWindow.title`
directly is display-only and does not touch it. Tracked as **#67**, which
lays out the two candidate fixes (a literal `CFBundleName` in `Info.plist`,
keeping the artifact name; or a real rename with all four `release.yml`
paths moved in lockstep) and notes the evidence is consistency, not a spec
sentence — page 01's macOS card never draws the Apple menu.

Two things found by measuring rather than reasoning, worth knowing before
touching this again:

- **macOS needs a deferred re-assignment.** Setting the title synchronously
  in `awakeFromNib`, in `MainMenu.xib`, *and* in
  `AppDelegate.applicationDidFinishLaunching` are all reverted to
  `CFBundleName` (`gbm_flutter`) before the window reaches the screen; only
  `DispatchQueue.main.async { self.title = … }` survives. That line looks
  like a redundant duplicate of the one above it, so
  `test/platform/window_title_test.dart` asserts it explicitly — delete it as
  "cleanup" and the title silently regresses.
- **A macOS debug build's app code is not in `Contents/MacOS/<name>`.** That
  file is a launcher stub with a `__debug_dylib` section; the compiled Swift
  lives in `Contents/MacOS/<name>.debug.dylib`. Grepping the stub for a
  string you just added returns nothing and looks exactly like a stale or
  cached build — several rebuilds were spent on that false lead here.

`test/platform/window_title_test.dart` asserts the three runner sources
directly. That tier choice is deliberate: no widget or integration test can
reach native runner code, and **PR CI never builds Windows at all** —
`ci.yml`'s Flutter job is ubuntu-only and `windows/runner/main.cpp` is
compiled solely by `release.yml` on tag — so this test is the only thing that
sees a Windows-side regression before a release. Same rationale as `cq.yml`'s
`flutter-action` version-pin check, which greps workflow source for the same
"nothing else can see this" reason.

The hole is one platform wider than that sentence implies: PR CI runs no
`flutter build macos` either, so `macos/Runner/` is equally uncompiled until
a tag. Only Linux is covered, by `flutter build linux --debug`. And a
source-assertion test catches a string drifting or a `flutter create`
regeneration — never a compile error. Tracked as **#69**; until it is
resolved, assume any edit under `windows/runner/` or `macos/Runner/` reaches
`main` having been compiled by nothing, and weigh the change accordingly.

One more thing this round surfaced without resolving: spec's `MSGS` Rebase
row says the step count 「只顯示在標題列」, but 標題列 means four different
things across this spec (OS title bar on page 01; dialog header on page 06;
panel header in page 02 item 16; column header row in the multi-select
table), and page 01 is the *only* place it means the OS window title. The
app already renders `rebaseStep`/`rebaseTotal` in three surfaces
(`workspace_screen.dart:1055`, `status_bar.dart:117`,
`conflict_resolve_window.dart:967`), so if this is a gap at all it is an
over-display one, not a missing feature. **#68** asks for the reading to be
settled before any code moves — implementing off a guess here is the exact
failure mode that closed #60.

### Tier 0c (fix/tier-0c-rename-branch-dialog) — issue #45, addendum

Two things worth carrying forward from the verification pass, both found by
*running* rather than by reading — see the Tier 0c section further up for
the feature itself.

**`RefInfo.hasTrackingInfo` does not mean "has an upstream".** It mirrors
git's `%(upstream:track)` (`RefStore.cpp`'s `parseTrack()`), which is an
**empty string** for a branch exactly in sync with its upstream — 0 ahead,
0 behind — even though `%(upstream)` is fully populated. The rename
dialog's first version gated its whole "Remote handling" section on
`hasTrackingInfo && upstream.isNotEmpty`, which therefore hid it for the
single most common case (a branch that was just pushed) and silently
downgraded those renames to local-only. Anything asking "does this branch
track a remote?" must read `upstream`, and reserve `hasTrackingInfo` for
"did git report ahead/behind numbers". The widget tests all passed
throughout, because the test fixture hardcoded
`hasTrackingInfo: upstream.isNotEmpty` — the same wrong assumption, written
twice, so the tests could not disagree with the code. A fixture that
derives one field from another is a fixture that cannot falsify the
derivation.

**Nothing but a device-tier test crosses the FFI signature seam.**
`test/**` runs on `FakeGbmBindings`; `tests/capi/**` calls the C++ directly;
`dart:ffi`'s `lookupFunction` matches by **symbol name only, never by
signature**. So changing a capi function's parameter list and its Dart
typedef in lockstep is checked by nothing — a mismatch compiles, analyzes,
and unit-tests clean, then corrupts the stack at runtime.
`integration_test/rename_branch_flow_test.dart` is the only thing that
would catch it for `gbm_branch_rename`. Same trap as the stale-dylib note
in `integration_test/README.md`, and it fired again here: the checked-in
copy was 21KB behind a fresh build.

### Tier 4 (fix/tier-4-file-at-revision) — issues #58 + #59

The 05-K batch, and the only tier since Tier 0h to need new `src/core` C++.
Both issues landed on one branch as sequential commits, per the user's
decision to do 4a and 4b together. **#58's implementation sketch was wrong
and was corrected during planning** — read this before re-reading its issue
text.

**The capi is an export, not a read.** #58 proposed mirroring
`gbm_request_working_tree_content`: return the file's content inline in the
event payload. But neither consumer displays content in-app — "Open file at
this revision" needs a path to hand `DesktopLauncher.openFile()`, "Save this
revision as…" needs bytes at a path the user picked, and the route tree has
no in-app file viewer at all. Following the sketch would have produced (a) a
capi whose `content` field nothing under `lib/` consumes, the orphan-wiring
pattern this repo's audits keep flagging, and (b) no support for binary
files, since a JSON string payload cannot carry one — and recovering an
image out of history is exactly the case to support. So
`gbm_export_file_at_revision(session, revision, path, destPath)` writes raw
bytes to a destination and fires `GBM_EVENT_FILE_AT_REVISION_EXPORTED` (34)
echoing all three parameters back. Same premise-correction convention as
#50/#51/#60: the reasoning is recorded on the issue and in the PR, not
silently applied.

**`IProcessRunner::run()` is not byte-exact, and nothing said so.** This was
found by measurement, not by reading: `run()` reassembles stdout from the
line splitter, which drops the final separator and strips a `\r` before
every `\n` (Windows CRLF tolerance, `ProcessRunner.cpp`'s `LineSplitter`).
A text blob therefore comes back one byte short and a binary blob is
silently corrupted wherever `\r\n` occurs. The first draft of `BlobStore`
used `run()` and its own `cat-file -s` size check caught the mismatch —
which is the only reason this is a note here rather than a bug in
production. `BlobStore` now goes through `CatFileBatch`, which reads exactly
the byte count `cat-file --batch`'s header declares straight off the pipe,
and is the per-repository co-process `docs/ARCHITECTURE.md` already
prescribes for object reads. **If you ever need verbatim stdout from git,
`IProcessRunner::run()` is not it.**

**The submenu flyout was #59's real blocker, not the capi.** `gbm_menu.dart`
rendered a `GbmMenuItem.submenu` trigger's label with a permanently-null
`onTap`, so every "More actions" item in the app was unreachable. It now
draws a chevron and opens a nested menu **on tap, not on hover** — that is
forced, not a preference: `showGbmMenu` is built on Material's `showMenu`,
which lays a modal barrier over everything beneath it, so a hover-opened
flyout would instantly make its own parent menu unhoverable. Choosing a
child closes the parent too, and the parent is popped *before* the child's
action runs: menu items routinely push a dialog, and popping afterwards
would take the dialog down instead of the menu. `gbm_menu_test.dart` has a
test that asserts exactly that ordering by pushing a route from a child and
checking it survives.

Two things that look like gaps but are deliberate:

- **"Restore file to this state" and "Restore and stage" open the same
  dialog.** `restore_file_dialog.dart` has always offered both as two
  buttons on one dialog because the confirmation text is identical; a second
  dialog would be the same dialog. Spec lists both as menu items, so both
  exist as menu items.
- **"Export as patch…" on a file row exports the whole commit.**
  `gbm_patch_export` is `git format-patch -1 <commit>` — commit-level. A
  single-file patch would be a different capi. Asserted in
  `history_commit_file_menu_test.dart` so it reads as a decision, not a bug.

`Directory.systemTemp`, not `path_provider`, backs the temp copy for
open-at-revision: no plugin channel means a widget test can exercise the
whole path, it is synchronous, and the macOS build does not run under App
Sandbox. The temp filename keeps the extension (without it the OS has no
file association) and carries the short oid (so two revisions of one file do
not collide).

`file_selector` is a new dependency, wrapped in `FileSavePicker` /
`fileSavePickerProvider` so tests can substitute it exactly as
`desktopLauncherProvider` allows. Spec page 01's platform-differences list
names the system file picker as one of the three things taken from the OS,
alongside the macOS `PlatformMenuBar` and the window title bar.
`log_drawer.dart`'s "this app has no file-picker dependency" comment was
made false by that and is corrected in place, but the drawer itself was
deliberately not switched over.

**Left open on purpose**: `gbm_context_menus.dart`'s 05-K submenu lists four
children where spec's own block lists five — `Restore file to before this
state` is missing from the catalog. That drift predates this work and was
*not* fixed here, because the catalog is the parity test's acceptance
baseline and editing it mid-fix would redefine the thing being verified.
Tracked as **#71**, which also flags that the page-05 audit's method —
comparing each render site against the catalog — could not have caught a
catalog-vs-spec drift in *any* group, so others may exist.

### Tier 0c (fix/tier-0c-rename-branch-dialog) — issue #45

The one item Tier 0 deferred, shipped once its blocker cleared. Read this
before re-reading #45's issue text: **both the issue's premise and its
deferral reason were out of date**, in opposite directions.

**The deferral reason expired.** Tier 0 scoped #45 out because there was no
design draft for the rename dialog and building one blind risked a rewrite.
That draft now exists: the spec gained four pages on 260820 (commit
`fc3bfb3`), and **P13 section A** is exactly it — layout, the two remote
options, and a `RENAMEVALID` table of five live-validation rules. Nothing
about the deferral was wrong; the condition it named simply came true.

**The issue text overstated the gap.** "Rename branch dialog + route + F2
missing" reads as though rename did not work. It did: `sidebar_panel.dart`
and `workspace_screen.dart` both renamed branches through a shared plain
`promptText` box. What was missing was the *dedicated* dialog, its route,
and the shortcut. The issue body has been corrected in place (same
convention as #60 and #50) rather than quietly retitled.

**The issue also understated the work.** It read "`gbm_branch_rename`
already exists; only wiring is missing." P13's 遠端連帶處理 section made
that false — see below.

Eight sequential commits, every one green and independently revertible.

**`gbm_branch_rename` grew three parameters** (`renameRemote`,
`remoteName`, plus an internal `askpassDir`). The remote option is
push-then-delete — git has no atomic remote rename — and it lives in
`RenameBranchOperation::run()` rather than being chained from Dart. Three
capi calls chained in the controller would produce three
`OPERATION_FINISHED` events and three error exits, against spec page 10's
one-background-task rule; `run()` was already multi-step anyway (the
case-only rename goes through a `.gbm-rename-tmp` two-stage). `TagOps.cpp`'s
`DeleteTagOperation` is the template followed throughout: local step first,
remote steps behind the flag with `askpass::wire()` and no local timeout,
and a partial-failure summary that says which half landed.

**Two things measurement caught that reading would not have:**

- **`git branch -m` keeps the upstream.** Spec says a local-only rename
  leaves the branch with no upstream, and the obvious reading is that
  renaming naturally drops the tracking config. It does not — `branch -m`
  carries `branch.<name>.remote/.merge` across, so the renamed branch
  silently still tracks the *old* remote branch. That needed an explicit
  `git branch --unset-upstream` step. Verified directly against a scratch
  repo before writing the test, precisely so the test could not pass
  vacuously.
- **`Session::submitOperation` had no unconditional hook.** `beginAskpass()`
  documents that `endAskpass()` must be paired unconditionally, but only
  `submitWorkingCopyOperation` had an `onAlways`; `submitOperation` had just
  `onSuccess`, which would leak the credential watch on failure. Rename had
  to stay on `submitOperation` (it emits `OPERATION_FINISHED`, an existing
  capi contract), so `onAlways` was added there as its own commit.

**`RefInfo.upstream` is the full ref name**, `refs/remotes/origin/main`, not
`origin/main` — it comes from `%(upstream)`, not `%(upstream:short)`. The
dialog recovers the remote with `remoteBranchParts()`; splitting on the
first slash would send `"refs"` as the remote name. **`delete_branch_dialog.dart`'s
`_remoteOf()` does exactly that split and is therefore broken today** — its
"also delete on remote" checkbox builds a request against a remote named
`refs`. Found while writing this dialog, deliberately not fixed here
(different feature, needs its own test), tracked as its own issue.

**F2 targets the current branch, not the sidebar selection.** Spec says
"sidebar 選中後按 F2", and the sidebar *does* have selection state — but
`_selected` is `SidebarPanel`'s local `State`, which
`WorkspaceScreen._buildActionHandlers()` cannot read. Lifting it into a
provider is work #54's multi-select round needs anyway. So F2 and the Branch
menu fall back to HEAD (matching the action id's own name) and the 05-B
context menu is what names a branch, via the route's `branch` query
parameter. Deliberate, not an oversight.

**Validation was extracted, not copied.** `branchNameError()`
(`features/dialogs/branch_name_validation.dart`) came out of
`new_branch_dialog.dart`'s private `_nameError`; two dialogs needing the
same rules is how two drifting copies start. The rename dialog additionally
excludes the branch's own name from the duplicate check — that is
RENAMEVALID's 未改動 row, which disables the button *without* red text.

`branch_tree_item.dart`'s Rename item gained the `conflictActive` gate the
menu and F2 paths already had through `isActionEnabled()`; it sets **both**
`enabled: false` and `onTap: null`, since `enabled` alone is only a visual
signal (`gbm_menu.dart`'s doc comment). Noted while there: `New branch from
here`, `Merge into current branch` and `Delete branch` in that same menu are
still ungated despite spec page 07 disabling all three mid-conflict — a real
gap of the same shape, left alone as out of scope for #45.

`test/integration/workspace_rename_branch_flow_test.dart` covers the seam the
widget tests cannot: F2 → handler map → route → dialog → controller. Its
value was confirmed by mutation rather than assumed — deleting the F2 binding
fails three of its four cases (the fourth, "mid-conflict F2 opens nothing",
correctly still passes).

**Docs**: `spec-conformance-matrix.md` gained a baseline banner recording
that the audit was written against 12 pages and the spec now has 16, and its
`REVISIONS`-affected rows were corrected in place — including two that had
been excused as spec-internal collisions and no longer are. P14/P15/P16 are
**not** audited; nothing under `lib/` was changed for them.

### Tier 2 + Tier 3 (feat/tier-2-3-multi-select-compare) — issues #54–#57

Spec **P13 section B**: the selection model itself, plus the three things
that were blocked on it. Twelve sequential commits on one branch. **Three of
the four issues' premises were wrong**, and all three corrections changed
where the work went — read this before re-reading their issue text.

- **#56 said `Merge into current` needed an oid→branch-name step.** It does
  not. `gbm_merge_branch`'s `target` is pushed straight into
  `git merge <target>` (`MergeOps.cpp:59,82`) and only an empty string is
  rejected; an oid is a legal committish, and `startRebase(upstream)` is the
  same. There was no prerequisite, only wiring.
- **#57 said `Compare with…` probably needed a new dialog.** It needed none.
  `sidebar_panel.dart`'s `_compareStash()`/`_compareTag()` already
  established the convention — open a Compare tab with only the left side
  filled and let the Compare page's own `CompareRefPicker` take the right.
- **#55 said there was no UI path to Compare at all.** `Repository →
  Compare…` (`Ctrl/Cmd+Shift+C`) already existed and worked. Only spec's
  literal 「同時選兩個分支 → 右鍵 Compare」 was missing.
- **#54 said there was no multi-select mechanism.** The sidebar already had
  a checkbox one (the "delete gone branches" flow). What was missing was
  MULTIKEYS' click semantics and the menus.

**One selection model, two providers.** `ListSelection<T>`
(`data/models/list_selection.dart`) is an immutable `(ordered items, anchor)`
pair with five transitions, `isContiguousIn` and `orderedBy`.
`commitSelectionProvider` and `branchSelectionProvider` each hold one —
separate on purpose, per spec's 「選取狀態跨 scope 不混用」.
`selectedCommitProvider` is no longer independently writable: it is now
`ref.watch(commitSelectionProvider(identity)).anchor`, which is exactly its
old single-select meaning and leaves `commit_detail_panel.dart` /
`changed_files_panel.dart` untouched. **The checkbox and Ctrl/Cmd-click
write the same `branchSelectionProvider` state** — a checkbox tick *is*
`ListSelection.toggle`. Growing a second selection set is the bug shape this
whole arrangement exists to prevent.

Things worth knowing before touching this again, most of them found by
running rather than reading:

- **Contiguity is judged on the unfiltered snapshot**, never on the rendered
  rows. Three commits that look adjacent under a search filter are not a
  range git can replay, so cherry-pick/revert correctly stay disabled for
  them. Every *transition*, on the other hand, is expressed against the
  visible list, so a Shift range never silently spans hidden rows.
- **`Ctrl/Cmd+A` must be bound inside the list's own focus scope, never
  app-wide.** A `Shortcuts` closer to a focused editor than
  `DefaultTextEditingShortcuts` steals text select-all — so the branch
  tree's binding wraps the tree scroll area only, deliberately leaving the
  filter `TextField` outside it. `GbmActionId.editSelectAll`'s handler
  follows `_invokeTextIntent`'s existing shape (non-null in the handler map,
  forwarding by focus, `GbmSelectAllIntent` first then `SelectAllTextIntent`)
  rather than inventing a second mechanism.
- **Tapping an `InkWell` does not give it focus.** It is focusable for
  traversal, but a tap does not request focus, so the branch tree's
  `Ctrl/Cmd+A` did nothing after clicking a row. `_onBranchSelect` now calls
  `_treeFocus.requestFocus()` first. The test for it must use a *modifier*
  click, since a plain click routes through checkout instead.
- **`gbm_push` grew `branches`/`branchCount`**, mirroring
  `gbm_branch_delete`'s existing multi-name convention. `git push <remote> a
  b c` is natively 「依序執行，失敗不中斷其餘」 and is one background task,
  where chaining N calls from Dart would emit N `OPERATION_FINISHED` events
  against spec page 10 — the same reasoning Tier 0c's rename hit.
  **`branchCount 0` is not equivalent to naming the current branch**: it
  passes no refspec at all, so git pushes through the configured upstream
  and *refuses outright* when there is none. Measured, not assumed — the
  first version of `PushWithNoBranchesStillPushesTheCurrentOne` failed on
  exactly that and its doc comment now records it.
- **Spec says nothing about how a multi-branch Fetch/Push picks its remote**,
  so `sidebar_panel.dart` owns that decision and documents it there: Fetch
  groups by each branch's own upstream remote (a branch with no upstream has
  no remote-tracking ref and is skipped) and passes `refs`/`refCount` so it
  is one call per remote, not N. Push does the same for published branches;
  unpublished ones go to the repository's *sole* remote in their own call
  with `--set-upstream`, because folding them into a same-remote group would
  let `push -u` repoint a branch that tracks a differently-named upstream.
  With several remotes and an unpublished branch selected, Push is disabled
  **with a stated reason** rather than silently dropping branches.
- **Remote names come from `remoteBranchParts()`, never a first-slash
  split.** `RefInfo.upstream` is the full `refs/remotes/origin/x`, so that
  split yields `"refs"` — the live bug tracked as **#74** in
  `delete_branch_dialog.dart`, untouched here.
- **`RefInfo.ahead` only means anything when `upstream` is non-empty.** A
  branch that never had one reports `ahead: 0`, which rendered literally
  would claim "0 unpushed commits" — the opposite of the truth. The
  delete-branches confirmation says 「no upstream」 for those instead. The
  test is `upstream.isNotEmpty`, **not** `hasTrackingInfo` (Tier 0c's trap).

**Right-click has two halves, both implemented**: on an already-selected row
the selection is untouched and the menu gains a counted title; on an
unselected row the selection collapses to just that row first, so no action
ever runs against a selection the user cannot see.

**Single-item-only actions stay visible and disabled with a tooltip**, never
hidden — 「隱藏會讓人以為功能不存在」. That means `enabled: false` **and**
`onTap: null`, since `enabled` alone is only a visual signal
(`gbm_menu.dart`). `GbmMenuItem` gained `tooltip` and `showGbmContextMenu`
gained `title` for this; the title deliberately does **not** count toward
`validateGbmMenuItems`' 8-item cap, which is spec page 05's limit on
*actions*.

**Two deliberate reductions, recorded rather than faked**:
`MULTIACTS`' `Squash` is not offered at all — no capi supports "squash these
N commits" (`gbm_capi.h` has merge's `--squash` mode and interactive
rebase's Squash ordinal, neither of which is that). And the History status
bar reports count + contiguity only, not spec's 「合計 diff」: `ChangedFile`
carries no +/- line counts, and the only `--numstat` path is
`CompareOps.cpp`'s range diff, so a running total would fire a diff on every
selection change.

**What is still not done from P13 B**: 05-B's own menu is now conflict-gated
(that gap is closed), but the file and stash rows in `MULTIACTS` — Stage /
Unstage / Discard on multiple files, Drop on multiple stashes — were already
partly present and were not re-audited against MULTIKEYS' click semantics
here. **#76** stays open for that and for P13 A/P14–P16.

### Tier 6a (fix/tier-6a-remove-operation-log-dialog) — issue #61

The Log reconciliation. #61 was written as a judgement call ("does
`operationLogDialog` have any capability the drawer lacks? **Read both
implementations fully before deciding**"), but by the time it was picked up
the spec had already ruled, so the round became an execution, not a
decision. Three things are worth carrying forward.

**The spec is four pages longer than this file said.** `CLAUDE.md` and
`docs/reports/spec-conformance-matrix.md` both recorded a 260820 baseline of
**16** pages. The checked-in
`docs/claude-design-demo/Flutter Desktop Spec (standalone).html` has **21** —
P17/P18 (dialog 版面, 流程類 12 + 修復類 8), P19 (管理面板樣版), P20 (未實作
功能), P21 (Pull 流程與錯誤). Both baselines are corrected in place. **P17–P21
are unaudited**; nothing under `lib/` was changed for them here. Anyone
reading a conformance verdict written before this round should check whether
a later page revises it — that is exactly how #61 and #62 both went stale.

**The capability comparison the issue demanded has one real answer, and it
is a loss.** The drawer beats the dialog on two axes (`Save as…`, and the
info/warning/error filter) and loses on exactly one: the dialog had a
`Clear` button. It was **not** ported. P10's `LOGRULES` 匯出 row lists only
`Copy all、Save as…`, and its 保留 row already caps memory at 500 entries
(2,000 via Preferences) with 7-day file rotation — so the need Clear served
is covered, and adding it back would be beyond-spec. Recorded rather than
silently dropped, per this repo's convention.

**`clearOperationLog()` went with it.** `RepoSessionController` had exactly
one caller for that method — the deleted dialog — so leaving it would have
recreated the orphan-wiring shape this repo's audits keep finding
(`deleteRemoteBranchDialog` was the same). Checked by grep before deleting,
not assumed.

Also corrected while there, and worth knowing because the two errors
concealed each other: `tab_row_test.dart`'s "More menu lists all 18 items"
asserted a list of 18 labels while `_MoreMenu` actually built **19** — the
list silently omitted `Repository Settings…`. Removing `Operation Log…`
brought the count to a genuine 18, and the missing label was added, so the
name and the list now agree. A test that names a count and then hand-lists
the members can disagree with itself in both directions at once.

The route tree is now **34** repo-scoped dialogs. That number went *up*
while this round deleted one, because the enumerated list in the route tree
above had itself drifted: `rename-branch` (Tier 0c) and `delete-branches`
(Tier 2+3) were both added as real routes and never listed, so the
documented "33" was two short before `operation-log` was removed. Counted
from `route_paths.dart`, not from the prose, and the two missing names are
now in the list.

### Tier 6c (feat/tier-6c-panel-tabs) — issue #76's twelve panels

The carrier swap Tier 6b set up and deliberately did not perform. All twelve
of `IAMAP`'s large management panels are now tabs; their dialogs, routes and
`RoutePaths.*DialogFor` helpers are deleted. Thirteen sequential commits, each
green and independently revertible.

**`GbmPanelKind.isPortedToTab` is gone, and that is the point.** Tier 6b
introduced it as the single per-panel carrier switch precisely so eleven
working dialogs would not be replaced by placeholders mid-port. With all
twelve landed it had no `false` case left, so it was deleted along with
`_openPanel`'s dialog fallback — a getter that is constantly true is dead
weight, and `PanelPage`'s switch is now exhaustive over `GbmPanelKind` with
**no default arm**, so a thirteenth kind is a compile error rather than a
blank pane. `workspace_tools_menu_test.dart`'s "an unported panel still opens
its dialog" test went with it, replaced by the real post-condition: every
Tools entry opens a tab and none falls back to a route that no longer exists.

**The shared pieces, extracted after the second and third panel copied them
verbatim** (P19's own rule is 「只換欄位不換造型」):

- `features/panels/panel_widgets.dart` — `PanelListRow` (two-line list row),
  `PanelDetailField`, `PanelDetailColumn`, `PanelEmptyList`.
- `features/panels/panel_file_diff_detail.dart` — the 「檔案清單 + diff（唯讀）」
  detail column.
- `features/panels/panel_diff_text.dart` — raw unified-diff **text** with
  per-line colouring.
- `test/features/panels/panel_test_support.dart` — `pumpPanel()`/`panelButton()`.

**Three things found by running rather than reading**, each of which would
have shipped as a real defect:

- **`DiffPage` is not a file list.** For a non-binary file it renders that
  file's hunks and *no header at all*, so a multi-file diff (a stash's, say)
  arrives as one unlabelled run of hunks. P19 names 「檔案清單 + diff」 for
  manage-stashes; satisfying it needed `PanelFileDiffDetail`, not a one-line
  `DiffPage(...)`. Found by asserting the file path in a widget test.
- **`RadioListTile` needs a `Material` ancestor.** `GbmPanelTabShell` wraps
  the detail column in a `Container(color:)`, which swallows the ink splash —
  Flutter asserts about it rather than silently degrading, so
  interactive-rebase's action picker is wrapped in
  `Material(type: MaterialType.transparency)`.
- **`str.replace` hit two getters at once.** Appending `interactiveRebase` to
  `isPortedToTab` also appended it to `isPerSubject`, because both ended with
  the same `this == GbmPanelKind.lineHistory;` line. Caught only by
  `panel_tabs_repository_test.dart`'s "only the three per-file panels are
  per-subject" — a test that exists to pin a set, not a count.

**Where a panel's PANELSPEC row could not be honoured, it is absent and
recorded — never faked.** The full list, and which need a capi to close, is on
issue #76. In summary: 待提交數 (worktrees), 最後 fetch (remotes), 預期 commit
(submodules), 大小 (LFS), 剩餘步數 and 自訂測試指令 (bisect), 欄位選擇器
(file-history). Two more are *design* decisions rather than gaps and say so in
their class docs: interactive-rebase's 訊息編輯 (Reword is deliberately not an
action — see `RebaseOps.h`) and file-history's 含重命名 (`git log --follow` is
unconditional in the capi, so a toggle would be a lie; it renders as a disabled
indicator instead).

**Where the dialog did something `PANELSPEC` does not list**, the #61-style
capability audit ran before deleting it. manage-remotes was the first such
case and the only real loss: its per-row **Pull / Push** are gone, because
`PANELSPEC`'s toolbar and P04 `MENUS`' Remote menu *both* exclude per-remote
sync. Fetching one remote is covered as a superset by `Fetch all remotes`;
pulling or pushing a non-upstream remote is not covered by anything, and is
recorded on #76 rather than kept as an off-spec extra (the Tier 6a `Clear`
precedent). Elsewhere the audit went the other way: `gbm_submodule_add`/
`_deinit`, `gbm_lfs_pull` and `gbm_patch_import`'s four calls have **no entry
point anywhere in the spec**, so deleting their buttons would have orphaned
working capi — they stay, ordered after the spec'd actions, tracked on #76
(the same call Tier 6b made for Cherry-pick, #86).

**Two controls that only matter in one state are not toolbar buttons**:
LFS's `Install` and bisect's `Start` live in their panel's own
not-yet-usable state, which explains itself and offers the one fix. A
permanently-irrelevant button is noise; a state that says why nothing works
is not.

Smaller things worth knowing:

- `RoutePaths.panelFor` grew a `query` map. It is **not** part of a tab's
  identity (`panelTabsProvider` keys on kind + subject), so re-opening a panel
  with a different query focuses the existing tab and hands it new state —
  which is why `StashesPanel` applies `initialSelectedIndex` in
  `didUpdateWidget` as well as `initState`.
- `lfs_pattern_match.dart` is an **approximation** of gitattributes matching,
  not a port of `wildmatch()`. A pattern it cannot parse matches nothing, so a
  group reads 0 rather than claiming a wrong number. 11 unit tests pin both
  sides.
- `FakeRepoSessionController.checkout` was dropping its `detach` argument, so
  no test could tell a detached checkout from a failed branch checkout. Fixed
  while wiring the reflog panel.
- `changed_files_panel.dart` was passing `identity.workDir` **unencoded** into
  a route; fixed on the way past.

### Tier 6b (feat/tier-6b-tools-menu-entry-points) — issue #62 (+ #76)

The entry-point reshuffle. Like #61, **this issue's central premise had
expired**: it says the placement of the 16 overflow items "intentionally
does NOT pre-assign… that's a design decision requiring explicit
confirmation at kickoff". Spec page 14 (`進階功能的入口與載體`, added
260820) already *is* that decision, with four numbered rules and three
tables (`IAMAP`, `TOOLSMENU`, `FILECTX`/`FILECTXSUB`). Nobody had read it
because the docs still claimed the spec had 16 pages when it has 21 — see
Tier 6a.

**What page 14 rules, verbatim where it matters:**

- A new **Tools** menu, the menu bar's eighth, "放在 Remote 之後、Help 之前；
  它是「開一個面板」而不是「對目前分支做事」，所以不塞進 Repository".
- The destructive/multi-step three (Interactive rebase, Bisect, Clean
  untracked files) go in a **Rewrite history** submenu, "不與唯讀面板同層 ——
  手滑點到的代價差太多".
- The context-menu 8-item cap stays; the way to add a ninth is a flyout
  ("如 History ▸"), "不是把項目擠掉" — which is exactly the reduction Tier 1
  was forced into and is now undone.
- The twelve large management panels become **tabs**, not dialogs
  (`IAMAP`), sharing P19's 〈toolbar + left list + right detail〉 template.

**Three of #62's factual claims did not survive checking**, all recorded on
the issue rather than quietly worked around:

1. *"Removing the button isn't removing the feature"* — true for Merge…
   (Branch menu) and Reset… (05-E's `Reset branch to here…`), **false for
   Cherry-pick…**: `cherryPickDialog` has no other entry point at all, since
   05-E's `Cherry-pick` calls `_session.cherryPick(...)` directly and skips
   the dialog. Removing it would have recreated the orphan-route defect this
   repo already fixed once for `deleteRemoteBranchDialog`. Spec contradicts
   itself here — P18 draws a full Cherry-pick dialog, 05-E's label has no
   ellipsis and P14 says only dialog-openers get one — so the button stays
   until **#86** settles it.
2. *`_MoreMenu` is 18 items* — it was **19**, see Tier 6a.
3. *The 16 items all have somewhere to go* — **`Create tag…` and `Undo last
   operation…` have no spec'd entry point anywhere** (not 05-D, not
   `TOOLSMENU`, not `MENUS`; P18 draws both dialogs but names no `from:`).
   So the menu could only be *reduced*, not deleted. **#84**/**#85**.

**The trap that mattered most: a carrier swap is not free.** Routing the
Tools menu at the tab carrier is what page 14 asks for, but only
manage-worktrees has actually been ported. Pointing the other eleven at an
unbuilt tab would have replaced eleven working dialogs with a placeholder —
a regression wearing conformance as a disguise. `GbmPanelKind.isPortedToTab`
is the single switch that decides the carrier per panel, read by both
`_openPanel` (Tools) and `_openFilePanel` (History flyout); flip it as each
panel lands. An integration test asserts an unported panel still opens its
dialog and creates no tab, so a future port cannot regress it silently.

**Panel tabs mirror Compare deliberately** — `PanelTabSpec` /
`panelTabsProvider` / `WorkspaceTabKind.panel` / `RoutePaths.panel` /
`TabRow.panelTabs` are one-to-one with the Compare equivalents, rather than
a second tab mechanism. One behaviour differs on purpose: re-opening an
already-open panel **focuses** it instead of stacking a duplicate, because
two Compare tabs hold two different ref pairs while two Worktrees tabs are
the same thing twice.

Two smaller things worth keeping:

- **`TabRow` dispatches tab-close by `WorkspaceTab.kind`, never by index.**
  Both closable kinds sit in one flat list, so an index-based lookup would
  hand a panel id to the Compare notifier the first time the ordering
  changed.
- **`GbmMenuItemModel` gained `children`.** The two pre-existing submenu
  parents (`viewGraphColumns`, `viewTheme`) have *dynamic* children built at
  the widget layer; Rewrite history's three are fixed action items, so they
  are declared in the model. A third widget-layer special case would have
  made "which submenus exist" unanswerable from the model alone.

**Deliberate reductions, recorded not faked**: P19's `PANELSPEC` wants
待提交數 in the worktrees detail column, but `WorktreeInfo` carries no
pending-change count and `gbm_capi.h` has no per-worktree status call (a
status read is scoped to the session's own work dir). And only the `History`
flyout was taken from page 14's `FILECTX` table — its `Open diff`, `Ignore ▸`
and `Reveal in Finder` rename conflict with page 05's own 05-F list, which
`REVISIONS` never reconciled (**#88**).

**Still open after this round**: the eleven unported panels (**#76**, which
now carries the per-panel progress table), plus **#84**–**#89** for the six
spec gaps and conflicts found here. Page 14's rule 4 wants the flyout to
open on **hover after 120ms**; it opens on tap, because `showGbmMenu` is
built on Material's `showMenu`, whose modal barrier makes a hover-opened
child unhoverable from its own parent — Tier 4 documented this and it has
not changed (**#87**).

### Cancel-surface integration tests (test/cancel-surface-integration-tests)

Integration coverage for the two halves of one question — *does the state
machine stay clean when intents switch, and when an operation is cancelled
abruptly?* Six sequential commits, each green and independently revertible.
Four new files under `test/integration/`, plus one `lib/` fix the tests
forced out into the open.

**The defect: `ref` inside `dispose()` never worked, in any of the three
interrupt dialogs.** `credential_dialog.dart`, `checkout_recovery_dialog.dart`
and `delete_branch_recovery_dialog.dart` each carried a `_resolved` flag plus
a `dispose()` that dispatched the cancel command when the dialog was popped
unanswered — the safety net for a barrier tap, a back gesture, or a route
change out from under it. It threw `StateError` every single time.
flutter_riverpod's `ConsumerStatefulElement._assertNotDisposed()` gates every
`ref` member on `context.mounted`, and by the time `State.dispose()` runs the
element is already unmounted. So the guard is unconditional: **any `ref` use
in a `ConsumerState.dispose()` throws.** Fixed by capturing the notifier in
`initState()` into a field and calling that, guarded on
`StateNotifier.mounted` in case the provider went first.

The blast radius was real, not theoretical. For the credential dialog the
net is what stops a blocked git subprocess hanging until `GBM_ASKPASS`'s own
timeout — so every non-button dismissal of a credential prompt left git
waiting.

**Why it survived so long is the more useful lesson.**
`workspace_interrupt_overlay_test.dart`'s header had *seen* the throw and
written it down — but attributed it to test-harness mechanics ("throws if it
fires after pumpWorkspace's ProviderContainer is already disposed by
addTearDown") and worked around it by resolving every dialog before the test
ended. A correct observation with a wrong cause becomes a permanent excuse:
the workaround was carried into every later test in that file, and the real
path was never exercised. That comment is corrected in place. **A note
explaining why a test must avoid a code path deserves the same scrutiny as
the code path itself.**

**Three harness facts found by running, each of which would otherwise read
as a bug in the code under test:**

- **Never `pumpAndSettle()` while `isRefreshing` is true.** `TopBar` renders
  an indeterminate `CircularProgressIndicator` for exactly that flag, and an
  indeterminate spinner schedules frames forever — `pumpAndSettle` times out
  instead of failing on the assertion under test, which looks like a hang in
  the status bar rather than a harness misuse. Use `pump()` until the flag is
  back off.
- **`StatusBar` lingers a finished task for 3 seconds** (`_lingerTimer`), so
  "the task cleared" cannot be asserted on the frame after the transition.
  Drain with `pump(Duration(seconds: 3, ...))` — asserting too early would
  pin the linger away by accident.
- **A barrier tap is the right gesture for "dismissed without answering"**
  (`dialogRoute`'s `barrierDismissible: true`); `router.pop()` reaches the
  same path and is the recorded fallback. Esc/`DismissIntent` focus semantics
  are not worth fighting.

**Two fixture rules this round re-earned:**

- **Do not borrow `workspace_conflict_transition_test.dart`'s `_mergeState()`.**
  It sets `isSequencerOperation: true` for a merge; the core's flag excludes
  merge on purpose (`gbm_sequencer_operation.dart`'s IMPORTANT block).
  Harmless there — that file only needs `conflictActive`, which the
  conflicted entry supplies — but `_backgroundTasks()` gates the status-bar
  sequencer task on exactly that flag, so borrowing it manufactures a
  "Merging" task and pins the *opposite* of the documented behaviour. The
  faithful fixture is what makes "a merge conflict shows the banner but
  contributes no status-bar task" meaningful, and mutation-checking confirmed
  it: swap the fixture back and the test goes red. Same shape as Tier 0c's
  `hasTrackingInfo` trap — a fixture that disagrees with its source cannot
  falsify anything.
- **Count, don't `any`.** Every "exactly once" assertion goes through
  `commandLog.where((c) => c.name == ...).length`. `.any(...)` is blind to a
  double dispatch, and a double dispatch is precisely what deleting
  `_resolved` would cause — the button path would fire the cancel, then
  `dispose()` would fire it again. The button-path tests are what pin that
  flag; the barrier-path tests alone would not.

**What the tests cover**, beyond the fix's own regression lock:
`workspace_conflict_abort_dispatch_test.dart` closes the gap left by the
existing revert-only case — all three dispatching arms of
`_handleConflictAbort/Skip/Continue` through the real buttons, plus the two
state-machine properties that motivated the batch: a mid-flight kind change
must re-target the same Abort button without repeating the previous call, and
`rebaseMerge | cherryPick` (a real on-disk state — a rebase on the merge
backend leaves `CHERRY_PICK_HEAD` mid-step) must resolve to rebase per
`activeSequencerOperation()`'s documented ladder. Mutation-checked by
inverting that ladder.

`FakeRepoSessionController` gained a `refreshHistory` override. Without it
the status-bar Cancel test could not tell a dead button from a dispatched
one — the unoverridden method hits the real `_session == nullptr` guard and
silently no-ops, which is the fake's documented failure mode for anything it
forgets to record.

### Graph edge continuity (fix/graph-edge-parent-lane-conjunction) — PR #97

The commit-graph rendering path had no section here before this round, and it
had a live defect: **wherever a branch merged back into an older lane, its line
stopped half-way down the parent's row in the neighbouring column instead of
touching the commit dot.** Visible on any repository with merges. Two commits,
each green and independently revertible.

**Where the render path lives**, since nothing above says: `src/core/graph/`
builds the DAG (`GraphBuilder` → `GraphSnapshot`, `Edge` = 16 bytes,
`{childRow, parentRow, lane, childLane, color, kind}`), and there are
deliberately **no per-row pass-through records** — straight segments are
reconstructed at paint time by interval query, keeping memory at O(N+E) rather
than O(N × lanes). On the Dart side that reconstruction is
`features/history_graph/widgets/graph_edge_geometry.dart`'s
`computeEdgeSegments()`, which returns `List<EdgeSegment>` in lane/Y-fraction
coordinates (Y ∈ {0.0, 0.5, 1.0}); `graph_column_painter.dart` maps those
straight to canvas and draws a cubic iff `hasBend` (`startLane != endLane`).
**`GraphAsciiRenderer.cpp` is the reference renderer** — a deterministic text
renderer that exists precisely so rendering decisions have a checkable
counterpart. When the two disagree, the C++ one is right.

**The root cause was a mistranslated comment, not a missed line.**
`GraphBuilder` delegates the *arrival* bend to the renderer on purpose:
`patchIncoming()` (`GraphBuilder.cpp:59-69`) fills in `parentRow` and
**never rewrites `edge.lane`**, and `:103-104` says why ("Every other incoming
lane bends into `lane` here"). So where several edges converge on one commit,
only the one `chooseLane()` picked has `lane == rows[parentRow].lane`; every
other one *must* be bent into it by whoever draws. `GraphAsciiRenderer.cpp:122-127`
does exactly that comparison. The Dart port hard-coded `endLane: edge.lane` and
carried a comment asserting the opposite — "bends only happen at the child row"
— so the next reader maintained the code the comment described. The fix is one
line (`endLane: graph.rows[rowIndex].lane`); `graph_column_painter.dart` needed
no change at all, because `hasBend` is derived and the arrival segment routes
itself through the existing cubic branch.

**`edge.lane == rows[parentRow].lane` is a false invariant.** The first plan for
this round was a C++ invariant test asserting it, in the style of
`GraphBuilderTest.cpp`'s `Invariant*` family. Reading the builder killed that:
the inequality is the design, not a bug, and a test asserting it would have
failed against correct code and pushed the fix into the wrong layer entirely.

**The fixture-falsifiability trap, in a third shape.** The pre-existing
`graph_edge_geometry_test.dart`'s `'draws into parent dot'` case reuses **one**
`GraphRow(lane: 1)` instance for all three rows, and its edge is also `lane: 1`
— so the fixture cannot express a conjunction at all and passes identically
before and after the fix. Same class as Tier 0c's `hasTrackingInfo` fixture
(which derived one field from another) and the cancel-surface round's borrowed
`_mergeState()` (which contradicted its source): **a fixture that cannot
disagree with the code proves nothing.** `graph_edge_continuity_test.dart`'s
`_mergeAndRejoin()` anchors its lane values to output `GraphBuilderTest.cpp`'s
`TrunkKeepsLaneZeroAcrossAMerge` already asserts, and says so in a comment, so
the numbers are not mine to bend when a test goes red.

Two implementation choices in that test worth keeping:

- **Segments are identified by position in the spanning list, never by
  `edgeColor`.** A real snapshot shares one colour per lane, so colour-matching
  silently attributes one edge's segment to another.
- **`_spans()` is re-implemented in the test** rather than imported, mirroring
  `gbm::Edge::spans()`. The test needs its own opinion about which rows should
  carry a line; borrowing that answer from the code under test would make P1
  ("exactly one segment per spanned row") vacuous.

Verified by measurement, not by reasoning: RED before the fix hit **exactly**
the two conjunction fixtures (16 other assertions green), and reverting the one
line afterwards reproduced **exactly** the same two. A broad red would have
meant the test was pinning something else.

**Corrected in place**: `graph_column_painter.dart` cited a reference
implementation at `src/app/models/GraphColumnDelegate.cpp` that **does not
exist** in this repository, and `GraphSnapshot.h`'s `Edge` doc comment
described only the child-row bend — the source of the mis-port. Both now name
`GraphAsciiRenderer` as the single reference and cross-link the Dart file.

**Found while there, not fixed and not tracked as issues yet**:
`GraphRowPainter.shouldRepaint` compares only `row`/`rowIndex`/`graph`, so a
`laneWidth` or `colors` change (theme switch, gutter resize) does not trigger a
repaint; and `graph_edge_geometry_test.dart`'s `'handles multiple edges'`
fixture uses `childLane != rows[0].lane`, a shape `GraphBuilder` cannot produce.

### Narrow-window layout (fix/narrow-window-layout)

The window had no layout floor. Six independent surfaces overflowed once it
got small, and **nothing in the suite could see any of them** — every widget
test sizes its harness wide enough that degradation never fires. The round
started as "add a test for the git graph at a small window" and the scope
grew twice on evidence: first to the sidebar and top bar, then to every
deliberately-deferred item, at the user's explicit instruction to fix rather
than file.

**The bug was reachable at the app's own default window size.** Mutation-
checking `workspace_narrow_window_test.dart` against the unfixed code failed
its `1280x720` case — the same 1280x720 `linux/runner/my_application.cc:55`
and `windows/runner/main.cpp:29` open with. "Small window" was the reported
symptom, not the boundary.

**The rule the whole round turns on**: `RenderFlex` lays out **non-flex
children first** and only then divides what is left. A flexible child can
therefore never rescue an overflow that non-flex children caused, and every
one of the six defects below is the same shape — a variable-width `Text` left
non-flex, or a fixed-width column with no width to come out of.

| Surface | What was non-flex | Symptom |
|---|---|---|
| `top_bar.dart` | `repoName`, `repoState.describe` | trailing controls pushed off the right edge |
| `sidebar_panel.dart` folder row | `Text` with no `maxLines` | wrapped to two lines inside a 26px row |
| `branch_tree_item.dart` | the `gone` / `↑N ↓M` label | branch name squeezed toward zero |
| `sidebar_panel.dart` selection bar | two `TextButton`s at their 64px minimum | count label had nothing left |
| `sidebar_panel.dart` tree indent | 12px per level, uncapped | deep leaves ran out of name |
| `commit_row.dart` | graph column, hash, the ref-chip `Wrap` | hard overflow at 12+ lanes |

**`MenuBarRow`, `TabRow` and `StatusBar` needed nothing** — all three already
wrap their variable content in `Expanded > SingleChildScrollView`
(`menu_bar_row.dart:97` says so explicitly: 「七個選單在 800px 左右的窄視窗
放不下」). The plan for this round assumed the opposite and was going to pass
`isMacOS: true` to suppress `MenuBarRow` "for attribution"; that would have
tested less for no gain. **`TopBar` was the one piece of chrome with no
guard**, and the audit found it only by grepping all four for the pattern the
other three shared.

#### The commit-row column plan

`features/history_graph/widgets/commit_row_layout.dart`'s
`planCommitRowColumns()` is the single decision point. **It is computed once
per list, in `CommitGraphView._buildList`'s existing `LayoutBuilder`, and
passed down** — never per row. Its inputs are deliberately restricted to
facts every row shares (width, `graph.laneCount`, the picker's hidden set):
author and date are trailing fixed-width columns, so a row deciding for
itself — the HEAD row, say, which is also the one most likely to carry ref
chips — would stop lining up with its neighbours and the list would stop
reading as a table. `workspace_narrow_window_test.dart`'s "every row shows
the same set of columns" is the only test at any tier that can see that
regression.

Ladder: **date → author → hash → refs**, then clip the graph column. Only the
first three were agreed up front; refs going last is the function's own call
(a branch chip is the one thing in the row saying *where you are*, and unlike
the hash it has no second home in the commit detail panel), recorded in its
doc comment rather than presented as a requirement. **Nothing about narrow
windows is spec'd** — `docs/` and the spec HTML have no breakpoints and no
minimum widths. The ladder is derived from P02 item 16's "Graph 與 Message
固定不可關", which is why those two are the only things it will not surrender.

Three things found by running, not reading:

- **A budget-driven column is not monotonic.** Refs were first implemented as
  "whatever is spare after the message floor", which made them *reappear* at
  narrower widths as other columns dropped out and freed space — the exact
  opposite of a degradation ladder. Only the monotonicity property test
  (`for w = 2000 down to 40`, assert no column ever comes back) caught it.
  The fix is `kRefsReserveWidth`, making refs a real rung.
- **`Expanded` satisfies "no overflow" while hiding its child.** A subject
  column collapsed to zero throws nothing. `kMinSubjectWidth` and the
  `subjectWidthFor()` assertions exist because "did not overflow" is not the
  same claim as "Message is visible", and P02-16 wants the second one.
- **`Spacer` competes for the space it looks like it is donating.** `TopBar`'s
  first fix left the `Spacer` in place beside two new `Flexible`s; being a
  flex child itself, it capped the repo name at a third of the free space
  even on a wide window. Replacing it with an `Expanded` around the pair
  leaves the identical blank gap without taking a cut.

#### Two premises that did not survive, and one that could not

- **"Hiding a column frees width for the ones that remain"** — written as a
  test, and unprovable: once the ladder has dropped date and author on its
  own, the plan is *identical* to the user having switched the same two off.
  That convergence is the property worth pinning, and is what the test
  asserts now. There is one set of rules, not two.
- **"The plan must always leave 80px for the message"** — false below ~160px,
  where the row still owes its inter-column spacing with every column gone
  and the graph clipped to zero. The contract there is only that nothing goes
  negative, and the test says so.
- **A `takeException()` test cannot see a cross-axis overflow.** The sidebar
  folder row's wrapped label grew *taller* than its row, and `RenderFlex`
  reports only main-axis overflow — so the broken version threw nothing and a
  "does not overflow" case passed identically before and after the fix. It
  was replaced by an assertion on the rendered label height. **Before writing
  a no-exception test, check which axis the defect is on.**

#### The column picker was wired to nothing

`GraphColumnsSelector` held its visibility map in local `State` and wrote it
straight to SharedPreferences; `readVisibility()` had **no caller on the
render path at all**. Switching Author off changed a stored preference and
nothing on screen — the same orphan-wiring shape as the old
`deleteRemoteBranchDialog` route. Fixed with
`GraphColumnVisibilityNotifier`/`graphColumnVisibilityProvider` (shaped after
`ChromeVisibilityNotifier`, its closest sibling) feeding
`hiddenGraphColumnsProvider` into the plan. Width may still take a column the
user wanted; it can never restore one they hid. `kLockedGraphColumnIds` puts
P02-16 in the store rather than only in a disabled checkbox — **a disabled
control is an affordance, not an invariant**, and a hand-edited preferences
file reaches the same state.

Consequence worth knowing: **`CommitGraphView` now depends on
SharedPreferences**, so any test that pumps the commit list must override
`sharedPreferencesProvider`. Two existing test files did not and began
throwing `UnimplementedError` inside the list's `LayoutBuilder` — the fake
seam working as designed, failing loudly rather than reaching a real store.

#### Smaller things

- `GbmSplitPane`'s extent mode never compared the persisted extent to the
  space it actually got (`_availableExtent` was read in the same
  `LayoutBuilder` but only the drag path used it), so a window narrower than
  the sidebar width the user last dragged to overflowed. `_clampedFixedExtent()`
  protects the **filling** pane at `spec.minExtent` and makes the fixed pane
  yield — the filling pane is the content the window exists to show, and the
  fixed one has a toggle. It deliberately does **not** write back to
  `_currentFlexes`: a temporarily narrow window must not overwrite the size
  the user dragged to.
- `GbmLayout.graphLaneWidth` was dead; `commit_row.dart`'s `kGraphLaneWidth`
  literal was the live number. The alias now points one at the other so a spec
  revision has one edit site that matters.
- **`GraphRowPainter.shouldRepaint` is not a live defect here.** It compares
  only `row`/`rowIndex`/`graph`, so a dynamic graph-column width looked like
  it might paint stale — measured instead of reasoned about (a resize-in-place
  test in `commit_row_narrow_width_test.dart`): `RenderCustomPaint` marks
  itself needing paint on a size change regardless. The `laneWidth`/`colors`
  concern recorded in the previous section still stands for theme switches.
- **`BranchTreeItem` renders `ref.shortName`, the full slash-separated branch
  name**, so a nested leaf repeats its whole folder prefix *on top of* the
  indent. Found by dumping the rendered `Text`s; the intuitive guess ("a leaf
  shows its last segment") is wrong and makes every finder miss. It is also
  why capping the indent at `_kMaxIndentedDepth` costs nothing — the hierarchy
  is already in the label.
- **The default test surface is 800x600.** A `SizedBox` wider than that is
  silently clamped, which made a 1200px control case overflow by exactly
  `(1200 - 80) - 800 = 320px` and look like a bug in the plan. Widget tests
  that assert a wide layout must size `tester.view.physicalSize` too.
- **`TopBar` has a floor this round did not chase**: its non-flex remainder
  (back button, Refresh, divider, three theme swatches) needs ~327 logical px
  under the test font, so 320 still overflows by 7.2px with the repo name
  already at zero. TopBar spans the whole window, so that is below any real
  one; closing it would mean degrading the trailing controls themselves.

### History column order and widths (feat/graph-column-order-and-widths)

P02 item 16, in full: 「Graph 與 Message 固定不可關，其餘可開關並拖曳排序。設定存
在應用層級，所有 repo 共用；欄寬各自可拖曳並記憶。」The previous round wired
`readVisibility()` to the render path and left `readOrder()` / `readWidths()` with
**no reader at all** — the same orphan-wiring shape as the old
`deleteRemoteBranchDialog` route. Both are now live, along with the two columns
spec lists and the app did not have (Committer, Changed files). **Twenty sequential
commits, each green and independently revertible** — the approved plan budgeted
fourteen, and the delta is itself ledger material: a visibility-fallback fix
(`f69ee0c`) and two extractions found while implementing, the drag-handle fix
(`07509e1`) and the picker entry-point test (`2371d49`) below, and one commit split
in two once a product fix was spotted riding inside a `test:` commit
(`dbf5e0e`/`77c1902`). The `chore:` prerequisite that removed the mis-committed
spec generator output (`b8c6c2b`) landed on the parent branch first.

**Where the column decision lives now**: `data/models/graph_column.dart` owns the
`GbmGraphColumnId` enum and two pure resolvers (`resolveGraphColumnOrder`,
`resolveGraphColumnWidths`); `graph_columns_repository.dart` holds the two
notifiers plus `graphColumnLayoutProvider`, which is the single 〈visible +
ordered + resolved widths〉 object that the row, the degradation ladder and the
resize strips all read. Growing a second source of column order is the bug shape
that arrangement exists to prevent.

**Three visible behaviour changes, none of them incidental**: the default order
is now spec's `graph │ message │ refs │ author │ date │ hash` (hash was second,
refs was fourth — a pre-existing drift, not introduced here); `refs` stopped being
"whatever is left after the message floor" and became an ordinary fixed,
draggable, remembered column, because a column that eats the remainder has no
width to remember; and the standalone `HEAD` text label is gone, replaced by the
`HEAD → <branch>` ref chip spec's mockup actually draws (with a bare `HEAD` chip
for detached, or the "you are here" marker would have vanished entirely).

#### Premise corrections — read these before re-reading the approved plan

- **Plan note 9 was backwards, and the correction is generalisable.** It said
  `ReorderableListView`'s default trailing drag handle is fine to keep and only
  the *test* must drag the handle rather than the row. Measured on the real
  widget: a mouse click with **2px** of travel loses its toggle outright.
  `ReorderableDragStartListener` hands the pointer to an
  `ImmediateMultiDragGestureRecognizer`, whose acceptance threshold is
  `computeHitSlop(kind)` — **`kPrecisePointerHitSlop` (1.0px) for
  `PointerDeviceKind.mouse`**, not `kTouchSlop` (18px). So the whole-row handle
  is not a test-only inconvenience; it is a real defect for anyone whose hand is
  not perfectly still. The row is now inert and a 20×24 `_GripHandle` at its
  trailing edge is the only drag surface. Related, and the only reason a
  transparent grip is hit-testable at all: **`Container(color:)` builds a
  `_RenderColoredBox` constructed `HitTestBehavior.opaque`**, while `Listener`
  (which `ReorderableDragStartListener` is) defaults to `deferToChild`.
- **Plan note 12's batch command would have shipped two screens disagreeing.**
  It specified `--no-renames` on the batch `git log`, reasoning that `diff-tree`
  defaults to no rename detection so the batch should match. Measured, both
  halves are wrong in the same way: **`git log --raw` honours `diff.renames`
  (default true since git 2.9, and settable per repo) while `git diff-tree --raw`
  ignores it entirely.** Hardcoding `--no-renames` on one path only would have
  put a column reading `2` beside a panel listing `1` on any repo that sets it.
  The flag is now **always passed explicitly on both**, from one shared
  `rawRenameFlag()`, and `parseRawRecords()` is shared too so the two cannot
  drift. `BatchFileCountsIgnoreTheRepositorysDiffRenamesSetting` is the test that
  makes this falsifiable — it sets `git config diff.renames false`, and the
  omit-the-flag mutation goes red on exactly it.

#### Measured, not reasoned

- **`git diff-tree` silently ignores `--first-parent`.** On a two-parent merge,
  `diff-tree -m --first-parent` emits **33** records = the first parent's 19 plus
  the second's 14; the flag does nothing and `-m` prints both sides. The correct
  spelling is **`--diff-merges=first-parent`** (git 2.31+), which gives 19 and
  agrees with `git diff <first-parent> <merge>`. `git log` *does* honour
  `--first-parent`, which is exactly why the wrong flag looks plausible. All
  three `DiffService` call sites use the explicit form.
- **The merge fix had to be all three call sites or none.** `changedFiles` (the
  panel's list) and the two single-file patch paths were each empty for merges.
  Fixing only the list would have produced 19 rows that each open an empty
  diff — worse than an honest 0. Non-merge output is byte-identical before and
  after (md5-checked on a normal commit and a root commit), so this is purely
  additive.
- **`git diff-tree --stdin` cannot carry a batch.** With `-m` it echoes the input
  commit lines back and produces output only for the last one; the rest vanish
  silently. The batch is `git log --no-walk --format=%x00COMMIT %H -r --raw -z`,
  sliced on the `COMMIT ` header fields.
- **`git log --no-walk` sorts by commit date, not by the order the oids were
  given** (`--no-walk=unsorted` would preserve it). Nothing may assume the reply
  is index-aligned with the request — which is why the payload echoes each oid.
- **Absent is not zero.** A commit git never answered for must be *omitted* from
  the file-count reply, never cached as `0`; `UnknownOidIsOmittedFromTheFileCountsReply`
  pins it. On the Dart side `fileCount == null` renders a skeleton and `0` renders
  a real zero, so the two states stay distinguishable on screen.

#### The popover defect only the device tier could see

`showGraphColumnsPopover` opened unconditionally below its anchor. On the 800×600
default widget-test canvas that always fits, so every widget and integration test
was green. On a real 1440×900 window the button sits at y=681, leaving 191px
below — **the last two rows of the eight-row list land off-screen and cannot be
clicked**. Found while writing the device test for something else entirely: the
tap on `Changed files` kept missing, and the button's actual rect
(`Rect.fromLTRB(950.6, 681.0, 978.6, 709.0)`) had to be recovered through a
deliberate `expect(1, 2, reason: …)`, because `debugPrint` does not reach the
piped output at device tier. The popover now compares the space above and below
and flips. **A placement bug is invisible to any tier whose canvas is bigger than
the real window.**

#### Harness and process notes

- **`pumpRealAppOn` now clears `graphColumns.*`** alongside `panelLayout.*`. Device
  tests share the machine's real `shared_preferences`, so a column the developer
  once dragged or switched off would silently change what every later device test
  renders — the same class of failure as the splitter-ratio incident recorded in
  the Tier 1 section.
- **`integration_test/README.md` claimed `scripts/build_capi.sh` does not exist.**
  It was added by `ab58282` (2026-08-13) while the README's last touch was
  2026-08-21, so the doc was stale rather than wrong when written. Corrected in
  place.
- **Do not revert a mutation check with `git checkout -- <file>`.** Doing that here
  discarded an entire uncommitted implementation, because the file's last commit
  predated the work. Every subsequent mutation went `cp file "$SCRATCH/x.bak"` →
  mutate → `cp` back. And every mutation script carries a hard
  `assert s.count(old) == 1` before writing: two mutations in this round failed to
  match after `clang-format` reflowed an argument list onto one line, and without
  that assert both would have read as a passing green.

#### Still open

- ~~**The refs column's default width sits in a measured 1.4px corridor** — floor 91
  (spec's own `HEAD → main` example chip) against ceiling 92 (bisected against
  `workspace_narrow_window_test.dart`'s twelve-lane 1280×720 case, the app's own
  default window size). 92 was chosen. The consequence, recorded in
  `graph_column.dart` rather than hidden: a HEAD **synced with its upstream**
  needs ~103px, so its cloud icon clips and what remains is glow-without-cloud —
  the signature spec assigns to the *opposite* state. Widening the column restores
  it and the width is remembered, but the default reads wrong. Not fixable by
  picking another default; 103 is past the ceiling. **Worth overruling if the
  synced case matters more than the twelve-lane lock.**~~ — **Fixed** by the
  next round's lane-pitch correction, not by overruling anything: 18 → 17px
  gives a twelve-lane row 13px back, which lifted the ceiling past 103 and let
  refs go to **104** (`ceil(103.1)`), so the synced-HEAD chip renders whole at
  the default. See "History density…" below for the re-bisection.
- **There is no column header row, so there is no obvious place to grab.** Spec's
  mockup draws none, and adding one would have changed the page's appearance for a
  feature the mockup does not show — so the resize surface is an invisible 8px
  strip on the list itself, revealed only by the cursor on hover. That it does not
  also eat the commit row's click rests on `HitTestBehavior.translucent` plus a
  horizontal-drag recognizer *only* (a plain tap has no recognizer to win, so it
  falls through) — a gesture-arena property, pinned by its own test because no
  layout assertion can see it. **Discoverability is the accepted cost** of keeping
  the mockup's appearance — and manual testing confirmed the cost is real: with no
  static hint, the strip is hard to find and hard to grab. Tracked as **#99**,
  deferred to the next spec revision, since every candidate fix (a header row, a
  faint always-visible divider, a width field in the picker) changes the page's
  appearance for something the mockup does not draw.
- **The manual pass is not done**: dragging to reorder, dragging an edge,
  restarting to confirm persistence, and clicking through a resize strip on a real
  repository are interactive and were not performed here.

### History density, graph geometry and the branch filter (fix/history-density-and-branch-filter)

Six problems found by running the app on a real repository, not by reading: a
live `RenderFlex overflowed by 2.3 pixels on the bottom`, a graph column that
grew without bound as branches ran in parallel, no way to suppress merge rows,
no way to give the graph less room, lines too far apart, and commit/file rows
too tall. They share one subject — **History's information density and how much
of it the user controls** — and the last of them is answered by a new capi
rather than by CSS. Twenty-two sequential commits, each green and independently
revertible.

**Two of the six were spec conformance, not taste.** `spec_logic.js:428` is
`const L0 = 15, L1 = 32, RH = 26` and the mockup's graph SVG is `height="182"`
= 7 × 26, so **the commit row is 26px and the lane pitch is 17** — the code had
34 (`rowHeightComfortable`) and 18. `rowHeightCompact = 26` was already a spec
token the sidebar and Working Copy used. So "shorten the spacing" was a
correction back to the spec's own numbers, and is recorded that way rather than
as a visual preference. The same reading gave the dot geometry (`r: 4.2`, halo
`2`, HEAD ring `r: 7` at `1.5`, connector `1.75`) — **all four values in
`graph_column_painter.dart` were wrong**, and none of them broke a test, so each
got one.

**SVG paints stroke on top of fill, and centres it on the path.** Spec's dot is
`r: 4.2` with a 2px panel-coloured stroke, which shows a **3.2px** coloured core
inside a halo reaching 5.2 — not a 4.2px dot with a ring around it. Drawing the
halo first and the fill second looks equivalent and is not. Pinned by
`graph_dot_geometry_test.dart`, which records draw calls through
`implements Canvas` + `noSuchMethod` (a `PictureRecorder` is opaque and cannot
be asserted on). Two traps inside that test: `GraphRow.isHead` is `flags & 0x20`,
not the low bit; and **`Paint.color` quantises on read-back**, so a comparison
against the source token fails while Expected and Actual print identically —
compare `.toARGB32()`.

**`isLocked` is not `!isResizable`.** The graph column is locked (P02-16:
「Graph 與 Message 固定不可關」) *and* now resizable: dragging it moves a **cap on
how many lanes are drawn**, never whether the column exists. The user's ruling
set the floor — 「git graph 保持最小一線寬度，使用者最小就這樣，但一樣維持欄位存
在」 — so the minimum is one lane, not zero. Because the stored width is a
maximum rather than a size, `renderedWidthOf()` supplies the drag origin;
without it a drag on a repository with two lanes would move nothing visible
until it passed the natural width.

**A resize strip must be withheld when the column is a spacer.** `showGraph:
false` is the live commit-search path — the column stays laid out but holds a
12px spacer, because `graph.edges` connect adjacent rows of the *unfiltered*
snapshot. The strip stayed up over that spacer and `renderedWidthOf` reported
12, so a drag near the left edge wrote a near-minimum lane cap into
SharedPreferences that outlived the search. `CommitRowColumnPlan.drawsGraph`
exists for exactly that gate.

**The refs ceiling recorded last round was measured before this round's cap and
is now false.** It said 105; re-bisecting `planCommitRowColumns` after the
153px graph cap landed gives **173**. So the previous round's recorded regret —
a synced HEAD's cloud icon clipping at the 104px default — is gone, and
`workspace_narrow_window_test.dart`'s title ("gives up nothing") was a lie in
the other direction: that case *does* give up Date. Retitled, with a negative
assertion and the date label derived through the real formatter rather than
hardcoded.

#### The branch filter was wrong in six of its nine rules

The user pointed at spec P02-14 directly (「因為你 filter branch 時做錯了…看
spec 02 頁 14 點」). Audited against the running code: rules 1, 2 and 5 already
conformed; **3, 4, 6, 7, 8 and 9 were all gaps**, each closed in its own commit.

- **Rule 3's own example did not match.** Spec says 「打 `gl` 命中
  `feature/graph-lanes`」 and `filterBranches` was
  `shortName.contains(needle)`, for which that is plainly false. Extracted as
  `matchesBranchFilter()` (substring first, then initials) rather than patched
  in place, because Tags and Stashes need the identical rule — the
  `branchNameError()` precedent. **The plan's own algorithm sketch was wrong
  and was corrected before implementing**: splitting on `/` alone gives `fg` for
  `feature/graph-lanes`, not `gl`; the separators are `/ - _ . space` plus a
  camelCase boundary. A deliberate negative test pins substring-over-initials
  rather than subsequence (`fl` must *not* match).
- **Folder identity must be the full path, not the display segment.** Rule 4
  (expand-all while filtering) had no effect at first because
  `_buildFolderNode` re-derived `isExpanded` from `_expandedFolders` instead of
  reading `folder.isExpanded`. Fixing that turned five existing tests red, which
  is how a **pre-existing** bug surfaced: the panel keyed on `folderName` (one
  segment, `sub`) while `buildBranchTree` keyed on the full path
  (`feature/sub`). They agree only at depth one, so `feature/sub` and
  `chore/sub` opened and closed together and Copy-folder-prefix gave `sub/`.
  `BranchTreeFolder.folderPath` is the fix. **A second source of truth for a
  computed fact is what hid it** — the re-derivation could not disagree with
  itself.
- **Rule 7's pin replaces the tree row, never joins it.** Rendering both shows
  `main` twice whenever HEAD does match the query. `filterBranches` is left
  alone — it is a pure name rule with no business knowing which ref is HEAD,
  which is also why rule 6's hit count still counts only genuine matches.
- **Rules 8/9 bind Esc and ↓ with `CallbackShortcuts` placed innermost, above
  the `TextField`**, so they resolve before `DefaultTextEditingShortcuts` and
  leave the tree's own Esc (MULTIKEYS' collapse) untouched. The first test for
  that was red on a **wrong premise, not wrong code**: a plain click on a branch
  row routes through checkout and never reaches `_onBranchSelect`, so focus
  stayed in the filter box. A modifier click is the pattern that works, as this
  file already records.
- **Recorded reduction**: ↓ enters the first *branch* result only, so a query
  matching only a tag or a stash no-ops. A defensible reading of 「第一個結果」,
  written down rather than left for the next audit to file as a bug.

#### `--first-parent --no-merges` breaks the trunk, and git will not fix it

The user's ruling was 「只有一個分支：我要有 no merge 的效果，但是不會有平行線。
兩分支以上，就照目前狀態顯示」. The flags alone do not deliver it, and this was
measured before any code was written:

- Under `--first-parent --no-merges`, a surviving row's recorded first parent is
  often a merge git never emits. `GraphBuilder::finish()` turns those pending
  edges into `kRowBoundary` stubs with `FlagBoundary`, which the Dart renderer
  draws as `EdgeSegmentKind.boundaryStub` — "arrives from above and stops
  halfway". **So the trunk would break once per removed merge**, the exact
  opposite of one continuous line.
- **git has no flag that bridges the gap**: `--parents` and `--ancestry-path`
  both still report the excluded merge. Checked directly, so nobody re-checks.

The bridge is a one-row lookahead in `HistoryProvider`'s walk loop, **not** a
mode in `GraphBuilder` — the builder stays single-path, so every existing
invariant test and `GraphAsciiRenderer` keep applying unchanged, and the
endpoints fall out for free (a complete walk ends at a root with no parents; a
`--max-count` walk keeps its real parent and so becomes a boundary stub, which
there is the *true* statement).

~~**It is faithful for a structural reason, not because this repository's history
happens to suit it.** `HistoryQuery::isLinearWalk()` requires **one** tip,
`--first-parent` and `--no-merges` together: one tip walked first-parent visits
exactly that tip's first-parent chain in order, so the `--no-merges` output is a
*subsequence* of that chain and any two consecutive rows are still first-parent
ancestor and descendant with only merges elided.~~ — **Corrected on sight of the
running app**; the argument was sound and the feature built on it was wrong. See
the next subsection.

#### The straight line must still contain the merged-in work

The first implementation read the ruling's 「no merge 的效果」 as `--first-parent`
and set it alongside `--no-merges`. Running it produced the correction:
「filter only one branch 要看到的是包含並進來的 commit，只是不寫 merge commit
不會出現，的一條直線」. `--first-parent` does the opposite of that — it keeps the
merge row's own line and discards everything that arrived *through* the merge.
**Measured on this project's own `main`: 3 rows with `--first-parent --no-merges`
against 442 with `--no-merges` alone**, and 485 unfiltered. The branch filter did
not narrow the graph, it emptied it.

`isLinearWalk()` is now **one tip + `--no-merges`**, with `--first-parent`
neither required nor forbidden. The single line comes entirely from the bridge,
not from narrowing the walk.

**The subsequence argument dies with it, and there is no weaker version to
keep.** Without `--first-parent`, even when a row's real parent *is* emitted it
need not be the next row — topo order can interleave a side branch's commits
between a trunk commit and its parent, and the bridge links to the interleaved
row regardless. So the drawn segment means **"the next row"** and nothing else;
anything wanting real edges must read an unfiltered snapshot. One property does
survive: `toRevListArgs()` always emits `--topo-order` or `--date-order`, both of
which guarantee a parent is never printed before its children, so a segment never
points from an ancestor down to its own descendant. **That depends on the
ordering flag staying unconditional.**

`--topo-order` was kept over `--date-order` (which `HistoryQuery` already
supports as a one-flag change): it groups a merged branch's commits at the point
they landed rather than interleaving them by timestamp.

**The RED test asserts presence, not count.** `GitIntegrationTest`'s fixture
already had a commit on each side branch; those are exactly the rows
`--first-parent` swallowed, so they are looked up by subject and asserted
individually. A 4→6 row-count bump can go green for the wrong reason, and
"the commits merged in are still there" *is* the requirement.

#### The whole of `HistoryQuery` had never been exposed

`gbm_history_refresh(session)` took no parameters, while `HistoryQuery` had
`includeRefs`, `excludeRefs`, `firstParentOnly`, `grep`, `author`, `maxCount`
and `dateOrder` — and `includeRefs`' own comment already said 「這是 Branches…
（graph 分支過濾）設的」 for a UI that was never built. `gbm_history_set_filter`
closes it, with two decisions worth keeping:

- **The filter is session state, not a parameter of one walk.** An operation or
  an auto-fetch resync calls `refreshHistory()` on its own; if that dropped the
  filter the graph would silently widen back out under the user while the
  sidebar still showed one branch. `HistoryFilterApiTest.SurvivesARefreshItDidNotAskFor`
  is the lock.
- **Stale ref names are dropped, not forwarded.** rev-list aborts the *entire*
  walk with "unknown revision" on one bad name, so a branch deleted or pruned
  while its filter was set would blank the graph rather than stop narrowing it.
  `RefStore::refExists` (which exists for exactly this) filters them; with every
  name gone the walk falls back to unfiltered, the same thing clearing the
  filter does. Mutation-checked: forwarding them turns both stale-ref tests red
  by *timeout*, because no completed `GRAPH_UPDATED` ever arrives — which is the
  blank-graph failure itself.

`toStringVector` had five identical copies across `src/capi/`; it moved to
`Handle.h` in its own commit rather than gaining a sixth.

#### The filter query had to leave the sidebar first

`SidebarPanel` is hideable, so local `State` holding the only copy of the query
would let the graph stay converged with nothing on screen to say why or to clear
it — the `material_state_hidden` shape this file's own UX rubric flags.
`branchFilterQueryProvider` is identity-keyed and deliberately **not**
persisted: a filter is something the user is doing now, not a setting.
`initState` re-seeds the `TextEditingController` from it, which is the half a
naive lift forgets — the rows stay narrowed and the box looks empty.

`historyFilterFor()` is the convergence rule, and it sends **`fullName`, never
`shortName`**: `mergeLocalAndRemoteBranches` strips the `<remote>/` prefix off a
remote-only row so it groups with a same-named local branch, so `origin/staging`
arrives as `staging` and would resolve to the wrong ref or to none. Same class
as `delete_branch_dialog.dart`'s first-slash split (#74).

**A measurement overturned this round's own test design.** The dispatcher has a
250ms debounce and compares against the last request *sent*; both mutations
(zero-delay timer, drop the comparison) left the first version of
`workspace_history_filter_convergence_test.dart` **green**. Instrumenting the
provider showed why: typing all eleven characters of `graph-lanes` fires the
listener **once**, because `historyFilterRequestProvider`'s value is *equal* for
every prefix that does not resolve to exactly one branch, and Riverpod does not
notify on an equal value. So the test that claimed to prove the debounce was
proving `HistoryFilterRequest.==`. The debounce's real job is a burst of
*different* values — backspacing out of a query and typing it back — and the
last-sent comparison's real job is the case where such a burst lands back on the
filter already in force. Both now have a case that goes red without them.
**Three mechanisms were doing overlapping work and only one was tested; the fix
was to name which case belongs to which, not to delete two of them.**

#### A retained query outliving its session

`branchFilterQueryProvider` is not autoDispose, so the query survives the
repository being closed; the C++ session's filter does not; and **`ref.listen`
never fires for the value already present when it registers**. Leaving a
filtered repository and coming back therefore showed one branch in the sidebar
and every branch in the graph -- the exact two-screens-disagree state this round
exists to prevent, and the one defect none of its own tests could see, because
every one of them pumps a workspace whose query starts empty.

`_syncHistoryFilter()` re-sends the current request after the first frame and on
the session's `isOpen` false->true edge, undebounced -- this is not a keystroke,
it is a session that has no filter and a query that says it should have one. The
`isOpen` arm clears `_lastSentHistoryFilter` first, or the comparison would
decide the core already knows. The provider's own doc comment claimed the
opposite (`重開 repository 會看到全部`) and is corrected in place.

**Generalisable**: every `ref.listen`-driven piece of session state has this
shape. The listener covers *changes*; something else has to cover the value that
was already there. The test that sees it is the one that seeds the provider
**before** pumping.

#### History's three panes were in the wrong place, all three of them

Spec P02 says it in one line — 「History 分頁：**右側 Changed files**（02-10）+
**下方 Commit detail**（02-08）」 — and its `SPLITTERS` table names both dividers:
`main.detail` 「Commit list ↔ Commit detail」 水平 62/38 min 160, and `main.files`
「中央 ↔ Changed files」 垂直 186px min 140. The page had detail on the right and
files below, i.e. both axes swapped.

**The third error was the one worth catching.** `history_page.dart` passed the
commit graph as pane 0 of an *extent-mode* vertical splitter, expecting "graph
first, so on top, filling". Extent mode pins **pane 0** to its fixed size, and
the old implicit rule put a vertical fixed pane at the **bottom** — so the
commit graph, the whole point of the page, rendered as a **186px strip along
the bottom** with the file list filling everything above it. Measured off the
rendered rects before touching anything: `graph=(255,677)-(1085,863)`,
`files=(255,112)-(1085,672)`.

**The root cause is a widget API, so that is where the fix went.**
`GbmSplitPane`'s fixed pane used to sit at an end chosen by the axis —
horizontal → leading, vertical → trailing — a rule invisible at the call site,
where `children: [a, b]` reads as "a then b" either way. It is now an explicit
`fixedPaneEnd: GbmFixedPaneEnd.leading | .trailing`, defaulting to leading, with
the two vertical call sites (log drawer, panel file list) saying `trailing`
outright. The drag-delta inversion follows the same flag instead of the axis.
The old rule could not express *horizontal + trailing* at all, which is exactly
what History's right-hand files column needs.

**Two existing tests were passing because of the bug**, and both are corrected
rather than relaxed:

- `history_column_resize_test.dart`'s "a single click on a strip still selects
  the row under it" tapped the strip's own centre. The strip spans the list's
  full height, so that point is only over a row while the list is *short* —
  which it was, at 186px. With the graph at its proper height the centre lands
  in the empty space below the last row. It now takes the strip's x and a real
  row's y.
- `workspace_narrow_window_test.dart`'s twelve-lane 1280×720 case asserted that
  Date is dropped. The commit list grew from `(1280-260)×0.62 ≈ 632px` to
  `1280-250-5-186-5 = 834px`, so nothing is dropped any more. That title has now
  been true, then false, then true again — the file records the sequence so the
  next reader does not trust it on sight.

**An axis flip invalidates a stored splitter extent, and the one machine
guaranteed to hold a stale value is the user's own.** Extent mode persists a
raw pixel number (`split_pane.dart` stores `[extentPx]`), keyed on `storageId`
alone with no axis in the key — so a files band anyone had dragged taller while
it lived *below* the graph would come back as a column that wide on the right.
`main.files` is therefore now `main.files.v2`; dropping the old key **is** the
migration, because the number has no meaning across the flip. `main.detail`
deliberately keeps its id — it is ratio mode, and 62/38 still reads as "the
graph gets more" whichever way the divider runs. **Rule: changing a
`GbmSplitPane`'s axis obliges you to decide what happens to its stored value,
and only ratio mode survives the change.**

**The refs column's ceiling moved again, and its doc comment had gone stale in
two directions at once.** It cited a ceiling of 173 bisected against a ~632px
commit list, and explained the 104px default by saying the twelve-lane case
gives up Date. The recomposition took that list to exactly 834px, so the real
ceiling is **287** (at 288 the ladder starts dropping Date) and *nothing* is
given up. Re-measured with a throwaway probe that reads the row's real width
off the rendered widget and then bisects `planCommitRowColumns` directly —
the pure function takes `widths` as a parameter, so no enum constant has to be
mutated to sweep the range. **A comment claiming its bounds are measured has to
be re-measured whenever anything upstream of the measurement moves**, and a
page recomposition is upstream of every width in the row.

**Nothing at any tier covered the page's composition**, which is how three
wrong placements stayed green through several rounds of work on this very page.
`history_page_layout_test.dart` is that cover, and it reads positions off the
**rendered rects**, never off which splitter nests inside which: "the files
column is to the right of the graph" is the requirement, the nesting is an
implementation detail. Both placement decisions are mutation-checked — dropping
`fixedPaneEnd` reddens exactly the files case, swapping the inner children
reddens exactly the other three.

#### A provider written from `build()`, and why no tier saw it

Found by the user running the app, not by any test: selecting branches and
then letting a branch vanish under the selection threw
`Tried to modify a provider while the widget tree was building` out of
`SidebarPanel.build()`. `_pruneSelection` drops selected names that no longer
exist and wrote `branchSelectionProvider` straight from `build()`.

**Pre-existing, not this round's** — the call has been in `build()` since
`4474d550` (the Tier 2+3 multi-select round). Fixed here anyway because this
branch had already reworked the lines around it and a fix off `main` would
have conflicted with the open PR.

**The throw is `assert`-guarded**, which changes what the bug *is*:
`riverpod/src/framework/element.dart` wraps `debugCanModifyProviders?.call()`
in `assert(() { ... }(), '')`, so debug and profile builds crash the sidebar's
build while a **release build strips the assert and lets the write land
mid-frame** — the inconsistent-state risk the message describes. Check whether
a Riverpod guard is assert-wrapped before writing "it crashes" in a report.

**Why no tier saw it, and it is the fixture rule again.** Every existing
sidebar test overrides `repoRefsProvider(...).overrideWithValue(...)` with one
fixed snapshot, and **a snapshot that cannot shrink cannot make a selected
branch vanish** — so no fixture in the suite could reach the code path at all.
`repoRefsProvider` derives from the session (`branch_repository.dart:11`), so
the new test simply leaves it un-overridden and lets `emit()` shrink it. Same
family as the `hasTrackingInfo` fixture and the borrowed `_mergeState()`.

**The fix defers the write rather than moving it to a listener**, and the
reason is the trap this file already records twice: `ref.listen` covers
*changes* only, and `branchSelectionProvider` is not autoDispose, so a
selection outlives the repository it was made in and can already be stale at
the first build with no change event to hang a prune on. Deferring to a
post-frame callback keeps one path for all three entry cases (mount, refs
change, identity change) because `build()` always sees the current pair. The
callback recomputes from the then-current refs instead of the captured list,
so a second refs change between frame and callback cannot write a stale
answer. Mutation-checked in both directions: writing directly reddens all four
failure arms, and simulating a listener-only fix (skip the first build)
reddens **exactly** the two mount arms and leaves the shrink arms green.

Checked while there, since `4474d550` created `commitSelectionProvider` and
`branchSelectionProvider` symmetrically: there is **no commit-side twin** —
`line_history_panel._goToCommit` and `blame_panel`'s "Go to commit" both write
from callbacks. `working_copy_selection_state.prune()` has no caller at all.

#### Harness and process notes

- **A stale `gbm_flutter` instance blocks the whole device tier.** Every
  `flutter test integration_test/... -d macos` failed instantly with
  `did not complete` (and, from the app side, `Failed to foreground app; open
  returned 1`) while a manually-launched debug build from an earlier session was
  still running. `pkill -f "gbm_flutter.app/Contents/MacOS/gbm_flutter"` is the
  fix. It looks exactly like a broken test — **run one pre-existing device test
  as a control before believing the new one.**
- **The device tier flakes on `pumpAndSettle` when run as a batch, and it is a
  different test every time (#101).** Running the eight files back to back
  leaves exactly one failing with `pumpAndSettle timed out` — `context_menu_flows`
  in one batch, `commit_flow_test.dart:67` in the next at **13m28s** — while
  every one of them passes alone. Mechanism confirmed, not guessed:
  `top_bar.dart:99` renders a bare **indeterminate** `CircularProgressIndicator`
  while `isRefreshing`, which schedules frames forever, so a `pumpAndSettle`
  that starts while a post-operation refresh is still in flight can only run out
  its 10-minute default. Batch runs load the machine, the refresh takes longer,
  and the race flips. **This file already states the rule** ("Never
  `pumpAndSettle()` while `isRefreshing` is true", cancel-surface section) — but
  only the widget and integration tiers follow it; `integration_test/` does not.
  **It is not #70**: that one is a fixed 10s `waitFor` budget in C++, this is a
  Dart indeterminate animation. Read the failure text before picking a family.
- **Never reduce a device batch's output to `tail -1`.** On failure the last
  line is the *test name*, not the error, so the whole diagnosis is lost and the
  run cannot be attributed — which is exactly what happened the first time #101
  fired here, costing a second full batch to recover the text.
- **Do not edit `lib/` while a background device-tier run is in flight.** Each
  `flutter test integration_test/... -d macos` recompiles the app from the
  working tree, so a mutation probe applied during the run is compiled into
  whichever tests happen to start after it — and the output cannot tell you
  which. Any green from such a run attests nothing and has to be discarded and
  re-run against a clean tree. Same family as the `git add -A` lesson below:
  the working tree is shared state, and a background job is another reader.
- **Swapping a widget for a design-system one breaks device-tier finders that
  nothing else uses.** `ListTile(dense: true)` → `GbmRow` in the Changed files
  list turned three `context_menu_flows_test.dart` cases red on
  `find.byType(ListTile)`. Neither the widget nor the integration tier goes
  through that finder, so `flutter test` stayed green throughout — **the eight
  device tests are the only thing that sees this class of change**, which is why
  a round that touches shared row widgets has to rerun all of them, one at a
  time.
- **`git commit` after `git add -A <dir>` swept an unrelated in-progress change
  into a `refactor:` commit.** Caught by reading `git diff --stat`'s output in
  the same call; split with `reset --soft` + selective `add`. Stage by file when
  two changes are live in one directory.
- **A `std::span<const ObjectId>` does not accept a braced list** in C++20
  (`initializer_list` construction lands in C++26), so the bridge passes
  `std::span(&record.oid, 1)`.
- **Comparing iterators from two separate `toRevListArgs()` calls compares
  iterators into two different vectors.** The first `--no-merges` test did that
  and failed for that reason rather than for the reason it was written.

### Gone marking after fetch, and log levels (fix/fetch-gone-marking-and-log-levels)

Two symptoms from one user session — 「刪掉遠端分支，然後 fetch」 — that turned out
to be unrelated, and both root causes were confirmed by *running*, not by reading.
Ten sequential commits, each green and independently revertible.

#### Symptom 1: the sidebar never marks anything gone

**`RefInfo.isGone` can only ever be true after a prune.** It comes solely from
git's `%(upstream:track)` reporting `[gone]` (`RefStore.cpp`'s `parseTrack()`),
and **git only reports that once the remote-tracking ref is already deleted
locally**. `FetchOperation::run()` emits `git fetch --all` with no `--prune`
(`FetchRequest.prune` defaults false and no Flutter call site passes it), so the
ref survives, git stays silent, and there is nothing for the sidebar to render.
The refresh itself *does* run (`Session::fetchRemote`'s `onSuccess →
refreshHistory()`) — the reported "no auto-refresh" was a correct observation
with a wrong cause.

**Adding `--prune` is the wrong fix and the spec says so.** P02's
〈遠端分支被刪除時怎麼看得到〉 is explicitly three-stage: mark (half-opacity,
strikethrough, cloud-off, a pending count in the section header) → badge the
tracking local branch and show `upstream gone` in the status bar → **only an
explicit Remote → Prune remote branches actually removes**. `--prune` deletes
the ref silently, which skips straight to stage 3 and makes stage 3 pointless.
P10's mockup does draw `git fetch --prune origin`, but the same panel then reads
「標記為 gone（尚未 prune）」 — it contradicts itself, and per the **Tier 5
precedent the prose wins over the mockup**.

So stages 1–2 need a source of truth that deletes nothing. `git remote prune
--dry-run` is exactly that, and the capi for it already existed
(`gbm_remote_prune_preview` / event 31, previously used only by the Prune
dialog). No new capi function; the whole C++ delta this round is **two
`kind()` overrides**.

**Attribution goes through `Operation::kind()`, never through `describe()`.**
"The next completion event is my fetch" is wrong whenever any of the ~thirty
other methods on the shared channel is submitted in between — which is what
`PendingOperationTracker` exists for, and `OperationRunner.h`'s `kind()` doc
comment names that tracker explicitly. Only `checkout` and `delete-branch` had
overrides; `fetch` and `prune-remote` gained them. Matching on `describe()`'s
`"Fetch all remotes"` would be taking user-facing English as a protocol.

- **Fetch rides event 5, prune-remote rides event 3.** `Session::fetchRemote`
  goes through `submitWorkingCopyOperation`, `pruneRemote` through
  `submitOperation`. One `OperationRunner` queue, one stamping path, two capi
  events — so one kind vocabulary is correct, but the two arms live in different
  handlers. `_handleOperationOutcome`'s switch carries an explicit
  `case PendingOperationKind.fetch: break;` with a comment: popping the fetch
  queue there as well would double-pop and misattribute the next fetch.
- **The exhaustiveness check is the mechanism, not a formality.** Adding
  `pruneRemote` to the enum made that switch a compile error at exactly the
  place the new arm belongs. Neither switch has a `default`, deliberately.

**Preview scope must match what was actually fetched**, so
`remotesToPreviewAfterFetch()` returns `[name]` for a single-remote fetch and
fans out only for `fetch --all`. It derives the remote list from
`refs.remoteBranches` via `remoteBranchParts`, **not** from `state.remotes`:
`_open()` never calls `refreshRemotes()`, so that field is routinely empty and a
`state.remotes`-based fan-out would silently preview nothing.

**The background preview must not be able to raise a banner, and that needed a
mechanism rather than a promise.** `requestRemotePrunePreview` fires
`GBM_EVENT_ERROR_OCCURRED` on failure → `state.lastError` →
`workspace_screen.dart` draws `GbmWarningBanner`; and it has **no askpass
wiring** (`CancellationToken{}`, no `askpassDir`), so an HTTPS remote without
cached credentials fails every time. Left alone, every fetch would flash an
error the user did not ask for, against P10's low-priority-background rule.
`_isSuppressedAutoPrunePreviewError()` matches `GitError.argv` for
`remote`/`prune`/`--dry-run` **plus the remote name**, counted per remote and in
flight only — so the Prune dialog's own failure for a *different* remote still
shows. Recorded limit rather than papered over: an automatic and a
dialog-initiated preview of the **same** remote overlapping produce identical
argv and the dialog's failure is swallowed once; fixing that needs the capi to
carry a request origin.

Costs written into doc comments rather than discovered later: `git remote prune
--dry-run` **contacts the remote**, so each fetch now costs one extra network
round-trip per remote; and `requestRemotePrunePreview` uses `postFront`, which
was meant for the dialog's interactive latency and now jumps N network jobs
ahead of already-queued viewport reads.

#### Symptom 2: a cancelled `for-each-ref` read as a failure

The user's log row was **exit 143** = 128 + SIGTERM.
`Session::refreshHistory()` calls `historyCancel_.cancel()` before posting a new
refresh, so a superseded read is terminated and leaves a
`cancelled: true, exitCode: 143` record. Not a git failure at all.

Three display defects made it read as one, and **the middle one is the real
bug**: `_filteredRecords`' warning predicate (`failed && !cancelled &&
!timedOut`) was a strict **subset** of its error predicate (`cancelled ||
timedOut || exitCode != 0`), so LOGRULES' three levels were not three sets —
picking *error* also showed every warning. Classification is now one function
(`OperationRecord.level`), and **`cancelled` is checked before `exitCode`**
because a terminated child carries both.

**Cancelled is warning, not error** — deliberate: a read superseded by a newer
one is not a fault, and treating it as one is precisely this misreport.
LOGRULES' own error example is a genuinely rejected `git push`.

`escapeControlChars()` renders `\x1f` field separators visibly. It is applied to
the **export** as well as the row, which is in tension with "log records the
command verbatim": the escape is reversible and unambiguous, and the user's own
report arrived with the separators silently deleted by copy-paste, which is what
made the command look corrupt. It deliberately does **not** touch backslashes —
`OperationRecord::commandLine()` (`Logging.cpp:36-38`) already doubles them
inside quoted args, and escaping twice would corrupt what it is trying to make
readable.

#### Things worth knowing before touching this again

- **`RemotePrunePreviewEntry.ref` is a short name** (`origin/x`) while
  `RefInfo.upstream` and a remote row's `fullName` are full
  (`refs/remotes/origin/x`). Comparing the two forms directly never matches and
  the marking would silently never appear. `fullRemoteRefName()` is the one
  idempotent normaliser both directions go through.
- **The two `pruneRemote` call sites disagree on ref form and always have**:
  `prune_remote_branches_dialog.dart` sends short names (`preview.refs.map((e) =>
  e.ref)`), `sidebar_panel.dart`'s `_pruneRemoteRef`/`_pruneGoneUpstream` send
  full ones. An un-normalised removal no-ops for the **dialog** path, which is
  the common one. Mutation-checked: dropping `.map(fullRemoteRefName)` reddens
  five tests.
- **The header count is derived from the rendered tree, not from
  `gonePendingRefs.length`.** A ref the user pruned in a terminal leaves the refs
  snapshot while the pending set still holds it, so the raw count would claim
  「3 待清理」 above zero marked rows. Counting effective-gone rows also means a
  missed B5 cleanup degrades to one stale round rather than a wrong number.
- **Assert prune-clearing on `state.gonePendingByRemote`, never on the sidebar.**
  A really-pruned ref also vanishes from the refs snapshot, so the row
  disappears either way and a rendering assertion goes green with the removal
  logic deleted entirely.
- **A failed prune must still pop its queue entry.** The queue tracks
  submissions, not successes; skipping the pop lets a failed request answer for
  the *next* prune's outcome and clear marks that prune never touched. Same rule
  as fetch, and each has its own test.
- **`_readUndoJournal()` was missing the `_session == nullptr` guard** every
  sibling has, which is why a reducer-level test tripped
  `FakeGbmBindings.noSuchMethod`. The fake seam failing loudly found a real
  robustness hole, exactly as documented.

#### Two defects this round introduced and then closed

- **A non-flex `Text` in the BRANCHES header overflowed by 13px** — the same
  `RenderFlex` rule the narrow-window round is entirely about, repeated one
  round later. **B3's own widget tests could not see it**: they pump
  `SidebarPanel` on the 800px default test canvas, where nothing is tight. It
  surfaced only once `pumpWorkspace` gave the sidebar its real width. Now a
  `GbmBadge` (truer to spec's 「待清理數量」 anyway), with a regression test
  pinned at `GbmLayout.sidebarMinWidth` and mutation-checked at 116px overflow.
  **Rule: a widget test that sizes its own canvas proves nothing about layout
  under real constraints.**
- The status-bar semantics test needed `find.bySemanticsLabel`, not
  `find.byType(Semantics).first` — `MaterialApp` has its own. And a
  `SemanticsHandle` must be disposed **inline at the end of the test body**, not
  via `addTearDown`: teardown runs after `flutter_test`'s handle verification.

#### Process notes

- **`clang-format` is version-sensitive the same way `dart format` is.** CI pins
  version 18 (`cq.yml`); a local 22 reformats pre-existing lines in
  `RemoteApiTest.cpp` that 18 left alone. Running it wholesale swept 40 unrelated
  lines into the diff. Fix: restore the file, re-apply only the intended edit,
  and verify the *new lines* survive the local formatter byte-for-byte. Never
  `git checkout --` a file whose work is uncommitted — copy it to the scratchpad
  first, as this repo already records.
- Deferred to their own issues with evidence, per the approved plan: **#102**
  (Preferences' three `autoFetch*` settings have no consumer at all —
  `Timer.periodic` appears nowhere, so P11 item 9's auto-fetch does not exist),
  ~~**#103**~~, ~~**#104**~~, ~~**#105**~~ — **all three fixed in the very next
  round**, see "Refresh coalescing and app-level log events" below. **#102 is
  still open.** Note that #105's issue text as written here (「cannot be
  expressed by `OperationRecord`, which is git-invocation-shaped and produced
  C++-side」) was half wrong: the shape claim held, the "produced C++-side"
  claim did not, and it changed where the fix went entirely.

### Refresh coalescing and app-level log events (fix/refresh-coalescing-and-app-log-events) — issues #103–#105

The three issues the previous round filed rather than fixed, closed in one
branch. Two of the three turned out to be a different problem than their issue
text described — read this before re-reading them. Six sequential commits, each
green and independently revertible.

#### #104 was not a race, it was a crash — and this repo can prove that

The issue said 「`historyCancel_` 在 worker thread 被改寫，UI thread 同時呼叫
同一個函式，無鎖保護」, which reads as a benign-until-proven-otherwise data
race. It is not benign. `HistoryRefreshApiTest.ConcurrentRefreshesDoNotRaceOn
TheCancellationSource` (4 threads × 25 `gbm_history_refresh` calls) reports,
under ThreadSanitizer, a data race **and then a SEGV** inside
`CancellationSource::cancel()` (`CancellationToken.h:146`, reached from
`Session.cpp:216`): two threads tear `CancellationState`'s callback list apart
and one of them invokes a freed `std::function`.

**`build/tsan` already existed and nothing in these docs said so.** `CMakeLists.txt`
has `option(GBM_SANITIZE "…address,undefined | thread")` and the tree carries
configured `build/tsan` and `build/asan-ubsan` presets. That is what turns "a
race, in principle" into a **falsifiable** test — the exact thing the #77 note
said was unavailable for a scheduling bug. It is not a substitute for #77's
reasoning (a *timing* race still cannot be reproduced on demand), but a
**memory-ordering** race can be, and should be:

```
cmake --build build/tsan --target gbm_capi_tests
./build/tsan/tests/gbm_capi_tests --gtest_filter=HistoryRefreshApiTest.*
```

The fix holds `historyCancelMutex_` (now `refreshMutex_`) across the whole
`cancel()` + replace + `token()` step, not just the assignment: a caller that
observed the old source *between* them would cancel a walk the other one is
about to start. Holding a lock across `cancel()` is safe because the only
callback ever registered on that source is `ProcessRunner::execute()`'s
`child->terminate()` — a signal send that takes no lock of ours.

#### #103: the class was fine, its driver did not exist

`RefreshCoalescer`'s own doc comment names the driver: 「RepositorySession owns
one single-shot QTimer, restarted (`QTimer::start(kDelay)`, which Qt restarts
if already running) on every request() call that returns Arm」. That Qt
`RepositorySession` is gone from this tree, capi has no event loop of its own
(the same reason `AskpassPoller` runs its own thread), and `ThreadPool` has no
delayed post. So connecting the coalescer meant **building the timer first**:
`src/core/workers/DelayTimer.{h,cpp}`, whose `arm()` deliberately reproduces
`QTimer::start()`'s restart-if-running semantics rather than inventing new
ones.

**The symptom reproduces deterministically**, which is worth knowing because
the user reported it from a real session and it looked untestable:
`ABurstOfRefreshesTerminatesNoGitProcess` fires eight `gbm_history_refresh`
calls 15 ms apart and, before the fix, logs **7 records with `exitCode: 143`,
`cancelled: true`**. The spacing is the whole trick — each call needs a chance
to actually start its child before the next one arrives, which is what the
shipping app does and what a tight loop does not.

Three things about the integration are worth keeping:

- **Publishing needs a monotonic gate, not an equality check.** Once superseded
  walks are no longer cancelled, a stale one can still be streaming chunks —
  and its `complete:true` would tell Dart the *newer* walk had finished.
  `publishedGeneration_` is compared and written inside the same `graphMutex_`
  critical section as `refs_`/`graph_` (`claimPublishLocked`). Comparing
  against `RefreshCoalescer::currentGeneration()` alone leaves a window between
  the check and the store, and a stale snapshot overwriting a newer one is
  worse than the log noise this whole change exists to remove.
- **`onFinished()` on every terminal path, via a scope guard.** Miss one and
  the coalescer stays `running_` forever, every later request folds into a
  batch nothing will drive, and **refreshes stop happening at all — silently,
  with no error anywhere.** `dispatchRefresh()`'s lambda has three early
  returns, so it uses a `ScopeExit` rather than a call per path. Same lesson as
  Tier 0c's `submitOperation` `onAlways` hook.
  `RefreshesStillWorkAfterABurstHasSettled` is the lock, and it goes red *by
  timeout* when the guard is deleted — mutation-checked, and the other three
  cases stay green.
- **`setHistoryFilter()` is now the only routine caller that cancels anything.**
  It uses `fireNow()` because the Flutter side already debounces the filter box
  by 250 ms, and it genuinely supersedes a walk whose filter is already wrong.
  A deliberate, user-initiated filter change leaving one `cancelled` record is
  honest; the per-operation churn was not.

**Cost, measured**: `ctest` went 124 s → 134 s, entirely from the 150 ms window
now sitting in front of every refresh. Worth watching against **#70**, whose
budgets are 10 s — 150 ms is far inside them, but the direction is the wrong
one.

`~Session()`'s ordering gained a step, and the position is not arbitrary:
`refreshTimer_.stop()` goes **after** `operations_->drain()` (those completion
callbacks are one of the two things that arm the timer) and **before**
`sharedReadPool().cancelQueuedAndDrain()` (firing the timer posts a *new* task
onto that pool). `DelayTimer::arm()` is a no-op after `stop()`, so a late arm
from a still-unwinding completion path cannot resurrect it.

#### #105's premise was wrong: there is no C++-side log at all

The issue said app-level events 「需要新的記錄型別 + capi 改動」. Checked
directly before designing anything: `src/core/base/Logging.{h,cpp}` has
**sinks and nothing else** — no file writing, no rotation, no storage (`grep
ofstream|fopen|rotat src/` hits only blob/askpass/rebase paths). The entire log
is `RepoSessionState.operationLog`, fed by `GBM_EVENT_OPERATION_LOG_RECORD`. So
an app-level event needs **no capi whatsoever**; the whole fix is Dart-side.

`GbmLogEntry` is the sealed supertype of `OperationRecord` (one git invocation)
and the new `AppLogEntry` (an event with no process). Sealed so the drawer's
rendering *and* its plain-text export must both handle every kind — those two
already drifted apart once, which is what the previous round's `level` fix was
about. Both members live in `operation_record.dart` because a sealed type's
subtypes must be in the same library.

`AppLogEvents` (`data/models/app_log_events.dart`) is a factory rather than
four constructor calls scattered through the controller, for two reasons that
are not style: the **wording is a product surface** (`LOGRULES` 匯出:
「回報問題時附這份即可，不需要另外重現」), and `LOGRULES`' 不記什麼 rule
(認證資訊、remote URL 中的 token、檔案內容) is easier to keep when one place
builds every line. Note what the four take: a work-tree path, a branch name, a
remote **name**, ref names — never a URL, which is where a token would live.

Two decisions recorded rather than left to be re-derived:

- **The lines are English.** The spec's wording is Chinese because the spec is;
  every string in this app is English, and page 10's mockup row is describing
  content, not dictating language.
- **The gone-marking log diffs against what is already marked.** An automatic
  prune preview runs after *every* fetch (previous round), so logging the whole
  preview would repeat the same warning on every fetch until the user pruned.
  `_logNewlyGoneRefs()` therefore runs **before** the state update and is
  judged per remote — `gonePendingByRemote` is per remote, and a shared set
  would swallow `upstream/a` because `origin/a` was seen first.

#### The one emit site no widget test can reach, and how to see it anyway

「開啟 repo」 is emitted in `_open()` right after `isOpen: true`, which
`FakeRepoSessionController` **never executes**: its `FakeGbmBindings.sessionOpen()`
returns `nullptr` by design, so `_open()` returns before allocating a handle.
The factory pins the wording at unit tier; the emit site is covered by
`integration_test/repo_lifecycle_test.dart` at device tier, and getting that
assertion to work taught two things:

- **`find.text` cannot see the oldest entry in the log drawer.** The list is
  `reverse: true` with a `ListView.builder`, so by the time the git records for
  open + checkout exist, 「Opened repository …」 has been scrolled out of the
  viewport and was never built. Reading `tester.widget<LogDrawer>(…).records`
  asserts the data instead — which is also what the widget-tier reachability
  test already does, for a different reason.
- **Do not assert a temp path verbatim on macOS.** `/var/folders/…` and
  `/private/var/folders/…` are the same directory, and which one arrives
  depends on who canonicalised it. `startsWith('Opened repository ')` is the
  claim being made anyway.

#### Smaller things

- `shortRemoteRefName()` joins `fullRemoteRefName()` in
  `remote_prune_preview_entry.dart`, equally idempotent. Display only — every
  *comparison* in this codebase is on the full form.
- `RepoSessionState.operationLog` is now `List<GbmLogEntry>`. Its cap is
  unchanged and shared: `LOGRULES` 保留 caps the log, not each kind of entry
  separately, so an app event and a git record compete for the same 500 slots.
- **`clang-format` version drift fired again, and the config decided it.** A
  local v22 wanted a blank line between `ScopeExit`'s one-line constructor and
  its destructor. That is `SeparateDefinitionBlocks: Always` in `.clang-format`
  — an option that exists since v14, so CI's pinned v18 applies it too and the
  change was safe to take. **Check whether a formatter suggestion comes from
  the repo's own config before assuming it is a version artifact**; the
  previous round's rule ("never run it wholesale") still holds for everything
  that does not.


### P02 item 2's toolbar (feat/p02-action-toolbar)

Spec page 02's numbered item **2** is the toolbar row directly under the menu
bar: `Fetch` / `Pull` / `Push` with Push carrying the primary emphasis, a
divider, then `Branch` / `Stash` (`spec_raw.html:1245-1255`). **None of it
existed under `lib/`.** Fetch/Pull/Push had exactly two entry points — the
keyboard shortcut and the Repository menu — and `top_bar.dart` held only the
back button, the repository name, the state label, `Refresh` and the three
theme swatches.

#### The premise that did not survive: what row 2 of the matrix was measuring

`docs/reports/spec-conformance-matrix.md` recorded P02 item 2 as **符合**,
titled 「Fetch/Pull/Push disabled during conflict」, with
`gbm_action_availability.dart:33-45` as its evidence. Both halves of that are
about the *gate*. Item 2 is about the *surface*: 「三顆同組。Push 為主要樣式。」
describes buttons, and 「conflict 狀態全部停用（見 07）」 is a clause attached to
them, not the item itself. So the row proved that three action ids would be
greyed out, in a bar nothing drew. The P07 STATES section carried the identical
defect one screen further down (「Toolbar Fetch/Pull/Push disabled」, same
evidence, same 符合).

This is the fourth time on this page alone that a row passed by checking a
different claim than the one written next to it — items 11, 12 and 14 were all
overturned the same way in earlier rounds. The distilled form is now in
CLAUDE.md: **a matrix cell whose evidence is `isActionEnabled()` proves the
gate exists, never the gated surface.**

#### Three vs five buttons

Only Fetch/Pull/Push have prose behind them — item 2's own note, P07's STATES
row (「三顆停用」) and P16's REVISIONS (「工具列 F / P / P 三顆同組，不能拆」).
Branch and Stash appear only in the mockup, which by this repo's own rule
(「A mockup shows what the user sees, not who draws it」) is not by itself a
requirement.

Built all five anyway, and the reasoning matters more than the outcome: the
prose-wins rule exists to settle **contradictions** (P10's `--prune` mockup vs
its own 「尚未 prune」 prose is the recorded case). Here there is nothing to
overrule — the prose is silent about Branch/Stash rather than against them, and
the spec's own icon choices name what they do: `git-branch-plus` is New branch,
`inbox` is Stash changes. Both handlers (`branchNewBranch`,
`branchStashChanges`) already existed in `_buildActionHandlers()`.

#### Why a new row rather than folding it into TopBar

`TopBar` occupies the same slot the spec gives the toolbar, so merging was the
obvious-looking move. It was rejected for two reasons already written down
here: `TopBar` is the one piece of chrome with **no** `Expanded >
SingleChildScrollView` guard (the narrow-window round found that by grepping
all four rows for the pattern the other three shared), and its ~327px non-flex
floor is a **measured** number carried in a source comment — anything added
upstream of it obliges a re-measurement. A separate `ActionToolbar` copies
`menu_bar_row.dart:97`'s guard, leaves `top_bar.dart` and its four
narrow-window tests untouched, and stays independently testable like
`MenuBarRow`/`TabRow`. Cost: one more 38px chrome row (three on macOS, where
`MenuBarRow` is not drawn). The extra row does not disturb
`workspace_narrow_window_test.dart`'s 800×600 chrome control.

`ActionToolbar` is drawn on **all three platforms**. Page 01 says only the menu
bar's *position* follows the system; macOS moving its menus into the system bar
says nothing about a toolbar.

#### The assertion that could not fail, and the one that replaced it

Branch and Stash are gated by the identical predicate and both do nothing but
`context.push(...)`. So the natural integration assertion — `onPressed` is
non-null when clean, null when conflicted, for all five — **stays green when
the two handlers are swapped**. Mutation-checking caught it: wiring `onStash`
to `GbmActionId.branchNewBranch` produced no red at all. That is the
「fixture that cannot disagree with the code」 shape again, in its fifth recorded
form: *two subjects the assertion cannot tell apart*. Registering sentinel
`dialogRoute`s for `newBranchDialog` and `stashChangesDialog` and asserting
which one opens is what makes the swap visible.

Three more mutations behaved: `onFetch: null` reddened the three clean-state
tests; `onFetch` bypassing the handler map straight to
`RepoSessionController.fetchRemote` (the orphan-wiring shape
`workspace_intent_dispatch_parity_test.dart` exists for) reddened both
conflict-state tests; removing the scroll guard reddened only the two 320px
tests.

#### Smaller things

- **The four new Lucide SVGs were fetched, not hand-authored.** The standalone
  spec renders them through `window.lucide.icons` (`spec_logic.js:706-715`) and
  embeds no path data (grep: 0 hits), so there was nothing to copy out of it.
  The normalisation applied to `lucide-static` v1.34.0 (drop the `@license`
  comment and the `class` attribute, `stroke` → `#000000`) was **verified by
  running it on `cloud-download.svg` and diffing against the copy already in
  the repo** — byte-identical, which is also how the version was pinned.
  Recalling a path from memory would have been a coin flip on
  `git-branch-plus` specifically.
- **Spec's `download-cloud` is Lucide's `cloud-download`**, already bundled;
  Fetch reuses it rather than adding a second copy of the same glyph.
- Icons go into `app_flutter/assets/icons/` only. `resources/icons/` is a stale
  16-file copy — `cloud-off`, `columns-3` and `grip-vertical` exist only on the
  app side, and `pubspec.yaml` packages only the app side.
- **Adding a widget can break an unscoped `find.text` two files away.**
  `_repositoryMenuItemColor()` in `workspace_conflict_transition_test.dart` read
  `find.text('Fetch')` with no scope, which was unambiguous only while the menu
  was the sole place that word appeared. `_GbmMenuPanel`/`_GbmMenuRow` are both
  private, so there is no type to scope to positively; the helper now excludes
  the `ActionToolbar` subtree instead.
- **Recorded reduction — Alt+click on toolbar Pull.** P17's Pull dialog note
  says 「這張預設不出現 — 工具列的 Pull 直接用 Preferences 的預設套用方式走。
  只有選單的 Pull… 或 Alt + 點工具列才開。」 `route_paths.dart` has no pull
  dialog route at all, so there is nothing for Alt+click to open. The plain
  click implements the first half (`pullChanges()` with the configured default);
  the modifier path is absent and tracked on **#109**, not faked.

#### What the verification does and does not cover

The plan's 驗證 section ended with 「實機：`flutter run -d macos`…肉眼確認工具列
位置/樣式/圖示」. **That human visual pass was not performed, and is recorded here
rather than left implied by the green suite.** Two substitutes were run instead,
and they cover different halves of the risk:

- **Device-tier finder ambiguity: checked, nothing to do.** Adding five
  permanently-rendered words (`Fetch`, `Pull`, `Push`, `Branch`, `Stash`) is
  exactly what broke `_repositoryMenuItemColor()` in the widget tier, and
  `flutter test` never runs `integration_test/`, so its green says nothing about
  the device tier. Grepping every finder in `integration_test/` for those five
  words and for un-scoped `byType(GbmButton)` / `byType(LucideIcon)` returned
  one hit — `rename_branch_flow_test.dart:137`'s `find.text('Rename Branch')`,
  which is a dialog title and does not collide (`find.text` is exact-match, so
  `'Rename Branch'` never matches `'Branch'`). No device file needed rerunning.
- **Icon rendering: rasterised, not just bundled.** The earlier check only
  proved the four SVGs ship in the asset bundle and parse as strings — which a
  file drawing nothing would also pass. A temporary test (run, mutation-checked,
  then deleted) loaded each of the five toolbar icons through
  `vg.loadPicture(SvgAssetLoader(...))` — the exact path `LucideIcon` uses —
  called `Picture.toImage()`, and counted non-transparent pixels. All five
  painted. Replacing `inbox.svg` with a well-formed but empty `<svg/>` reddened
  that one test and only that one, so the assertion is falsifiable and narrow.

What neither covers, and what the deferred pass would have: that each glyph is
the *intended* one (a rasterised heart passes a "painted something" test), and
that the row's position, height and spacing look right in a real 1280×720
window. The first is mitigated by provenance rather than by assertion — the
files came from `lucide-static` v1.34.0 and the transform was proven
byte-identical on an icon already in the repo — and the second is what the
800×600 and 320px widget tests approximate.

One trap worth carrying: **`Picture.toImage()` inside `testWidgets` hangs
forever without `tester.runAsync()`**, with no output and no timeout of its
own — the first attempt was killed at eight minutes having printed nothing.
flutter_test's fake-async zone never completes it.
