# Code review — spec-conformance audit (2026-08)

Whole-codebase architectural review requested alongside the spec-conformance
audit (`docs/reports/spec-conformance-matrix.md`), not a diff review — the
issues below are pre-existing, not introduced by this branch's own commits
(which only add reports and tools). Run via `/ecc:code-review` (Local Review
Mode adapted: target list supplied explicitly instead of `git diff
--name-only HEAD`, since the branch's own diff is just docs/tooling and
wouldn't surface these).

Severity levels follow the project's own convention (CRITICAL/HIGH/MEDIUM/
LOW, per `~/.claude/rules/ecc/common/code-review.md`).

---

## HIGH

### H1. Context-menu catalog (`gbm_context_menus.dart`) is unreferenced by production code

**File**: `lib/features/context_menus/gbm_context_menus.dart`

The file fully specifies all 11 spec context-menu groups (05-A…05-K) with
labels matching the design spec verbatim, and its own doc comment (lines
1-16) describes it as the canonical structure. But grepping `lib/` for
imports of this file finds none — only `test/` reads it (and only for
05-D/05-H/05-I/05-J, which have dedicated `*_menu_items.dart` files a
render site actually calls). Every other render site
(`branch_tree_item.dart`, `commit_row.dart`, `changed_file_row.dart`,
`diff_line.dart`, `changed_files_panel.dart`) hand-writes its own item
list with no reference back to this catalog.

**Failure scenario**: a developer edits one of those render sites to add,
remove, or reword a menu item. Nothing fails — no test, no lint, no type
error — because nothing checks the render site against the catalog except
the four groups that happen to have a dedicated file. The catalog's own
claim to be authoritative silently becomes false the moment any of the
other 7 render sites changes. This is precisely how 7 of 11 groups
independently drifted from the spec (documented in
`spec-conformance-matrix.md`'s Page 05 section) without any test noticing.

**Recommendation**: either (a) make the 7 non-conforming render sites
build their `GbmMenuItem` list from `gbmContextMenuGroups[target].items`
the way 05-D/H/I/J's dedicated files do — turning "parity by test" into
"parity by construction" — or (b) if some divergence is permanent and
intentional (05-A's session-less reduction, 05-C's gone-row reduction),
encode that reduction as a documented, tested transform of the catalog
rather than a fully independent hand-written list. Either way, the four
existing `*_menu_items.dart` files are the template to follow — they're
the only groups this audit found zero drift in.

### H2. Commit/Amend buttons don't react live to typing — only to an unrelated rebuild

**File**: `lib/features/working_copy/working_copy_view.dart:59,65-68,471-474`

*Found while writing `test/integration/workspace_states_table_test.dart`'s
"Commit" STATES row coverage, not from static reading alone — the test
failure is the evidence.*

`canCommit` (line 471-474) reads `_summaryController.text` directly, and
`_summaryController` is a plain `late TextEditingController` seeded once
in `initState` (line 65-68) from `ref.read(workingCopyDraftProvider(...))`
— a one-time read, not a watch. `CommitMessageBox`'s `onSummaryChanged`
callback (wired at line 487) writes typed text back into that same
provider via `ref.read(...).updateSummary(text)` — again a write, not a
watch. Nothing in `_WorkingCopyViewState` calls `setState` (or
`ref.watch`s something that changes) in response to
`_summaryController`'s own text changing (confirmed by grep — the only
`setState`/`addListener` calls in the file are for the diff-scroll
controller and the side-by-side toggle, unrelated to the summary field).

**Failure scenario**: a user opens Working Copy, stages a file, types a
commit summary, and the Commit button stays visibly disabled — because
`_buildCommitBox`'s `canCommit` was computed during the *last* actual
`build()` call, which happened before any character was typed, and
nothing after that triggers `WorkingCopyView` to rebuild. The button only
catches up whenever some *unrelated* rebuild fires (e.g. a background
`repoSessionProvider` update, or navigating away and back). This audit's
own test proves the underlying gate logic (`canCommit`) is correct in
isolation — pre-seeding the draft provider *before* the widget mounts
produces an enabled button immediately — the defect is specifically the
missing "text changed -> rebuild" wire-up, not the enable/disable
condition itself.

