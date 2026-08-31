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

## Adding a round — not here any more

**This file is closed to new rounds.** Write yours as its own file,
`docs/ledger/<YYYY-MM-DD>-<branch>.md`, and add one line to
[docs/ledger/INDEX.md](ledger/INDEX.md). The shape is unchanged; only the
destination is. See [docs/ledger/README.md](ledger/README.md).

The reason is in this file's own record, under "Sidebar continuation":
appending every round to one end-of-file made a conflict certain for any two
parallel branches — "git saw one region replaced two ways". One round per file
removes the shared append point entirely.

The 101 rounds below stay here, in place and byte-identical. Migrating them
would break the two properties the preamble above calls load-bearing: a record
you can checksum, and "above"/"below" cross-references that only resolve while
the order is intact. History is never appended to again, so it cannot conflict.

Distillation also moved: it goes to [docs/rules/](rules/), one file per
category, in the four-field shape [docs/rules/README.md](rules/README.md)
specifies — not to CLAUDE.md's "Invariants and traps", which no longer exists
as a section there.

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

### Changed files line counts (feat/changed-files-line-counts)

Spec P02 item 10's mockup draws each Changed files row as `檔名 + 綠色 +12
badge`. The panel drew only the檔名. This round carried added/removed line
counts from git to that badge, through all four layers.

#### The gap was already written down — as the reason for a *different* cut

`commit_selection_summary.dart` explains why P13's status-bar 合計 diff was cut:

> **Reduced deliberately: no 合計 diff.** … `ChangedFile` carries no
> added/removed line counts, and the only path in the core that runs
> `--numstat` is `CompareOps.cpp`'s range diff — so a running total would mean
> firing a range diff on every selection change.

That was accurate about the cause and it named the fix, but the *other* feature
sitting on the same missing field — P02-10's badge, which needs no running
total and no range diff, only the counts for one commit — was never filed. The
note is now corrected in place to say the field exists; the 合計 diff stays
absent for its own separate reason (it would still have to sum across a
selection). **A reduction note names one victim of a missing capability; it is
not a survey of them.** Grep for other readers of the thing being called absent
before assuming the note covers the whole blast radius.

#### `--raw` and `--numstat` cannot be the same invocation

git's diff-options output-format is a single slot, so `diff-tree --raw
--numstat` silently honours one of them. `CompareOps.cpp`'s `readFiles()`
already worked around this for the Compare tab by running two commands and
joining by path; `DiffService::attachLineCounts()` is the same shape for
`changedFiles()`. What that costs and what pays for it:

- The numstat pass makes git actually compute the diff, so `changedFiles()` is
  no longer as close to free as `diff-tree --raw` alone. `ChangedFile`'s own
  「Cheap: no content is read, so clicking through commits stays instant」
  comment was rewritten rather than left standing — **a comment asserting a
  performance property is a claim, and the round that invalidates it owns it.**
- The join happens *before* `fileListCache_.put()`, so a cached list is never
  one missing its badges, and clicking back to a visited commit re-runs
  nothing.

#### Every flag on the raw call had to be repeated, and each one fails silently

This is the whole risk of the change, and all three failure modes look
identical on screen — a file listed with no badge, no error anywhere:

| Missing flag | What numstat returns | Which commits lose their badge |
|---|---|---|
| `--root` | nothing | the first commit of every repository |
| `--diff-merges=first-parent` | nothing | every merge |
| matching `rawRenameFlag()` | a different path set | renames, which then join to nothing |

Each is pinned by a test that fails *alone* under that mutation:
`ReportsLineCountsForARootCommit`, the line-count assertion added to
`ReportsAMergeCommitAgainstItsFirstParent`, and
`JoinsLineCountsOntoARenamedFileByItsNewPath`. Measured, not reasoned about —
each flag was removed in turn and the red confirmed narrow.

#### `-z` numstat spends three records on a rename

Every other change kind is one record (`added\tremoved\tpath`). A rename is
`added\tremoved\t` with an **empty** path field, then the old path, then the
new path. A loop that assumes one record per entry reads the old path as the
next entry's counts and every count after that point is wrong — not missing,
*wrong*, which is worse. Mutation-checked by collapsing the three-step to two:
only the rename test went red.

#### The join key is `path`, and the reason is narrower than it first looks

The implementation comment first claimed a join on `oldPath` would break
deletes. Mutating the key to `oldPath` proved otherwise: `parseRawRecords()`
leaves `oldPath` **empty** for everything except renames and copies, so such a
join breaks nearly everything and the delete case is not special at all. Both
the comment and the test's rationale were corrected to the true reason —
`path` is the only field populated for every kind. **A mutation that fails to
land where the comment predicted is the comment being wrong, not the mutation.**

#### Binary reads 0/0 and no `binary` flag was added

numstat prints `-` for a binary blob. `std::from_chars` leaves its output
untouched on a non-numeric field, so a missing check produces 0/0 *by
accident*; the guard is explicit anyway so a later reader cannot mistake the
zero for a measurement. A `ChangedFile::binary` field was deliberately **not**
added: no UI would have read it, which is exactly the orphan-wiring shape this
repo has shipped at least five times (**#102**).

#### The 186px test is the only one that could see the layout bug

Four widget tests cover the badge. Removing the `Expanded` around the path
`Text` — a real overflow at the column's true width — was caught by **only**
the test that sizes itself to `GbmLayout.splitterMainFiles.defaultExtent`.
The other three, on the default 800×600 canvas, passed with the broken layout.
Same mechanism as the column-picker popover that shipped off-screen.

#### Deliberately not done

- **No file icon.** P02-10's mockup row is `icFile + 檔名 + badge`; only the
  badge was added. Compare's file rows are also icon-less, and matching the
  shipped precedent beat matching the illustration. Recorded here so the next
  conformance audit reads it as a decision rather than filing it as a bug.
- **Working Copy (P03) still has no counts.** Its `+34` comes from
  `StatusService`/`WorkingCopyEntry`, an entirely separate data path needing
  its own numstat runs against index and worktree. Out of this round's scope
  by explicit decision, not oversight.

#### Smaller things

- `JsonCodec.cpp` has **two** serializers emitting `addedLines` — `DiffFile`'s
  (pre-existing, for Compare) and `ChangedFile`'s (new). A mutation script
  anchored on the field name alone matched both and the `count(old) == 1`
  guard caught it. That guard earns its keep; the anchor had to include the
  neighbouring `similarity` line to be unique.
- The Dart fields are `required` with no default. Five fixtures broke and were
  updated by hand, which is the point: a default of 0 would have made every
  one of them silently assert "no badge".
- `model_parsing_test.dart`'s ChangedFile case is named 「decodes every field」
  and did not decode the new two. A test whose name is a completeness claim
  has to be revisited whenever the shape it covers grows.
- **The commit that made those fields `required` was red on its own**, and the
  full-suite run that would have shown it happened one commit later. Commit 3
  shipped the model plus five of the six fixture sites; the sixth,
  `model_parsing_test.dart`, was filed with commit 4 because that is where its
  *assertions* belonged. But `fromJson` reads `json['addedLines'] as int`, so a
  fixture without the key is `null as int` — checking out commit 3 alone fails
  two tests. Caught by review, not by any run, because every run was at the
  branch tip. Commits 3–6 were rewritten to move the file (the resulting tree
  is byte-identical: `git diff` against a backup branch was empty), and each of
  3 and 4 was then checked out detached and verified green — 1930 and 1934
  tests respectively. **Rule**: a commit that adds a `required` field to a
  model must carry every fixture that constructs *or feeds* it, including raw
  JSON fixtures, which grep for the constructor name will not find.

### Sidebar branch rows: P02 item 12 and P13 (fix/sidebar-p02-branch-rows)

Five complaints about the sidebar's branch rows — a checkbox that should not
exist, checkout on single click, hover that never shows, a ragged actions
column, and branch names still carrying their folder prefix. Unpacking the
spec (`python3 tools/extract_design_spec.py`; the HTML is a gzip+base64
bundle) showed four of the five are one change seen from four sides, and the
fifth is independent and small.

**P02 item 12** (`spec_logic.js:490`): 「Local 與 remote 不再分兩段…名稱中的斜線
自動摺成資料夾。」 Its companion mock `BRANCH_TREE` (`spec_logic.js:337-347`)
lists `graph-lanes`, `lfs-prune`, `worktrees` under a `feature` folder — the
last segment, not the full path.

**P13 `MULTIKEYS`** (`spec_logic.js:295-304`) defines the branch list's
selection model, and it is **entirely modifier clicks and keys — there is no
checkbox anywhere in the spec**. Its first row is 「單擊 ＝ 只選這一項，anchor
移到這一項」. The app had it the other way round: single click checked out, and
selection was driven by a `Checkbox` the spec never asks for.

#### Why removing the checkbox could not be done on its own

`branch_tree_item.dart`'s `selected` parameter had exactly **one** consumer in
the entire widget — the checkbox's `value:`. The row background keyed off
`ref.isHead` alone. So deleting the checkbox without first giving selection a
background would have made selection a completely invisible state, which is
the `material_state_hidden` violation the UX rubric's D dimension exists to
catch. The commits are ordered so no intermediate revision is ever in that
shape.

#### Premises that did not survive the source

- **`sidebar_panel.dart:305-307` claimed the Shift range was measured over
  「the rows as rendered」. It was measured over git's ref order.** The same
  file, ~20 lines later, said so outright about the same function: 「Deliberately
  not `_selectableBranchNames().first`: that list is **in ref order**」. Two
  contradictory claims about one function, with the code backing the second.
  With branches `alpha, beta, delta, gamma` the sidebar paints them
  alphabetically, so Shift-clicking alpha then gamma must take `delta` with it —
  and the ref-ordered list silently dropped it. `_extendBranchSelection`
  (Shift+↑/↓) had the identical defect. Fixed by walking the built tree during
  `build`, exactly as the neighbouring `_firstResultName` already does for the
  same reason.
- **The existing Shift test could not fail on this.** It was named 'Shift-click
  takes a range over the rendered rows' and asserted
  `containsAll(['alpha','beta','gamma'])` — a superset check satisfied by both
  the rendered-order answer (4 rows) and the ref-order one (3). A test named
  for the very property it cannot observe.
- **`sidebar_narrow_width_test.dart`'s fixture comment asserted the bug as
  fact**: 「a leaf nested under folders still shows the whole slash-separated
  path… the obvious guess ("the leaf shows its last segment") is **wrong**」. The
  obvious guess is what the spec's own mock draws; the comment was describing
  the defect, discovered by dumping rendered Texts and then written up as
  intended behaviour.
- **`_kMaxIndentedDepth`'s justification was consumed by this round.** Its doc
  comment capped the indent at depth 3 partly because 「a branch leaf renders its
  *full* slash-separated name anyway, so the indent is not the only thing
  expressing the hierarchy」. Printing only the last segment removes precisely
  that fallback, leaving a depth-4 row with neither indent nor prefix. Rows past
  the cap now print the full name again, which is the compensation the cap was
  already leaning on. Its 「~93px … on a checkbox, an icon and the actions
  button」 measurement was re-stated too, since the checkbox is gone and the
  button became a fixed slot.

#### Found by running, not by reading: the gesture arena

The plan said to wire selection to `GbmRow.onTap` and accept the delay. That
did not survive contact.

An `InkWell` carrying **both** `onTap` and `onDoubleTap` makes Flutter's
gesture arena withhold the tap until `kDoubleTapTimeout` (~300ms) — the
`DoubleTapGestureRecognizer` does not concede before then. First measurement:
11 sidebar tests failed, and `Ctrl/Cmd-click toggles rows` reported
`Actual: []` because `pumpAndSettle()` returns before the window closes. The
fix would have been to teach ~11 tests to pump 300ms — i.e. to encode a lag
as if it were behaviour, on the sidebar's most-used interaction. Selection
moved to `Listener(onPointerDown:)`, which never enters the arena; the timing
failures vanished in one step. This is not a second source of truth: select
and checkout are two different actions on two different triggers.

Two further consequences only a run would surface:

- **A double-tap recognizer anywhere on the ancestor path taxes every child
  button.** With `onDoubleTap` on `GbmRow`, pressing a row's ⋯ button waited
  ~300ms for its own menu, and two gone-row tests failed because the second
  menu never opened. Both primary gestures moved down onto the row *body*,
  where the button is a sibling rather than a descendant. Hover survives that
  because `InkResponse.isWidgetEnabled` is
  `_primaryButtonEnabled || _secondaryButtonEnabled` (read from the SDK source,
  not assumed) and every row always passes `onSecondaryTapDown`.
- **Selecting from a whole-row Listener made opening a menu mutate the
  selection.** Instrumenting the failing test printed `1 selected` after a mere
  ⋯ press: the action bar appeared and pushed every row down. The Listener now
  wraps only the row body, so the body selects and the actions button does not.

`GbmRow.onDoubleTap`, added in this round's first commit, ended up with no
caller under `lib/` once the double-tap moved to the body — orphan wiring of
exactly the shape CLAUDE.md names — and was removed again in the same branch.

#### The alignment is structural, not tuned

The folder indent is `EdgeInsets.only(left:)` (`sidebar_panel.dart`), so it can
never touch a row's right edge: every leaf's right inset is already constant at
any depth. What actually broke the column was the ⋯ button rendering only when
one of four branch callbacks was set — which a **tag** row never has. The TAGS
section had a hole in the column, and a tag's 05-D menu had no visible entry
point at all. Every row kind's `_buildMenuItems()` is non-empty, so every row
now gets the button, inside a fixed-width slot.

The alignment test measures the slot rather than `find.byTooltip`, because a
`Tooltip` measures the icon's painted box and sits a pixel inside the tap
target. The panel-edge inset is three nameable terms — `space2` + `space1` +
the 1px right border the panel paints — with no slack left over. Mutating the
indent to `EdgeInsets.symmetric` fails the depth-invariance test and nothing
else, which is what makes that test worth having.

#### Deliberately not done

- ~~**`BRANCH_STATES` says the current branch is 「永遠置頂於所屬資料夾內」.**~~
  ~~`sidebar_panel.dart` pins it above the whole tree, and only while
  filtering.~~ **Done in the continuation below**, at the user's request.
- ~~**`sidebar_panel.dart` is ~1,700 lines**, past the project's own 800
  ceiling.~~ **Done in the continuation below**, as a behaviour-free move
  after the pinning fix landed.
- **Tag rows moved to double-click checkout** along with branches. No test
  covered a tag row tap either way; the context-menu path is unchanged.
- This round partially audits **P13 section B** (`MULTIKEYS`, `MULTIACTS`,
  `MULTIBRANCHMENU`), which **#76** still lists as unaudited.

#### What the verification does and does not cover

`flutter analyze` clean, 1,970 widget/unit/integration tests green,
`dart format --set-exit-if-changed` clean on all 14 touched files. Every new
test was mutation-checked and the red was recorded; two are worth keeping:
reverting the range to ref order fails exactly the two order-dependent tests
and leaves the alpha→beta Compare test green (2 items either way), and
mutating the folder indent to `EdgeInsets.symmetric` fails the depth-invariance
test and nothing else.

**The device tier earned its keep this round.** `repo_lifecycle_test.dart`'s
「switch branch via sidebar updates HEAD」 failed with `Expected: 'feature',
Actual: 'main'` — the old single-click contract, asserted against a real git
repository. `flutter test` never runs `integration_test/`, so the widget tier's
green said nothing about it. **All nine macOS device files pass**, one file at
a time, after updating that one to a double-click: `repo_lifecycle`,
`commit_flow`, `rename_branch_flow`, `context_menu_flows`,
`commit_file_counts`, `conflict_flow`, `history_filter`, `multi_push_flow`,
`update_check_flow`. The last five were run even though grepping their finders
showed none of them taps a branch row, because this round adds a `Material` and
an always-painted `IconButton` to **every** sidebar row — a widget-tree shape
change, which is precisely the class the ledger already records as breaking a
finder two files away from the edit. `commit_flow_test.dart:54`'s
`find.byType(Checkbox).first` was a live risk — the sidebar's checkbox used to
sit earlier in the tree than the working copy's — and removing it made that
finder unambiguous rather than breaking it.

**Hover needed two tests, and neither subsumes the other.** Mutating
`hoverColor` to `Colors.transparent` fails only the new pixel-diff test
(`branch_tree_item_hover_paint_test.dart`, which rasterises the row before and
after a real mouse move). Dropping `hoverColor` entirely — *the bug this round
fixed* — fails only the token-identity assertion in
`branch_tree_item_row_chrome_test.dart`, because ThemeData's ~4% fallback does
change the pixels, just not perceptibly. A pixel diff alone would have called
the original bug fixed.

**Removing the checkbox removed the row's only keyboard-focusable control, and
that is the spec's model rather than an oversight.** `GbmRow`'s `InkWell` now
has no primary tap callback (selection runs off `Listener`), so nothing in a
branch row takes focus by Tab. `Ctrl/Cmd+A` and `Shift+↑/↓` still work, but only
after a mouse click has handed focus to the tree — which is exactly what
`MULTIKEYS` describes, since every entry in it is a pointer gesture or a
modifier on one. Recorded so the next round reads it as a decision; if
keyboard-only selection is ever wanted it is a new spec question, not a
regression of this one.

**No human looked at it.** The plan asked for a `flutter run -d macos` eyeball
pass on hover and on the 等距 column, and that was not performed; it is recorded
here rather than left implied by a green suite. The device runs do launch the
real app, and the two hover tests bracket "paints nothing" and "paints the
wrong colour" between them, but neither is a person confirming the highlight
reads as a highlight at a normal viewing distance.

### Sidebar continuation: pinning, and the 800-line split (fix/sidebar-p02-branch-rows)

Same branch, second pass. The user picked three of the four items the section
above listed as deliberately not done — the `BRANCH_STATES` pinning drift, the
1,700-line panel, and back-filling **#76** — and asked for `main` to be merged
in on the way. Only the human visual pass was left, because it cannot be
delegated to a test.

#### `main` merged first, and the conflict was two appends

`main` had moved six commits ahead (`feat/changed-files-line-counts`, PR #111).
The only conflict was `docs/ledger.md`, and it was structural rather than
semantic: both branches append a new section at the end, so git saw one region
replaced two ways. Resolved by keeping both, `main`'s first — it landed on
`main` first, and the file is chronological. Merging before touching code was
deliberate: the merge brought capi JSON changes across the FFI seam, and every
later verification run should be measuring the merged tree, not this branch's
older one.

#### The pinning rule is two rules, and they were both wrong in different ways

`BRANCH_STATES`' 目前分支 row reads 「名稱加粗、整列以 selected 底色標示，**永遠
置頂於所屬資料夾內**，且**不受 filter 影響**」. The code pinned the current branch
above the *entire* tree, and only while a filter was active — so it failed the
folder clause always, and the "永遠" clause whenever no query was typed.

**`BRANCH_TREE` settles the folders-vs-pin question**, which the prose alone
does not: the mock draws `main` (`current: true`, `depth: 0`) *above* the
`feature` / `bugfix` / `release` folders at the same depth. So at any level the
pin outranks the folders-before-leaves rule rather than yielding to it. (The
mock's own folder ordering is *not* alphabetical — `feature`, `bugfix`,
`release` — and was deliberately not read as a requirement; "a mockup shows
what the user sees, not who draws it".)

**The ordering half went into the comparator, not the panel.** Sorting a level
is the only place that knows what "its own folder" means, and every level goes
through `_compareTreeNodes`, so one `isHead` clause covers the whole tree at
every depth. A detached HEAD pins nothing and the tree sorts as it always did;
only one ref can be HEAD, so two pinned nodes never have to be ordered against
each other.

**The filter half turned out to be a deletion, not an addition.** The old code
removed HEAD from `filteredBranches` and prepended a separate row above the
tree — and a row rendered outside the tree *has no folder to sit in*, which is
precisely why it had to be hoisted. Adding HEAD back into `buildBranchTree`'s
input instead makes the whole special case disappear: the builder recreates the
ancestor folders the query had dropped (a pinned row cannot appear inside a
folder that is not drawn), and the comparator then puts it first inside them.
Two consequences had to be chased down, and each is now its own mutation-checked
test:

- `_firstLeafName` gained a `skip`, because P02-14 rule 9's ↓ must not land on
  a row the query excluded — and now that the pin leads its own folder, that is
  exactly the row the walk reaches first.
- the `No matches` empty state was keyed on `branchTree.isEmpty`, which stops
  being a test for "nothing matched" the moment the tree always carries HEAD.
  It reads `filteredBranches.isEmpty` now.

Matched on `fullName` rather than identity: `RefInfo` has no `operator ==`, so
`contains` compares object references and would silently start re-adding a HEAD
that *did* match if `filterBranches` ever stopped returning the caller's own
instances.

**Rule 7 and `BRANCH_STATES` disagree on paper, and the reading is recorded on
purpose.** P02-14 rule 7 says a bare 「目前分支永遠置頂顯示」. Under the fix, a
matching folder that sorts before HEAD's folder renders *above* it — the test
asserts `['chore/docs', 'feature/zeta']`, HEAD second. `BRANCH_STATES` is the
specific rule and it scopes 置頂 to the folder, so this is conformant, not a
regression; it is written into the matrix and CLAUDE.md because an auditor
reading rule 7 literally would otherwise file it as one. That is the #45/#60
precedent: an unrecorded reading becomes a stale issue.

**The fixture is the point.** Every test here puts HEAD *inside* a folder and
names it so it sorts last among its siblings (`feature/zeta`, in a folder that
sorts after `chore`). A fixture with HEAD at the root cannot tell the two
readings apart — root *is* its folder, so 「置頂於所屬資料夾內」 and 「置頂於整棵
樹」 name the same row. That is exactly why `sidebar_filter_test.dart`'s `main`
fixture stayed green through the entire bug, and why its rule-7 tests still pass
unchanged after the fix.

`branch_tree_builder_test.dart`'s very first test had to be corrected: it
asserted `develop` above `main` with `main` carrying `isHead: true`, i.e. it
stated the pre-fix ordering as the expected one.

#### The split: 1,782 → 741, in four commits, no behaviour change

The panel was more than double the project's 800-line ceiling. Split along two
different seams depending on what each piece owns, rather than one rule applied
uniformly:

- **Presentational** (`features/workspace/widgets/` precedent — plain callbacks,
  no Riverpod): `BranchSelectionActionBar`, `BranchesSectionHeader`,
  `SidebarFilterField`, `BranchFolderRow`, `SidebarSectionLabel`,
  `BranchSelectionShortcuts`.
- **`ConsumerWidget`**: `SidebarTagSection`, `SidebarStashSection`. Their
  actions are the *only* callers of the controller methods behind them, so
  routing ten callbacks up through the panel would add a hop and leave the
  panel holding state it does not otherwise use. The branch tree is the
  opposite case — its selection *is* panel state — so that half stayed.
- **Collaborator objects**: `BranchBulkActions` (page 13's `MULTIBRANCHMENU`
  over a selection) and `BranchRowActions` (05-B / 05-C / 05-J per-row menus),
  split along the line the spec itself draws. Both are built fresh at each call
  site and never stored: the selection is the panel's, and a stored second copy
  is the shape this repo keeps finding bugs in.
- **Pure functions**: `branch_selection_rules.dart` (`isBulkSelectable`,
  `isInMultiSelection`, `isGoneAndBulkSelectable`, `prunedSelection`,
  `extendedSelection`, `liveBranchNames`) and two more tree walks moved into
  `branch_tree_builder.dart` beside `collectFolderLeafRefs`.

**What stayed, and why.** Expand/collapse (`_expandedFolders`) is the panel's
own `setState`; moving it would put tree state in two places. `firstLeafName`
and `selectableLeafNames` moved as *functions* but their calls stay in
`build()`, walking the same `branchTree` instance — pushing the walk itself
into a child widget would recreate the second-copy-of-render-order bug the
first pass had just fixed. Batch delete stayed with the panel's routing because
spec page 13 requires item-by-item confirmation, so it opens a dialog.

**One real finding fell out of the move.** Extracting the filter field exposed
that the clear button was keyed on `_filterQuery.isEmpty` while the 命中/總數
readout was keyed on `trim().isNotEmpty`. For a whitespace-only query those
disagree: nothing is filtered, no count shows, but the clear button *does* —
and it is the only way to get rid of the text. Collapsing them into one
`isFiltering` flag would have stranded the user. Preserved faithfully as two
parameters, `hasQuery` and `isFiltering`, with the reason written on the field.

#### Verification

`flutter analyze` clean throughout, `dart format` limited to the touched
directory. The suite ran green after **every** extraction, not just at the end:
1,988 tests. Both new panel behaviours were mutation-checked and the red was
narrow *and* doubled — reverting the `No matches` key and dropping the ↓ skip
each failed both the new pin test and the pre-existing `sidebar_filter_test.dart`
tests that were already guarding those contracts.

**All nine macOS device files were rerun, one at a time**, not the four the
first pass needed. The split changed the widget-tree shape of every sidebar
row, and the merge changed the capi JSON across the FFI seam — the fake-backed
suite attests to neither. The dylib is rebuilt and re-copied by the macOS
Runner's own build phase on every `flutter test -d macos`, so the stale-copy
trap does not apply here.

#### Deliberately not done, still

- **No human visual pass.** Unchanged from the first pass, and now covering the
  pinned row's position as well as hover and the 等距 column.
- **`branch_selection_rules.dart` has no dedicated unit test file.** Its six
  functions are covered transitively by the panel and builder suites, which is
  how they were covered as private methods too — extracting them makes a direct
  test *possible*, and that is worth doing, but writing one was not part of what
  was asked.

### 更新流程的三個缺陷 (fix/update-flow-windows-and-recheck)

使用者回報三件事：Windows 上更新不了、自動更新「第一次進入沒有作用」、
重開更新對話框不會重新檢查。三件都落在 PR #107（`feat/github-auto-update`，
v0.32.0 首次出貨）自己在 test plan 裡標成**未驗證**的那一塊 ——「真正的自我安裝
＋ 重啟」與 Windows leg。`release.yml` 的檔頭也早就寫著 macOS 與 Windows 兩腳
從未在真機驗證過，而 **#69** 記著 PR CI 根本不編譯 `windows/runner/`。

#### 最誘人的假設在第一個問題就死了

「Windows 建置沒有拿到 `GBM_VERSION`」可以一次解釋全部三個症狀：沒有版本身分
⇒ `check()` 直接停在 `developmentBuild` ⇒ 自動檢查靜默、手動檢查說 updates are
disabled、而 `developmentBuild` 又是終端狀態所以重開不會再查。三個症狀，一個成因，
而且 `release.yml` 的 Windows 那一步是 `run: >` 沒有指定 `shell`，在
windows-latest 上預設落到 PowerShell，引號處理是經典地雷。

**問使用者 About 對話框那一行顯示什麼，就把它推翻了：顯示的是版本號。**
`GBM_VERSION` 有進去。統一解釋不存在，三個問題必須分開診斷 —— 事後看，這是這一輪
最有價值的一次提問，因為那個假設漂亮到很容易直接動手。

#### Windows：更新腳本站在它自己要搬走的資料夾裡

`launchUpdater` 呼叫 `Process.start` 時沒有傳 `workingDirectory`。沒有指定時
它**繼承父行程的**，而從 Explorer 雙擊 exe 啟動的 app，CWD 就是安裝資料夾本身
—— 也就是 `installTarget()`。於是 detached 的 `powershell.exe` 站在它接下來要
`Move-Item` 的那個資料夾裡。

**Windows 不允許改名或刪除任何行程的目前工作目錄**：CWD 的 handle 開啟時不帶
`FILE_SHARE_DELETE`，而對目錄做 `MoveFile` 需要 DELETE access，結果是
sharing violation。腳本 20 次重試全部失敗 → `exit 3`，而 `exit 3` 這條路當時
**沒有任何 relaunch**，app 早在 `_exitProcess(0)` 就走了。使用者看到的正是
「按了安裝並重啟，畫面關掉，然後什麼都沒有，版本也沒變」。

POSIX 允許改名一個正在被當成 CWD 的目錄 —— 這就是為什麼 macOS 與 Linux 一路正常，
只有 Windows 壞。

`ProcessStarter` 這個 typedef **本來就有 `workingDirectory` 具名參數**
（`desktop_launcher.dart:14-19`），只是 `launchUpdater` 從沒傳過。又一次
orphan wiring，而且這一次那個沒人用的參數就是修法本身。

腳本自身也補了雙保險，而 PowerShell 需要兩行而不是一行：`Set-Location` 只移動
PowerShell 的 provider location，真正握著 handle 的 **Win32 行程目錄不會動**；
必須指派 `[System.Environment]::CurrentDirectory` 才會呼叫 `SetCurrentDirectory`
把舊的 handle 放掉。只寫 `Set-Location` 會看起來對但完全沒有效果。

#### 第二個 Windows 缺陷，修好第一個才會浮出來

`script.writeAsStringSync(...)` 預設寫出**無 BOM 的 UTF-8**，而
`powershell.exe`（Windows PowerShell 5.1，`-File` 在原廠機器上就是解析到它）
在沒有 BOM 時把 `.ps1` 當 **ANSI** 讀。`$target` / `$staged` / `$backup` 三個
路徑是以字面值烤進腳本的，所以使用者名稱含中文就足以讓三個一起變成亂碼，
`Move-Item` 指到不存在的地方 —— 產生**與 CWD 問題一模一樣的無聲 `exit 3`**。
兩個一起修，因為第二個會被第一個完全遮住。

`sh` 的要求正好相反：第一行的 BOM 是語法錯誤而不是提示，所以 BOM 只加在 Windows 端。

#### 「自動更新第一次進入沒有作用」的直接成因是一個看不見的閘門

`SharedPreferences` 存在 `%APPDATA%`，**在安裝資料夾之外**，所以
`update.lastAutoCheck` 會跨過版本置換活下來。剛裝好的新版第一次啟動之所以靜默，
極可能是同一天稍早的某次啟動（甚至是前一版的啟動）已經把閘門用掉了 —— 這在設計上
是對的（你才剛更新完），但畫面上**沒有任何地方說得出來**，也沒有辦法叫它再試一次。

加上 `checkAutomatically()` 刻意把「已是最新」與「連不上」收斂成同一個靜默的
`idle`，使用者無從分辨自動檢查是跑了沒事、被閘門擋掉、被 `skippedVersion` 消音、
還是失敗了。這正是本專案 UX rubric D 標記的 hidden material state，而同一個
Preferences 對話框早就為 `skippedVersion` 立好了「指名 + 可撤銷」的先例。

**這一輪明確反轉了 PR #107 一個刻意的取捨。** 原始碼寫著「a failed check
therefore uses up the day, which costs an offline launch its check -- accepted,
because the alternative needs the controller to report whether the network
answered」。代價實測下來是：一次離線啟動、或一個沒有版本身分的建置，就能讓接下來
24 小時完全靜默。`AutoCheckOutcome` 就是把當初被收斂掉的那個 distinction 重新
打開 —— 但只打開給呼叫端，不外洩到 `UpdateState`，所以畫面上的靜默規則一字未改。
時間戳仍然**在檢查之前**寫入（兩次快速啟動不能都打 GitHub），只是在非 `concluded`
時**還原**成先前的值；還原而不是清除，否則每天早上都離線的機器一連上網就有無限次請求。

#### 「重開不會再查」是實作對不上自己的測試名

`update_dialog.dart` 的 mount 閘門寫成 `status == UpdateStatus.idle`，但既有測試
的名字是 `checks once when opened with nothing in flight` —— 說的是正確意圖。
`upToDate`、`failed`、`developmentBuild` 三個都是終端狀態，流程裡沒有任何東西把
它們收回 `idle`，所以手動檢查過一次之後，重開只是重播同一個答案。

修法不是把閘門反過來寫成「不是在途就查」，而是切成**三組**：在途工作不重啟；
**`available` 也不重查**（那是使用者還沒處理的提議，而且啟動時自動檢查推出來的
對話框正是這個狀態 —— 重查會在最常見的路徑上多花一次 API，還可能讓第二次失敗
蓋掉已經找到的版本）；其餘才是過期的答案。

順帶關掉一個既有的卡死邊角：對話框在自動檢查**進行中**被打開時 mount 閘門會跳過，
而靜默結束的自動檢查會把狀態收回 `idle`，畫面就永遠停在「Checking for updates…」
且沒有任何按鈕。補的 `ref.listen` 刻意只認 `checking → idle` 這一條轉移，
而不是「落在 idle」—— `dismiss()`（Skip this version 呼叫的就是它）也會落在 idle，
在那裡重查會把使用者剛拒絕的版本又端出來。

#### 靠「跑」而不是靠「讀」才拿到的三件事

1. **第一版的共用資料夾測試殺不掉 mutation。** 把 `target.length != home.length + 1`
   放寬成 `<` 之後，全部測試照樣綠。原因是三個「不該擋」的案例各自因為**別的**理由
   回 false（家目錄根本不匹配、或最後一段不在清單裡），沒有一個踩在那條長度規則上。
   補上 `C:\Users\jane\Apps\Downloads` —— 位於家目錄底下、名字也叫 Downloads、
   卻是使用者自己的資料夾 —— 之後才殺得掉。
2. **exit-3 relaunch 的測試佈局差一點為了錯的理由變綠。** 要讓 `mv` 失敗必須把
   target 的**父目錄**設成唯讀（改名要的是父目錄的寫入權），而 sentinel 檔如果也
   寫在那個唯讀目錄裡就一起失敗，測試會看到「沒有 relaunch」而通過。所以 target
   多埋一層（`root/lock/install`，chmod 555 在 `lock` 上），sentinel 留在 `root`。
3. **`isSharedUserFolder` 不能走 `Directory.parent`。** 那個 API 依**主機**的路徑
   規則走，所以 `C:\Users\jane\Downloads` 在 macOS 上是一整個沒有分隔符的字串，
   fixture 完全沒有意義。改成自己切 `[/\]` 之後，同一個測試才真的涵蓋到 Windows 拼法。

#### 刻意不做，記錄下來

- **Windows PowerShell 腳本仍然只有文字斷言。** 這台是 macOS，`ci.yml` 的 Flutter
  job 是 ubuntu-only，`windows/runner/` 只有 tag 才編譯（**#69**）。sh 腳本是**真的
  被執行**的（`update_installer_script_test.dart` 跑 `sh`），PowerShell 這一半不是。
  曾考慮在 `cq.yml` 加一個 `windows-latest` 的純靜態 job，用
  `[Management.Automation.Language.Parser]::ParseInput()` 檢查語法 —— 沒有做，
  代價是 CI 多一個平台 job，留給使用者決定。
- **真正的「安裝並重啟」全程仍未驗證**，與 PR #107 當初的狀態相同，只能等下一個
  正式 release 用舊版實測。差別是這一輪之後，失敗**會留下 `gbm-update.log`**，
  而且 app 會自己回來 —— 下一次失敗第一次變成可診斷的。
- **`Copy-Item -LiteralPath $staged -Destination $target -Recurse` 沒有改寫。**
  目標在改名之後必然不存在，這是 PowerShell 「destination 不存在就把 source 的
  內容複製進去」的記載行為。想過改成先 `New-Item` 再複製 `$staged\*`，但那會把
  wildcard 帶回一個刻意全用 `-LiteralPath` 的腳本裡。

### Working Copy 重新設計：行數、兩欄、scope 與草稿 (feat/p03-working-copy-redesign)

規格 P03 的整頁重做，外加 P02 的兩處版面落差與 **#75** 的四項快捷鍵。二十一個
commit 橫跨 `src/core/` → `src/capi/` → `data/ffi/` → `features/**` 五層。

#### 沒有撐過原始碼的前提

計畫表格裡有幾格是讀規格與讀舊註解得出的，實作時被原始碼推翻，修正它們才是那些
commit 的主要內容：

1. **「Close repository → 新增 `File → Close repository`」是多餘的。**
   `_buildActionHandlers()` 裡 `GbmActionId.fileCloseWindow` 的 handler 本來就是
   `context.go(RoutePaths.welcome)`。`TopBar` 那顆返回鍵早就等於既有的
   `File → Close window`，不必新增 action id，也就不必為此偏離 P04 的 `MENUS` 表。

2. **「repo 狀態（MERGING…）已在狀態列，直接刪」是錯的。** `RepoState::describe()`
   對正常 repo 回傳空字串，只在 sequencer 操作與 **`indexLocked`** 時有內容；而
   `StatusBar` 只在 conflict label 裡顯示 sequencer 狀態，`ConflictBanner` 又只在
   `conflictActive` 時出現 —— `indexLocked` **不會**設 `conflictActive`。照計畫刪
   會安靜丟掉「另一個 git 行程正在執行」這個訊號。狀態列因此真的接下 `describe`
   （非空才畫）。

3. **`FileListModeSwitcher` 的 doc 自己記著一個已經過期的理由**：「`working_copy_board`
   需要三態資料夾 checkbox，所以自己直接建 `FileTreeList`」。checkbox 一走那個理由
   就不成立，`_buildFlatList` 與 `_buildTreeList` 是純重複。給 switcher 一個可選的
   `folderBuilder` 就收斂掉了。CLAUDE.md 記過「一段解釋自己為什麼繞開某條路徑的註解，
   值得和那條路徑本身一樣的審視」—— 這是第二次。

4. **規格從來沒有要求 side-by-side diff。** 動手刪 `lastDiff` 單槽之前 grep 全部
   讀者，才發現 `side_by_side_diff.dart` / `side_by_side_diff_view.dart` 的規格依據
   只有一個 mockup 裡的**假 commit 訊息**字串。兩個檔案連同測試隨 C13 刪除。

5. **`docs/reports/spec-conformance-matrix.md` 的 P03 段落有兩格是錯的**，方向相反：
   item 10（List/Tree 共用偏好）記為「唯一的真缺口」，但 History、Compare、Conflict
   window 與 panels **早就都** `ref.watch(fileListViewModeProvider)` 了，這格已經過期；
   反過來，「7 個 `SCOPES` granularity 全部實作」那句所依據的欄／資料夾三態，靠的是
   `WorkingCopySelectionState.getCheckState` 與 `FileTreeNode.getCheckState` ——
   grep 全 `lib/` 後確認**兩者在宣告它們的檔案之外沒有任何呼叫端**。詳見下面的
   「矩陣的新案例」。

#### 「跑」出來、不是「讀」出來的

- **`core.fsmonitor=true` 的機器上，多一趟背景 `git diff --numstat` 會讓使用者的
  寫入以 12 次 9 敗的比率死在 `index.lock`。** CI 上沒有 fsmonitor，所以 CI 看不見；
  讀 diff 的人也看不見。三個各自獨立的開關都能壓回 12 次 0 敗（拿掉那一趟、讓全域
  git config 失效、給那一趟加 `-c core.fsmonitor=false`）。
  **建立那個鎖的行程始終沒有被指認出來。** 被直接觀測排除掉的包括：git 的讀取指令
  根本不會建立 `.git/index.lock`（一支能正向抓到 `git add` 拿鎖、單次取樣 8162 次的
  poller，對 status、兩趟 numstat 與 `-U3` 工作區 diff 在 daemon 冷啟動／暖機／stat
  過期／別的行程剛改寫過 index 之後，全都是 0），因此 `--no-optional-locks` 是有效的，
  而兩個本來能解釋一切的機制（fsmonitor token 寫入、`diff.autoRefreshIndex` 的收尾
  refresh）也隨之死亡。任何觀測手段 —— `GIT_TRACE2_EVENT`、exec shim、甚至只做一次
  `write()` 的 shim —— 都會讓它完全消失。修法（`GitCommand::worktreeReadFlags()`）
  有效且以 argv 斷言釘住，**但機制未明，註解裡沒有假裝有**；若日後有人指認出兇手，
  那個 flag 就可以刪，註解裡寫了這句。
- **分頁列的位置 bug 出貨的原因是沒有任何測試分辨得出它。** 改完之後整套 2039 支
  測試依然全綠 —— 沒有一支斷言過分頁列在哪。新測試因此每一條都斷言 **rect**：
  `find.byType(TabRow)` 在錯的位置一樣找得到。
- **臨時 scope 的三個 bug 全都是「第一幀正確、之後才壞」**，只有把手勢做完再多 pump
  幾幀才看得到：GlobalKey 重複註冊、插入位置造成的 reparent 閃爍，以及真正的迴圈
  「touched 一變就 `setState` → 重建擾動選取幾何 → delegate 再回報 → touched 又變」。
  第三個的解法是只在 pointer down 到 pointer up 之間聽（`_latched`）。
  `scope stays put on idle frames` 那支測試專門釘它 —— 一幀的斷言看不到，因為第一幀
  從來都是對的。
- **選取拖曳錨在 `getCenter` 會選不到任何東西。** diff 列的 `Text` 坐在一個遠比字形寬
  的 `Expanded` 裡，方框中心早就過了字串尾端。改錨在 `rect.left + 1` / `rect.right - 1`。
- **C16 有兩個 mutation 回綠**，追下去各有收穫：一個補出「同一個 HEAD 的無關 refresh
  不該清掉訊息」這支測試；另一個證明 `next == _pendingCommitFrom` 這道防護
  **不可能到達** —— `select` 只在選到的值真的改變時才通知 —— 於是刪掉防護、把理由寫成
  註解。

#### 刻意偏離規格的四項

每一項都是使用者拍板，不是實作自行縮減：

1. **兩欄完全沒有 checkbox**（偏離 P03-1 / P03-3 / P03-10 與 `SCOPES` 第 1、4、5 列）。
   檔案改用**拖曳**在左右切換。刪掉的是列上的 `drag_handle` 裝飾圖示、標題列的三態
   `Checkbox`、樹狀模式資料夾列的三態 `Checkbox`，以及只服務它們的三個 helper。
   **沒有任何 scope 因此失去入口**：整欄走 `Repository → Stage all`
   （Ctrl/Cmd+Alt+A）與右鍵選單；整個資料夾改成**資料夾列本身可拖曳**，一次帶走底下
   所有葉節點。半暫存狀態改由行數（`+34 −12`）表達，那正是 checkbox 的三態原本要說
   的事，而且說得更精確。
2. **`repositoryStageAll` 的鍵位從 `Ctrl/Cmd+Shift+S` 改為 `Ctrl/Cmd+Alt+A`。**
   規格沒有指定 Stage all 的鍵位，但 260820 的 `REVISIONS` 指定 `branchStashChanges`
   要 `Ctrl/Cmd+Shift+S`；兩者相撞，使用者裁定讓路的是 Stage all。
3. **新增 `GbmActionId.viewRefresh` ＋ `View → Refresh` ＋ 裸 F5**，P04 的 `MENUS` 表
   沒有這一項。`refreshRepoHistory()` 全 `lib/` 只有 `TopBar` 一個呼叫點，刪掉 TopBar
   之後它是唯一真的沒有別的家的元素。F5 不走 `_makeShortcut()` —— 那會硬塞一個這裡
   不要的 Ctrl/Cmd；兩個修飾鍵旗標都 false 是合法的 `GbmKeyboardShortcut`。
4. **scope 按鈕的文字以「匡選行數」為主、括號寫「實際會變動的行數」**
   （`Stage 3 lines (1 changed)`）。這是使用者的裁定。**「兩數相等時省略括號」那一半
   是實作判斷，不是使用者的裁定** —— 相等時括號恆為冗詞，但這件事沒有被裁定過，
   在此標明。實作在 `diff_scopes.dart` 的 `scopeButtonLabel()`，是唯一一處。

#### 刻意做的取捨，記錄下來

- **草稿寫入用「飛行中合併」而不是計畫寫的 500ms debounce timer。** timer 會讓每一支
  「在輸入框打字」的 widget test 都得負責把它排乾，否則死在 pending timer —— 就是
  C14 踩到的那種傳染性義務。合併版本不需要 timer，硬當機掉的東西還更少：只掉一次
  磁碟寫入期間打的字，而不是固定 500ms 份。
- **草稿只存 summary / description，`diffScrollOffset` 留在記憶體。** 那是某個檔案
  diff 裡的位移，重開後根本沒有選檔案，還原它只會把不相干的東西捲到奇怪的地方。
- **存成長度 2 的 `StringList` 而不是兩把 key。** 訊息是一個東西，兩次 `setString`
  可能只落地一半，留下配錯主旨的內文；讀到長度不對就當空草稿。
- **`2 file` 模式下 staged 那一欄的捲動位移不保留。** 一個 controller 驅動不了兩個
  scrollable，而草稿只有一個 `diffScrollOffset`。
- **`_dropSelection` 的 `alsoClearHighlight` 只有視覺意義，沒有測試釘住。** widget
  test 讀不回 `SelectableRegion` 的選取內容。它只從送出路徑呼叫：在 diff 換掉的時機
  呼叫 `clearSelection()` 會撞上還在變動的 `selectables`，丟
  `ConcurrentModificationError`。
- **送出後等待期間任何錯誤都取消等待，且不做歸因。** fetch 失敗也會取消它 ——
  這個 repo 自己的規則就是「下一個事件是我的」永遠不是安全的歸因。取捨方向是刻意的：
  誤取消的代價是訊息比成功的 commit 多活一會，不取消的代價是之後某次 checkout 移動
  HEAD 時，清掉使用者在失敗後才寫的訊息。
- **untracked 檔案的行數是讀檔算出來的，不是 git 算的**（`git diff` 完全看不見它們），
  binary 或超過 **1 MiB** 就不給數字。上限存在的理由是 `--untracked-files=all` 會列舉
  未建置輸出目錄裡的每一個檔案。四個行數欄位的 **0 一律代表「沒量到」**，不是「量到
  0」，UI 據此不畫 badge。
- **`WorkingCopyEntry` 的四個新欄位都是 `required`**（20 個測試檔、31 個建構點一併補），
  `fromJson` 用嚴格的 `as int` 而不是 `?? 0`：capi 與 model 同一次建置一起出貨，少一個鍵
  代表兩側漂開了，那要大聲壞掉。用 `?? 0` 兜底會讓漂開偽裝成「這些檔案剛好都沒變動」。

#### C17 追加：一句沒有兌現的承諾

寫 C17 的文件時重讀 **#75** 的結案留言，發現它對第 3 項的處置寫著
「`Ctrl/Cmd+Shift+Enter` 之後留在 diff 區自己的 focus scope 內」—— 那句是承諾，
而 grep 之後確認**沒有兌現**：全 `lib/` 沒有任何地方綁它。規格與決策紀錄兩邊都
寫得很清楚（P16 的 `REVISIONS` 給 `Ctrl/Cmd+Alt+S`、P03-5 與 `SCOPES` 第 7 列給
`Ctrl/Cmd+Shift+Enter`，#75 裁定兩種讀法都保留），所以照長期規則第 1 條直接補完，
沒有丟出來問。`ScopedDiffView` 內加一層 `CallbackShortcuts`。

寫測試時遇到一個**無法和程式碼意見不合的夾具**，處置是刪掉它而不是留著：
「沒有選取時按這個鍵不會 stage 任何東西」這支測試，把空值防護拿掉是綠的，把整個
callback 換成無條件 stage 也是綠的 —— 因為沒有選取時 diff 區內根本沒有東西持有
焦點，鍵事件從來就到不了那個 callback。防護真正擋的是**已經花掉 scope 之後的第
二次按鍵**：一次空送出，唯一的效果是多呼叫一次 `clearSelection()`，也就是樹還在
重組時會丟 `ConcurrentModificationError` 的那一呼叫。widget test 讀不回
`SelectableRegion` 的選取內容，所以它和 `alsoClearHighlight` 一樣沒有測試釘住 ——
這句寫在防護旁邊，而不是留一支假裝有涵蓋到的測試。

#### 矩陣的新案例：evidence 證明的是 gate，不是被 gate 的那個東西

CLAUDE.md 那條陷阱原本的形狀是「一格 conformance cell 拿 `isActionEnabled()`
當證據，證到的是 gate 存在，不是被 gate 的介面存在」。這一輪撞到**同型的第三次**，
換了一個外殼：

P03 段落開頭那句「7 個 `SCOPES` granularity 全部實作 —— 包含 column tri-state /
folder tri-state」，靠的是 `WorkingCopySelectionState.getCheckState()` 與
`FileTreeNode.getCheckState()` 存在且有單元測試。兩者確實存在、確實正確、確實被
測試 —— 但 grep 全 `lib/` 之後，**它們在宣告自己的檔案之外沒有任何呼叫端**。
被算成「已實作」的那個 granularity，靠的是一個沒有人畫出來的 helper。這是這個
repo 記錄過的 orphan wiring 第八次，也是第一次它假扮成一格 conformance 證據。

實務上的差別：如果那句話當初寫的是「哪個 widget 畫出這個三態」，checkbox 被拿掉
這件事會直接落在同一格上；寫成 helper 的存在之後，拿掉 checkbox 反而讓那格看起來
沒有變化。`getCheckState` / `CheckState` 與 `WorkingCopySelectionState` 那六個
只服務 checkbox 的方法排在 C18 刪除。

#### C18：重用與快取稽核

計畫列了五個快取候選。**兩個的前提沒有撐過原始碼**，一個早在 C11 就做完了，
剩下兩個實作了。逐項攤開如下，順序照計畫。

**(a) 未追蹤檔案的行數 —— 實作了。** `WorkingCopyStatusReader` 那三個 git 子行程
維持不快取，理由沒變（誠實的 key 得包含每個檔案的 mtime 與 size，那個 stat 掃描
比它省下的還貴）；但未追蹤檔案這一半可以，因為 1 MiB 上限本來就得先問 size，那個
stat 已經付過了。`UntrackedLineCountCache`，key 是 path + size + mtime。

三件事寫在它的類別註解裡，一件都不省：key 是什麼（三個欄位各擋掉哪一種漏判）、
什麼會讓它失效（**沒有外部事件**——編輯器存檔不會發出任何 `GBM_EVENT_*`，key 本身
就是失效機制，另外每一輪用 `retainOnly` 掃掉已經不是 untracked 的項目）、漏掉失效
會看到什麼症狀（unstaged 欄位顯示編輯前的行數，也就是一個**錯的**數字，而不是缺
一個數字——正是這個檔案裡 byte cap 與 binary 判定都拒絕的那種失敗）。

另外套了 git 自己的 **racily clean** 規則：mtime 不比本輪開始時間嚴格更舊的檔案
不進快取。同一個時間戳刻度內，「改過」與「沒改過」無法分辨，記下去會讓錯的數字
黏住到下次編輯為止，而不是下次 refresh 就清掉。`passStartedAt` 在第一個 stat 之前
就讀一次，不是每檔讀一次——每檔讀會讓「本輪讀取期間被改寫」的檔案仍然看起來比自己
的檢查點更舊。

**(b) scope 切分 —— 實作了，但 key 不是計畫寫的那個。** 計畫寫
`(path, staged, diff identity)`；實際用的是 **`DiffFile` 的物件識別加上 `maxGap`**。
識別在這裡是誠實的 key，正因為這些是每次 `workingCopyDiffReady` 重新解析出來的
不可變 DTO：沒有人原地改 `DiffFile`，所以同一個實例不可能有不同內容。而
`scoped_diff_view.dart` 的 `didUpdateWidget` 本來就用
`!identical(oldWidget.file, widget.file)` 當「換了一份 diff」的訊號 —— 同一個訊號
用在同一個檔案的另一個決定上，不是新發明一個。

值得的理由是量出來的，不是猜的（debug JIT，`Stopwatch`）：一個 40 hunks × 200 行
的檔案切一次 **197µs**，典型的 10 hunks × 80 行 **21µs**。拖曳文字選取會讓
`ScopedDiffView` 每一幀重 build，所以那 197µs 是每幀都在燒的純浪費；換成一次
`identical` 比較。`temporary` / `touchedChangedLines` **沒有**快取，它們在同一份
diff 內就會變。

**(c) `workingCopyDiffs` 的成長 —— C11 就做完了，這一輪只是確認。**
`repo_session_repository.dart` 的 `_readWorkingCopyStatus()` 把它整個重設成
`const {}`，而且已經帶著三段式註解。順帶記一筆計畫的重載時機表裡那列
「單一檔案 stage/unstage 只清該檔的兩側」**是多餘的**：這張 map 的上限就是一個
選定檔案的兩側，所以「全清」和「只清那個檔」是同一個動作。寫下來，免得日後有人
去補一個更細的失效機制。

**(d) `sameLogicalFile` 的兩兩配對 —— 前提不成立。** 計畫說它做 O(n²) 配對、要
改成建一次索引。實際上它**在 `lib/` 底下一個呼叫端都沒有**：board 用
`logicalFileKey` 當 key，從不直接比較兩個 entry，也就是說以 key 為主的做法早就
取代了兩兩比較。它沒有被刪，而是搬進 `working_copy_file_identity_test.dart` 當
**oracle** —— 「key 與關係必須一致」那支測試需要一個獨立寫成的「同一個檔案」敘述，
才不會讓 key 的 bug 躲進檢查它的東西裡。留在 `lib/` 才是問題，因為下一次孤兒稽核
會再把它標一次。

**(e) `FileTree.fromPaths` —— 前提不成立，而且底下藏著一個真的 bug。**
計畫說用 path list identity memoize。那個 key **永遠不可能命中**：兩個呼叫端都是
每次 build 現做 `items.map(pathOf).toList()`。但追下去發現的東西比快取重要得多。

`working_copy_board.dart` 的 `_keysInRenderOrder` 無條件建一棵樹取葉子順序，理由
寫在它自己的註解裡：「list 與 tree 兩種模式都經過 `FileTree.fromPaths`」。**那句話
是錯的。** `FileListModeSwitcher.build` 在 list 模式直接把 `items` 交給
`ListView.builder`，根本沒有樹。跑出來確認（pump 兩種模式、按 y 座標排序畫面上的
文字）：

| 模式 | entries 為 `lib/a.dart, zz.txt, lib/b.dart` 時畫出來的順序 |
|---|---|
| list | `lib/a.dart`、`zz.txt`、`lib/b.dart` |
| tree | 資料夾 `lib`、`zz.txt`（葉子預設收合） |

所以在**預設的 list 模式**下，使用者從 `lib/a.dart` 拖到 `lib/b.dart`，畫面上明明
夾在中間的 `zz.txt` 不會被選中 —— 「範圍要用畫成的順序量」這條規則被自己的實作
違反了。而原本那支測試用預設（list）模式 pump 卻斷言 tree 順序，並在註解裡重述那句
錯的前提，所以它**把 bug 釘住當成正確行為**。現在拆成兩支，一種模式一支，兩個方向
的變異各自只讓對應的那支變紅。

修法讓快取候選 (e) 直接消失：list 模式現在完全不建樹，比快取它更省。tree 模式量
到每次點擊 100 個檔案約 **41µs**（500 個檔案 174µs），不值得為它把
`FileListModeSwitcher` 從 `StatelessWidget` 改成有 State 的版本——`listEquals` 本身
也是 O(n) 字串比較。**這是一個量出來的取捨，不是「本輪不做」**，數字留在這裡以便
下一輪重新裁定。

#### 重載時機表（照計畫逐列核對）

| 時機 | 誰負責 | 怎麼確認的 |
|---|---|---|
| `workingCopyStatusUpdated` | `_readWorkingCopyStatus()` 把 `workingCopyDiffs` 重設成 `const {}`；scope 快取隨之失效（新的 reply 必然是新物件） | C11 既有註解 + `DiffScopeCache` 測試 |
| 單一檔案 stage/unstage | 同上，且**不需要更細的機制**——map 的上限就是一個檔案的兩側 | 讀 `_readWorkingCopyStatus()` |
| `workingCopyDiffReady` | 覆寫該 key；`DiffScopeCache` 因為物件換人而重切 | `'splits again when a new reply arrives for the same path'` |
| 切換 repo | 結構性：`repoSessionProvider` 是 `RepoIdentity` family；C++ 側 `UntrackedLineCountCache` 掛在 per-repo 的 `Session` 上 | 讀型別，非測試 |
| session 關閉 | 結構性：provider 自動 dispose；`~Session()` 帶走 reader | 讀型別，非測試 |
| 未追蹤檔案 mtime/size 改變 | `UntrackedLineCountCache` 的 key 本身 | 三支 `Rereads...` 測試 |

#### C18 的重用稽核：三筆，都是同一個陷阱的重演

1. **`FileTreeFolderRow` 手刻了 `InkWell`**，所以繼承的是 `ThemeData.hoverColor`
   （約 4% 黑/白，真實螢幕上看不見），而它同一份清單裡上下相鄰的檔案列是 `GbmRow`、
   hover 正常。一份清單裡兩種行為。改成 `GbmRow`（水平 padding 設零，因為
   `FileTreeList` 已經用 `EdgeInsets.only(left: level * 16)` 做了縮排）。
2. **`working_copy_view.dart` 的私有 `_MiniButton`** 手刻了
   `GbmButton(secondary, sm)` 已經有的 borderDefault 外框、textXs、space2 內距，
   而且同樣沒有 hoverColor —— 全 app 唯三沒有 hover 的按鈕。

3. **`WorkingCopyDiffPane` 的 `2 file` 模式手刻了 `GbmSplitPane`**：寫死 1:1 的
   `Row` 加一條 1px `Container` 分隔線。應用裡其餘八個雙欄／三欄面向全部是真的
   splitter，包含**正上方那塊 board 自己的 `wc.columns`**——所以使用者拖得動 board
   的欄寬、拖不動 diff 的欄寬，兩條分隔線長得一模一樣。
   新增 `GbmLayout.splitterWcDiffSides`（storageId `wc.diffSides`）。規格 P09 的
   SPLITTERS 表只有八列、沒有這一條，因為那張表早於已裁定的變體 B（原本的 P03 只有
   單欄 diff）；比照 `splitterPanelList` / `splitterPanelDetailFiles` 的先例，數字
   跟隨同一個 view 裡另一組 1:1 雙欄的 `splitterWcColumns`，並把「規格沒有、跟隨誰、
   為什麼」寫在常數的註解裡。`minExtent` 取 140 而非 200，因為這塊 pane 巢狀在
   `splitterWcDiff` 的 54% 之內。
   flex 模式的 `minExtent` 只夾拖曳、不夾 layout（面板是 `Flexible`），所以窄視窗
   不會因此溢出——這件事是讀 `split_pane.dart` 確認的，不是假設的。

前兩筆都用 identity 斷言 token（`ink.hoverColor == colors.surfaceHover`），不是
「沒有丟例外」：錯的 hover 顏色不會丟任何例外，這正是它們躲過所有測試的方式。
第三筆斷言的是**內容真的移動了**（拖完之後 staged 側的文字中心 x 變大），不是
`onFlexChanged` 有被呼叫：一個沒有任何 layout 會讀的持久化數字也能通過後者。

#### 查過、沒有動的三項

- **`GbmSegmentedControl`** 沒有重複既有元件，而且它自己有明確傳
  `hoverColor: colors.surfaceHover`。
- **`GbmBadge`** 在計畫指定的位置（C9 的檔案列尾）確實用了。但 `scoped_diff_view`
  的 scope 卡片標頭把 `+N` / `−M` 畫成裸的等寬彩色文字而不是藥丸，於是同一個畫面
  上同一件事有兩種畫法（左邊 board 是藥丸、右邊 scope 標頭是文字）。**規格對此沒有
  答案**：SCOPES 第 7 列只規定「按鈕文字寫出實際數量」，計畫的 C13 也只寫按鈕。因此
  這是一個待裁定的設計問題，不是一筆稽核缺失——依本輪的工作規則，規格與決策紀錄裡
  沒有答案的就丟出來問，而不是自行產生「本輪不做」。
- **`FileListModeSwitcher` / `FileTreeList`** 見上面候選 (e) 那一段：本輪不但沒有
  重複它們，還把 list 模式對 `FileTree` 的多餘依賴整個拿掉了。

#### 量出來、沒有修掉的一件事

衝突橫幅在 **440px 寬**以下會 `RenderFlex` 溢出。三顆按鈕是 non-flex，旁邊的
`Expanded` 救不了它們造成的溢出（本 repo 踩過六次的那條規則）。這一輪**沒有修**，
但也不是沒動：換成 `GbmButton` 之後 440px 的溢出從 **17px 降到 6.3px**，也就是說
這一輪縮小了它而非造成它。要讓它消失需要設計上的答案（改圖示？收進溢出選單？），
不是排版微調。已加一支 500px 的守門測試把量到的餘裕釘住，斷言的是文字寬度大於零
而不是「沒有丟例外」——`Expanded` 會一邊滿足「沒有溢出」一邊把子節點壓成零寬。

#### 裝置層：交接時留的第一個未完項目

C1 的四個 capi 欄位補了 `integration_test/working_copy_line_counts_test.dart`。
fixture 刻意做成半 staged 的單一檔案，四個數字互不相同（unstaged +7/-3、
staged +2/-1），因為這四個欄位存在的理由就是「一個檔案同時有四個數字」，而讀錯
欄位（拿另一欄的那一對）是真實的風險——數字若相同，讀錯也會過。

**驗過會紅**：把 `JsonCodec.cpp` 的 `stagedAdded` 改成送 `unstagedAdded`、重建
dylib 後，「+7」變成兩個、「+2」一個都沒有。還原後綠。

順帶踩到一次 CLAUDE.md 記過的陷阱：`app_flutter/build/native/libgbm_capi.dylib`
當時是 **8/23 的舊複本**，早於 C1。跑裝置測試前若沒重跑 `build_capi.sh`，測到的
是舊 dylib，而新欄位會表現成「badge 沒出現」，不是任何一種錯誤。

#### 裝置層全掃：兩支紅，其中一支是真的產品缺陷

依 CLAUDE.md 那條「動到共用列元件的一輪，十支裝置測試要一支一支重跑」，
`FileTreeFolderRow` 換成 `GbmRow`、`_MiniButton` 換成 `GbmButton` 之後把
`integration_test/` 十支全跑過。八綠兩紅，而兩紅都不是這兩個 commit 造成的
——是 **C7–C13 的重做在四輪之前就打壞的**，而裝置層不在任何 CI job 裡、也
不屬於 `flutter test`，所以沒有任何一層看得見。

1. **`commit_flow_test` 還在點 `find.byType(Checkbox).first`。** 變體 B 把
   checkbox 全刪了。改寫成拖曳之後，才浮出下面那個真的缺陷。
2. **`context_menu_flows_test` 05-F 的 `find.text('fixture.txt')` 中兩個。**
   C10 讓 diff pane 的標題列也寫出選中的檔名，而 `tap()` 拒絕含糊的 finder。
   finder 收斂到 `WorkingCopyBoard` 之內。
3. **同檔 05-G 的夾具前提過期。** 兩處插入之間只隔一行，而變體 B 的預設
   scope 會把「相隔 ≤ 2 行」的變更併起來——選單因此寫的是
   `Discard 2 lines…`（測試找的是 `Discard…`，找不到），而且真的按下去會把
   兩行一起丟掉。夾具改成隔三行：仍在同一個 hunk 內（`-U3` 的合併門檻是
   2×context），但落在兩個 scope，這支測試才重新是它宣稱的「行粒度」測試。
   **這一項不是測試壞了，是測試描述的行為已經被裁定改掉了**——夾具沒跟上
   規則，於是它悄悄改測了另一件事。

#### 空欄位不是 drop target：拖曳是唯一的路，而那條路在起點就斷了

把 (1) 改寫成拖曳之後裝置測試仍然紅：拖進 Staged 欄什麼也沒發生。原因在
`_buildColumn`——`entries.isEmpty` 時它畫的是 `Center(Text('No staged
changes'))`，**取代**了 `_buildFilesContent`，於是那一欄整個沒有
`DragTarget`。一個什麼都還沒 stage 的 repo（每個 repo 的起點）因此拖不進
任何東西；而變體 B 刪光了 checkbox，拖曳是唯一換邊的方式，所以那等於
**完全 stage 不了**。

會躲到現在，是因為**拖放從來沒有被任何一層真的執行過**：元件測試只斷言
`Draggable` 存在（`find.byWidgetPredicate((w) => w is Draggable)`），裝置層
那支則還在點已經不存在的 checkbox。「有 Draggable」和「拖得動」之間的距離，
就是這個缺陷活著的地方。

修法是把 placeholder 移進 `DragTarget` 的 builder。兩支新元件測試：拖到有
內容的欄、拖到空欄，都用 `staged.length == 1` 計次。

**變異的第一版沒有紅**，因為我把 `Center` 改回去時仍然留在 builder 內部，
`DragTarget` 還在。要還原 `_buildColumn` 的短路才紅，而且只紅那一支。這是
CLAUDE.md 那條「變異沒有落在註解預測的地方，錯的是註解不是變異」的實例：
缺陷在欄位的組裝處，不在 builder 裡，我第一次找錯了位置。

#### 一支假的測試，抓法是變異

「同尺寸編輯必須重讀」那支 C++ 測試第一版寫了 8 bytes 再寫 7 bytes —— 不是同尺寸。
把 key 的 mtime 拿掉（只剩 size）的變異照樣綠，因為 size 真的變了。改成 8 bytes
兩行對 8 bytes 三行之後變異才紅。這件事寫進那支測試的註解裡，因為它是
「**夾具無法與程式碼意見不合就什麼都沒證明**」的第五種形狀：夾具的**內容與它自己
的名字不符**。

### 三個待裁定問題的裁定（同一條分支）

C18 依「規格與紀錄裡沒有答案才丟出來問」的規則留了三個問題給使用者。裁定回來
之後，同一條分支上把它們做完。

#### 1. scope 卡片標頭的行數：統一成 `GbmBadge`

裁定是統一成藥丸。實作把 `scoped_diff_view.dart` 的兩段裸文字換成
`GbmBadge(kind: added/removed)`，間距也對齊 board 的節奏（標題後 `space2`、
兩顆藥丸之間 `space1`）。

**glyph 刻意沒有一起統一。** 檔案列用 ASCII `-`（和 `changed_files_panel`
同一種），diff 面用 U+2212（和 `panel_file_diff_detail` 同一種）——這個分裂是
按「面」切的，不是意外。裁定的是形狀；統一 glyph 會把第三個面一起拖下水，
那是另一個決定。使用者選的預覽裡寫的也是 `−`。

兩支新測試都斷言 **kind 而不只是 label**：在 added 的位置放一顆 neutral 藥丸
看起來就是錯的，但不丟例外。兩次變異各自只紅一支——`added`→`neutral` 只紅
kind 那支，`> 0`→`>= 0` 只紅「零不畫」那支。

#### 2. 樹狀模式的 `FileTree` 記憶化：不做

裁定是不做。n=500 每次點擊 174µs，遠低於一幀 16.7ms，而少一個要維護、要寫
失效測試的快取。**這一條沒有程式碼變更，只有這筆紀錄**——一個經過裁定的
「不做」和一個自行產生的「本輪不做」不是同一件事，差別就在這裡有裁定。

#### 3. 衝突橫幅：窄寬時換行——而稽核記的數字是錯的

裁定是換兩行。但真正動手時第一件事就是這個前提垮了：

**稽核記的 6.3px 溢出是錯的，實測 27px。** 而這個差別會改變修法。6.3px 小到
「把控制搬到自己那一行」顯然就夠；27px 不是——控制列自己在測試字型下就有
435px，而 440px 扣掉 padding 只剩 408px。所以外層 `Wrap`（文字一行、控制
一行）之後仍然溢出 27px，一模一樣的數字，因為溢出從來就不是文字造成的。

修法因此是**兩層 `Wrap`**：控制列自己也會斷行。橫幅於是在任何寬度都不會溢出，
只會變高。一顆被推出右緣的按鈕就是使用者按不到的按鈕，這比多佔一行嚴重。
形狀沿用 `scoped_diff_view.dart` 的 scope 卡片標頭，那裡解的是同一個問題。

**寬版那支測試的第一版斷言是假的。** 我寫的是「控制在文字右邊」，然後把
`WrapAlignment.spaceBetween` 變異成 `start` —— **綠的**，因為兩種對齊都讓
它成立。改成拿控制列的 `right` 去比外層 `Wrap` 的 `right` 之後，同一個變異
才只紅那一支。這是「夾具/斷言無法與程式碼意見不合就什麼都沒證明」的第六種
形狀：**斷言弱到兩個候選實作都通過**。

順帶記下一個量測陷阱，因為它直接害我第一次量錯：**`flutter_test` 的預設字型
把每個字都畫成 fontSize 寬**，所以 `Rebase in progress (3/8): 1 file conflicted`
在測試裡是 548px，真實的比例字型窄得多。再加上預設畫布 800×600 會把更寬的
`SizedBox` 靜靜夾掉（CLAUDE.md 記過），寬版測試因此明確 `setSurfaceSize`。
兩支測試在保守的方向上失真：真實橫幅比 440px 更窄才會斷行。

裝置層跑了 `conflict_flow_test`（會 `tap('Resolve…')`，是唯一真的去打橫幅
hit-test 的地方）與 `context_menu_flows_test`（scope 卡片標頭變高會推移列的
位置），兩支都綠。

### 「左右 diff view 沒辦法選取 line 去左或右」

使用者回報。診斷先做**排除**，再做修正——因為報告描述的是症狀，不是原因。

#### 先證明機制是通的，才知道問題不在那裡

寫了 `integration_test/stage_lines_flow_test.dart`，四支測試把整條路跑完：
文字選取 → 觸碰到的列 → scope → hunk index + line indices →
`gbm_stage_lines` → `git apply --cached` → index，而且斷言的是
`git diff --cached` 的輸出而不是 UI，所以一顆「按下去什麼都沒送出」的按鈕
過不了。兩個方向各兩支（卡片按鈕／文字選取 × 往右 stage／往左 unstage）。

**四支全綠。** 這一層之前完全沒有測試：`scoped_diff_view_test.dart` 把 view
裸著 pump 然後斷言 callback 有被呼叫，`working_copy_diff_pane_test.dart` 在
真的容器裡做同一件事，兩者都跑在 `FakeGbmBindings` 上，所以 `stageLines()`
到 index 之間什麼都沒被執行過；C++ 那半有
`WorkingCopyApiTest.StageLinesStagesOnlyTheSelectedAddedLines`，但它是從 C++
呼叫的，從來沒有經過 `dart:ffi`。

#### 真正的缺口：規格指名的**輸入法**，兩條非拖曳的路都不存在

`SCOPES` 有一個 `how` 欄位，而「這個粒度搆得到」不等於「規格指名的那個輸入
法存在」：

- **第 6 列 how：「點 hunk 標頭列（@@ …）」**。`_HunkHeading` 是一個裸
  `Text` 包在 `Padding` 裡，完全沒有手勢。它的 *note*（右鍵 Stage hunk）有
  實作，`how` 沒有。
- **第 7 列 how：「按住拖過多行，或 Shift + ↑ ↓」**。只有拖曳那半。

也就是說，只要不是用滑鼠拖，就真的沒有路——這正是報告的內容。

**Flutter 不會白送第 7 列的另一半。** 一開始的假設是「`SelectableRegion`
有延伸選取，只是 tracker 的 `_latched` 讓報告進不來」。用一個能區辨的實驗
證偽：把 `endGesture()` 改成什麼都不做（tracker 永不重新上鎖），拖曳後按
Shift+ArrowDown，卡片上的數字**仍然一動不動**。所以 region 本來就沒有在這
裡延伸選取，latch 不是（唯一的）阻礙。

#### 兩個順帶挖出來的缺陷

**(a) `addPostFrameCallback` 不會排 frame。** `_scheduleNotify` 把通知合併到
一個 post-frame callback 上，而那個 API 只是登記「下一幀結束時跑」，**不會
要求下一幀**。拖曳自己會源源不斷產生 frame，所以這個洞被藏了整輪；單擊不會，
通知因此可能永遠不送達，標頭點擊已經記下的 scope 會停在看不見的狀態，直到
別的東西剛好畫了一幀。widget test 裡更絕對：`tester.pump()` 只在
`hasScheduledFrame` 時才跑一輪，**連按六次 pump 什麼都沒發生**。修法是加
`SchedulerBinding.instance.ensureVisualUpdate()`。

**(b) 送出本身就是「diff 變更」的路徑。** `_dropSelection` 的註解早就寫了
「從 submit 路徑安全，從 diff 變更路徑不安全——後者會在樹重組還在改
`selectables` 的時候走它，框架從 `handleClearSelection` 丟
ConcurrentModificationError」。沒被注意到的是：**stage 會換掉 diff**，所以
submit 路徑只差一個 dispatch 就是 diff 變更路徑。延後到 dispatch 之後的
`clearSelection()` 正好落在它自己造成的重組裡。

主機層以下看不見這個當機：fake 不會真的重新 stage，diff 從不改變，清除永遠
碰到一棵安定的樹。**裝置層一跑就炸。** 修法是把 highlight 的清除搬到
dispatch **之前**、同步做。

#### 實作要點

點標頭是**選取**而非直接 stage：規格寫「該段所有變更行一起處理」，處理在選取
之後，而該列自己的 note 把 stage 交給右鍵選單。在變體 B 的語彙裡選取就是那張
一次性卡片，所以點下去升起的正是「拖過整個 hunk」會升起的卡——一按搬走整個
hunk，這是逐張 scope 卡片做不到的。

Shift+↑↓ 是 anchor/focus 的**範圍**，不是只增不減的集合：往上按把 focus 那端
走回 anchor。範圍走**畫面實際的順序**，也只有那個順序能讓「跨 hunk 但不能跨
檔」有意義。種子放在第一個**有變動**的列而不是第一列，否則前幾次按鍵都花在
連卡片都不會出現的 context 上，第一次按下去讀起來就是「這個鍵沒反應」。拖曳
結束時把框到的範圍收成 anchor/focus，兩種輸入共用一個範圍。

選取中的列現在會上色（`foregroundDecoration`，不是混色背景——這些列坐在兩種
不同底色上，overlay 才不需要知道底下是哪一種）。拖曳的高亮是 SelectionArea
免費給的，另外兩種輸入法完全沒有選到任何**文字**；沒有這層上色，使用者唯一
的線索就只有按鈕上的數字。拖曳也一起畫：一種選取一種樣子。

#### 驗證

主機層 2154 全綠。裝置層九支：新檔六支（兩方向 × 卡片按鈕／文字選取，加標頭
點擊與 Shift+↓），外加 `context_menu_flows` / `commit_flow` /
`working_copy_line_counts` 三支迴歸（`DiffLineView` 是共用列元件）。七次
mutation，只有「種子改成第一列」紅三支（種子位置會位移後面每一個斷言，是對
的），其餘每次只紅該紅的那一支。

### 一次性 scope 的按鈕位置：實作方便壓過了設計稿

使用者指出「一次性選取範圍的按鈕位置跟設計稿不一樣，應該在 scope 上套，而不是
最上方多一列」。去讀 demo（`Diff Scope Studies`，變體 B 第 3 塊「臨時 scope」）
的原始 HTML，設計是明確的：

```
.variant-B-card .variant-B-card-muted
├ .variant-B-cardhead   變更 1  +2 −1   [Stage 3 lines] ← .variant-B-btn-off（disabled + 刪節線）
├ .variant-B-cardbody   ← 選取「之前」的行
├ .variant-B-temp       ← 虛線 accent 外框，**就在卡片裡**
│  ├ .variant-B-temphead  臨時選取 [一次性]  [Stage 3 lines] ← 活的
│  └ .variant-B-cardbody  ← 被選取的那幾行本身
└ .variant-B-cardbody   ← 選取「之後」的行
```

而出貨的是一張釘在欄位最上方的獨立卡片。

**那不是一個設計決定，是一個實作方便。** 原本的註解寫得很誠實：把卡片插進列與列
之間會 reparent 底下每一列，而那些列身上掛著 `SelectionListener`，它們的回報正是
「這張卡片該不該存在」的依據——所以擾動它們是一個回饋迴圈。固定槽位可以完全避開。

**讓巢狀形式安全的，正是那條註解自己指到的東西。** 那些 key 是 `GlobalKey`，
Flutter 會把同一個 element **搬**進新的父節點，而不是卸載重建，註冊因此存活。
tracker 的 `keyFor` 文件從一開始就寫了這句：「a row moves between subtrees as the
diff changes … a global key makes Flutter reparent the one element instead」。當初
只是沒有把那句話用在這裡。

順帶一提，巢狀之後 `_wellChildren` 的清單長度**根本不會變**了——不再需要那個
`SizedBox.shrink()` 佔位。原本為了保持定長而存在的東西，在正確的結構下自動消失。

#### 一個 scope、一顆按鈕

選取跨越兩張卡片時，只有**第一張**（畫面順序）帶頭與按鈕；後面的卡片只有虛線
body，讓延伸範圍看得見。兩顆按鈕會讀成兩個動作，而它其實是一次。把
`showHead` 改成永遠 true 的 mutation 紅了五支——寬，但那正是「多一顆按鈕會弄壞
一堆 finder」的真實訊號；另外補了一支直接針對「只有一顆頭」的測試。

#### 位置測試的夾具要能falsify「就地」

第一版夾具是 `.+..-.` 配 l1→l2 選取，而那兩列剛好在卡片列的**開頭**——所以
「就地」和「釘在卡片最上面」在那個夾具下無法分辨。換成 `.+++.` 只選中間那一列，
上面一列、下面一列都在，`temp.top > 上一列.bottom` 與 `temp.bottom < 下一列.top`
才是能被 falsify 的主張。把區塊挪到卡片內最上面的 mutation 因此只紅那一支。

muted 的左邊框顏色本來沒有任何測試在看——一張保留 accent 條紋的卡片不會丟例外，
只會同時有兩個東西宣稱自己是活的 scope。補上以身分比對的斷言。

#### 巢狀之後的代價：拖曳中途不能畫

使用者接著回報「要等我 mouse up 才畫自選 scope，不然只能選一行」。

這正是原本那條註解擔心的事，只是它擔心的方向反了：問題不在**插入時 reparent 會
不會把註冊弄丟**（`GlobalKey` 解決了那個），而在**拖曳進行中**那次 reparent 會移動
底下每一列的幾何，而那些列身上的 `SelectionListener` 正在回報選取——選取因此被
擾動，拖曳塌回一列。

修法就是使用者說的那句：**指標還按著的時候，不畫任何從 touched 推導出來的東西。**
拖曳期間的即時回饋是 `SelectionArea` 自己的文字高亮；一次性區塊是拖曳**沉澱**成的
結果。`endGesture()` 因此要發通知——在所有中途重建都被抑制之後，指標放開是唯一
還會觸發渲染的訊號。

**第一次 mutation 又回綠了，而且指出我的因果講錯了。** 我把閘門做成兩層（`build()`
裡 `settledTouched` 的三元式，加上 `_onTouchChanged` 在拖曳中提早 return），拿掉
前者是綠的——因為後者根本不讓重建發生，測試碰不到前者。加了一行「從外部強制一次
重建」（用**同一個** `DiffFile` 實例重 pump，否則 `didUpdateWidget` 會因為換檔而清
掉選取，斷言就會因為錯的理由通過）之後，同一個 mutation 才紅。

反過來拿掉 `_onTouchChanged` 的提早 return 是**綠的**。所以正確性只靠 `build()` 那道
閘門，另一半純粹是重建成本——拖過二十列時每幀重建整欄、而輸出完全一樣。註解照這個
事實改寫了，因為 CLAUDE.md 說註解宣稱的東西必須是真的。

#### 沒有任何合成手勢重現得出那個症狀——這一點要講清楚

**四次 mutation 全是綠的。** 把閘門完全拿掉（`settledTouched` 的三元式與
`_onTouchChanged` 的提早 return 都拿掉），在裝置層一列一列拖是綠的，改成列內三段
的次列移動也是綠的。所以**「畫在拖曳中途→reparent→選取塌成一列」這條因果，沒有
被這個 repo 裡的任何東西證實**，修法也沒有被任何測試驗證對得上那份回報。

被釘住的是那個**不變式本身**（指標按著時不畫），以及它在外部重建下也成立。使用者
回報的症狀本身，只能由使用者在真機上確認。裝置層那支測試的註解裡直接寫了這句，
免得未來有人把它讀成驗證。

過程中找到第二個有根據的嫌疑犯，而且它有明確的框架行為當依據：**`SelectableRegion`
失去焦點時會清掉自己的選取**（`_handleFocusChanged`，非 web），而上一輪為了
Shift+↑↓ 加的 `Focus` 節點在每次 pointerDown 都無條件 `requestFocus()`——那是一條
把選取從正在製造它的手勢底下抹掉的活路。改成只在 `!hasFocus` 時才要：`hasFocus`
對 primary focus 的**祖先**也成立，所以「底下的 region 才是真正持有焦點的那個」
這個情況已經被涵蓋，按鍵事件兩種情況下都到得了 `CallbackShortcuts`。

這一條同樣沒有測試能證實它就是症狀的成因。兩個修法都是**有根據但未經驗證**的。

#### 「因為我是用觸控板」——這條線索被框架自己駁回了

使用者補了一個細節：他是用**觸控板**拖的。那看起來正好解釋了四次 mutation 為何
全綠——我注入的一直是 `PointerDeviceKind.mouse`。而且有依據：`ScrollBehavior`
預設的 `dragDevices`（`_kTouchLikeDeviceTypes`）**不含 mouse、含 trackpad**，所以
可捲動區域可以搶走一個它絕不會從滑鼠手上搶走的拖曳。於是把裝置層那支拖曳測試改成
在兩種 kind 上各跑一次。

**跑出來是紅的，但紅在框架的斷言上，不在我們的行為上：**

```
'package:flutter_test/src/test_pointer.dart': Failed assertion: line 567 pos 12:
'_pointer.kind != PointerDeviceKind.trackpad': is not true.
  #2  TestGesture.moveTo
```

追到 `gestures/events.dart`：`PointerDownEvent`、`PointerMoveEvent`、
`PointerUpEvent`、`PointerCancelEvent`、`PointerEnterEvent`、`PointerExitEvent`
**六個類別的建構式各自都斷言 `kind != PointerDeviceKind.trackpad`**。也就是說，
指標式的拖曳事件在這個框架裡**根本不可能**帶 trackpad 這個 kind——`trackpad` 專屬
於 `PointerPanZoom*`（雙指平移／縮放），而那也是它能碰到 `dragDevices` 那個集合的
唯一途徑。觸控板的**按下並拖曳**，引擎是當成一般滑鼠指標送上來的。

所以：

- 那支參數化測試是在測一條硬體不會產生、框架也不允許的路徑，已還原成單一 mouse 版。
- **「合成手勢只說 mouse，所以看不見觸控板的路」這個假說是錯的**——原本那支測試
  走的就是回報來源的那條路。
- 上一節「四次 mutation 全綠、因果未被證實」的結論**不變**，而且現在少掉一個可以
  推給裝置差異的藉口：仍然無法解釋。

使用者後來在真機上確認修好了。那是這一輪唯一一份症狀層級的證據，但它**分不出**是
兩個修法（拖曳中途不畫、`requestFocus` 加 `!hasFocus` 守衛）裡的哪一個治好的，
也可能是兩個一起。這裡照實記著，不把它讀成任一個修法的驗證。

#### 一支無法與程式碼意見不合的測試，刪掉

我先在主機層寫了一支「一列一列拖，四列都要留住」，**它在缺陷還在的時候就是綠的**
——主機層的選取幾何撐得過中途的樹重組，真實的撐不過。依 CLAUDE.md 那條「夾具無法
與程式碼意見不合就什麼都沒證明」，那支從主機層刪掉，改寫進裝置層
（`stage_lines_flow_test`）；主機層留下的是**能**被證偽的那個不變式：指標按著時
不畫。

### macOS 的 About 是原生面板，Help 的 Check for updates 是規格外的第五項 (fix/macos-about-dialog-parity)

使用者的回報只有兩句：「macOS 上的 Help > About 樣式與 Windows 上不同」、「Windows
版有包含 check for update，因此要把 Help > Check for update 拿掉」。兩句都成立，
而且第一句的成因不是主題、字型或視窗裝飾，是一條明確的程式碼分支。

#### 一個 action id，兩個不同的視窗

`platform_menu_bar_host.dart` 有一個叫 `_systemProvided` 的集合，裡面放
`fileExit` 與 `helpAbout`；落在集合裡的 id 不會被掛成一般的 `PlatformMenuItem`，
而是在選單尾端補一個 `PlatformProvidedMenuItem`。Quit 那半是對的——它屬於 Apple
應用程式選單，macOS 確實自己提供。About 那半不是：`PlatformProvidedMenuItemType
.about` 叫的是 `orderFrontStandardAboutPanel:`，也就是**原生 About 面板**，而
Windows / Linux 走的是 `_buildActionHandlers()` 裡的
`context.push(RoutePaths.aboutDialog)`，開的是 `AboutDialogContent`。同一個
`helpAbout`，兩個平台兩個不同的視窗。

規格頁 01 的散文把這件事判乾淨了：意圖行寫「三平台統一樣式，只有 menu bar 位置與
標題列跟隨系統」，自繪清單把範圍寫死在「視窗**內**所有內容」，而「依平台不同的部分
（僅三項）」列的是 menu bar 的**位置**、標題列按鈕樣式、系統檔案選擇器——沒有一項
是「選單項的行為」。About dialog 是視窗內內容。

#### 為什麼三條 dispatch path 的 parity 測試看不見它

這才是值得記的部分。CLAUDE.md 有一條既有的不變式：鍵盤、macOS 系統選單、in-window
選單三條路徑必須共讀 `_buildActionHandlers()` 那張 map，而且 repo 裡有一支
`workspace_intent_dispatch_parity_test.dart` 專門守它。這個缺陷從那張網底下穿過去
了，原因是：

**system-provided 的項目根本不從 map 取 handler。** parity 測試問的是「handler 是不
是非 null」，而一個 `PlatformProvidedMenuItem` 連 `onSelected` 欄位都沒有——它不是
「handler 為 null」，它是「不在被問的那組東西裡」。同時 in-window 的點擊測試只跑
非 macOS 那條路徑，所以它看到的一直是正確行為。兩邊都綠，缺陷在中間。

修法對應的測試因此不能只斷存在：`workspace_about_dialog_test.dart` 拿到真
`WorkspaceScreen` 建出來的 `PlatformMenuItem` 之後，**呼叫 `onSelected!()` 再斷言
渲染出什麼**。而且路由表裡放了 `keyboardShortcutsDialog` 當**誘餌**——沒有它，接錯
線會失敗在「找不到 route」，那是比「內容不對」弱的紅，會讓測試看起來證明了比實際更
多的東西。

突變檢查把這兩層分開量了：

| 突變 | 變紅的 |
|---|---|
| `helpAbout` 放回 `_systemProvided` | `platform_menu_bar_host_test` 的結構斷言 + macOS 的呼叫斷言（in-window 那條維持綠，正確——突變只影響 macOS） |
| `helpAbout` 的 handler 改指 `keyboardShortcutsDialog` | **兩條渲染斷言都紅**（突變落在兩者共讀的 map）。而只斷 `onSelected != null` 的那半在同一個突變下維持綠 |

第二列的後半是這一輪真正的收穫：**「非 null」與「指向正確的 route」是兩個不同的
命題，而前者一直被當成後者的證據。**

#### Apple 選單那個 About 沒有被動到，而那是對的

一開始擔心拿掉 Help 的原生 About 會讓 macOS 一個原生 About 都不剩。查證後不會：
Flutter 的 `PlatformMenuBar` 只取代 index 0 之後的選單，`MainMenu.xib` 裡
`systemMenu="apple"` 的那個應用程式選單原封不動保留，`About APP_NAME` /
`Hide` / `Quit` 一直都在。macOS 慣例本來就把 About 放在應用程式選單，所以 Help 裡
再放一個原生的是**重複**而不是必要。`fileExit` 留在 `_systemProvided` 也是同一個
理由。

#### 第二句：Help 的第五項

`Check for updates…` 坐在 `Report an issue` 與 `About` 之間，原始碼註解自己寫著
「Not in the spec at all」。而規格 P04 `MENUS` 給 Help **四項**，
`spec-conformance-matrix.md` 記的是 `Help 4`，`gbm_menu_model.dart` 自己的
`// Help (4 items)` 與 `gbm_action_id.dart` 的 `// Help (4)` 也都寫四——**三處宣稱
四，清單裡有五，沒有任何測試看過 Help 的內容**。所以移除它不是 deviation，是回歸
符合；三處註解也才名副其實。

移除前先照 orphan 規則查了 `RoutePaths.updateDialog` 的生產者，扣掉要刪的那個還有
三個：`about_dialog.dart` 的 primary 按鈕、`preferences_dialog.dart` 的
「Check for updates now」、`app.dart` 的 `AutoUpdateCheck` 開機檢查。About 那顆是
關鍵的一個——`WelcomeScreen` 完全不建 menu bar，所以沒開 repository 時它是**唯一**
到得了更新檢查的路。因此 `GbmActionId.helpCheckForUpdates` 連 enum 值一起刪，
`gbm_shortcuts.dart` 本來就沒有它的綁定。

裝置層也 grep 過了：`update_check_flow_test.dart` 走的是 WelcomeScreen 的 About
tooltip → About dialog 的按鈕，不是 Help 選單，所以不受影響。**而且真的跑了**
（`flutter test integration_test/update_check_flow_test.dart -d macos`，先跑
`scripts/build_capi.sh` 免得載到過期的 dylib）：2/2 綠，2 分 37 秒，含向真的
GitHub Releases 下載資產並比對已發布的 sha256。這是「拿掉選單項之後更新檢查仍然
到得了」在實機上的證據，不只是 grep 的推論。

新測試斷的是 **label 不是 id**：enum 值刪掉之後，引用 `GbmActionId
.helpCheckForUpdates` 的測試會編不過，那是壞掉不是變紅。而既有的
「every GbmActionId appears exactly once」斷言 `idSet == GbmActionId.values
.toSet()`，兩邊同時縮小會自動維持綠——它**看不到**這次移除，這正是新測試不是重複的
原因。

突變檢查在這裡踩到一個自己造成的假訊號：第一版突變是「把第五項塞回去」，但任何新增
的項目都得複用一個既有 id（每個 id 依設計恰好出現一次），於是重複 id 也讓
「appears exactly once」變紅，紅得比預期寬。改成「把 `About` 的 label 改成
`About…`」之後只有目標那條紅。**紅得太寬時先懷疑突變本身，再懷疑測試。**

#### 順手了結 #67

修好 Help → About 之後，Apple 選單裡仍寫著 `About gbm_flutter`。`MainMenu.xib` 把
Apple 選單、About、Hide、Quit 都寫成字面 placeholder `APP_NAME`，由 AppKit 在載入
時從 bundle 解析（`CFBundleDisplayName` → `CFBundleName`），跟
`MainFlutterWindow` 設的 `NSWindow.title` 完全無關——#66 修的是後者，所以前者留著。

使用者裁定採 #67 的候選修法 1：`Info.plist` 的 `CFBundleName` 從 `$(PRODUCT_NAME)`
改成字面 `git-branch-manager`。不動 `PRODUCT_NAME`，因為它同時是**產出物**的名字，
`release.yml:161,204,226,254` 硬編 `gbm_flutter.app` / `.exe`，改它要連簽章、公證、
DMG 三步一起動，而那只有 tag build 驗得了。

這一段是本輪唯一沒有任何 Dart tier 到得了的東西，所以真的跑了一次
`flutter build macos --debug` 取證。產出物層面確認了三件事：bundle 仍叫
`gbm_flutter.app`、`CFBundleExecutable` 仍是 `gbm_flutter`（`release.yml` 不受影
響）、而 `Contents/Info.plist` 的 `CFBundleName` 已是 `git-branch-manager`。

**照實記一個限度**：畫面上的 Apple 選單文字沒有被程式化地讀到。`osascript` 走
System Events 需要輔助使用權限（未授予），而截圖驗證會拍到使用者整個桌面，做了一次
之後就停手並刪除了。所以「Apple 選單顯示 git-branch-manager」這句的證據是
**因果鏈**（#67 觀察到實機顯示 `gbm_flutter` → AppKit 解析 app 名稱的唯一來源是
bundle → bundle 現在是對的），不是直接觀察。要直接觀察得由人在機器前看一眼。
#67 原文自己留了退路：若還有地方顯示舊名（Dock tooltip 最可能），補一行
`CFBundleDisplayName` 同樣的字面值即可——目前的 bundle 沒有這個鍵。

#### 一句過期的註解

`MainFlutterWindow.swift` 那段「同步指派會被還原成 `CFBundleName`，也就是
`gbm_flutter`」在 `CFBundleName` 改掉之後就過期了。機制沒變（同步指派仍然會被還
原），變的是後果：現在還原到的是同一個字串，所以那行延後指派**單看起來變成可以刪
的**。它沒有被刪，而且註解裡寫明了理由：`CFBundleName` 是 *application* 名稱，
`self.title` 是 *window* 標題，兩者現在只是碰巧相同，沒有任何機制讓它們保持同步；
因為「還原本來就會落在正確值」而刪掉它，等於把兩者悄悄耦合起來。

### 側邊欄目前分支不再置頂 (feature/head-branch-removal)

使用者要求三件事：側邊欄不要顯示 head branch、不要把目前分支釘在上面、改成預設展開
到它所在的資料夾，而且不改分支優先權、純字母排序就好。

#### 三個特殊待遇必須先被拆開，才知道要拿掉哪些

「不要顯示 head branch」讀不出唯一解，所以先把 HEAD 在側邊欄實際享有的待遇逐一列
出來，再讓使用者裁定：① 過濾時就算不符合查詢也被強制加回樹裡（P02-14 rule 7）
② 在所屬資料夾內置頂（`BRANCH_STATES`）③ 名稱粗體加整列 `surfaceSelected` 底色。

裁定是 **①② 拿掉、③ 保留**。這個切法不是折衷：③ 是位置消失之後唯一還在說「我在
哪」的訊號，而且 `branch_selection_rules.dart` 的 `isBulkSelectable(ref) =>
!ref.isHead` 的理由整條就架在它上面——目前分支永久畫著 selected 底色，如果它同時
還能被多選，兩種狀態會畫得一模一樣。拿掉 ③ 會連帶讓那條註解變成謊話。

另外兩個問題也一併問了：資料夾在前算不算「branch priority」（不算，樹狀結構慣例，
保留），以及展開的觸發時機（開啟時加上每次 HEAD 變動，且不自動收合）。

#### 沒有活下來的前提

**「一併把視覺標示也拿掉」不成立**，理由如上。

**`origin/HEAD` 不是使用者說的 head branch**：`mergeLocalAndRemoteBranches` 早就用
`!r.isSymbolic` 排除掉符號性遠端 ref 了，這個讀法在改任何東西之前就被原始碼駁回。

**「側邊欄有一個樹以外的目前分支列」也不成立**：`TopBar` 拆掉之後，側邊欄從上到下
是 `RepoSwitcherButton` → `BranchesSectionHeader` → 過濾框 → 動作列 → 樹，沒有任何
一個地方單獨畫 HEAD。所以①才是「顯示了不該顯示的東西」的唯一候選。

#### 由跑出來、而不是讀出來的事

**Commit 1 如果照原訂範圍切，它單獨 checkout 是紅的。** 原本打算把
`sidebar_current_branch_pin_test.dart` 整個留到 Commit 2 再改，但那個檔的 no-filter
兩條測的是 comparator 而不是過濾——置頂子句一刪就紅，跟 rule 7 還在不在無關。這正是
CLAUDE.md 那條「每次都在分支頂端跑就永遠是綠的，只有逐 commit checkout 才看得到」的
同一個形狀，所以那兩條被移進 Commit 1。

**順序的影響範圍比展開大，而且我一開始只掃了展開的那一半。** 事前 grep 找的是
「shortName 帶斜線的 HEAD fixture」，那界定的是自動展開會多畫幾列；但 Commit 1 同時
改了 **root 層**的順序（HEAD leaf 原本壓過同層資料夾，現在資料夾一律在前），受影響
的是「HEAD 在 root、同層又有資料夾」的 fixture——`sidebar_filter_test.dart` 的
`main` 就是。跑整個 `test/features/sidebar/` 才看到那兩條紅。掃描條件要對著**改動
的性質**寫，不是對著改動的檔案寫。

**`skip` 不是被順手刪的，是刪不掉才有問題。** `firstLeafName(nodes, {RefInfo? skip})`
的 `skip` 存在的唯一理由，就是 rule 7 硬塞進樹裡、↓ 不該落上去的那一列。那一列消失
之後它必然沒有呼叫端——留著就是 CLAUDE.md 列了八次的 orphan wiring。

#### 自動展開為什麼不需要 post-frame

`_pruneSelection` 的 doc comment 花很長篇幅說明它為什麼一定要延後到 frame 之後：它
寫的是 provider，會撞上 Riverpod 的 `_debugCanModifyProviders`，而那個 assert 在
release 版被剝掉，寫入會直接落在 build 中間。

自動展開**沒有這個問題**：`_expandedFolders` 是 `_SidebarPanelState` 自己的欄位，不是
provider，也不需要 `setState`——因為同一個 build 在幾行之後就把它讀進
`buildBranchTree`。所以第一幀畫出來就是展開的，不會先閃一下收合的樹。兩者的差別是
「寫的東西歸誰管」，不是「在 build 裡寫東西安不安全」，這個區分值得寫下來，免得下一輪
照抄 `_pruneSelection` 的結論。

閘門 `_seededExpansionForHead` 讓 mount 與 checkout 走同一條路徑（`null → 'main'` 也
算一次變動）。這是 `ref.listen` 做不到的那一半：它不會為註冊當下就已經存在的值觸發，
而 refs 通常在這個面板 build 之前就載好了。只 `addAll` 不 `remove`，「不自動收合」就
是靠這個成立。

#### Mutation check

- `_compareTreeNodes` 的「資料夾在前」翻成 `return 1`：紅在 4 條，全部是斷言同層順序
  的，其餘 245 條綠。
- 把 rule 7 的豁免整段加回 `buildBranchTree` 的輸入：紅在 10 條，全部在新改寫的兩個
  檔案裡。
- `if (headBranch != _seededExpansionForHead)` 改成永遠不成立：4 條展開測試紅，兩條
  「不展開」的 CONTROL 維持綠。
- 只拿掉 `_seededExpansionForHead = headBranch;`（等於每幀重新種）：**只紅一條**，
  就是「使用者手動收合的資料夾不會被強制重開」。這條的紅是窄的才有意義——它是「不自動
  收合」這個承諾唯一的持有者。

#### 刻意留下的

`sidebar_panel.dart` 空狀態的 `filteredBranches.isEmpty` 沒有改回 `branchTree.isEmpty`。
兩者現在確實等價（樹不再永遠帶著 HEAD），但 0 命中是**查詢**的性質，從畫出來的東西
反推會讓它變成**渲染**的性質——那正是它上一次出錯的方式。註解就地改寫成這個理由，
而不是刪掉。

命中/總數（rule 6）本來就只數真正的比對結果，這輪不該讓它動，所以那條測試原封保留
當回歸測試——但它的敘述從「豁免的那列不算命中」改成「那列根本不在畫面上」。

#### 驗證

`flutter analyze` 零問題、`dart format` 乾淨、`flutter test` 2166 條全綠。裝置層依
CLAUDE.md 的規則一起掃了：`rename_branch_flow_test.dart` 的分支刻意不帶斜線
（`lane-allocator`），自動展開對它無效，但 HEAD 那一列的位置會從置頂變成字母序；重建
capi 之後跑過，綠。

### History 的並排 diff：把刪掉的東西請回來 (feature/history-split-view)

使用者要 History 選檔案後的 diff 能左右並排看 舊/新。裁定兩件事：並排的意思是
side-by-side（不是「檔案清單與 diff 左右分割」），而且檢視模式要持久化到
shared_preferences（不是只存在 widget state）。

#### 這一輪最值錢的一句話，在紀錄裡而不在程式碼裡

開工前 grep 規格，得到的答案是「規格從來沒有要求 side-by-side diff」——這句話本身
到今天都還是對的。但同一次 grep 也翻出上面第 4 點：`side_by_side_diff.dart` 與
`side_by_side_diff_view.dart` **曾經存在，而且是被刻意刪掉的**，理由正是「規格依據
只有 mockup 裡一個假 commit 訊息」。

於是這一輪不是「新做一個功能」，是**在使用者裁定下把它請回來**。而請回來這件事，
真正的工作量不在寫程式，在**當場更正那筆判定**：

- `docs/reports/spec-conformance-matrix.md` 那段「orphaned code answering no
  requirement」已就地劃掉並改寫（比照 #45/#50/#51/#60 的先例：更正並留證據，不是
  悄悄改標題）。規格那半句保留——規格確實沒要求；改變的是「規格沒依據」不再足以
  構成刪除理由。
- 兩個還原的 `.dart` 檔各自在 doc comment 裡帶上同一段引述與裁定日期，所以下一次
  orphan 清掃**從程式碼就讀得到**，不必先想到要去翻 ledger。

不做這件事的後果很具體：orphan 清掃讀的就是那張表。原樣留著，它會用使用者已經
推翻過的理由，把同樣兩個檔案再刪一次。

#### C++ 那半邊還活著，而且沒有呼叫者

`src/core/git/SideBySideDiff.{h,cpp}` 連同 `tests/unit/SideBySideDiffTest.cpp`
**都還在**，只有 Dart 那半被刪。查證後確認 C++ 版沒有任何呼叫者。

決定是**保留**，並把「這是決定不是疏忽」寫進 `SideBySideDiff.h`：需要配對的是
Flutter 那一側，它手上已經有解好的 `DiffHunk`，為了一次同步的重新排版繞一趟 capi
是純粹的額外成本。所以活的實作是 Dart 版，C++ 版留作它逐行鏡射的**參考實作**——
與 `GraphAsciiRenderer.cpp` 對 commit graph 的地位相同。CLAUDE.md 已經記過
「不是每個沒被呼叫的函式都是 orphan」（`sameLogicalFile` 那個 oracle 的案例），
這是同一類的第二例。

#### 兩份 suite 都沒走到的那個分支

還原後逐案比對，六個案子與 C++ 版一對一無誤。但 `pairHunkForSideBySide` 的
`noNewlineMarker` 那一臂**兩邊都沒有測試走到**——而它就緊接在 Context 案下面，是
最容易被後人「順手簡化」成同樣 `rows.add(row(line, line))` 的一段。兩邊各補兩案
（marker 接在 removed 之後只留左側、接在 added 之後只留右側），維持逐案鏡射，並在
兩個檔案裡都寫下「改一邊就要改另一邊」。

Mutation：把該分支改成無條件雙側，恰好只有這兩支新測試轉紅（+6 −2）。

#### 還原的 view 有三個缺陷，都是任何一層測試都看不見的

這是「刪掉的程式碼不能原封照抄」的具體理由。三個都在還原時逐行讀出來，不是跑出來的：

1. **行號取錯邊**，最嚴重。原版是 `kind == removed ? oldLine : newLine`：對 removed
   （左欄）與 added（右欄）都對，但 **context 行兩者皆非**，於是一律落到 `newLine`
   ——左欄替「變更前」標上了「變更後」的行號。只要 hunk 的 `oldStart == newStart`
   就完全看不出來；前面一有增刪，整個左欄的行號就是錯的。
   改法把歸屬換了個層級：行號由 `SideBySideSide` 決定（左讀 `oldLine`、右讀
   `newLine`），也就是**欄位的性質**，而不是從行別去推論。這一類 bug 的形狀值得記
   ——用「衍生量」去推「本來就有的量」，在多數樣本上剛好相等，於是不相等的那少數
   永遠沒人看見。
2. **空白補位格寫死 `height: 20`**。對面那格一換行，空白側下方就露出沒上色的區域。
   改成配對的 `Row` 走 `CrossAxisAlignment.stretch`，外面包 `IntrinsicHeight` 給它
   一個撐得到的高度；空白格自己不再宣告任何高度。
3. **少了 `SelectionArea`**。現行 `DiffPage` 在 ListView 外包了一層，並排版沒有，
   換個模式就不能拉選複製。

三個各補一支測試，各自 mutation 過，每次都恰好只有對應那一支轉紅。

#### 換行不需要處理，這點一開始想錯了

原本擔心兩欄換行會讓左右錯位，準備上 `softWrap: false` 加同步水平捲動。實際上不必：
**一組配對就是一個 `Row`**，跨欄對齊由結構保證，某一格換成三行，它的夥伴跟著長高，
兩欄永遠是齊的。於是換行維持與 `DiffPage` 一致。

代價是另一件事：兩欄共用一個選取範圍，跨欄拉選會複製到 舊+新 交錯的文字。Working
Copy 的 `2 file` 模式是同樣形狀的先例，05-G 的 `Copy` 是單側逃生口。分成兩個選取
範圍會修好複製、但弄壞「選一整段變動」這個遠遠更常見的情況，所以是**選擇的取捨**，
已寫進 doc comment，不假裝沒有。

#### 量到的數字：預設為什麼是 unified

1280×720（app 自己的預設視窗）下中央欄約 834px = 1280 − 側邊欄 250 − Changed files
186 − 兩條分隔線。commit detail 橫跨整欄。對切後每側再扣掉 36px 行號槽與 padding，
只剩約 360px 等寬字，**約 48–52 字元**。

並排在預設視窗是偏窄的，所以預設 `unified`，而持久化的意義正在這裡：想用的人切一次
就好。這個數字寫下來，是為了下一輪重新決定時能對著數字而不是對著同一個猜測。

#### 三層測試各自證明什麼，用 mutation 劃清界線

- `diff_view_mode_repository_test.dart`：store 會來回，但什麼都沒畫。
- `commit_detail_panel_test.dart`：兩個 renderer 接對了 enum，但**對 provider 一無
  所知**——容器就算什麼都沒接，這 12 支照樣全綠。
- `history_diff_view_mode_test.dart`：兩者之間的接縫。

界線是量出來的而不是宣稱的：把容器的 `onDiffViewModeChanged` 改成空 callback
（切換鍵照畫、照回報，就是什麼都沒寫回去），**integration 轉紅、widget 層 12 支
全綠**。那一層看不見這個缺陷，這支測試因此有存在的理由。

#### 順手補掉的一個既有缺口

`real_repo_harness.dart` 的 prefs 清除清單只涵蓋 `panelLayout.` 與 `graphColumns.`
兩個**前綴**，平鍵一律漏掉。新的 `diffViewMode` 是平鍵——開發者在真機切過一次並排，
之後每支裝置層測試畫出來的東西就都變了，而且只在他機器上變。

`fileListViewMode` 早就有一模一樣的暴露（Tree 模式會把列塞進資料夾列底下，正是讓
finder 失準或落空的形狀），一併補上。既然踩到就補掉，不留給下一輪當 flake 重新發現。

#### 刻意沒做的事，逐項寫明

- **範圍只有 History 的 `CommitDetailPanel`。** Compare、管理面板、Working Copy 的
  diff 區、Conflict 視窗都不動，`DiffPage` 本身一行未改——它是四個介面共用的。
- **不加選單項目與快捷鍵。** Working Copy 的同型切換也只有標題列這一個入口，比照
  辦理；這是刻意對齊，不是漏掉。
- **不與 Working Copy 共用同一筆偏好設定。** 那組的兩欄是 unstaged／staged，這組是
  old／new。長得像，意思不同；一個偏好翻兩邊，會在使用者沒在看的那個視圖造成意外。

#### 裝置層：先誤判成「跑不成」，再被自己的重跑推翻

第一次跑 `flutter test integration_test/... -d macos` 回的是
`Failed to foreground app; open returned 1`，同時 `pgrep` 查到**另一個 Claude
session 正在 `feature-soft-warp` 底下跑裝置層**，`gbm_flutter` 活著（PID 96171）。
兩件事湊在一起，看起來因果分明：資源被佔用，所以前景化失敗。沒有 kill 它——
CLAUDE.md 寫著「憑臆測殺掉會毀掉真正的工作」，而那確實是別人正在跑的工作——
於是把「裝置層本輪未跑」連同代償的靜態稽核一起寫進了這一節。

**那段結論是錯的，而且是這一節原本的內容。** 稍後那個 process 結束、重跑一次，
`Failed to foreground app; open returned 1` **照樣印出來，然後測試照樣全綠**。
這行字不是失敗訊號，它在完全綠燈的 run 上也會出現；真正能分辨的是它後面有沒有
接上測試結果那幾行。當時只讀到那行就停了，於是把一個警告讀成了阻塞。

蒸餾進 CLAUDE.md 的裝置層那條既有條目（不是新開一條）：**讀過那行、看到計數，
再判斷 tier 是不是真的被擋住。**

實際跑完的結果：先跑 `build_capi.sh`——**編譯無事可做（`ninja: no work to do`），但
載入路徑上的 copy 原本並不存在**（`app_flutter/build/native/libgbm_capi.dylib` 那次 `ls`
是失敗的），補的正是 copy 那一步，也就是「過期 dylib」那條陷阱真正防的東西。接著控制組
`commit_file_counts_test.dart` 2/2 綠，其餘 10 支逐支重跑，**11 支檔案、26 個 test，全綠**（控制組 `commit_file_counts` 2 ＋ `commit_flow` 1 ＋ `conflict_flow` 1 ＋ `context_menu_flows` 5 ＋ `history_filter` 2 ＋ `multi_push_flow` 2 ＋ `rename_branch_flow` 2 ＋ `repo_lifecycle` 1 ＋ `stage_lines_flow` 7 ＋ `update_check_flow` 2 ＋ `working_copy_line_counts` 1）。

靜態稽核本身仍然成立，而且後來補的一次 grep 讓它更硬：`integration_test/` 底下
**沒有任何一支測試提到 `CommitDetailPanel`、`DiffPage`、`commitFile*` 或
`selectedCommitFilePath`**，一個字都沒有。也就是說這輪新增的那條標題列，在整個裝置層
的流程裡從頭到尾沒有被畫出來過——這解釋了為什麼全綠是預期中的結果，而不是運氣。

還是要說清楚它證明的邊界：全綠證明「改動沒弄壞既有的裝置層測試」，**不證明
「並排檢視在真機上長得對」**。後者沒有任何一層自動化測試涵蓋，只有人眼能確認，
所以它仍然是使用者的一個手動步驟，不是已經發生過的事。
### History 捲動卡頓：主因不是圖，是整個 shell 在重建 (fix/graph-scroll-issue)

使用者的問題是「捲動 History 會頓」，並自己提了一個假設：**能不能先把線畫好再
顯示**。方向是對的，但那不是主因，而找到主因靠的是使用者補的第二句話：
**「每次捲動 menubar 都會閃爍」**。

menubar 不在 `CommitGraphView` 裡，它在 `WorkspaceScreen`。它會閃，就代表整個
shell 每次捲動都在重建。這也解釋了原本解釋不了的事：**這個 repo 只有 703 個
commit，捲動一樣頓**。O(N) 掃描在 703 筆下太小，撐不起那個體感；重建風暴在任何
repo 大小下都一樣發生。

#### 主因：`ref.watch` 監聽整包 state

`workspace_screen.dart:216` 原本是 `ref.watch(repoSessionProvider(identity))`。
捲動的迴圈是這樣接起來的：

```
_onScroll（每個捲動 tick）
  → _requestVisibleMeta → requestCommitMeta → FFI
  → commitMetaReady
  → state.copyWith(commitMetaCache: ...)   ← 新的 RepoSessionState 物件
  → WorkspaceScreen.build() 整個跑一次
  → MenuBarRow / PlatformMenuBarHost / ActionToolbar / TabRow
    ＋ _buildActionHandlers() 全部重建
```

macOS 上 `PlatformMenuBarHost` 重建的是真的原生 `PlatformMenuBar`，那就是使用者
看到在閃的東西。而 metadata 是隨捲動連續回來的，所以整段捲動期間這個迴圈不停。

**最乾淨的佐證是欄位盤點**：`WorkspaceScreen` 全檔讀十個 session 欄位，
`commitMetaCache` 一個都沒讀到——它是這個 shell 重建的唯一原因，卻不可能改變畫面
上任何一個像素。

修法是 record 版的單次 `.select()`，只挑真正消費的九個欄位。`copyWith` 對沒給的
參數保留同一個實例，而這些型別都沒有覆寫 `==`，所以 record 以 identity 比較。

**兩個 derived getter 刻意不放進 record**：`gonePendingRefs` 每次呼叫都
`expand().toSet()` 生成新的 Set，Set 沒有值相等——放進去會讓 record 永遠不相等，
等於把要修掉的重建風暴原封不動裝回來。這是那種「改了、測了、看起來對，其實什麼
都沒修」的形狀。

**沒有改四十個呼叫端**：`session` 是整包傳給 `isActionEnabled()`、
`_backgroundTasks()`、`_headTrackingRef()` 與 `_ConflictBanner` 的。第一版想把
record 傳下去，盤點後發現 `grep 'session\.'` **會漏掉整包傳遞的呼叫端**，真正的
數字是約四十個而不是十個。所以改成 watch 一個 record、`read` 完整狀態：不增加第
二個訂閱，而且跑在那次 watch 已經決定要跑的 build 裡，值是最新的。

#### 量測：第一次量錯了，錯在 JIT 暖機

四個數字全部用 debug JIT + `Stopwatch`，比照 `DiffScopeCache` 的先例。**第一輪的
數字是錯的**，而且錯得很有教育意義：我在同一個迴圈裡依 N 遞增地量，於是最小的
N 跑在最冷的 JIT 上。索引版看起來是這樣：

| N | 索引版（未暖機） |
|---|---|
| 703 | 8.85us/列 |
| 10,000 | 2.08us/列 |
| 100,000 | 0.58us/列 |

**成本隨 N 下降**——一個索引不可能有這種形狀。那不是資料，那是暖機。結論當時甚至
是「703 筆下索引比暴力掃描還慢」，差點據此加一個沒必要的門檻。兩條路徑都先跑
20,000 次暖機之後：

| N | edges | 暴力 | 索引 | 25 列視窗 |
|---|---|---|---|---|
| 703 | 800 | 1.5us/列 | 0.79us/列 | 37us → 20us |
| 10,000 | 11,561 | 25.7us/列 | 0.46us/列 | 644us → 12us |
| 100,000 | 115,739 | 260.5us/列 | 0.49us/列 | 6,514us → 12us |

索引後成本與 N 無關，這才是索引該有的形狀。建索引本身 100k 筆約 26ms，惰性建立。

`matchingRowIndices`（空查詢）同樣重量：

| N | 之前（generate） | 之後（視圖） |
|---|---|---|
| 703 | 4.0us | 0.30us |
| 10,000 | 41.2us | 0.063us |
| 100,000 | 669.9us | 0.073us |

#### 使用者的想法，換成不推翻既有決定的形式

「先把線畫好」如果照字面做成 per-row segment 清單，會直接撞上
`graph_edge_geometry.dart:108-109` 白紙黑字拒絕過的東西（O(N x lanes) 記憶體）。
所以做的是**每份 snapshot 一份 spanning 索引**：`_startsAt` 加上每 64 列一次的
`_activeAtBlockStart`，記憶體仍是 O(N+E)，查詢從 O(E) 降到 O(該列實際有的邊)。

**刻意不依賴 lane**：`_activeAtBlockStart` 是對真實 span 掃出來的結果，不是從圖形
性質推導的。CLAUDE.md 記過一條被相信但為假的 lane 不變式
（`edge.lane == rows[parentRow].lane`），任何靠 lane 結構的索引都會站在同一種前提上。

快取掛在 `Expando` 上，key 是 snapshot 實例。不需要失效機制，而**那是設計不是缺口**：
新的 snapshot 是新物件所以必然 miss，舊的 entry 隨 key 一起被回收（Expando 不會
延長 key 的壽命）。

#### 三個「夾具／斷言無法與程式碼意見不合」的當場實例

這一輪踩到三次，全部是 CLAUDE.md 已經記載過的形狀，而且都是變異驗證抓出來的：

1. **oid 前綴夾具**：`UnfilteredRowIndices` 的過濾測試用
   `i.toRadixString(16).padLeft(40, '0')` 生成十個 oid，索引落在**尾端**，於是十筆
   的前八個字元全是 `00000000`。前綴查詢是 `startsWith`，所以那個夾具無法分辨任何
   兩列。改成把索引放在開頭。
2. **`hits.sort()` 的變異是綠的**：拿掉排序，13 支全綠。原因不是斷言弱到看不見
   順序（`orderedEquals` 看得見），而是**夾具生成的 edge 本來就照 childRow 排序**，
   那個順序下區塊 carry-over 的串接剛好就是正確順序。補了一支把 edge 陣列反轉的
   夾具，sort 才變成有承重，變異也才紅得只有那一支。
3. **索引的 extent 取自 rows**：第一版用 `graph.rows.length` 定大小，讓三支**既有**
   測試轉紅。追下去發現既有測試是對的：`edgesSpanning` 契約上是 `edges` 的純函數，
   `graph_snapshot_test.dart` 就是拿 `rows` 為空、edge 橫跨 5..20 的 view 在問。
   改的是實作，不是測試。

第四個實例在別的地方：`FakeRepoSessionController` 原本**沒有**覆寫
`refreshWorkingCopy`，所以它會撞上 `_session == nullptr` 的守衛安靜地什麼都不做，
focus 測試分不出死掉的 listener 與活著的。補覆寫時又差點加重複的 `refreshHistory`
——它早在 362 行就有了，我第一次 grep 被 `head -20` 截斷所以沒看到，77 支測試因此
編譯失敗。

#### focus 回來不更新：不是壞掉，是從來沒做

`app_flutter/lib/` 底下 grep `AppLifecycleState`、`WidgetsBindingObserver`、
`AppLifecycleListener`、`didChangeAppLifecycleState`——**零命中**。要接的兩個進入點
（`refreshRepoHistory` / `refreshWorkingCopy`）本來就都在。

節流用 `Timer` 而不是 `DateTime.now()`，理由是可測試性：牆鐘不受 `tester.pump()`
推進，「超過節流視窗要再重整一次」那個案例會變成寫不出來。

**誠實的限制**：測試用 `handleAppLifecycleStateChanged` 模擬轉換，證明了接線，
**沒有**證明 macOS 真的會在視窗焦點變化時送出 inactive/resumed 這組轉換。那要在
真的 app 上確認。

#### 沒做的：載入期每個 chunk 重抄整張圖

`repo_session_repository.dart` 每收到一個 `graphUpdated` chunk 就 `readGraphSnapshot()`
把整張圖重新複製進 Dart，其中 `_readOids` 對每個 oid 跑 20 次 `toRadixString` +
`padLeft` + `StringBuffer.write`。C++ 側是幾何級數分塊，所以一次 refresh 約
log2(N/256) 個 chunk，每個都全抄。

這是**載入期**成本不是捲動成本，而且量它需要真的 FFI 與大 repo，這一輪拿不到數字，
所以照使用者「先量，需要再修」的裁決留著。

**真要做的話有一個阻擋物先要處理**：walk 的 generation 在 C++ 側存在
（`Session.cpp:375,438` 的 `RefreshCoalescer::Generation`），但**沒有經由 capi 曝露**
——`gbm_capi.h` 完全沒有 generation，`GBM_EVENT_GRAPH_UPDATED` 的 payload 只有
`{"complete": bool}`。沒有它，Dart 端分不出「同一次 walk 的第 5 個 chunk」與
「force push 後新一次 walk 的第 1 個 chunk」，正是使用者自己點名的風險。走 payload
加欄位而不是新增匯出函式，理由是簡單而非安全：新符號在舊 dylib 上是**大聲的**
lookup 失敗，真正無聲的危險是改動**既有**函式的參數列。

#### 沒做的（二）：有過濾字串時的 `matchingRowIndices`，以及 `isContiguousIn`

核准的計畫 Phase 2 有兩項，只出了一項。空查詢那條**移除**了（`UnfilteredRowIndices`），
非空查詢那條**原封不動**，這是一次縮減，所以連同數字寫在這裡讓使用者裁決，而不是
安靜地做掉。

同樣條件量（debug JIT、兩條路徑各先熱身 20k 次）：

| N | 空查詢（已修） | 非空查詢（未修） | `isContiguousIn`（未修，單選一列） |
|---|---|---|---|
| 703 | 4.0 → 0.30 µs | 35.2 µs | 0.9 µs |
| 10,000 | 41.2 → 0.063 µs | 489.7 µs | 12.5 µs |
| 100,000 | 669.9 → 0.073 µs | **5.03 ms** | 121 µs |

非空查詢是這三條裡最貴的，而且 100k 下一次 5ms、一幀最多呼叫兩次
（`_visibleOids` 每個捲動 tick 一次、`build()` 每次重建一次），已經吃掉大半個
16.7ms 預算。**但它不像空查詢那條可以直接刪掉**：比對的是 metadata 的
subject/author，match 集合真的是 `commitMetaCache` 的函數。

而計畫裡要 memo 它的那把 key（`(graph, metaCache, query)` 的物件識別）有個結構性
問題：**`metaCache` 每收到一批 metadata 就換一個新實例**，而那正是捲動時它一直在
發生的事。所以這個 memo 在最需要它的路徑上大約只有一半命中率（同一個 metaCache
底下 `build()` 與下一個捲動 tick 共用），不是接近全中。要不要為此付一份三段式失效
契約 + hits/misses 計數測試，是使用者的裁決。

另外兩點誠實話：

- 這條路徑**只有使用者在 History 過濾框打了字才會付**，而這一輪回報的症狀
  （menubar 閃爍）是沒有過濾時的純捲動。兩者是不同情境。
- `isContiguousIn` 慢在 `all.indexOf(item)`，是 O(選取數 × N)。但**沒有選取時它
  第一行就回 false**，也就是捲動最常見的狀態下是 O(1)，所以量級雖然到 121µs
  也排在最後面。

##### 裁決結果：memo 做了

使用者看過上面的數字後裁決「做，memo 加計數測試」，所以「沒做的（二）」的第一項
已經不成立了，記在這裡而不是改寫上面那段——留著原本的推理，補上結論。

memo 的形狀：`Expando` 掛在 `GraphSnapshotView` 上（跟 `GraphSpanIndex` 同一個模式），
entry 裡再存 `metaCache` 實例與 `query` 字串。三者缺一不可，各自擋掉不同的錯答案：
換 snapshot 是不同的列、換 metaCache 會讓原本不 match 的列開始 match、換 query 是
完全不同的問題。前兩者用實例識別是誠實的，因為兩者都不可變且整份重建——snapshot 由
`readGraphSnapshot()`，metaCache 由 `withCommitMeta()` 的展開語法（`{...old, ...new}`
生成**新** map，不是就地改）。

命中後的成本（同條件、熱身 20k 次）：

| N | 未命中（＝原本的成本） | 命中 |
|---|---|---|
| 703 | 35.2 µs | 0.080 µs |
| 10,000 | 489.7 µs | 0.046 µs |
| 100,000 | **5.03 ms** | **0.012 µs** |

命中是 O(1)（一次 Expando 查詢加兩個比較），所以隨 N 變大反而更快，那是量測噪音不是
趨勢。量的時候順便斷言計時區間內 `MatchMemoStats.misses` 沒有增加，確認量到的真的是
命中路徑而不是混了重算。

回傳值改成 `List.unmodifiable`。原本每次都是新 list，呼叫端愛怎樣都行；memo 之後
同一條 list 會被兩個呼叫點跨影格共用，所以把「不可以改」從「目前的呼叫端剛好都沒改」
變成型別本身的性質。動手前確認過兩個呼叫點（`_visibleOids` 與 `build()`）都只有
`.isEmpty` / `.length` / `[]` / 迭代。

計數測試七支，斷言的是 hits/misses 的**差值**（計數器是 isolate 全域、不重置，跟
`GraphSpanIndex.debugBuildCount` 同一個讀法）。三次變異驗證都紅得很窄，而且落點跟預測
一致：

| 變異 | 預測 | 實際 |
|---|---|---|
| 拿掉 memo | 只有「只算一次」那支 | ✅ 只有那支 |
| key 漏掉 query | 「換 query 要重算」 | ✅ 那支，**外加** `commit_search_test.dart` 既有的「nothing matches」 |
| key 漏掉 metaCache | 症狀測試 | ✅ 症狀測試 + 「同內容不同實例算 miss」 |

第二項那個額外的紅是意外收穫：既有那組四支測試共用同一個 `graph` 實例、只換 query，
所以 key 漏掉 query 時它們會互相拿到對方的答案。**既有測試免費守住了一個維度**，
純屬夾具剛好長對，不是設計出來的。

順帶修正了一段自己一個 commit 前才寫下的註解：`UnfilteredRowIndices` 的說明裡寫著
「非空查詢那條刻意不動，是使用者的裁決」，memo 一落地那句就成了假的。這正是本檔
一再記載的「註解與程式碼互相矛盾」形狀，所以跟著這次改動一起改掉，而不是留給下一輪
當成真話讀。

以及一個補上的縫：memo 的 key 誠不誠實，整個押在 `withCommitMeta` 用展開語法生成
**新** map 而不是就地改。這件事原本只有讀原始碼確認過，**沒有任何測試釘住**——
memo 測試裡那幾個「新的 metaCache」全是測試自己用展開語法造的，從來沒有經過真正的
生產者。哪天有人把 `withCommitMeta` 「優化」成就地改，過濾就會一直回舊答案，而現有
測試沒有一支會紅。補了一支跨過真生產者的測試。

這支測試自己踩了一次「紅得不是原因」：第一版用 `const RepoSessionState(isOpen: true)`
當起點，而它的 `commitMetaCache` 預設是 **`const` map、不可修改**，所以就地改的變異會在
那裡直接丟 `UnsupportedError`——測試是紅的，但紅的是「丟例外」，不是我寫的那三行斷言。
換成明確的 growable map literal（也才是 app 從第一批 metadata 之後真正持有的東西）之後
變異才成功執行，紅的位置也才變成 `withCommitMeta must not mutate the cache in place`
那一句。**測試紅了不等於測試有承重**，得看紅在哪一行。

## feature/soft-warp — soft wrap 偏好與長行水平捲動

需求：Preferences 加一個 soft wrap 開關、預設關閉，關掉時長行改用水平捲動。
使用者另外拍板三件事：行號欄**釘住不動**（不是整列一起捲）、涵蓋所有跟檔案有關
的介面（commit message 輸入框除外）、入口只放 Preferences 不加選單或快捷鍵。

### 兩份探索報告的前提都是錯的，而且錯在同一個方向

兩支 Explore 都回報「長行目前會被截斷／溢出」。其中一份還進一步宣稱
「`Text` 在 Row 裡預設 `softWrap: false`，所以長行會產生水平捲動」。

實際讀 `diff_line.dart:122-132` 後，兩者都不成立：`Text.softWrap` 預設是
**true**，`Expanded` 又給了受限寬度，所以**今天每一個檔案介面的長行都是自動
換行**，沒有截斷，也不存在任何水平捲動。

這把任務性質整個換掉。原本以為是「把一個 flag 接到既有的兩條路徑」，實際是
**預設行為翻轉 + 從零建一條水平捲動路徑**：

| | 這輪之前 | 之後 |
|---|---|---|
| 預設 | 永遠換行（沒得選） | 不換行 + 水平捲動、行號欄釘住 |
| 水平捲動 | 完全不存在 | 五個介面都新建 |

唯一例外是 `BlamePanel`，它本來是 `maxLines: 1` + ellipsis，長行直接被切掉、
沒有任何辦法看到後面。兩種新模式對它來說都是修好一個既有缺陷。

教訓不是「subagent 不可信」，而是**兩份獨立報告在同一點上錯得一樣，並不構成
佐證**。它們錯的方式甚至不同（一個說截斷、一個說已經會水平捲動），卻共同支撐
了「現況不是換行」這個結論。判準是自己讀那 10 行原始碼，30 秒的事。

### `dragDevices: {}` —— 我自己也犯了一次同型錯誤

設計 `GbmCodeHScroll` 時，我原本要對水平 scroller 覆寫
`ScrollConfiguration(dragDevices: const {})`，理由寫得很篤定：「保護
`ScopedDiffView` 的選取拖曳不被 scroller 搶走」，還在計畫裡標成「整個設計最關鍵
的一行」。

查 Flutter 的 `scroll_configuration.dart` 之後，這條前提兩頭都錯：

- **不需要**：`ScrollBehavior.dragDevices` 預設是 `_kTouchLikeDeviceTypes` =
  `{touch, stylus, invertedStylus, trackpad, unknown}`，**mouse 不在裡面**。桌面
  的選取拖曳是 mouse kind（CLAUDE.md 早就記過：觸控板的 click-and-drag 是以
  mouse 抵達的），scroller 的 drag recognizer 根本不受理，arena 上沒有競爭。
- **有害**：觸控板雙指水平 pan 正是**透過**該集合的成員資格抵達 `Scrollable` 的
  （同一條 CLAUDE.md 記載：`PointerPanZoom*` 是 trackpad kind 進入
  `_kTouchLikeDeviceTypes` 的唯一路徑）。清空等於把最主要的水平捲動輸入砍掉，
  只剩捲軸拉桿與 Shift+滾輪。

諷刺的是，推翻它的兩項事實**都已經寫在 CLAUDE.md 裡**，就在「A pointer drag can
never carry `PointerDeviceKind.trackpad`」那一條。我讀過那條、也在計畫裡引用了
它的前半，卻沒把後半（trackpad 靠成員資格進入該集合）接到自己的決定上。

`gbm_code_hscroll_test.dart` 因此有一條專門釘住這個前提的測試：**mouse kind 的
拖曳不得捲動**。哪天 Flutter 把 mouse 加進那個集合，紅的會是它，而真正壞掉的是
diff 的拖曳選取。

### 釘住行號欄需要兩種策略，不是一種

「gutter 釘住、程式碼從底下滑過去」有一個立即的推論：**gutter 必須不透明**，
否則會看到捲動後的行文字出現在自己行號的左邊。

對 diff 的列這是無縫的——`DiffLineView` 自己就畫滿整列寬的背景
（`Container(color: background)`），gutter 重畫同一個顏色看不出接縫。

**對 Blame 的列這是災難。** 它的列是 `GbmRow`，背景是**祖先**畫的 hover 與選取
底色。不透明的 gutter 會把兩者都蓋掉，而且不是只在捲動時——**捲動位移為 0 時就
會蓋**，等於 hover 回饋直接消失。這正是 CLAUDE.md 記過的
「sidebar 有好幾個月沒有可見 hover」那一類。

所以有第二條路徑 `GbmPinnedGutterClip`：gutter 什麼都不塗（`opaque: false`），
改成把內容依 **viewport 座標**裁掉，裁切左緣 = 捲動位移 + gutter 寬。程式碼永遠
到不了 gutter 底下，所以沒有東西需要遮，列自己的底色原封不動。

規則寫在 `GbmPinnedGutter.opaque` 的 doc comment：**列自己畫滿寬背景 → 不透明；
背景由必須保持可見的祖先畫 → 裁切。** 這不是同一件事的兩個真相來源，是兩條有
明確適用條件的算繪路徑。

裁切的幾何只能直接問 clipper——`ClipRect` 不改變 `getRect`，所以「內容有沒有被
正確裁掉」沒有任何位置斷言測得出來。測試因此斷言
`clipper.getClip(size).left == 捲動位移 + gutterWidth`。

### 量錯 render object：finder 對了，結論還是不成立

`ScopedDiffView` 的釘住測試第一版紅了，訊息是 gutter 移動量剛好等於捲動量——
看起來就是「反向平移完全沒發生」。獨立的 `gbm_code_hscroll_test` 裡同樣的機制
卻是綠的。

寫了一支探測才知道程式是對的：controller 有找到、`hasClients` 為 true。錯的是
**測試量錯了 render object**。`find.byType(GbmPinnedGutter)` 解析到的第一個
RenderBox 是它內部的 `RenderTransform` **本身**，而 `localToGlobal` 只把 transform
套用給**子節點**、不套用給自己——所以量到的永遠是未平移的位置，會跟著捲動跑。
獨立測試用的是 `find.byKey`，命中的是 Transform **底下**的 `Text`，所以才對。

這是 CLAUDE.md 那條「a finder proves existence, never position」的下一層：
finder 找對了 widget，render object 還是可能是錯的那一個。修法是往下找一層
（`find.descendant(... matching: find.byType(ColoredBox))`）。

### 三個 mutation 教訓

**一、anchor 對不上 = 假綠，不是測試缺口。** `panel_diff_text.dart` 的前兩個
mutation 回綠，我差點讀成「測試沒覆蓋到」。實際上是 `dart format` 重排過參數
列，我的 anchor `count == 0`，**mutation 根本沒套用**。CLAUDE.md 要求 mutation
script 先斷言 `count(old) == 1` 就是為了這個——沒有那行斷言，兩個假綠會直接變成
兩條不存在的「缺口」記進 ledger。改抓格式化後的實際內容之後兩個都紅。

**二、一個真的綠 mutation，揭露 fixture 的盲點。** 把 `_GapBlock` 的
`softWrap` 硬寫成 `true` 是綠的。原因：fixture 裡唯一的長行在 scope 卡片裡，
gap block 只有一行短 context，所以 `find.byType(GbmPinnedGutter).first` 落到
卡片那顆、照樣釘得住。卡片與 gap block 是**兩個各持一份旗標副本的 builder**，
fixture 必須讓兩邊都有長行，斷言也必須改用**計數**（`findsNWidgets(2)`）而不是
「有沒有」。衝突視窗的三欄是同一個形狀，所以那裡一開始就用
`findsNWidgets(3)`——硬寫其中一欄仍然換行就會紅。

**三、`git checkout -- <file>` 一次都沒用。** 全部走 scratchpad 備份再 `cp`
回來，照 CLAUDE.md 記載的那次事故。

### 量測數字（debug JIT，測試字型）

`widestLineWidth` 一次 `TextPainter.layout` 量整份文字，取 `maxIntrinsicWidth`
（多行段落的 `maxIntrinsicWidth` 就是各行的最大值，所以是一次 layout 不是每行
一次）：

| 行數 | 每次呼叫 |
|---|---|
| 200 | 2.8 ms |
| 1,000 | 8.6 ms |
| 5,000 | **46 ms** |

5,000 行 46ms 表示**每次 build 重量會直接掉幀**，所以 `CodeWidthMemo` 是必要條件
而不是優化。數字寫在這裡是為了讓下一輪從數字重新決定，而不是從同一個猜測。

刻意**不用**「等寬字寬 × 最長行字元數」這個便宜很多的公式：CJK 與全形字是兩格
寬，公式會低估，而低估的正好是最需要捲動空間的那些行，症狀是行尾被切掉。

### 裝置層這輪無法作為證據——而這是量出來的，不是推測的

計畫把 `stage_lines_flow_test.dart` 列為**唯一**能證明「水平 scroller 沒有搶走
`SCOPES` row 7 拖曳選取」的測試，並要求 C2 一開始先跑。跑了，掛了：前 3 個測試
綠，第 4 個「staged 側的文字選取」卡住 7 分 50 秒沒完成。

沒有直接歸因，而是 detached 到 C1 **之前**的 commit（5fce758）跑了真正的對照組。
結果是決定性的：**之前更糟**——第 2 個測試就在 25 秒內 did not complete。兩次
輸出都有 `Failed to foreground app; open returned 1`。

**這一段的結論後來被 main 上的 side-by-side 那輪推翻，在此就地更正。**
當時寫的是「既有的環境問題（#101 那一類，macOS 視窗拿不到前景），裝置層這個
session 無法作為證據」，依據是兩次輸出都有
`Failed to foreground app; open returned 1`。那條訊息**在全綠的 run 上也會印**
（side-by-side 那輪重跑後證實的），真正的判別是它後面有沒有測試結果行——而我
的 log 後面有，就寫在同一份輸出裡：`00:15 +1`、`00:31 +2`、`00:46 +3`。

所以正確的讀法是：**這不是拿不到前景，是第 4 個測試掛住了。** 而且拆開來看，
這輪拿到的證據比原先以為的多：

| | 前進到 | 其中包含 |
|---|---|---|
| 這輪（C5 之後） | 3 條綠，第 4 條掛 | **「a text selection stages exactly the lines it framed」通過** |
| 父 commit 5fce758 對照組 | 1 條綠，第 2 條掛 | —— |

第二列那個 tick 正是計畫指名要驗的東西：**風險 1（水平 scroller 搶走 `SCOPES`
row 7 的拖曳選取）在裝置層被證否了一次**，只是我當時把整份輸出丟進「環境壞掉」
這個桶子裡，沒去讀它。對照組更早掛，所以「這輪沒弄壞裝置層」仍然成立。

**留下的真問題是第 4 個測試（staged 側的選取取消暫存）為什麼掛 7 分 50 秒**，
那是一條具體的線索，不是一句「環境不行」。教訓已蒸餾進 CLAUDE.md：先讀過那行
訊息看後面的計數，再決定它是掛一條還是整層不通——兩者的下一步完全不同。

**第二次就地更正：那條線索也結掉了。** 分支收尾時重跑同一個檔——先
`pkill` 殘留的 `gbm_flutter`、再跑 `scripts/build_capi.sh` 重建 dylib（merge 帶進
了 `src/core/git/SideBySideDiff.h`，而 `build/native/` 的那份是複製品）——結果是
**7 條全綠，1 分 50 秒，`EXIT=0`**，第 4 條在 15 秒內通過。所以那個 7 分 50 秒
不是缺陷，重現不了。

誠實的界線：**沒有隔離出是三件事裡的哪一件**（重建 dylib、清掉殘留 process、
樹上多了三個 commit）。能說的是「掛住在新的樹上重現不了」，不能說「原因是陳舊的
dylib」——雖然那是嫌疑最大的一個，因為 CLAUDE.md 已經記過一份三天前的
dylib 會靜默地讓新的 capi 欄位看起來像 Dart bug。

因此計畫的驗收項目 `[ ] ScopedDiffView 的拖曳選取暫存沒有回歸（裝置層綠）`
**在這輪最終的樹上是真的綠的**，不是靠上面那個「至少證否過一次」的部分證據。
七條裡有三條直接就是這件事：「a text selection stages exactly the lines it
framed」、「a selection on the staged side unstages what it framed」、
「a row-by-row drag keeps every changed line it crossed」。

`real_repo_harness.dart` 的 prefs 清除清單加上了 `appPrefs.softWrapEnabled`（merge
後與 main 的 `fileListViewMode` / `diffViewMode` 併成同一組 flat key），
理由與 `panelLayout.*` / `graphColumns.*` 同型：兩種模式是兩棵不同的 widget 樹、
兩套不同的 hit-test 幾何，開發者本機開過換行就會讓所有位置相關的測試在他機器上
與別處不一致——而這一層沒有 CI，不一致不會被任何地方看見。

### 明寫的取捨（不是靜默縮減）

1. **`ScopedDiffView` 的卡片、hunk 標頭、scope 按鈕會跟著水平捲走**，只有每列的
   行號欄釘住。要讓卡片邊框也釘住等於把卡片拆成「固定框 + 內部捲動」，而卡片
   內部就是那些帶 `GlobalKey` 的 `SelectionListener` 列——重排那個子樹是
   CLAUDE.md 明確記載的危險動作。
2. **`_ResultLine` 的刪除按鈕跟著列捲走**，不釘右緣。兩邊都釘會從左右夾擠可讀
   區，而那顆按鈕作用在「這一列」。
3. **衝突視窗的 result `TextField` 有一道接縫。** 多行 `TextField` 沒有原生水平
   捲動，作法是給它比 viewport 寬的盒子再捲那個盒子。關掉換行時，欄位自己的
   游標追蹤捲動與外層 scroller 是兩個獨立的捲動位置，所以打字超過右緣會讓游標
   移出視野而不是被追。打開換行沒有這個問題（就是以前那個盒子）。

### 補上計畫承諾、但一開始漏掉的那條整合層測試

計畫的「測試」段承諾過一條 `test/integration/` 的測試：「diff 在畫面上時切換偏好，
版面確實改變」。實作完六個 commit 後回頭核對，發現它沒被寫出來——**這輪所有的
wrap 測試都是先 seed 偏好再 pump**，每個模式都只在剛建好的樹上被證明過。

補上的 `soft_wrap_preference_flow_test.dart` 有兩個測試，而它們的價值**不相等**，
這點值得寫下來，因為 mutation 的紅寬窄直接說明了哪一條在守真正的縫：

| mutation | 這個檔 | 套件其餘部分 | 讀法 |
|---|---|---|---|
| `PanelDiffText` 的 `ref.watch` → `ref.read` | **紅** | **全綠** | 這道縫本來完全沒人守 |
| `selection_touch.dart` 的 row key memo 拿掉 | 紅 | `scoped_diff_view_test.dart` 也紅約 20 條 | 寬紅，別的測試早就釘著了 |

第一條是真正的發現：**seed 過的測試對「只在 mount 時讀一次 provider」這個缺陷是
盲的**，因為它那唯一一次 build 讀到的就是對的值。要分辨「每次 build 都讀」與
「讀一次就記住」，只有在畫面上活著的樹上翻轉 notifier 這一種辦法。

第二條依 repo 規矩（窄紅才算數）誠實降級為「守一條沒別人走過的路徑」而不是
「唯一偵測者」，並且**寫進測試自己的註解**，免得下一輪把它讀成比實際更強的保證。

### 一個量出來的缺陷，沒有修，交給使用者決定

`ScopedDiffView` 的水平捲軸**在長檔案上看不見**。

量測（測試字型，viewport 高 300px，60 行的 diff）：

```
viewport height = 300
GbmCodeHScroll rect = Rect.fromLTRB(17.0, 42.0, 403.0, 1428.0)
```

`Scrollbar` 沿著自己盒子的下緣畫，而 `WorkingCopyDiffPane` 把 `ScopedDiffView`
放在垂直 `SingleChildScrollView` 底下（`working_copy_diff_pane.dart:120/124/130`），
所以它的高度是**無界**的——盒子高 1386px，拇指落在 y≈1428，使用者看到的是
y=0..300。任何比一個畫面高的 diff，那條捲軸都在畫面外。

**只有這個介面有這個問題。** 另外四個都被 bounded 的 `ListView` 收著：`DiffPage`、
`BlamePanel`、衝突視窗三欄都是，`PanelDiffText` 的宿主也是。

捲動本身沒壞——觸控板雙指與 Shift+滾輪都正常。壞的是**靜止時「右邊還有東西」
這個訊號**，那正好是 UX 評分表 D 維度的 `material_state_hidden`。

兩條候選修法，都不是 drive-by：

1. **把水平 `ScrollController` 上提到 pane**，`GbmCodeHScroll` 收一個外部
   controller 並在收到時不畫自己的 `Scrollbar`，改由 pane 用
   `Scrollbar(controller: hCtrl, notificationPredicate: (n) => n.metrics.axis
   == Axis.horizontal, child: <垂直 SCSV>)` 畫在 pane 的下緣（pane 是有界的）。
   **卡住的地方**：`thumbVisibility: true` 在 controller 還沒 attach 時會 assert，
   而「有沒有溢出」只有 layout 之後才知道，所以 pane 得靠一個 post-frame 回呼
   才拿得到——那正是 CLAUDE.md 記載的 `addPostFrameCallback` 不會自己要求
   一幀那一則，要配 `ensureVisualUpdate()`。
2. **改用二維捲動**（`TwoDimensionalScrollView` / `two_dimensional_scrollables`），
   兩軸各自有界。結構更正確，但等於重寫這個 pane 的捲動骨架。

沒有零風險的第三條：`Scrollbar` 沒有「釘在 viewport 而非自己盒子」的模式，而
內容本來就比 pane 高，所以無法靠收緊約束解決。

依 repo 規矩，規格與決策記錄兩邊都沒有這題的答案（P11 根本沒有 wrap 條目，
計畫也沒預期到），所以這是「問」的情況，不是我自己決定砍掉的情況。

### 修掉那個捲軸缺陷——但沒有用 `TwoDimensionalScrollView`

使用者選了 ledger 上列的第 2 條修法。動手前先驗工具，結論是**它在這個介面上不能
用**，而且理由有兩層：

1. **Flutter core 只給抽象半邊。** `TwoDimensionalScrollView`、
   `TwoDimensionalViewport`、`RenderTwoDimensionalViewport` 全是 abstract，用它
   等於自己實作 `layoutChildEntries`。這只是成本。
2. **它是惰性 viewport。** 離開畫面的 child 會被銷毀（除非逐一 `keepAlive`，
   `_keepAliveBucket`）。而 `ScopedDiffView` 的每一列**必須保持 mounted**：每列
   持有自己的 `SelectionListener`，回報「目前的文字選取有沒有碰到我」，那正是
   `SCOPES` row 7 的拖曳暫存知道自己框了什麼的唯一機制
   （`selection_touch.dart` 開頭就寫死這個前提）。要靠 `keepAlive` 保住全部列，
   等於付出一個自訂 render object 的代價換回一個非惰性列表。

換句話說，**2D viewport 的唯一賣點正好是這個介面不能接受的性質**。

真正要的是它承諾的那個**結構性質**——兩軸都被 pane 收界，所以兩條捲軸都畫在
pane 自己的邊上。那個性質用普通 widget 就拿得到，新的 `GbmCodeScrollWell`：

```
Scrollbar(vertical)          <- 畫在「這個」盒子上，而它是有界的
  Scrollbar(horizontal)      <- 同上
    SingleChildScrollView(horizontal)
      SizedBox(width: contentWidth)
        SingleChildScrollView(vertical)
          child
```

水平在外、垂直在內，而**兩條捲軸都在兩個 scroll view 之外**。兩個 scroll view
對調沒差；把任何一條捲軸移進去就會在另一軸重現同一個 bug。

還有一個只有在桌面平台才看得見的第三條：**ambient `ScrollBehavior` 會自己加
捲軸**，而那些是包在內層 scrollable 上的——正是缺陷本身，只是更難發現，因為
finder 仍然每軸只數到一條。所以內層用
`ScrollConfiguration(scrollbars: false)` 抑制掉。

#### well 上提到 pane，不是留在 ScopedDiffView

`unified` 模式的整個意義就是兩側共用一個垂直位置，一側一個 well 表達不出來。
所以 well 歸 `WorkingCopyDiffPane`，量測（`diffFileContentWidth`，搬到
`diff_line.dart` 與 `kDiffGutterWidth`／`kDiffCodeTextStyle` 同住）也歸它，
`unified` 取兩側的較大值。列仍然找得到 well——`GbmPinnedGutter` 是從 context 讀
`GbmCodeHScrollScope`，不在乎誰建的。

`ScopedDiffView` 因此不再自帶 scroller，`scoped_diff_view_wrap_test.dart` 的
`_pump` 也改成把它包進 well 裡。**這比原本更誠實**：原本測的是一個不會出貨的
組合，而且 well 搬走之後它會繼續綠——那正是「無法與程式碼相左的 fixture」。

#### 兩則 mutation，其中一則抓到我自己留的空白

| mutation | 結果 |
|---|---|
| pane 把 well 再包一層垂直 `SingleChildScrollView`（＝還原缺陷） | **窄紅**，拇指 1623 對 pane 底 460.5；只有這個檔的測試紅 |
| 拿掉 `ScrollConfiguration(scrollbars: false)` | **第一次綠** |

第二則綠的理由值得記下來：**`flutter_test` 預設回報
`TargetPlatform.android`，而 Material 的 ambient 捲軸只在桌面平台加**。這個 app
只出貨 macOS／Windows／Linux，所以測試的預設平台是唯一不會發生的情況。補了一條
用 `debugDefaultTargetPlatformOverride = TargetPlatform.macOS` 的測試之後，同一則
mutation 變成窄紅（ambient 捲軸右緣 975，pane 右緣 660.5）。

那個 override 要在測試本體裡還原，不能用 `addTearDown`——flutter_test 檢查
「沒有 foundation debug 變數活過這個測試」的時機**早於** tearDown。

順帶再次踩到記載過的陷阱：`dart format` 重排參數列之後 mutation 的 anchor 對不
上，Python 的 `assert count == 1` 當場擋下來，證明那個規矩不是多餘的。

### merge 帶進來一個沒接 soft wrap 的檔案介面

`origin/main` 上的 side-by-side 那輪加了 `SideBySideDiffView`，而它的 doc
comment 寫著：

> Lines wrap, exactly as `DiffPage`'s do. Cross-column alignment survives it
> for free… no `softWrap: false` and no synchronised horizontal scrolling
> needed.

**寫的當下是對的，兩條分支相遇的那一刻就不對了**——這輪讓 `DiffPage` 預設不換行。
兩條分支平行開發，各自的前提在對方那邊被推翻，而 merge 不會告訴你這件事。這是
「有關 file 的都要」在合併後的樹上還沒關閉的最後一個缺口。

接法與其他四個介面同型（`ListView` 已經把高度收界，所以 `GbmCodeHScroll` 直接
可用），但有兩件事是這個介面特有的：

1. **一個 well 蓋住兩欄，寬度是「一欄 × 2 + 分隔線」。** 兩欄一起捲，所以一對
   永遠對齊。而且關掉換行之後**對齊反而更容易**：每個 cell 都剛好一行高，
   `IntrinsicHeight` 沒有東西要拉平。
2. **兩欄都不釘行號欄，這是決定不是遺漏。** 兩欄有兩個行號欄，只有左邊那個在
   viewport 邊緣。只釘它會讓左欄的號碼凍住、右欄的號碼滑過去，讀起來像壞掉而
   不像貼心。所以 `GbmPinnedGutter` 在這裡刻意缺席，與 `DiffLineView` 的單欄
   列不同。

順帶更正一條既有測試的前提：`side_by_side_diff_view_test.dart` 那條
「blank padding cell 要跟旁邊換行的那一列等高」是在「換行是唯一行為」的年代寫的，
現在預設翻轉了，所以它改成**明確傳 `softWrap: true`**。其餘測試則明確跑在
出貨的預設值下。這正是 CLAUDE.md 那則的第二次應驗：規則變了，每個編碼了該規則的
fixture 都要重讀一次，別的東西都不會發現。

#### 兩則 mutation，第二則抓到四條測試的共同盲點

| mutation | 結果 |
|---|---|
| cell 的 `softWrap` 硬寫成 `true`（pane 仍讀偏好） | 窄紅，只有「每個 cell 都帶著旗標」那條 |
| 寬度算成一欄（`* 2 + 1` → `+ 1`） | **前四條全綠** |

第二則值得記：**半寬的 well 仍然會產生 scroller、仍然溢出 pane**，所以每一條
「有沒有 scroller」的測試都看不見它——看得見的是「右欄的文字被切掉」。補的那條
用測試裡**獨立量出來**的最寬行當 oracle，而不是重述實作的算式，mutation 之後
是 513.75 對上需要的 1086.5。

### 同一個機制，另一條軸：五個唯讀檔案介面的垂直捲軸

上一節修的是 `GbmCodeScrollWell`（Working Copy 的水平捲軸）。修完之後回頭問了一
句「同一個機制會不會出現在別的地方」，答案是會，而且早在 C1 就已經存在：

`GbmCodeHScroll` 在關閉自動換行且檔案夠寬時，把 child 放進
`SizedBox(width: contentWidth)`。桌面的 ambient `ScrollBehavior` 會替**裡面**那個
`ListView` 包一層 `Scrollbar`，而 `Scrollbar` 是畫在自己盒子的邊上——於是垂直
拇指落在 `x = contentWidth`。用 `DiffPage` 量：pane 190→610（寬 420），捲軸盒
190→**1025**（寬 835 ＝ contentWidth）。C1 之前 `ListView` 的盒子就是 pane，所以
這是這一輪自己帶進來的回歸。

受影響的是 `GbmCodeHScroll` 的全部五個使用者：`DiffPage`、`SideBySideDiffView`、
`PanelDiffText`、`BlamePanel`，以及 `ConflictResolveWindow` 的三欄。

**為什麼整個套件都看不到**：跟上一節同一個理由，`flutter_test` 回報
`TargetPlatform.android`，Material 在那裡根本不加 ambient 捲軸。這已經是同一個
盲點第二次讓一則 mutation 假綠了；新測試
（`diff_page_scrollbar_placement_test.dart`）因此開宗明義寫「本檔必須跑在桌面
平台」。

作法與 `GbmCodeScrollWell` 對齊：兩條捲軸都由 `GbmCodeHScroll` 自己畫在有界的盒
子上，內層 `ScrollConfiguration(scrollbars: false)`。因此新增
`required verticalController`——**刻意沒有預設值也沒有自備 fallback**。有考慮過讓
它自己持有一個，但呼叫端的 `ListView` 才是那條軸真正的驅動者，兩者不同步的話會
得到一條拖不動的捲軸，比原本的 bug 更糟；required 讓漏接的呼叫點變成編譯錯誤。
六個呼叫點（三個在 `ConflictResolveWindow`，各一條 controller，因為三欄行數不同，
共用一個垂直位置在其中兩欄是沒有意義的）都跟著改。

順帶把兩個共用的 `notificationPredicate` 提成頂層函式
（`isHorizontalScroll`／`isVerticalScroll`），因為兩個 widget 都需要——
`defaultScrollNotificationPredicate` 濾的是 `depth == 0`，那是另一個問題，內層那
條軸照樣穿過去。

#### 三則 mutation

| mutation | 結果 |
|---|---|
| 錨點只寫 `ScrollConfiguration(...)` 那一段 | **`count == 2`，當場擋下** |
| 拿掉 `ScrollConfiguration(scrollbars: false)` | 窄紅，第 3 條 ambient 捲軸回來（2 條測試） |
| 把垂直 `Scrollbar` 移進 `SizedBox` | 窄紅，只有 rect 那條，訊息正是「捲軸盒超出 pane 右緣」 |

第一列是那條規矩第二次救場，而且這次的原因更值得記：**這兩個 widget 的這一段
程式碼字面完全相同**，所以任何以它為錨的 mutation 都會同時命中兩個。錨要改成先
切出 `_GbmCodeHScrollState` 的區段再取代。

第三列存在的理由是第二列的紅**停在 count 斷言就結束了**，rect 迴圈根本沒被走
到——一條沒被走過的斷言等於沒被驗證過。M-B 讓 count 維持 2 而只動組成順序，rect
迴圈才第一次以偵測器的身分紅過。

### 更正一條自己上一節才寫下的理由

上一節把「不用 `TwoDimensionalScrollView`」的第一條理由寫成「core 只給抽象半
邊」。那句話本身沒錯，但**它不是否決理由**：ledger 當初列的第 2 條修法點名的是
`package:two_dimensional_scrollables`，而那個套件的 `TableView` 是具體類別，抽象
與否在它面前不成立。

真正跨得過套件形式的理由只有惰性那一條：`TableView` 也建在同一個
`RenderTwoDimensionalViewport` 上，一樣按 vicinity 建 child、一樣銷毀離開畫面
的。所以 doc comment 改成惰性為主、抽象為次要成本。

**這是「拿一個成本冒充否決理由」的錯誤**，跟 CLAUDE.md 那則「conformance cell 的
證據是 `isActionEnabled()`」同型：兩者都是拿一個真的、可查證的事實，去頂替真正該
被檢驗的那個claim。

### arena 那個前提比原本說的更強，而測試釘的是組成不是 arena

`scoped_diff_view_test.dart` 的二十幾條拖曳測試是**裸 pump `ScopedDiffView`**
的。well 上提到 `WorkingCopyDiffPane` 之後，那棵樹的 `SelectionArea` 上方沒有任何
捲動器——一個使用者永遠看不到的形狀。那些測試所倚賴的「well 的兩個 `Scrollable`
不會跟 mouse 拖曳搶 arena」，在 `GbmCodeScrollWell` 上沒有任何層級在檢查。

補了 `diff_pane_drag_stage_test.dart`：先證明 fixture 真的兩軸都溢出（否則後面兩
條會在**沒有競爭對象**的情況下假綠），再證明拖曳仍然升起一次性 scope，最後證明
按下去送出的是「變動的行」而不是「匡選的行」。

然後對前提本身下了一則 mutation——**把 `mouse` 加進 well 的 `dragDevices`**，也就
是把 CLAUDE.md 那條「mouse 不在 `_kTouchLikeDeviceTypes` 裡，兩者根本不會相遇」
反過來。結果**全綠**。

沒有就此收下這個綠：另寫一支探針確認突變本身有效，同樣設定下一次 mouse 拖曳讓水
平位移從 **0 變成 50**。所以結論不是「測試看不到」，而是：

> **即使捲動器真的進了 arena，選取仍然贏。**

這比原本的說法更強一層。原本的論證是「兩者不會相遇」；現在多一句「相遇了也是選取
贏」。CLAUDE.md 那條「絕對不要為了保護選取而覆寫 `dragDevices`」的「不必要」那一半
因此有了直接證據，而不再只是推理。

**這也意味著本檔釘的是組成，不是 arena**，檔頭就這樣寫，不假裝它釘住了後者。它真
正擋得住的是「有人在 pane 外面再包一層會吃手勢的東西」這類回歸，以及第三條那個
payload：把 `onStageScope` 的參數換成 `const <int>[0]` 之後只有它紅
（Expected `[1]`，Actual `[0]`）。

順帶量到一個既有取捨的實際數字：內容比 pane 寬時，**scope 按鈕會跟著水平捲出可視
區**（中心 x=638.8，pane 右緣 660），所以第三條得先 `ensureVisible`。這正是計畫裡
明寫的「只有行號欄釘住，卡片／hunk 標頭／scope 按鈕都跟著捲」的後果，現在它有一
條可執行的紀錄，而不只是一句散文。

### 規格狀態

P11 的 Appearance 段只有主題切換，21 頁規格全文沒有任何 wrap／自動換行／水平
捲動的條目。**這是使用者指定的增補，不是規格條目**，`AppPreferences.softWrapEnabled`
的 doc comment 已寫明，免得後續稽核把它讀成規格符合項。

## fix/focus-refresh-repo-state — focus 回來時重讀整份本地 git 狀態

需求：視窗失去焦點再回來時要跟上衝突徽章、working copy diff 變動、git graph、
分支數量變化，以及其餘每一項本地會變動的狀態。使用者另外拍板兩件事：
**不碰網路**（所以 gone 標記不在裡面），以及**「branches more or gone」指的是
分支數量變化**，不是 gone 徽章。

### 點名的四項裡，三項本來就是好的

focus refresh 的接線是上一輪（`History 捲動卡頓` 那輪）做的。這一輪查下去，
四項裡只有一項壞掉：

| 面向 | 現況 | 憑證 |
|---|---|---|
| git graph | 已覆蓋 | `gbm_history_refresh` 契約上先送 `REFS_UPDATED` 再送一或多個 `GRAPH_UPDATED`（`gbm_capi.h:283-289`） |
| 分支數量變化 | 已覆蓋 | 同一支呼叫的 `REFS_UPDATED` → `_readRefs()` 整份換掉 `RefSnapshot` |
| working copy diff | 已覆蓋 | `_readWorkingCopyStatus()` **無條件**清掉 `workingCopyDiffs`，而 `WorkingCopyStatus` 沒有 `operator ==`，每次都是 JSON 解出的新實例 → `select()` 必然視為變動 → `working_copy_view.dart:156-161` 的 `ref.listen` 必然重抓 |
| 衝突徽章 | **半舊** | 見下 |

`conflictActive` 是兩項的 or。右半邊 `workingCopyStatus.conflicted` 會更新，
**左半邊 `repoState?.isSequencerOperation` 不會**：`_readRepoState()` 全專案
只有兩個呼叫點，session 開啟時與 `operationFinished` 事件。也就是
**只有 app 自己跑過一個 operation，`repoState` 才會動**。

症狀有三種，第二種最惡劣因為它完全隱形：

1. terminal 裡 `git rebase --abort` → 狀態列與衝突橫幅繼續說 rebasing，
   `isActionEnabled()` 那 12 個閘繼續鎖著。
2. terminal 裡 `rebase -i` 停在 `edit`（**沒有衝突檔案**）→ 兩半邊都是空的／舊的，
   app 完全不知道有 sequencer 在跑，照樣讓人 checkout。
3. `rebaseStep / rebaseTotal` 與 `indexLocked` 只存在於 `repoState`。

修法便宜到不需要新 capi：`Session::repoState()` 就是 `RepoState::read(paths_)`
（`Session.cpp:249-251`），每次呼叫都重算、沒有快取，而 `RepoState.h:73-74`
自己寫著「Only stats a handful of paths」。所以 `refreshRepoState()` 是這一輪
唯一一支**同步**的 refresh：讀 staging buffer 直接 `copyWith` 發佈。

### 撿到的：F5 只重讀 history

`GbmActionId.viewRefresh` 的 handler 是 `refreshRepoHistory(ref, identity)`。
按 F5 之後 Working Copy 的徽章、diff、衝突狀態都不動——而這是使用者**明確要求
刷新**的那條路徑。同一個缺陷形狀，照 repo 規則 1 一併修掉。

### 量測：規劃階段就量完，而且數字推翻了我自己的第一版設計

本機 macOS + homebrew git；本 repo 752 commits / 933 tracked files / 64 refs /
**無 submodule** / `git-lfs` 不在 PATH。每支 12 次，**丟掉前 2 次暖 page cache**，中位數。

| 指令 | 中位數 | 指令 | 中位數 |
|---|---|---|---|
| `for-each-ref` | 7.3ms | `remote -v` | 4.9ms |
| `rev-list --topo-order --all` | 9.4ms | `config --file .gitmodules --get-regexp` | 5.0ms |
| `status --porcelain=v2 -uall` | 32.3ms | **`submodule status`** | **79.2ms** |
| `diff --numstat` | 18.2ms | `bisect log` | 4.9ms |
| `diff --cached --numstat` | 21.4ms | `config --local --get` / `config --get` | 4.8 / 4.9ms |
| `stash list` | 11.6ms | *(行程啟動地板 `rev-parse`)* | *5.0ms* |
| `worktree list --porcelain` | 4.9ms | *(候選述詞 `ls-files --stage`)* | *18.5ms* |

並發牆鐘（`sharedReadPool()` 是 2–6 執行緒，`WorkingCopyStatus.h:244`）：

| 池大小 | 今天（5 支） | 全部 12 支（採用） | *(參考：若短路掉 submodule)* |
|---|---|---|---|
| 2（最差） | 44.8ms | **135.1ms** | *65.6ms* |
| 4 | 33.7ms | **106.6ms** | *36.5ms* |
| 8 | 34.0ms | **94.9ms** | *32.4ms* |

`git submodule status` 一支就佔掉新增成本的 66%，而且在**沒有 submodule 的 repo
上也一樣要 79ms**。成因不是 repo 大小：`git-submodule` 是 POSIX shell script
（`/opt/homebrew/opt/git/libexec/git-core/git-submodule`），那 79ms 是 fork +
shell 啟動的固定成本。

### 想設閘、被駁回、為什麼駁得對

這段留全程，因為結論的價值不如推翻它的那句話。

第一版計畫要在 `.gitmodules` 不存在時短路掉 `submodule status`，而且找到了看起來
很漂亮的落點：**`SubmoduleOps.cpp:236-238` 已經算好了那個述詞**——

```cpp
const bool hasGitmodules = !paths_.workDir().empty() &&
                           std::filesystem::exists(paths_.workDir() / ".gitmodules", ec);
```

它只用來決定要不要讀 `.gitmodules` 的 config，然後**無條件**往下跑
`submodule status`。延伸它成本是 0、省 79.2ms，而且與 `Session::refreshLfs()`
（`Session.cpp:1501-1507`，`git-lfs` 不在 PATH 時 `emitEmpty` 直接 return）
形狀一致。

**使用者駁回，理由是正確性而不是成本**：「submodule status 有就應該顯示，
不是加上『index 裡有沒有 gitlink』就逃避他」。

這句話同時殺掉了兩個候選述詞，而且殺得對：`.gitmodules` 在不在、index 有沒有
gitlink，**兩個都只是在猜 `git submodule status` 會說什麼**。答案要跟 git 一致
就只能問 git；放在 core 猜或放在 Dart 猜是同一個錯誤換個地方而已。

**`refreshLfs()` 的短路不是反例**，而分清這一點是整段推理的關鍵：它的條件是
「`git-lfs` 根本不在 PATH」——那不是在近似答案，是那支指令**跑不起來**。
一個是「我猜它會回空的」，一個是「它不存在」。

而回頭重讀自己的數字，本來就不需要那個閘：

- 79ms 幾乎全是 fork + shell 啟動的**等待**，不是 CPU。
- 它跑在 `sharedReadPool()` 上，**不擋 UI**，2 秒節流保證最多兩秒一次。
- **沒有任何使用者看得到的東西在等它。** 唯一需要即時的是衝突徽章，
  而它走同步的 `refreshRepoState()`，不論如何都在同一幀落地。
- 最差情況（2 執行緒池）是 working copy status 晚 ~70ms 到。

也就是說我**在最佳化一個沒有人在等的數字**。量測本身是對的（而且是使用者堅持
「成本秒數要量，量完如果有需要就設閘，這是你應該隱含做的事」才量的），錯的是
把「這個數字大」直接讀成「要修」，中間跳過了「誰在等它」。

**留給未來的一條路**：真要讓 submodule 便宜又正確，唯一誠實的做法是在 core 自己
算——`ls-files --stage` 濾 `160000`（量過 18.5ms，且**隨 index 大小成長**，
本 repo 933 檔就吐 91KB）再逐個判斷狀態字元，也就是不呼叫那支 shell script。
那是重寫一支 git 指令，成本與正確性風險都不小，要做該是有數字要求時單獨一輪。

### 收納規則寫成規則，不是清單

`refreshRepoStatus()` 的成員資格是**「controller 上每一支零參數的 `refresh*`」**
（十二支）。這樣下一輪新增 `refresh*` 時，「要不要進來」是一個有答案的問題，
而不是又一次憑印象補漏。

`request*` 一律不收，因為它們綁在使用者的選取上（path、oid、ref、stash index），
focus 回來時那個選取可能不存在。三個沒有必填參數、看起來像例外的，在 doc comment
裡逐一點名以示這是決定而非疏漏：`requestReflog({ref})`（panel 自己抓、按 ref 分頁）、
`requestCleanPreview()`（`git clean -n` 走訪整個 work tree，只餵一個 dialog）、
`requestOriginalOperationMessage()`（只在衝突流程中有意義）。

十二支逐一查證過都不連網。兩個特別確認的：**`refreshRemotes()` 是乾淨的
`git remote -v`**（`RemoteOps.cpp:325`），prune preview 在 `fetchRemote()` 的成功
路徑上（`remotesToPreviewAfterFetch()`）不在這裡；**LFS 連網的那兩支**
（`lfs pull` / `lfs fetch`，`LfsOps.cpp:108,141`）是獨立 operation。

### 「不連網」釘成可執行的斷言

doc comment 說「全部本地」是沒有承重的。所以補了一支測試斷言 `commandLog` 裡
**不得出現** `requestRemotePrunePreview` 與 `fetchRemote`。

它不是空頭斷言，變異驗證過：把 `requestRemotePrunePreview('origin')` 塞進
`refreshRepoStatus()`，**只有它轉紅**。

### fake seam：十支覆寫，以及為什麼 `refreshRepoStatus()` 不覆寫

`FakeRepoSessionController` 原本只覆寫 `refreshHistory` 與 `refreshWorkingCopy`。
其餘十支不覆寫就會撞上 `_session == nullptr` 守衛**安靜地什麼都不做**，
計數斷言分不出死掉與活著的——上一輪 `refreshWorkingCopy` 踩過同一個坑。

`refreshRepoStatus()` 本身**刻意不覆寫**：讓 fake 繼承真的那支，`commandLog`
收到的就是真的組合，而不是測試自己在 fake 裡重述一遍。一份會跟被測物一起變的
清單不能拿來測那份清單。

變異驗證確認這一半有承重：拿掉 fake 的 `refreshRepoState` 覆寫，兩支新測試轉紅。

### 三條 dispatch 路徑都測了

F5 有三條路：鍵盤（`WorkspaceActionShortcuts`）、macOS 系統選單
（`PlatformMenuBarHost` 的 `PlatformMenuItem.onSelected`）、in-window `MenuBarRow`。
改只動 `_buildActionHandlers()`，不碰 `MenuBarRow` 的具名參數——CLAUDE.md 記載的
dispatch parity bug 就是「只修 MenuBarRow」造成前兩條靜默 no-op。

`workspace_intent_dispatch_parity_test` 補的兩支涵蓋前兩條，用**差值**而非絕對值
（開 session 本身就會刷新一次）。既有的「F5 reaches refreshHistory」不受影響仍綠，
因為 `refreshRepoStatus()` 仍然包含 `refreshHistory()`。

### 沒做到的

- **LFS 量不到**，理由可檢查：`git-lfs` 這台機器上根本沒裝（`command -v git-lfs`
  空、`/opt/homebrew/Cellar` 沒有、`git lfs version` 回 "not a git command"），
  所以 C++ 側 `Session::refreshLfs()` 直接短路，成本就是一次
  `git lfs version` 的失敗探測、**量到 11.0ms 且每 session 只跑一次**。
  裝了 `git-lfs` 的機器上 `lfs track` + `lfs ls-files --long`（timeout 60s）
  **沒有數字**。這裡寫「沒有數字」而不是「很快」。
  注意量到之後也不是拿來設閘的——與 submodule 同一條理由。
- **量的是 git 指令層，不是完整 FFI 往返**。子行程主導總成本，但 event dispatch
  與 JSON 解析沒算進去，上表是下界。
- **「沒有畫面在等 submodule」是推理，不是量到的**。依據可檢查（衝突徽章走同步
  路徑、其餘在背景池、2 秒節流），但終究是推理。實機上若感覺得到延遲，該量的是
  「切回視窗到畫面正確」那一段，而不是回頭爭論這個閘。
- **lifecycle 轉換仍未實機驗證**，沿用上一輪、這輪沒有改變它：測試用
  `tester.binding.handleAppLifecycleStateChanged` 直接驅動，證明了接線，
  **沒有**證明 macOS 真的會在視窗焦點變化時送出 inactive/resumed 這組轉換。
- **既有行為，不是這輪造成的**：`_readWorkingCopyStatus()` 無條件清
  `workingCopyDiffs`，所以即使 focus 回來什麼都沒變，diff 面板仍會清空再重抓，
  視覺上一次閃動。要消掉它得讓 `WorkingCopyStatus` 有值相等，是另一個題目。

## feat/graph-lane-pitch — commit graph 的 lane 間距縮到 2/3

使用者要求把 commit graph 的**水平** lane 間距縮到現在的約三分之二，並明確指定
**點與線的大小都不變**。四個 commit，每個各自綠、可單獨 revert。

### 先確認問的是哪一個方向

原句是「commit graph line 間距」。這個字面在這個畫面上有兩個都成立的讀法：列與
列的垂直間距（`kCommitRowHeight` 26），以及 lane 與 lane 的水平間距
（`GbmLayout.graphLaneWidth` 17）。上一輪 fix/history-density-and-branch-filter
的敘述裡兩件事還一起出現過（「lines too far apart」與「rows too tall」），所以
從歷史也推不出來。**問了，答案是橫向**——列高完全不動。這裡把它寫下來是因為兩
個讀法會導向完全不同的改動，而不是因為問題本身難。

### 這是裁定的偏離，不是修正——而它推翻的是上一輪自己的修正

17 不是隨便來的：`spec_logic.js:428` 的 `const L0 = 15, L1 = 32, RH = 26` 是兩
個 lane 圓心相距 17，而 17 正是上一輪把既有 drift 的 18 改回規格的結果。所以這
一輪的 11 是**把上一輪的規格修正再蓋掉**，性質和 Working Copy 拿掉 checkbox、
側邊欄不再置頂目前分支同一類：規格引文仍然為真，只是不再是決定這個數字的東西。

三處記錄同時改，就是為了不讓下一輪照著舊理由改回去：`GbmLayout.graphLaneWidth`
的 doc comment、`gbm_layout_test.dart` 那條斷言的註解（它本來叫
「matches spec (17)」），以及 CLAUDE.md 的蒸餾條目。`docs/reports/spec-conformance-matrix.md`
沒有 lane pitch 這一列，不需要劃掉重寫。

### 「點不變」把一個非動不可的東西逼了出來

點在 11px 下其實放得下：半徑 4.2 加上 2px halo 的一半是 5.2，半個 lane 是 5.5。
**放不下的只有 HEAD 環**：半徑 7 加上 1.5px 描邊的一半是 7.75。

而 7.75 超出半個 lane 這件事本身**不會撞到任何東西**——鄰道的線近緣在
`11 − 1.75/2 = 10.125`，比 7.75 遠。真正的缺陷只有一個，而且要把它找出來得先知
道畫布是被裁的：lane 0 的圓心在 `0.5 × 11 = 5.5`，環會伸出欄位左緣 2.25px，被
`commit_row.dart:383` 的 `ClipRect` **切掉**。HEAD 多半就在 lane 0 這條主幹，所
以這會是常態可見的。

在「不准縮環」的前提下唯一的解法是把 lane 0 推離左緣，也就是
`kGraphLaneInset = 8`（`ceil(7.75)`），圓心公式從 `laneWidth * (lane + 0.5)` 改
成 `kGraphLaneInset + laneWidth * lane`。**它把「環有沒有空間」從 pitch 的函數
變成一個獨立常數**，這才是本輪真正的結構性改動；把 pitch 從 17 改成 11 只是改
一個數字。

值得記下來的是規格站在 inset 這邊而不是半格這邊：`L0 = 15` 配 pitch 17，lane 0
的圓心離半格（8.5）差得很遠。原本那個 `+ 0.5` 從來就不是規格，只是沒被質疑過。

欄位自然寬度公式 `laneWidth * (laneCount + 1)` **不用改**：它留下的尾端餘裕在
任何 lane 數下都比前置 inset 寬（12 lanes 時寬 143、最後一個圓心 129、環到
136.75），所以最後一條 lane 的環從來不是有風險的那個。這也是查過才敢說的，不是
推的。

### 被換掉的那條斷言，本來是一條代理規則

`graph_dot_geometry_test.dart` 原本寫的是「環塞得進半個 lane」，而且它自己就預
告了這一輪：

> 「7px 的半徑加上 1.5px 描邊的一半是 7.75，對上 17px 的 lane（到邊界 8.5）和
> 26px 的列（13）。兩個都是規格數字，但只差一點點就不相容——**未來 lane pitch
> 低於 16 就會把環切掉，這裡把它講出來**。」

它之所以成立，只是因為 lane 0 的圓心剛好在半格。它代理的是兩件不同的事，而
inset 進來之後兩件都可以直接講：

1. `kGraphLaneInset ≥ 環外緣` —— lane 0 的環在欄位內畫得完整。
2. `laneWidth − 線寬/2 ≥ 環外緣` —— 環不碰到鄰道的線。**這條比原本的代理鬆**：
   環可以越過名目上的 lane 邊界，只要它停在那裡真正畫著的東西之前。

第 2 條在 11px 下是 10.125 ≥ 7.75，成立；換句話說原本那條代理規則**過嚴**，照
它字面走會誤判本輪不可行。這是「代理規則會在兩個方向上都說錯話」的一個實例。

兩個 mutation 分別驗這兩件事，各自窄紅：inset 改 0 只紅環那條；公式改回
`lane + 0.5` 只紅新增的圓心那條（Expected 8.0、Actual 8.5）。第二個 mutation 是
必要的——第一個對圓心那條測試無效，因為它是拿 `kGraphLaneInset` 這個符號去比
的，常數改 0 兩邊一起變，測試照樣綠。**符號化的斷言擋得住公式改壞，擋不住常數
改壞；反過來也一樣**，所以兩條都要有自己的 mutation。

### 三個以 pitch 為前提的數字被一起帶動，一個沒有

- **`GbmGraphColumnId.graph` 的 153/34/425 → 99/22/275。** 這三個是刻意寫死的
  字面值（該檔沒有任何 import，這是它能被 repository 反向依賴的原因），只有
  `graph_column_test.dart` 用「必須是 lane 的整數倍」把推導關係釘住。它們是**用
  像素表達的 lane 數**，不動就等於把上限從八條 lane 悄悄變成十三條。
- **`commit_row_narrow_width_test` 的兩個 fixture。** 八條 lane 下「只掉 date」
  的 rung 從 563..670 滑到 **509..596**，原本取中點的 610 掉到區間外，重量後改
  552。另一個更隱蔽：十二 lane 的縮放案在 1000 與 240 兩個寬度下量到的 graph 都
  是 99（上限），`narrow < wide` 於是失效——240 本來能吃滿 153 的上限、現在也吃
  得滿 99 的上限，所以改成 160（量到 60px）才真的在測「盒子變窄」。**這正是
  CLAUDE.md 那條「grouping 規則一改，所有編碼了間隔／數量／相鄰的 fixture 都要
  重讀」的寬度版本。**
- **refs 欄位的 corridor ceiling 287 → 341。** 那段註解自稱是量出來的，而 graph
  的上限是它的上游：十二 lane 的成本從 153 掉到 99，多出來的 54px 全部落在 refs。
  重新二分量到 341 留得住 Date、342 開始掉，**差值 54 與上限的差完全相等**，兩
  邊互為交叉驗證。
- **沒有被帶動的是 refs 的 floor 91**，它是 JetBrainsMono 下 `HEAD → main` 加雲
  朵圖示的字寬量測，與 pitch 無關。一個「量出來的走廊」的兩端未必同時失效，這是
  要分開看的原因。

### 用 golden 看實際結果，而不是只看斷言

斷言只能說「7.75 ≤ 8」。實際長什麼樣是另一回事，所以用一支拋棄式的 golden 測試
把同一份 fixture 以 pitch 11 與 17 各畫一次並排放大 4.5 倍，直接看圖：lane 0 的
HEAD 環左緣完整、鄰道的線與點沒有互相吃到、間距的差異一眼可見。

**同時看到的一件事寫進 CLAUDE.md 了：餘裕只有 0.25px**（inset 8 對環外緣
7.75）。所以任何讓環變大的改動都必須連 inset 一起動，否則會安靜地被裁掉——而
那個裁切不會有任何錯誤訊息。

### 沒做、以及留下的取捨

- **列高沒動**（仍是規格的 26）。橫向縮到 2/3 而縱向不動，結果是點在視覺上比以
  前稀疏——這是使用者的裁定，不是疏漏。
- **HEAD 環在 11px 下橫跨約 1.4 個 lane**，比以前搶眼。依裁定不縮；如果實機用起
  來不喜歡，縮環是一個獨立且不影響其他東西的 commit。
- **`graphColumns.widths` 沒有做 migration。** 舊安裝存下來的 153px 在新 pitch
  下等於十三條 lane 而不是八條。存的本來就是「最多畫幾條 lane」的像素上限，語意
  隨 token 改變；這裡選擇記下來而不是加一次資料轉換。
- **計畫裡寫的實機 `flutter run -d macos` 目視沒有做**，改用放大 4.5 倍的並排
  golden 加一支綠的裝置層測試代替。要說清楚這個代替涵蓋到哪裡：幾何是等價證據
  （同一個 painter、決定性繪製），所以「lane 0 的 HEAD 環沒被裁掉」這件事是成立
  的；**不成立的是觀感**——1x 螢幕上 1.75px 的線配 11px 間距看起來會不會太密、
  太細，golden 放大之後正好看不出來。這一項留給使用者實機確認。

## feat/graph-dot-and-lane-colors — 點放大，以及分支顏色不再撞在一起

使用者提了兩件事：「點的大小放大」，以及「分支顏色太容易重複了，兩兩相臨分支之間
顏色盡量在色環上差異多一點」。第二件裡有一半是 bug，而不是品味問題——這是這一輪
最值得記下來的部分。

### core 說十二種顏色，UI 只畫得出六種

`src/core/graph/GraphSnapshot.h:25` 是 `constexpr std::uint8_t kPaletteSize = 12`，
`LaneAllocator::colorForSeed` 因此發出 `0..11`。`app_flutter` 這邊的
`GbmColors.graphLanes` 只有六色，而 `graph_column_painter.dart` 取
`row.color % colors.graphLanes.length`。於是：

| core 發出的 id | UI 實際畫出的 |
|---|---|
| 6 | 0 —— **主幹自己的顏色** |
| 7, 8, 9, 10, 11 | 1, 2, 3, 4, 5 |

十一種非主幹 id 折成六個顯示類別，大小分別是 2,2,2,2,2,1。兩條隨機分支看起來同色
的機率是 `5 × (2/11)² + (1/11)² = 21/121 ≈ 17.4%`，而十二色都畫得出來的話是
`1/11 ≈ 9.1%`。使用者說的「太容易重複」有一半就是這個。

**沒有任何東西把這兩個常數連在一起**，這是它能無聲存在的原因：一個是 C++ 標頭裡
的 `constexpr`，一個是 Dart 清單的 `.length`，中間隔著一個 `%` 運算子——那個 `%`
本來就是防呆用的，結果它把 bug 也一起吞了。所以這一輪的測試不是抄一份 12 過來
比對，而是 **`gbm_lane_palette_test.dart` 直接開 `../src/core/graph/GraphSnapshot.h`
用 regex 讀出 `kPaletteSize`**。抄一份常數正是先前漂移的成因；再抄一份只是把漂移
往後延一輪。檔案讀不到時它是 fail 而不是 skip，理由相同。

### 兩個問題其實不是同一個問題

「顏色重複」和「相鄰的顏色太像」聽起來像同一件事的兩種說法，但在這個 codebase 裡
它們住在兩個不同的層：

- 重複是**色盤大小**的問題，住在 Dart。
- 相鄰是**指派方式**的問題，住在 C++——因為 `colorForSeed` 是
  `1 + (oid.hash() % 11)`，跟 lane 的位置完全無關。兩條相鄰分支拿到什麼顏色是
  雜湊擲骰子決定的，所以**把色盤加大、排得再漂亮，都不會讓相鄰的兩支比較不像**。
  只會讓撞色機率從 17.4% 降到 9.1%。

這個區分是要使用者裁定的原因：只補色盤是把要求砍掉一半，而「本輪不做」不是實作者
能自己決定的。使用者選了完整的做法。

### 讓 core 能談「色相」而不必看見任何 RGB

`LaneAllocator` 在 `src/core/` 裡，而 `src/core/` 不能依賴 UI——所以它永遠拿不到
一個 `Color`。要讓它把新 lane 推離鄰居，唯一的辦法是讓 **index 距離本身就是色相
距離**：

- Dart 這邊：`graphLanes` 的第 `i` 個顏色固定坐落在 `hue(0) + 30 × i` 度（OkLCH），
  三套主題各自以自己的 lane 0 為錨。
- C++ 這邊：`colorDistance(a, b) = min(|a−b|, 12−|a−b|)`，然後要求 `>= 3`。

3/12 就是四分之一個色環。這條契約兩邊的註解都寫了，而且寫的是**它壞掉時不會有任何
症狀**：把 `graphLanes` 重排一下，core 照跑不誤，只是它「最大化」的那個數字不再
代表任何東西。所以測試裡有一條專門釘住排序（把相鄰兩色對調就會紅）。

**色相用 OkLCH 而不是 HSL，這一點是量出來的。** 同一組十二色在 HSL 色環上的相鄰
間距是 12.4°（青帶）到 68°（綠帶）——HSL 的色環不是等感知的，綠佔掉一大塊、青綠
擠成一條。如果拿 HSL 寫斷言，一組真正等距的色盤會被判成不等距，而一組在 HSL 上
剛好等距的色盤（實際看起來不等距）會通過。測試檔裡自己實作了一份 OkLCH 換算當
oracle，理由跟 `sameLogicalFile` 留在測試檔一樣：**用產生色盤的同一份程式去驗色盤，
它不可能跟自己不一致。**

三套主題各自量過對比度，都不低於原本六色時的最差值：白底 3.34 → 3.44、
`_darkTechnical` 的 #0D1117 底 5.64 → 6.19、`_lightIde` 白底 3.75（不變）。
`_lightIde` 沒有直接複製 `_neutralProfessional`，而是取它原本五個非 accent lane 的
OkLCH 平均（L=0.546 C=0.151）當目標——兩套淺色主題的 lane 0 都是 `_accent500`，
不特別處理的話整組色盤會變成同一份。

### 「雜湊優先，撞到才修」而不是「一律散開」

`colorForSeed` 的新形狀是：雜湊選一個 index，如果它跟左右鄰居都差 ≥3 步就直接用；
否則從那個 index 往外 `+1, −1, +2, −2, …` 探測十一個非主幹 index，取第一個過關的。

為什麼不是直接挑「離鄰居最遠的那個」：因為那會讓每個 lane 的顏色都變成整個活著的
lane 集合的函數，任何一條不相干的分支開或關都會讓別人換色。雜湊優先的版本只在真的
擋路時才偏移，而且偏移量最小，所以**不再擁擠時它會回到原本想要的顏色**。

**末尾那個 `return base` 目前不可達，而且這件事是可以證明的**：兩個鄰居各自只封鎖
「與自己距離 ≤2」的五個 index，最多封鎖十個；候選有十一個（`1..11`），所以至少剩
一個。註解裡寫了這個推導，也寫了為什麼它是 `return` 而不是 assert——將來若把約束
放寬到更多鄰居，退化成純雜湊比 trap 好。

### 順手改正兩處被高估的註解

這是這一輪的第二個「記錄本身是錯的」案例：

1. `LaneAllocator::seed` 的註解說顏色綁 oid「是它能跨 refresh、跨增量 append 保住
   分支顏色的原因」。但 ref tip 的 lane 是**用 tip commit 本身當種子**
   （`GraphBuilder.cpp:96` 的 no-incoming-edges 路徑），所以往該分支 commit 一次
   顏色就變了——這在鄰居規則出現之前就已經是這樣。oid keying 真正買到的是「freed
   lane index 被重用時不會亂」，範圍比註解宣稱的窄很多。**這一點會影響決策**：
   「改成看鄰居會破壞穩定性」這個代價，大部分本來就不存在。
2. `InvariantColorsAreStableWhenHistoryIsAppended` 的註解寫「appending 不能讓既有
   分支換色」，但迴圈裡的 `if` 只在 lane 0 兩邊都成立時才斷言——prepend 50 個
   commit 之後，絕大多數 row 的 lane 都變了，全部被跳過。**一條只驗了主幹的測試，
   掛著一個通用宣稱的註解。** 註解改成說它實際驗的東西，以及通用宣稱在鄰居規則前後
   各以什麼方式不成立。

### 點的大小：5.0 是被 HEAD 環挑出來的，不是隨便選的

環維持規格的 `r: 7` / stroke 1.5，所以它的**內緣**在 6.25。點含 halo 的外緣是
`radius + 1`。5.0 是還能讓兩者之間留下背景的最大值（6.0，餘裕 0.25px）；再大一點，
HEAD 那一列的環就不再讀成一圈環，而是讀成點的粗邊。

**這件事沒有任何例外看得見**：環是後畫的，畫過去也不會有錯誤，只會變醜。所以測試
是一條純算術斷言（`dotOuter <= ringInner`），mutation 到 5.3 就紅。

使用者在被告知「再大就要連環和 `kGraphLaneInset` 一起動、graph 欄的三個寬度和
narrow-width fixture 要重量」之後選了 5.0，所以這一輪 inset 完全沒動。

### 驗證

- `flutter analyze` 0 issues；`flutter test` 2292 passed
- `gbm_core_tests` 448 tests，446 passed / 2 skipped（兩條 LFS 測試本來就 skip）
- clang-format：本機是 v22 而 CI 釘 v18，所以在 scratchpad 開 venv 裝
  `clang-format==18.1.8` 來比對。順帶確認 `cq.yml` 的 `check-path` 只有 `src`，
  `tests/` 不在 format gate 內——v18 對 `GraphBuilderTest.cpp` 有兩處既有的意見，
  那兩行在 HEAD 就已經那樣，不是這一輪弄的，照規矩沒有整檔重跑
- mutation：四條，每一條都紅在該紅的地方
  - `kGraphDotRadius` 5.0 → 5.3：只有兩條點的測試紅
  - `graphLanes` 少一色 / 相鄰兩色對調：分別只紅長度那條、只紅色相順序那條
  - `kMinColorSeparation` 3 → 1：兩條分離度測試紅
  - 探測順序從「以雜湊為起點」改成「從雜湊+1 開始」：只有「沒被擠到時仍用雜湊色」
    那條紅
- 拋棄式 golden 放大 3 倍看實際結果：十二色在暗底逐格轉一圈、舊六色折成兩輪的重複
  一眼可見、六條相鄰 lane 的實際列、兩套淺色主題的色盤、以及 4.2 對 5.0 的並排
- 裝置層 `history_filter_test.dart -d macos`，跑在重建過的 `libgbm_capi.dylib` 上
  （core 改了，不重建的話跑的是舊的那份）

### 沒做、以及留下的取捨

- **實機 `flutter run` 目視沒做**，同上一輪：幾何與顏色由 golden 涵蓋，1x 螢幕上
  十二色會不會有兩支在特定主題下仍嫌接近，留給使用者實機確認。
- ~~**相鄰只看左右各一欄**，不是所有活著的 lane。這是照字面的「兩兩相臨」，也是
  保住雜湊穩定性的原因：約束越多，偏移越頻繁，顏色越容易被不相干的分支推著跑。
  隔一欄的兩支仍可能相近（最壞是 3 步 = 90°）。~~
  **下一輪被使用者用截圖推翻**：隔一欄的兩支不只是「相近」，而是同一個顏色，而且
  在 400 commit 的 fixture 上一再出現。這段的兩個理由也都站不住——約束變寬並不會
  「把顏色推著跑」，因為顏色是 seed 當下決定、之後不再重算；而且 ±1 比字面更窄，
  `allocateLeftmost` 給的是最低空 lane，ref tip 這條路右邊必然是空的。改正見
  「相隔一欄仍然撞色」一節。
- **顏色仍會在往分支 commit 之後改變**，因為種子是 tip。這是既有行為，不是這一輪
  造成的，也不在使用者的要求範圍內——但既然註解被改正了，就一起記在這裡。
- **spec 只定義 `--graph-lane-1` 到 `--graph-lane-6`**，十二色是使用者裁定的偏離。
  三處記錄：`tokens.dart` 的 `graphLanes` 註解、`gbm_lane_palette_test.dart` 的
  檔頭、以及 CLAUDE.md 的 invariant。


## fix/graph-lane-color-window — 相隔一欄仍然撞色

上一輪把「兩兩相臨的分支顏色差遠一點」實作成 `LaneAllocator` 檢查左右各一欄。
使用者接著送來一張截圖：兩支同色的分支中間只隔一個 lane。這一輪把窗口拉寬並分級。

### 截圖說的是真的，而且測得出來

先把它寫成測試，再看紅不紅。`GraphBuilder.InvariantAColourIsNotRepeatedWithinThree
ColumnsAtAnyRow` 走真正的 builder，對 400 commit 的隨機 DAG 掃每一列上同時被畫出來
的欄位。第一次跑出來的頭幾行就是截圖本身：

```
row 7: lane 1 (c9) is 2 column(s) from lane 3 (c9)
row 9: lane 3 (c9) is 2 column(s) from lane 5 (c9)
row 35..38: lane 1 (c9) is 3 column(s) from lane 4 (c9)
row 60: lane 2 (c3) is 2 column(s) from lane 4 (c3)
```

`c9` 在 darkTechnical 是 `02B685`，就是截圖裡那個青綠。**同色、隔一欄、反覆出現**——
不是機率問題，是規則根本沒管到那一欄。

### ±1 其實比字面更窄，但沒有窄成「只有左邊」

寫這一輪的第一版註解時我斷言：`allocateLeftmost()` 回傳的是最低的空 lane，所以
seed 當下左邊必定被佔、右邊必定是空的，「左右各一欄」實際上等於「只有左邊」。

**mutation 打掉了這個斷言的一半。** 把 `crowdingOf()` 的右側整段刪掉重跑，紅的不只
是這一輪的新測試，還有上一輪的 `InvariantAdjacentColumnsNeverLookAlikeAtAnyRow`——
右側的檢查在真的 builder 裡會觸發。原因是第二條配置路徑：merge 的第二個以後的
parent 走 `allocateAfter(lane)`，落點是 merge commit 右邊的第一個空 lane，兩側都
可能已經有東西。所以正確的說法是**分路徑**的：ref tip 那條路右邊必然是空的，
merge parent 那條路不是。註解與測試註解都照這個改寫了。

這正是 repo 那條「mutation 沒有落在註解預測的地方，就是註解錯了」的用法。

### 分級窗口，以及為什麼是最小化而不是過濾

規則現在是 `kNeighborWindow = 5`，每一段要求不同的色相距離：

| 距離 | 要求 | 在 pitch 11 下 | 意思 |
|---|---|---|---|
| 1 欄 | 3 步（90°） | 11px | 貼在一起，必須差四分之一個色環 |
| 2 欄 | 2 步（60°） | 22px | 中間隔一個，明顯不同色 |
| 3–5 欄 | 1 步（30°） | 33–55px | 只要求「不是同一個顏色」 |
| 6 欄以上 | 0 | — | 不管 |

遞減是因為「撞色」的傷害本身就隨距離遞減：貼在一起的兩支同色會被讀成一支加粗，
隔五欄的兩支同色只是重複用色。而窗口不可能再寬——非主幹的顏色只有 11 個，
`kMaxLanes` 是 48，夠寬的圖一定會重複，規則能決定的只是**重複落在哪裡**。

也因此這裡是**最小化**而不是過濾。五欄寬的窗口最多有十個鄰居，11 個候選對上十個
鄰居，約束真的可能無解；無解時「盡量遠」是有意義的答案，「找不到就退回雜湊」不是。
`colorForSeed` 仍然先照雜湊走：由 `1 + hash % 11` 向外 `+1, -1, +2, -2, …` 探，
第一個 penalty 為 0 的候選直接回傳，所以沒被擠到的 lane 拿到的顏色跟以前一模一樣。

### 權重是把字典序寫成加總，而且那個界是算得出來的

`penaltyWeight` 是 100 / 10 / 1。這不是調參，是要讓三段不能互相交換：距離 2 以外的
所有 penalty 加起來最多是 `2 × 10 × 2 + 6 × 1 × 1 = 46`，小於「對緊鄰 lane 改善一
步」的 100。所以一個候選永遠不會為了讓四個遠處鄰居開心而去擠貼著自己的那一欄。

**這個界一開始沒有任何測試看得到。** 把 `penaltyWeight(1)` 從 100 改成 1 重跑，
全綠——現有的每個 fixture 都存在「全部滿足」的候選，而只要存在，權重就從來不會被
問到。補了兩個測試，各自造出一個**無解**的鄰居配置：

- `ACloseLaneOutranksAnyNumberOfDistantOnes`：左一欄是 c4，而三到五欄外剛好擺著
  「能跟 c4 差四分之一圈」的那六個顏色（c1, c7, c8, c9, c10, c11）。每個候選都被
  擠到，答案必須是 c1（重複一個五欄外的顏色），不是 c2（差 c4 只有兩步）。
- `TheMiddleTierOutranksTheDistantOneToo`：同一個論證降一階，兩欄外是 c4 與 c10，
  能同時差它們 60° 的五個顏色全被擺到三到五欄外。答案是 c2，不是雜湊原本要的 c3。

### 五個 mutation

| mutation | 結果 |
|---|---|
| `requiredSeparation(2)` 2 → 1 | 紅：新的兩個（單元 + DAG invariant） |
| `kNeighborWindow` 5 → 1（退回上一輪） | 紅：新的兩個；上一輪的 adjacency invariant 仍綠 |
| `crowdingOf()` 刪掉右半邊 | 紅：新的 DAG invariant **和上一輪的 adjacency invariant** |
| `penaltyWeight(1)` 100 → 1 | 一開始全綠 → 補測試後紅：`ACloseLaneOutranksAnyNumberOfDistantOnes` |
| `penaltyWeight(2)` 10 → 1 | 一開始全綠 → 補測試後紅：`TheMiddleTierOutranksTheDistantOneToo` |

第三個是這一輪最有價值的一個：它同時證明了右側檢查是活的，也證明新測試沒有把舊
的那條蓋掉。第四、五個是「綠的 mutation 一樣常代表斷言太弱」的又一次實例。

### DAG invariant 是量出來的，不是證出來的

`InvariantAColourIsNotRepeatedWithinThreeColumnsAtAnyRow` 的註解明寫這一點。11 個
非主幹顏色對 48 欄，這條性質不可能是定理；它是「一個長得像真實 repo 的 400 commit
DAG，在三欄以內不重複」的一次量測。沿用了 adjacency invariant 的
`comparedPairs > 200` 反空過守衛。

### 這輪沒做

- **完全不動 Dart。** 顏色 id 仍然是 0..11，palette、painter、token 一個字都沒改，
  所以沒有跑 `flutter test`／`analyze`／裝置層——驗證面就是 `gbm_core_tests`
  （452 個，450 通過，2 個既有的 LFS skip）加上 `LaneAllocator.h` 的 clang-format
  v18。
- **超過五欄仍可能撞色**，11 欄以上必然撞。上面說過原因。
- **既有 repo 下次開啟會再重排一次顏色**，跟上一輪同理：規則變了，seed 當下的答案
  就變了。主幹仍是 accent。
- **1x 實機觀感仍然沒有覆蓋**。這一輪連 golden 都沒重畫（Dart 沒動），使用者手上
  就有真機，交給使用者看。

## fix/branch-prune-and-gone-marking — prune 壞掉的表象下有六個缺陷

使用者回報三件事：prune 失敗（附了三行 exit 1 的 git log）、「從來沒 push 過的分支
被標成 gone，而且只能選 delete」、以及「有本機分支的列應該用 05-B 不是 05-C，02 的
分支狀態圖示也用錯了」。

追下去是**六個獨立缺陷**，其中只有一個是「prune 壞掉」。

### 沒活過原始碼的前提

> 以為使用者遇到的是 prune 這個功能壞了。

實際上使用者看到的整個現象——灰雲、fetch 後變黃雲斜線＋gone、右鍵只剩 prune 與
delete remote——都不是 prune 造成的，而是**側邊欄把一條分支畫成了兩條**（或畫成了
遠端那一條）。prune 確實也壞了（D1），但它是第二個問題，不是那個症狀的成因。

`mergeLocalAndRemoteBranches()` 當時是這樣濾掉重複的：

```dart
final Set<String> trackedUpstreams = localBranches
    .map((b) => b.upstream).where((u) => u.isNotEmpty).toSet();
final List<RefInfo> remoteOnly = remoteBranches
    .where((r) => !r.isSymbolic && !trackedUpstreams.contains(r.fullName))
```

只有「某條本機分支的 upstream 設定**正好等於**這條 remote ref」才會濾掉。用
`git push origin HEAD`（沒有 `-u`）或走 PR 流程推上去的分支，`branch.<name>.merge`
是空的，同名的 `origin/X` 就逃過了過濾：

```
名字沒有斜線 (main):
  rootNodes['main'] = local  →  rootNodes['main'] = remote   ← Map，後寫贏
  結果：畫面上只剩 remote 那一列（灰雲 ＋ 05-C 選單，不能刪分支）

名字有斜線 (feat/x):
  folderIndex['feat'].children = [ local leaf, remote leaf ]  ← List，不去重
  結果：兩列並排，一列 git-branch 一列灰雲
```

fetch 之後 prune preview 把 `origin/X` 標成 gone-pending，那一列就變成 cloud-off ＋
gone ＋ 刪除線。**完全對上使用者描述的「剛進來灰雲、fetch 後黃雲斜線」。**

這條前提的代價不只是找錯方向：如果照使用者字面上的抱怨只修 prune，六個缺陷會修好
一個，而使用者看到的症狀一個都不會消失。

### 六個缺陷

| # | 缺陷 | 怎麼找到的 |
|---|---|---|
| D0 | 同名的 local 與 remote 沒合成一列 | 讀碼 |
| D1 | Prune 送出**完整 ref 名**，git 只吃**短名** | 真實 git 實測 |
| D2 | 批次刪除「部分成功」被當成全失敗，強制重試又重送已刪的名字 | 真實 git 實測 |
| D3 | 有本機分支的 gone 列套 05-C，只剩 Prune／Delete on remote | 讀碼 |
| D4 | BRANCH_STATES 第 3 列的 `local` badge 完全沒實作；dim 多套在 gone 列上 | 全 repo grep `'local'` 無結果 |
| #74 | `_remoteOf()` 把 `refs/remotes/origin/x` 切成 `"refs"` | issue 既有，本輪一併修 |

D1 與 D2 是**跑出來的，不是讀出來的**——兩者都在 scratch repo 上用 git 2.55.0 實測。

#### D1 實測

```
$ git branch --delete --remotes refs/remotes/origin/feat/x
error: remote-tracking branch 'refs/remotes/origin/feat/x' not found      exit=1
$ git branch --delete --remotes origin/feat/x
Deleted remote-tracking branch origin/feat/x (was 668c5ce).               exit=0
```

`RemoteOps.h` 的契約寫的就是短名，Dart 這邊卻兩份呼叫端不一致：prune dialog 送短名
（對），`branch_row_actions.dart` 兩處送全名（錯）。
`remote_prune_preview_entry.dart` 的註解甚至明白寫著兩種形式並存——被知情地放行了，
但 C++ 只收短名。

#### D2 實測

```
$ git branch -d a cur b
error: cannot delete branch 'cur' used by worktree at '...'
Deleted branch a (was 668c5ce).       ← a 與 b 真的被刪了
Deleted branch b (was 668c5ce).
exit=1                                 ← 但仍然 exit 1

$ git branch -D a2 cur b               ← 重試時 a2/b 已不存在
error: branch 'a2' not found
error: branch 'b' not found
exit=1
```

`BranchOps.cpp` 只看一次 exit code，所以：`-d` 刪掉一半 → 報全失敗 → 使用者按
「Delete anyway」→ `-D` 重送全部 5 個名字 → 已刪的變成 "not found" → 又報全失敗。
**使用者要的事其實都做完了，畫面兩次都說失敗。** 這正是使用者貼上來那三行 log 的
全貌。

修法是執行前先探一次 `git for-each-ref` 算出「哪些還在」，只送這些；執行後失敗再探
一次，算出「這次真的刪掉了哪些」，誠實列出成功與失敗。**刻意不解析 per-name
stderr**——git 訊息會被 gettext 在地化，既有的 `"not fully merged"` 比對已經是脆弱
前例，只留給**訊息**用，不讓**正確性**依賴它。

### 使用者裁定（會記成規格偏離）

1. **選單不再出現 prune 這個字**，背景做掉。本機分支列只有 `Delete branch…`
   （P18 風格 dialog ＋「同時刪除遠端分支」核取方塊，預設不勾）；遠端分支列只有
   `Delete remote branch…`（同樣跳 dialog，但沒有那個核取方塊）。
2. **fetch 後自動背景 prune**，僅限「遠端已刪且沒有任何本機分支對應」的 ref。
   有本機分支的保留 cloud-off，因為使用者還能 repush 回去。
   `Remote → Prune remote branches` dialog 保留為手動退路。
3. 圖示規則按 BRANCH_STATES 重排（見下方 C7）。
4. 補上 `local` badge。
5. #74 一起修。

### 一次量測，換掉一個二次方

C4 的第一版 `remoteCounterpartOf()` 是每條本機分支掃一遍遠端清單，L×R。量出來：

| L = R | 每次 merge |
|---|---|
| 50 | 140µs |
| 200 | 2,162µs |
| 500 | 14,092µs |

側邊欄每次 build 都會呼叫，500 條分支的 repo 不算罕見，14ms 是掉幀。改成一次建好
`RemoteBranchIndex`（一趟 O(R)，之後每查 O(1)）：

| L = R | 每次 merge |
|---|---|
| 50 | 15.7µs |
| 200 | 58.2µs |
| 500 | 141.9µs |

500 條那格快了 99 倍，而且成長回到線性。數字寫在這裡，是為了下一輪要動這條路徑時
從數字重新決定，而不是從同一個猜測。

### 兩個變異回綠，各自暴露一個測試盲點

**C4 M1（`remoteCounterpartOf` 的同名規則拿掉）全綠。** 原因是 merge 層還有一道
`takenNames` 去重：同名的 remote 列**無論如何**都會被丟掉，所以任何 merge 層的斷言
都看不見同名規則是死是活。兩個機制剛好蓋住同一個結果，其中一個壞掉沒有症狀。補了
五個直接打 `remoteCounterpartOf` 的測試之後，六個變異才全部窄紅。

**C7 M4（`SidebarPanel` 傳 `ref.upstream` 而不是解析後的 counterpart）全綠。**
`branch_tree_item_test.dart` 是把 counterpart 當參數餵進去的——widget 收到什麼就畫
什麼，永遠正確。缺的是「panel 到底算出了什麼再傳下去」。補的測試在 panel 層放兩列
`upstream` 都是空的分支，唯一的差別是遠端有沒有同名 ref，再用 y 座標確認 badge 長在
對的那一列上。

這兩個是同一種形狀的兩個變體：**斷言的位置錯過了實際做決定的那一層。**

### 計畫外的發現

**`deleteSingle()` 根本沒開 dialog。** C6 在改右鍵選單時發現，`Delete branch…`
（有刪節號）直接就 `deleteBranch()` 下去了。刪節號、規格第 6 頁、以及使用者這輪的
裁定三者都說要跳 dialog。改成 `context.push(deleteBranchDialogFor(...))`。

**delete dialog 從來沒收到本輪自己的規則。** C6 把側邊欄的 prune 入口拿掉之後，這個
dialog 成了刪除遠端分支的唯一路徑，但它仍然只讀 `upstream` 與 `isGone`。三個後果：
沒設 tracking 的分支看不到核取方塊；`isGone` 只在 prune **之後**才為真，所以從 fetch
發現到 prune 記錄之間整段期間方塊都可勾，勾了就送出注定失敗的 push；最嚴重的是標題
印 upstream 的分支名、派發送本機分支名——`feature/x` 追蹤 `origin/renamed-x` 時，
畫面說「Also delete renamed-x」而實際刪 `feature/x`。**一個事實兩處各自推導，已經
上線。** 這是本輪第二次踩到同一種形狀（第一次是 C3 自己的核取方塊述詞），所以
C8b 把 remote 名與遠端分支名一起收進 `deleteBranchRemoteTarget()` 一次算完。

值得記下的是這個缺陷為什麼能活這麼久：**除了改過名的 upstream，兩個名字永遠一致。**
測試 fixture 只要不刻意讓它們不同，就看不到。

### 多 remote 同名：一個明說的減量

`origin/x` 與 `upstream/x` 同時存在、而本機的 `x` 沒設 tracking 時，「同名」指向兩個
不同的 ref。這時 `RemoteBranchIndex` **誰都不認領**——明示的 tracking 設定優先，
沒有設定就不猜。後果是那條本機分支會顯示成 `local`，兩條遠端列則各自畫出來；一條
分支的遠端對應本來就無法從同名推得，猜錯比不猜糟。

另外，同一個名字在樹上只會有一列，先到先得，本機分支永遠先排。這是為了讓
`buildBranchTree` 的 `rootNodes[name] =` 不再有靜默覆蓋——**但刻意沒有加 assert**：
計畫原本要在那裡加一道防護，實作時判斷那會把一個既有的靜默 bug 變成 debug 期崩潰，
而使用者手上的是 release build，換來的只是把問題推到下一個人身上。

### 自動 prune 的兩個邊界

**preview 不是只有 fetch 會發。** Prune dialog 自己一開啟就會要一份。若不分來源，
使用者一打開那個 dialog，自動 prune 就會把清單上的 ref 從他眼皮底下刪掉，接著他按下
Prune 會對已不存在的 ref 跑 `git branch -d -r` → exit 1 → dialog 報失敗。判別方式
**本來就存在**：`_autoPrunePreviewsInFlight`（remote → 尚未回覆的自動 preview 數）。
自動 prune 只在這個計數涵蓋這次回覆時觸發。

**自動 prune 失敗不該跳 banner。** 使用者沒有要求這件事，失敗也不影響他正在做的事。
所以 `automatic` 的失敗不寫進 `lastError`，但仍然照常進 operation log——不通知，不
等於不記錄。

### 第三個計畫外的發現：另一條刪除遠端分支的路徑

C6 把 05-C 的項目改名成 `Delete remote branch…` 之後，它的能見度提高了，而它走的
是另一個 dialog——本輪從沒檢查過。兩件事：

`openDeleteRemoteBranchDialog()` 的 remote 名來自 `remoteBranchParts(fullName)`，
branch 名卻來自 `remoteRef.shortName`。**今天不會出錯**，只因為
`mergeLocalAndRemoteBranches` 會把每一列重建成去掉前綴的形式；core 自己的
shortName 是**保留**前綴的（`RefStore.cpp` 的 `substr(13)` 從 `refs/remotes/`
起算）。拿未經合併的 ref 呼叫它就會靜默送出
`git push origin --delete origin/feat/x`。

**這裡的測試盲點值得單獨記一筆**：經由側邊欄的每一個 ref 都已經正規化過，所以
**沒有任何 fixture 能讓那兩處推導不一致**——mutation 一定回綠。唯一能釘住它的
方式是繞過側邊欄、直接用 core 形狀的 ref 呼叫那個函式，並且 fixture 要用**巢狀
名**（`origin/feat/x` vs `feat/x`）才分得出「去掉 remote」與「取最後一段」。

當時這條只寫進測試的註解裡，而使用者的回應把它推到正確的位置：**知道了就不該只寫
註解，要寫成測試才算真的保證**。於是往下做了兩件事，見下一節。

第二件：遠端已刪的 remote-only 列仍會畫出來（自動 prune 進行中，或失敗了），而它
的 `Delete remote branch…` 送出的是必然被拒絕的 push。與 C8b 修掉的核取方塊同一種
缺陷：在只會失敗的狀態下仍提供動作。改成停用並附原因，不隱藏。這一項超出原計畫，
單獨一個 commit 以便需要時只回退它。

### 把那個盲點補成真的保證

使用者的裁定：註解不算保證。兩件事，一件是釘前提，一件是把前提拿掉。

**釘前提。** 「側邊欄拿到的 remote ref 一定去掉前綴」原本只以兩種間接形式存在：
panel 層有 `_remoteOnlyRelease`（扁平名 `origin/release` 畫成 `release`），merge
層有「同前綴的 local 與 remote 落在同一個資料夾」。前者是扁平名，在「去掉第一段」
與「取最後一段」兩種實作下都會過；後者用了巢狀名，兩種變異都紅，但它斷言的是**資料
夾數量**，名字只是推論出來的，而且不是讀 `BranchRowActions` 的人會翻的地方。所以補
的是一條**具名**的契約測試：巢狀 remote-only 進去，`shortName` 出來必須是 `feat/x`
——一個期望值同時排除 `origin/feat/x`（沒去）與 `x`（取最後一段）。這條的價值是可被
引用，`openDeleteRemoteBranchDialog` 的註解現在指向它。

**把前提拿掉。** 更值錢的一半：既然 05-C 有三個動作，就三個都查。`fetchRemoteRef`
本來就從 `fullName` 推導（安全），`openDeleteRemoteBranchDialog` 上一節剛改好，而
**`checkoutRemoteAsNewLocal` 還在拿 `shortName` 當新分支名**——同一個缺陷，而且失敗
得更安靜：`git` 接受 `refs/heads/origin/feat/x` 這種 ref，所以不會有任何錯誤，使用者
只是從此擁有一條長得像遠端分支的本機分支。三個動作現在共用同一個 core 形狀的具名
fixture，各有一條直接呼叫的測試。

變異驗證把「為什麼一定要直接呼叫」也量出來了：把 `fetchRemoteRef` 改成讀
`shortName`，**只有新的直接呼叫測試變紅**，原本走 panel 的那條 fetch 測試（扁平名
`release`）在同一個變異下仍然是綠的。

### 一個本輪造成的矛盾（提出時未決，當輪內由使用者裁定移除）

Preferences → **General** 的 AUTOMATIC FETCH 段有一列 **「Prune while fetching
— Also drop remote-tracking refs whose branch is gone on the remote」**（早先的
記錄寫成 Preferences → Git，是錯的，它在 `_GeneralSection`）。`autoFetchPrune`
被儲存、被畫出來，**沒有任何程式碼讀它**（#102 記錄的三個 `autoFetch*` 孤兒之一）。

本輪之前它只是「調了沒反應」。本輪之後，它描述的行為**無條件會發生**，而開關預設
是關的——使用者把它關掉，ref 仍然會在 fetch 之後消失。孤兒設定從「沒作用」變成
「畫面上寫的事情正背著它發生」。

而且照字面接上去做不到：那一列的文案是**完整** `--prune`，使用者的裁定則是有本機
分支的要留著。文案本身就與裁定衝突。三條路（移除該列／改寫文案只控制子集／接受
不一致）都是產品決定，已寫進 #102，本輪不擅自處理。

**使用者裁定：移除。** 於是 `autoFetchPrune` 從 model、dialog 與儲存三處一起刪掉，
不是留著不接線——留著的話那個控制項就是會說謊。依據是 `AppPreferences` 自己的類別
註解那句話：「a preference that silently does nothing is worse than one that is
not offered」，計量網路暫停早就是照這句話處理成「不提供」。P11 item 9 的
「可選同時 prune」因此成為一條**使用者裁定的規格偏離**，已就地改寫進 matrix。

刪的時候順手查證了一件事，結果比預期糟：`autoFetchEnabled` 與 `autoFetchMinutes`
**同樣沒有任何讀取端**，沒有任何計時器會因為它們發出 fetch。所以 matrix 上 P11
第 9 列原本那個 符合 從頭就只驗到「設定存在」，沒驗到「行為存在」——與 P02 item 2
同一種形狀。那一列一併更正，剩下的兩個孤兒留在 #102（沒有新開 issue）。

### 這輪沒做

- **超過一個 remote 的同名推斷**：見上面，明說的減量。
- **`buildBranchTree` 的重複 key assert**：見上面，刻意不加。
- **實機驗收**：使用者手上就有這個 repo 的真實狀態，交給使用者看。
  `git remote prune origin --dry-run` 當場確認了預期：`origin/fix/focus-refresh-repo-state`
  與 `origin/fix/graph-lane-color-window` 兩條遠端已刪，且都沒有本機分支認領，
  所以按 fetch 之後這兩列應該自動消失。刪除遠端分支與批次刪除本機分支會動到使用者
  真實的 repo，不由實作者代跑。

### 驗證

`flutter analyze` 零 issue、`flutter test` 2352 綠 1 skip、`dart format
--set-exit-if-changed .` 乾淨、`ctest` 603/603（2 個既有的 LFS skip）、
clang-format **v18**（CI 的 pin，本機是 v22，所以另外裝了 18.1.8 來比對）掃過整個
`src/` 沒有一個檔要改。**十二個 commit 各自單獨 `flutter analyze` 都是零 issue**，
在獨立 worktree 上逐一 checkout 驗證。

裝置層 11 個檔一個一個跑，**全綠**。其中 `stage_lines_flow_test` 7/7、1 分 47 秒
——soft-warp 那輪把它記成「掛住，但重跑之後 7/7，所以誠實的說法是『無法重現』」，
這一輪的結果與那個判斷一致，那條懸而未決的記錄可以再多一筆佐證。

## fix/origin-head-is-not-a-branch — 側邊欄那一列 `HEAD`，以及三個從來沒生效過的過濾器

使用者只說了一句：「remove HEAD that can be select in branches sidebar」。

側邊欄裡有一列叫 `HEAD`，而且**選得起來**。

### 沒活過原始碼的前提

> 以為使用者說的是「目前分支（HEAD）可以被複選」。

不是。`branch_selection_rules.dart` 的 `isBulkSelectable(ref) => !ref.isHead`
早就是唯一真相來源，而且每一個進入點都已經過濾：`sidebar_panel.dart` 的
`onSelect`、右鍵 collapse、Ctrl/Cmd+A（經 `selectableLeafNames`）、
select-all-gone、Shift+↑↓。這條規則是使用者自己裁定過的（見「側邊欄目前分支不再
置頂」那節），本輪一行都沒動。

真正被畫出來的是 `refs/remotes/origin/HEAD` —— git 給每個 remote 存的那個
symref，指向該 remote 的預設分支。它的 `shortName` 是 `origin/HEAD`，
`remoteBranchParts()` 取出的分支名就是 `HEAD`，沒有任何本機分支認領它，於是
`mergeLocalAndRemoteBranches()` 把它當成一條 remote-only 分支輸出，側邊欄照畫。

### 真正的缺陷：一個從來沒有被指派過的欄位

Dart 端**早就有三個過濾器**專門擋這個 ref，而且各自都有測試、都是綠的：

| 位置 | 條件 |
|---|---|
| `branch_tree_builder.dart:204` | `if (r.isSymbolic \|\| claimed.contains(r.fullName)) continue;` |
| `remote_counterpart.dart:23` | `if (remote.isSymbolic) continue;` |
| `graph_ref_chips.dart:75` | `if (r.kind == RefKind.remoteBranch && !r.isSymbolic)` |

三個全是死碼。因為：

```
$ grep -rn "isSymbolic *=" src/
src/core/git/RefStore.h:36:    bool isSymbolic = false;    ← 只有預設值
```

`RefStore::load()` 組的 `for-each-ref` 格式有八個欄位，**沒有 `%(symref)`**，
而 `info.isSymbolic` 在整個 `src/` 裡從來沒有被指派過。`JsonCodec.cpp:215`
再忠實地把這個永遠為 `false` 的布林送過 FFI，`ref_snapshot.dart:49` 忠實地讀回來。
整條鏈路每一環都「正確」，只是最上游從來沒有人填值。

修法是一行格式加一行指派，Dart **一個字都不用改**：

```cpp
format += kFieldSeparator;
format += "%(symref)";          // 第九個欄位，加在尾端
...
if (fields.size() > 8) {
    info.isSymbolic = !fields[8].empty();
}
```

加在**尾端**不是隨手決定的：sink 的邊界是 `fields.size() < 7` 就跳過、
`> 7` 才讀 `worktreepath`，插在中間會把既有每一個八欄位 fixture 的索引全部錯開。

### 這一輪最值得記的一件事：跨語言的「無法與程式碼相左的 fixture」

CLAUDE.md 已經記過五種「無法與程式碼相左的 fixture」。這是第九種，而且形狀是新的：
**fixture 手動設了一個 production 永遠不會設的欄位**。

`branch_tree_builder_test.dart:374` 這條測試叫
`excludes symbolic remote refs (e.g. origin/HEAD)`，`branch: 'HEAD'`，
斷言正確、邏輯正確、**從第一天就是綠的**。`remote_counterpart.dart` 那條
（`:477`，`a symbolic remote ref is never a counterpart`）也一樣。

它們錯的地方不在測試本身，而在**它們手寫 `isSymbolic: true`**。C++ 那側的測試
也全綠，因為 struct 的欄位確實存在、確實會被序列化。兩側各自都對，中間沒有人問
「這個欄位到底有沒有值」。

**跨語言邊界會讓兩側的測試同時失去偵測力**，而且兩邊的覆蓋率報表都看不出來。
唯一能分辨的只有真的 git 二進位檔，這就是本輪把測試放在
`GitIntegrationTest.cpp` 而不是往上一層放的原因。

### 三條測試，每條都做過變異驗證

1. **`RefStore.MarksARemoteHeadSymrefAsSymbolic`**（`ProcessRunnerTest.cpp`）——
   假回覆刻意掛在 `{"for-each-ref", "%(symref)"}` 上。`FakeProcessRunner` 是
   逐 arg 子字串比對（`FakeProcessRunner.cpp:16`），所以格式字串一旦不再要
   symref，就沒有規則命中，fake 退回空的預設回覆而變紅。
   **只餵九欄位假回覆再斷言解析的測試會漏掉這件事** —— 那正是本輪修的錯誤本身，
   只是換一層樓重演。
2. **`RealRepoTest.MarksTheRemotesHeadSymrefAsSymbolic`**（`GitIntegrationTest.cpp`）
   —— 真 git，`git remote set-head origin main` 造出真的 symref。刻意不用
   `--auto`：那要跟 bare repo 碰巧的預設分支一致，是本測試沒有立場的 git 版本細節。
3. **`CapiSessionTest.RefsJsonCarriesTheSymbolicFlagAcrossTheFfiBoundary`**
   （`SessionApiTest.cpp`）—— 補上最後一段。`refInfoJson()` 的欄位清單是手寫的，
   欄位被刪或改名時 C++ 與 Dart 兩側都不會紅，正是原缺陷的同型、低一層。
   斷言以 `fullName` 切出**單一 ref 物件**再比對，否則 `"isSymbolic":true`
   落在錯的 ref 上也會通過。

變異結果（`cp` 到 scratchpad 再改再 `cp` 回來，沒有用 `git checkout --`）：

| 變異 | 結果 |
|---|---|
| 格式字串拿掉 `%(symref)` | 459 條裡**恰好** 2 條紅（1、2） |
| `info.isSymbolic = false` | 同樣**恰好**那 2 條紅 |
| `jsonAppendBool(out, false)` | 145 條 capi 裡**恰好** 1 條紅（3） |

三次紅的範圍都窄，沒有牽連到別條。

### 連帶生效的一處，以及一個被實機打掉的預測

修好之後生效的是**兩個**過濾器，不是三個：

- **側邊欄那一列 `HEAD` 消失**（`branch_tree_builder.dart`）。← 使用者要的
- **`RemoteBranchIndex` 不再收 `origin/HEAD`**（`remote_counterpart.dart`）。

計畫裡原本寫「History 的 `origin/HEAD` chip 也會跟著消失」。**實機證明這是錯的**，
而且錯得很有代表性：`graph_ref_chips.dart:75` 那個 `!r.isSymbolic` 確實存在、
確實在檔案裡，但它濾的是 `remoteByFullName` 這張**用來把 local 的 upstream 反查回
remote ref 的查表**，不是 chip 清單。chip 清單來自同一函式下面的

```dart
final List<RefInfo> refsAtRow = refs.refs
    .where((RefInfo r) => r.target == targetOid)
    .toList(growable: false);
```

**完全沒有 symbolic 過濾**。所以 `origin/HEAD` 的 chip 修完之後照樣畫在 merge
commit 上，實機截圖看得一清二楚。

這是「**在正確的檔案、正確的行號上，讀出錯誤的結論**」：grep 找到了
`!r.isSymbolic`，行號沒錯、引用沒錯，錯的是把「這個旗標在這個檔案裡被用到」讀成
「這個檔案的輸出會因此改變」。同一份原始碼裡，一個旗標可以同時是某張查表的條件、
又完全不是渲染清單的條件。**只有跑起來看才會知道是哪一種**——三層測試全綠、
`grep` 全對，這個預測仍然是錯的。

`BranchOps.cpp:78-87` 用 `/HEAD` 字尾比對擋掉 `origin/HEAD` 的那段**保留不動**：
它讀的是 `for-each-ref --contains` 的原始輸出，不經過 `RefInfo`，是另一條資料路徑。
那段註解其實老早就把這個 ref 的性質寫得很清楚 —— 這個 codebase 一直知道
`origin/HEAD` 是什麼，只是知識停在一個 operation 裡，沒有進到 ref 快照本身。

### 一個順手撿到的既有陷阱

`app_flutter/build/native/libgbm_capi.dylib` 在動手前是 **8 月 28 日**的，
比本輪的 capi 改動早三天。CLAUDE.md 記過這件事，這次又碰到一次：實機驗收前
`app_flutter/scripts/build_capi.sh` 不是可選步驟。

### 這輪沒做

- **`RefInfo.isSymbolic` 的 C++ 讀取端**：core 自己沒有任何地方讀這個旗標，
  本輪也沒有替它找用途。它存在的唯一理由就是給 Dart 過濾用。
- **History 那顆 `origin/HEAD` chip：使用者裁定保留。** 實機發現它還在（見上），
  是同一個 ref 被當成分支的同一族缺陷，修法是 `refsAtRow` 加一個 `!r.isSymbolic`。
  提出給使用者裁定而不自己動手，是因為那是他沒有指名的另一個介面，這個 repo
  對「未經裁定就改介面」有前科。**裁定是保留**：`isSymbolic` 在本輪之前恆為
  `false`，那顆 chip 從第一天就在，留著是零回歸，拿掉反而是新的行為改變。
  這不是實作者的減量，是一條裁定過的保留；CLAUDE.md 那條條目已同步改成
  user-ratified，不再寫「待裁定」。

### 驗證

`gbm_core_tests` 459 條：457 綠、2 個既有的 LFS skip、0 紅。
`gbm_capi_tests` 145 條全綠。
`flutter analyze` 零 issue、`flutter test` **2355 綠 1 skip**（`lib/` 沒有改動，
數字與修改前一致）。
clang-format 用 repo 自己的 `.clang-format` 比對過改動檔：`RefStore.cpp`
與 `ProcessRunnerTest.cpp` 逐位元組乾淨；`GitIntegrationTest.cpp` 與
`SessionApiTest.cpp` 各有幾個 hunk，逐一與**改動前的同一份檔案**比對，確認
全是本機 v23 與 CI pin 的 v18 之間既有的落差，沒有一個落在本輪新增的行上
（`SessionApiTest.cpp` 原本有一個落在新測試裡，是 `ColumnLimit: 100` 造成的
lambda 收合，來自 repo 自己的設定，已照做）。

**實機驗收本輪自己跑了**，而且是它推翻了上面那個 chip 預測。`flutter run -d macos
--release` 開這個 repo（它自己就有 `refs/remotes/origin/HEAD`），截圖確認側邊欄
`BRANCHES` 底下只剩 `backup`、`fix/`、`main`，那一列 `HEAD` 不見了。

過程中踩到 CLAUDE.md 已經記過的那個陷阱的一個新變形：**第一張截圖是錯的機器**。
機器上同時跑著兩個 `gbm_flutter` —— `/Applications/gbm_flutter.app`（使用者自己
安裝的，8:06PM 起，dylib 裡 `strings | grep symref` 是 0）與剛建好的 Release
（8:35PM 起，grep 是 1）。`osascript` 的 `first process whose name contains
"gbm_flutter"` 挑中了前者，於是截出一張「修了等於沒修」的畫面，差一點就把一個
正確的修正判成失敗。**用 `unix id` 指名 PID，不要用 name 挑 process**；
`ps aux | grep gbm_flutter` 是動手前該先跑的那一行。既有那條「stale
`gbm_flutter` process 看起來就像壞掉的測試」講的是裝置層，這次證明它在**人工實機
驗收**上同樣成立，而且更難察覺——畫面長得完全合理。