**Recommendation**: give `_WorkingCopyViewState` a listener on
`_summaryController` that calls `setState(() {})` (mirroring the pattern
already used for `_diffScrollController` at line 72), or drive
`_buildCommitBox` off `ref.watch(workingCopyDraftProvider(...)).summary`
instead of the raw controller so Riverpod's own rebuild-on-change does
the work. Either fix is small and localized to this one file.

---

## MEDIUM

### M1. `_MoreMenu` in `tab_row.dart` has no architectural boundary and duplicates two menu-bar entries

**File**: `lib/features/workspace/widgets/tab_row.dart:167-301`

`_MoreMenu` is an 18-item overflow menu, and `TabRow.build()` additionally
renders 3 standalone buttons (Merge…/Cherry-pick…/Reset…) not named in
the tab row's own spec definition. The file's own doc comment (line
164-166) explains the growth pattern candidly: "keeps the tab row from
growing a new inline TextButton per milestone" — i.e., every new
milestone's feature gets appended here by design, with no upper bound and
no grouping/categorization within the 18 items (they're a flat list, not
sectioned by concern — stash vs. tag vs. worktree vs. history-inspection
vs. app-settings are all interleaved).

Two items are outright duplicate entry points: `Repository Settings…`
(line 289) and `Preferences…` (line 295) already have menu-bar homes
(Repository → Settings…, File → Preferences… per `gbm_menu_model.dart`).
A user — or a future contributor wiring a new dialog — now has two places
that both claim to be *the* way to reach these, with no single source of
truth for "how do I open Preferences."

This is also the direct cause of the largest finding in the spec-
conformance audit (F-A): every one of these 18 items' underlying feature
is legitimate and shipped (`docs/FEATURES.md`), but this menu is not a
spec-sanctioned entry surface (neither a page-05 context menu nor a
page-04 menu-bar menu).

**Recommendation**: not a request to remove functionality — these are
real, working features. But the growth pattern needs a boundary before a
19th milestone adds a 19th item to the same flat list. Options worth
weighing (decision deferred to the follow-up fix session per this audit's
scope): fold groupable items into an existing menu-bar menu (e.g. tag/
worktree/remote management under Repository or a new menu), or section
`_MoreMenu` itself so it stops growing as one undifferentiated list. At
minimum, drop the two duplicate entries (`Repository Settings…`,
`Preferences…`) — they add code and a second decision point for zero
benefit, since both are already one click away on the menu bar.

### M2. Stale doc comment claims 05-C is "not yet wired" — it is

**File**: `lib/features/context_menus/gbm_context_menus.dart:23-27`

```dart
/// Right-click a remote-only or "gone" branch row in the sidebar.
/// Not yet wired; will need to distinguish remote-only rows from gone.
/// Per spec note: for a "gone" row specifically, only "Prune this ref"
/// and "Copy branch name" stay enabled; others disabled.
remoteOnlyOrGoneBranch, // 05-C
```

`branch_tree_item.dart` already implements exactly this distinction
(`_buildGoneMenuItems()`), documented as fixed in `CLAUDE.md`'s "Known
gaps" section and confirmed working by this audit's spec-conformance pass
(05-C: 符合, verified). The comment here was never updated when that work
landed. Low blast radius on its own, but it sits in the same file as H1 —
a contributor who trusts this file's comments over the actual render site
(which is exactly the failure mode H1 describes) would either
re-implement already-working code or wrongly distrust a correct
implementation. Fix alongside H1, or as a standalone one-line comment
edit if H1 isn't tackled this cycle.

### M3. `_MoreMenu` labels use Title Case against the project's own documented convention

**File**: `lib/features/workspace/widgets/tab_row.dart:209-296`

`gbmMenus`' own doc comment in `gbm_menu_model.dart:18-21` states: "labels
verbatim from the spec — sentence case throughout, including button
labels." `gbmMenus` itself follows this correctly (`New repository…`,
`Find in history`). `_MoreMenu`'s 18 items do not: `Stash Changes…`,
`Manage Stashes…`, `Create Tag…`, `Manage Worktrees…`, `Operation Log…`,
`Interactive Rebase…`, `Clean Untracked…`, etc. are all Title Case. This
menu was added later and wasn't held to the same label-casing rule as the
menu bar it visually sits next to. Mechanical fix (relabel to sentence
case) once M1's structural question is resolved — no point relabeling a
menu that might get restructured or partially removed.

---

## LOW / INFO — leads checked, findings updated

### L1. `commit_row.dart` skeleton-width jank (CLAUDE.md "Known gaps") — checked, no defect found

**File**: `lib/features/history_graph/widgets/commit_row.dart:174,188,205,267-271`

CLAUDE.md lists this as an "unconfirmed lead." Read in full: the subject/
author skeleton placeholders (`_SkeletonBlock`) use fixed widths (220,
80) inside their real columns' containers (`Expanded`, `SizedBox(width:
110)`), and the widget's own doc comment (lines 267-271) explains this is
deliberately a static, non-shimmer placeholder — `CommitMeta` batches
resolve within one `cat-file` round trip per viewport (typically visible
for a single frame or two), so an `AnimationController` for a shimmer
effect was judged not worth the churn. No layout-shift pattern was found
in this reading (skeleton and real content share the same parent
constraints, so there's no width jump between the two states). Recommend
downgrading this from "unconfirmed lead" to "checked, no defect found" in
CLAUDE.md rather than leaving it open (folded into Phase 5 below) — if a
real jank exists, it wasn't reproducible from a static code read and would
need an actual running-app repro to pin down further, which is out of
this review's scope.

### L2. Sidebar-toggle widget test (CLAUDE.md "Known gaps") — resolved, not missing

**Files**: `test/integration/workspace_intent_dispatch_parity_test.dart:100`,
`test/features/workspace/menu_bar_row_test.dart:145`,
`test/integration/workspace_focus_residue_test.dart:77`

CLAUDE.md lists "missing widget test for sidebar-toggle state" as an
unconfirmed lead. It's covered: `workspace_intent_dispatch_parity_test.dart`
has an integration test ("Ctrl+B (Toggle sidebar) actually hides
SidebarPanel") that specifically exists to catch the class of dispatch-
path bug CLAUDE.md's "Action / Intent layer" section warns about, plus a
widget-tier test in `menu_bar_row_test.dart` and a residue check in
`workspace_focus_residue_test.dart`. This gap should be removed from
CLAUDE.md's "Known gaps" as stale (folded into Phase 5).

### L3. `operationLog` cap of 500 vs. spec's 2,000 — deliberate, not a code defect

**File**: `lib/data/repositories/repo_session_repository.dart:239-243`

Investigated per this review's scope (item 6 of the audit brief). The cap
is intentional and well-reasoned: the doc comment explicitly states it
mirrors `OperationRunner.cpp`'s own `kMaxUndoEntries` cap on the native
side, for the stated reason that "a live panel fed one record per `git`
invocation needs a bound too." This is a real spec-vs-implementation
*number* mismatch (already captured correctly in
`spec-conformance-matrix.md`'s Page 10 section as 措辭不符/缺少), but it
is not a code-quality finding — the code is doing something deliberate
and defensible; if the number changes, it should change alongside (or
with an explicit note about no longer mirroring) `OperationRunner.cpp`'s
own cap, not in isolation.

---

## Summary

| Severity | Count | Items |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 2 | H1 (dead catalog file, root cause of 7/11 context-menu drift), H2 (Commit/Amend don't react live to typing -- found while writing Phase 3's STATES-table test) |
| MEDIUM | 3 | M1 (`_MoreMenu` unbounded growth + 2 duplicate entries), M2 (stale doc comment), M3 (label casing) |
| LOW/INFO | 3 | L1–L3, all "checked, not a defect" or "spec-mismatch not code-defect" — recorded so CLAUDE.md's Known Gaps can be updated accurately in Phase 5 |

No CRITICAL security or correctness issues found. The dominant pattern
across this review is **architectural drift from missing enforcement**,
not unsafe code: a correct, spec-matching catalog exists (H1) but nothing
makes render sites conform to it; a correct label-casing rule exists (M3)
but nothing enforces it outside the menu bar it was written for. Both are
naturally fixed the same way — by making the existing correct artifact
the actual source of truth, rather than writing new logic — which keeps
any follow-up fix small and low-risk.

No decision (BLOCK/APPROVE) is rendered here, per this audit's scope:
findings are reported for a separate fix session, not applied in this
branch.
