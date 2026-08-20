# Spec ↔ implementation conformance matrix

Audits every action, menu, dialog, and state rule against
`docs/claude-design-demo/Flutter Desktop Spec (standalone).html` (12 pages),
decoded via `tools/extract_design_spec.py`. Scope decision from this audit's
kickoff: functionality beyond the spec is acceptable **only if its entry
point is a context menu or the menu bar** — any other entry surface (a
toolbar button, an overflow menu not in the spec, etc.) is a conformance
gap even if the underlying feature is legitimate and already shipped per
`docs/FEATURES.md`.

Verdict column: `符合` (matches) / `缺少` (missing) / `多出` (extra) /
`措辭不符` (wording mismatch).
Classification column (for gaps only): **(i)** wireable now — backing capi
or Dart service already exists; **(ii)** needs new capi surface; **(iii)**
already-documented absence (see CLAUDE.md's Known gaps).

This report is descriptive only — no fixes are applied here. See
`docs/reports/code-review-2026-08.md` for the accompanying code review.

---

## Page 04 — Menu bar & shortcuts (`gbm_menu_model.dart`, `gbm_shortcuts.dart`)

**Menu bar (`gbmMenus`, 7 menus, 52 items):** matches spec's MENUS table
verbatim across all 7 menus (File 8 / Edit 8 / View 11 / Repository 10 /
Branch 7 / Remote 4 / Help 4). The one addition —
`repositoryStageSelectedLines` ("Stage selected lines") — is not in the
page-04 MENUS table, but the spec's own page-03 prose (SCOPES row 7 / P3
item 5) names `Repository → Stage selected lines`, so this is the spec's
own table missing a row it documents elsewhere, not an app-side addition.
**符合** (spec-internal inconsistency, code sides with the prose).

**Keyboard shortcuts (`gbmActionShortcuts()`, 35/52 ids bound):**

| Spec item | Verdict | Evidence | Reason |
|---|---|---|---|
| Edit → Find in files, `Ctrl/Cmd+Shift+F` | 缺少 (spec-internal collision) | `gbm_shortcuts.dart` has no `editFindInFiles` entry | Spec's own MENUS table assigns `Ctrl/Cmd+Shift+F` to BOTH "Find in files" and "Repository → Fetch". Code kept `repositoryFetch`'s binding and left `editFindInFiles` unbound. Classification: spec defect, not a code bug — but flag for spec authors. |
| Branch → Stash changes, `Ctrl/Cmd+Shift+T` | 缺少 (spec-internal collision) | `gbm_shortcuts.dart` has no `branchStashChanges` entry | Same pattern: spec's MENUS table assigns `Ctrl/Cmd+Shift+T` to BOTH "View → File list as tree" and "Branch → Stash changes". Code kept `viewFileListAsTree`. |
| Branch → Rename current branch…, `F2` (from DIALOGS table + CTX 05-B) | **缺少 (real gap)** | `gbm_shortcuts.dart` has no `branchRenameCurrentBranch` entry; `F2` is otherwise unused — no collision excuse | Compounds with the missing dialog route below (page 06). This is the one shortcut gap that is NOT explained by a spec-internal collision. Classification **(i)** — action id and presumably a rename capi call already exist; only wiring is missing. |
| File → Exit, `Alt+F4 / Cmd+Q` | 符合 (by design) | `gbm_shortcuts.dart:103-104` doc comment; no `fileExit` entry | Correctly left out of the app's `Shortcuts`/`Actions` binding — these are OS-native window-close accelerators, not something the Flutter shortcut layer should intercept. |
| Context-menu-scoped keys (Space/F2/Ctrl+Enter for file actions; Alt+Left/Right/↓, Ctrl/Cmd+↑/↓/Z for the conflict window) | 待查 | — | These are architecturally separate from the global 52-id map (bound locally at the widget that owns that context). Verification folded into pages 03/08 below. |

---

## Page 05 — Context menus (11 targets, `gbm_context_menus.dart` + render sites)

**Architectural finding (root cause of drift, see also code review report):**
`lib/features/context_menus/gbm_context_menus.dart` declares all 11 spec
groups (05-A…05-K) with labels that match the spec verbatim, but **no file
under `lib/` imports it** — only `test/` reads it. Every render site
hand-writes its own item list independently, so the catalog and the actual
UI have drifted apart. Only 05-D/05-H/05-I/05-J have a dedicated
`*_menu_items.dart` file that a render site actually calls.

**Update (Tier 1, branch `fix/tier-1-spec-conformance-gaps`, issues
#51–#53).** 05-F and 05-G now have their own `*_menu_items.dart` too
(`working_copy_file_menu_items.dart`, `diff_line_menu_items.dart`), so six
of eleven groups follow the reference pattern and `context_menu_parity_test.dart`
checks both against the catalog directly with no `skip`. 05-K's two
(i)-classified items were wired but its parity assertion stays skipped —
see its row. Only 05-B and 05-E remain fully hand-written and drifted.

Two premises in the rows below were **wrong** and are corrected in place
rather than silently edited away, because both changed where the fix had to
go: 05-F pointed at a widget nothing in `lib/` ever built, and 05-G's
"only Discard is missing" undercounted the drift. Details in each row.

| Group | Verdict | Evidence | Detail |
|---|---|---|---|
| 05-A Repository | 符合 (deliberate reduction) + 1 minor 多出 | `repo_switcher_popover.dart:740-877` `RepoSwitcherRow._openContextMenu()` | Omits Fetch/Pull/Push vs. the catalog's 7 items — documented in the catalog's own comment: a repo row in the switcher list has no open session to act on. Renders: Open / Open in file manager / Open in terminal / Settings… / [separator] / Remove from list (5 items). The leading `Open` item is not in spec's 05-A list at all — low-severity addition (mirrors the row's own double-click action, a reasonable convenience), noted for completeness rather than flagged as something to remove. |
| 05-B Local branch | **缺少** | `branch_tree_item.dart:321-387` `_buildMenuItems()` | Renders: Checkout / New branch from here / Rename branch / Merge into current branch / Copy branch name / Delete branch (6 items). Missing vs. spec's 8: `Rebase current onto here`, `Compare with…`. Also wording: `Rename branch` vs. spec `Rename…`, `Merge into current branch` vs. spec `Merge into current`. The file's own doc comment (lines 321-327) explains why: both omissions are deliberate, not oversights — "no per-branch entry point exists yet; a targeted rebase/compare would need the same UI as its repository-level peer, not yet surfaced." Classification **(i) with a prerequisite** — `gbm_rebase_start`/`gbm_request_compare_refs` exist in capi, but there's no per-branch rebase/compare UI to route to yet (same shape as the 05-E correction below: capi existing ≠ Dart-side wiring existing). |
| 05-C Remote-only / gone branch | 符合 (verify) | `branch_tree_item.dart` | CLAUDE.md's "Known gaps" section documents this as fixed (`_buildGoneMenuItems()`), matching spec's 05-C note that a gone row keeps only Prune+Copy. The *catalog file's* doc comment still says "not yet wired" — that comment is stale, not the implementation; flagged for correction in Phase 5. |
| 05-D Tag | 符合 | `tag_menu_items.dart` | Labels and order match spec exactly (5 items). Reference-quality implementation. |
| 05-E Commit | **缺少** | `commit_row.dart:226-259` menu build | Renders: Checkout this commit / Cherry-pick / Create branch here… / Copy SHA / Revert commit (5 items, no submenu). Missing vs. spec's 7 top-level + "More actions" submenu of 5: `Merge into current`, `Compare with…`, and the ENTIRE submenu (`Rebase onto here`, `Reset branch to here…`, `Revert commit`, `Export as patch…`, `Compare with working copy`). Note spec keeps `Revert commit` inside the submenu; code promotes it to top level. **Classification correction**: `commit_row.dart`'s own doc comment (lines 226-229) gives the real reason for each omission, and it's not uniformly "(i) trivial wiring" as first assumed from capi existing alone — `Merge into current` is omitted because `mergeBranch` takes a branch **name**, not a commit oid (needs either an API change or a name-resolution step, not just a UI hookup); `Compare items` are explicitly deferred as "M6" (a planned milestone, not an oversight); `rebase/reset` are noted "destructive, not wired" — meaning the *Dart-side* plumbing, not just the menu item, doesn't exist yet, so capi having the C function is necessary but not sufficient. Revised classification: `Compare with…` stays **(i)** (capi + Dart service both proven elsewhere); `Merge into current` and `Rebase/Reset` are **(i) with extra work** (need a name-resolution step or Dart-side wiring first, not pure UI); nothing here is **(ii)**. This is exactly the kind of per-site nuance the audit plan flagged as necessary to check before trusting a grep-derived classification. |
| 05-F Working copy file | ~~缺少~~ → **符合** (Tier 1 / #51) | `working_copy_view.dart:576` `_openContextMenu()` → `working_copy/widgets/working_copy_file_menu_items.dart` | **This row audited the wrong file — twice.** The first pass grepped `label: '...'` and so missed ternary-labelled items; the "corrected" second pass fixed that but still pointed at `changed_file_row.dart`, which **no file under `lib/` ever constructed**. `WorkingCopyBoard` (commit `39d6303`) replaced that row widget and commit `5581538` moved the 05-F menu into `working_copy_view.dart`; `ChangedFileRow` had been orphaned since, referenced only by `test/`. So the live menu already had `Open terminal here` and full multi-select pluralization, and the real gap was two items, not three. **Fixed**: `Open file` and `Show in file manager` added (`DesktopLauncher.openFile()` is new; `openInFileManager()` already existed, and both now normalize `/`→`\` on Windows, without which `explorer.exe /select,` silently opens Documents instead of revealing). The orphaned widget and its test file were deleted in their own commit. **Deliberate reduction**: `Blame…`/`File History…`/`Line History…` were dropped from this menu — they are beyond-spec, and 6 spec items + 3 extras is 9, over `showGbmContextMenu`'s asserted 8-item cap (spec page 05's own "最多 8 項"); `GbmMenuItem.submenu`'s flyout does not render yet, so nesting them was not available. All three stay reachable from `tab_row.dart`'s overflow menu, minus the pre-filled path. |
| 05-G Diff line | ~~缺少~~ → **符合** (Tier 1 / #52) | `diff_line.dart:140` `_showContextMenu()` → `diff/widgets/diff_line_menu_items.dart` | **The gap was larger than the corrected second pass reported.** Reading spec's own 05-G block verbatim (`{ label: 'Stage 12 lines' }, { 'Stage hunk' }, { 'Unstage hunk' }, { 'Copy lines' }, { sep }, { 'Discard 12 lines…', danger }`) shows four differences, not one: the missing `Discard`, plus `Stage line` vs `Stage`/`Stage N lines`, `Copy line` vs `Copy lines`, and spec listing **both** hunk directions as separate entries where the code ternaried between them. **Fixed, all four.** Both hunk items now always render with the inapplicable direction disabled (`enabled: false` *and* `onTap: null` — `enabled` alone is a visual signal only, see `gbm_menu.dart`); the count comes from `_DiffHunkSection`'s checkbox selection using 05-F's own "right-click inside the selection keeps the batch" rule. `Discard` needed a **new capi** — `gbm_stage_lines`/`gbm_unstage_lines` are `git apply --cached` (index only), so `gbm_discard_lines` was added (`git apply --reverse` without `--cached`, patch built with `unstaging=true` since that flag means "will be reverse-applied, check the new side"). It is offered only on the unstaged side and always routes through the discard-changes dialog's new line mode, never straight to the controller. **Follow-up defect, found by writing the missing coverage rather than by reading the diff**: that new line mode reaches the dialog through a URL, and the router's inline parsing cross-nulled `hunk` against `line`, so a half-parsed line selection silently degraded to *whole-file* discard behind the same danger button. Parsing moved to `DiscardChangesRequest.fromQuery` (`features/dialogs/discard_changes/discard_changes_request.dart`); an unhonourable line request is now `isMalformed` and the dialog offers `Close` and no destructive button. |
| 05-H Stash entry | 符合 | `stash_menu_items.dart` | Labels and order match spec exactly (6 items). Reference-quality. |
| 05-I Conflict hunk | 符合 | `conflict_hunk_menu_items.dart` | Labels and order match spec exactly (5 items). Reference-quality. |
| 05-J Branch folder | 符合 | `branch_folder_menu_items.dart` | Matches spec's 4 items (aside from a possible deliberate omission — see pending device/widget-tier note in Phase 3). |
| 05-K Commit file | **部分修復** (Tier 1 / #53) | `changed_files_panel.dart` menu build | **Fixed**: the two (i)-classified top-level items are wired — `Compare with working copy` (opens a Compare tab via `compareTabsProvider.open(left: <oid>)` with a null `right`, then `context.go`, mirroring `sidebar_panel.dart`'s `_compareStash`; `push` would stack the tab over History rather than switch to it) and `Open terminal here` (the repository work dir, like 05-A/05-F — a historical commit's file has no directory of its own). **Still missing**: `Open file at this revision` / `Save this revision as…` are **(ii)** — `gbm_capi.h` still has no blob-read entry point — and `Restore and stage` / `Export as patch…` sit in the "More actions" submenu, whose flyout `gbm_menu.dart` does not render at all, so they would be unreachable even if wired. Both are Tier 4. The parity test's 05-K group therefore stays `skip: true`; regression coverage for the two new items lives in `changed_files_panel_test.dart` and `test/integration/history_commit_file_menu_test.dart` instead. |

**Net**: after Tier 1, 6 of 11 groups (05-D/F/G/H/I/J) are
reference-quality — each a pure `*_menu_items.dart` function checked against
the catalog with no `skip` — and remain the template for the rest. 05-K is
partially fixed (its two wireable items landed; the other four need capi or
a submenu flyout). 05-B and 05-E are the only fully-unfixed groups left.
The original text follows: 4 of 11 groups (05-D/H/I/J) are reference-quality
and can be used as the template for fixing the other 7. 05-A and 05-C's apparent
"gaps" are deliberate, documented reductions — not gaps. **Correction
note**: the first pass of this audit derived 05-F and 05-G's findings
from a `label: '...'` grep, which is blind to menu items whose label is
a ternary expression (`staged ? 'Unstage line' : 'Stage line'`) rather
than a literal string — this under-counted both menus significantly (see
the "corrected" markers in their rows above). 05-B, 05-E, and 05-K were
already read in full in the first pass and needed no correction beyond
adding the "why" context their own doc comments supplied. The lesson:
grep is a fine way to generate a *candidate* list, but every render site
needs a full read before its row is trusted — exactly the risk this
audit's plan flagged going in.

---

## Page 06 — Dialogs (16 entries in spec's DIALOGS table)

| Spec dialog | Verdict | Evidence | Reason |
|---|---|---|---|
| Switch repository | 符合 | `repo_switcher_popover.dart` | Correctly a popover, not a modal dialog — matches spec's own note that this is deliberately lightweight, not one of the 33 modal dialog routes. |
| Clone repository | 符合 (documented gap, iii) | — | Already recorded in CLAUDE.md: no `git init`/clone capi entry point exists; File → Clone repository… stays disabled by design. |
| New branch | 符合 | `route_paths.dart: newBranchDialog` | Route exists. |
| **Rename branch** | **缺少 (real gap)** | `route_paths.dart` has no rename-branch route among its ~36 dialog constants | Spec's DIALOGS table names this dialog explicitly (from 05-B → Rename…, key F2). `GbmActionId.branchRenameCurrentBranch` exists as an action id but has no dialog to open and no shortcut (see page 04 above) — the whole feature has zero conforming entry points despite the enum id existing. Classification **(i)** — `gbm_branch_rename` exists in capi; only the Flutter dialog + route are missing. |
| Delete branch | 符合 | `deleteBranchDialog` | — |
| Checkout | 符合 | `checkoutDialog` | — |
| Merge | 符合 | `mergeDialog` | — |
| Rebase | 符合 | `rebaseOntoDialog` | — |
| Stash changes | 符合 | `stashChangesDialog` | — |
| Restore file to this state | 符合 | `restoreFileDialog` | — |
| Discard changes | 符合 | `discardChangesDialog` | — |
| Force push | 符合 | `forcePushDialog` | — |
| Delete remote branch | 符合 | `deleteRemoteBranchDialog` | — |
| Prune remote branches | 符合 | `pruneRemoteBranchesDialog` | — |
| Repository settings | 符合 | `repositorySettingsDialog` | — |
| Preferences | 符合 | `preferencesDialog` | — |

**14/16 present, 1 real gap (Rename branch), 1 documented absence (Clone).**

### Dialogs beyond the spec's 16 — entry-point audit

Per this audit's scope rule, the question isn't whether these dialogs
should exist (they're documented, shipped `docs/FEATURES.md` scope) but
whether their **entry point** is a context menu or the menu bar.

- `aboutDialog`, `keyboardShortcutsDialog` — reached via Help menu (page
  04's Help section). **符合** — legitimate menu-bar entries, just not
  listed in DIALOGS because the spec documents them via the Help menu
  itself instead.
- `manageBaseFoldersDialog` — see the Preferences page (11) section below
  for whether this duplicates the "Repository sources" tab.
- `credentialDialog`, `checkoutRecoveryDialog`, `deleteBranchRecoveryDialog`
  — auto-triggered recovery/credential flows per CLAUDE.md's "Credential
  and recovery flows" section, not user-initiated navigation. Out of scope
  for the context-menu/menu-bar entry-point rule (they have no menu entry
  by design — they interrupt).
- `manageStashesDialog`, `manageWorktreesDialog`, `manageRemotesDialog`,
  `createTagDialog`, `operationLogDialog`, `blameDialog`, `fileHistoryDialog`,
  `lineHistoryDialog`, `reflogDialog`, `undoLastDialog`,
  `interactiveRebaseDialog`, `manageSubmodulesDialog`, `bisectDialog`,
  `manageLfsDialog`, `patchesDialog`, `cleanUntrackedDialog` (16 dialogs) —
  **多出，入口面不合規**. Their *sole* entry point is
  `lib/features/workspace/widgets/tab_row.dart`'s `_MoreMenu`, an 18-item
  overflow menu attached to the tab row — not a context menu target from
  page 05, and not one of the 7 menu-bar menus from page 04. See "Page 02
  item 13" finding for the full detail; recorded once here to avoid
  duplicating the list.
  - Two of the 18 items (`Repository Settings…`, `Preferences…`) are
    **duplicate entry points** — both already exist on the menu bar
    (Repository → Settings…, File → Preferences…) per page 04.
  - Labels use Title Case (`Stash Changes…`) against the project's own
    documented sentence-case convention (`gbm_menu_model.dart`'s doc
    comment: "Sentence case throughout, including button labels").

---

## Architectural findings that span multiple pages

### F-A. `tab_row.dart`'s `_MoreMenu` is a third, spec-unsanctioned entry surface

The spec's page-02 item 13 / page-03 item 9 describe the tab row as: two
persistent tabs (History / Working Copy) + an additional closable Compare
tab when opened — nothing else. The actual `TabRow` widget also renders:

- An 18-item overflow menu (`_MoreMenu`) that is the *only* entry point for
  every dialog beyond the spec's DIALOGS table (see page 06 above).
- Three standalone buttons: Merge…, Cherry-pick…, Reset… — none named in
  the spec's tab-row item, though `Merge`/`Cherry-pick`/`Reset` do have
  legitimate menu-bar (`branchMergeIntoCurrent`) or context-menu (05-E)
  homes already.

Per this audit's scope rule, this is the single largest source of
"functionality beyond spec, but through a non-conforming entry point."

### F-B. Log panel has two competing implementations

Spec page 10 defines Log as a bottom drawer (`main.log` splitter,
draggable height, zero space when collapsed). The code has both
`lib/features/log_drawer/` (matches the spec) and a separate
`operationLogDialog` modal route, reachable only from `_MoreMenu`. Same
concept, two surfaces — full detail pending the page-10 discovery pass
below.

---

## Page 01 — Platform & window chrome

| Item | Verdict | Evidence | Reason |
|---|---|---|---|
| macOS: menu bar in system tray only | 符合 | `platform_menu_bar_host.dart:58`, `workspace_screen.dart:249` | `PlatformMenuBarHost` builds a native `PlatformMenuBar`; `MenuBarRow` is conditionally hidden via `if (!isMacOS)`. |
| Windows/Linux: in-window menu bar, all 7 spec menus | 符合 | `workspace_screen.dart:249-265`, `gbm_menu_model.dart:98-280` | `MenuBarRow` renders on Windows/Linux with all 7 menus. |
| Windows/Linux: custom title bar (minimize/maximize/close, lucide icons) | ~~**缺少**~~ → **符合 (by design)** (Tier 5 / #60) | Spec page 01's own prose, quoted below; `pubspec.yaml` correctly has no `bitsdojo_window`/`window_manager`/`window_size` dependency | **This row was wrong, and wrong in the direction that would have cost the most work.** It read the page-01 mockup as a requirement to *draw* a title bar; the spec says the opposite. Page 01's intent line: 「三平台統一樣式，只有 menu bar 位置與**標題列跟隨系統**」. Its 「依平台不同的部分（僅三項）」 panel, item 2: 「**標題列按鈕位置與號誌燈樣式沿用系統原生**」— and the other two items in that same three-item list (macOS `PlatformMenuBar`, the system file picker) unambiguously mean "use the OS's own facility", so item 2 is the same sentence shape. The facing 「統一的部分」 panel scopes Flutter self-drawing to 「視窗**內**所有內容」 — the title bar is deliberately placed in the *other* list. The three mockup cards illustrate what each OS's **native** decoration looks like: the macOS card draws red/amber/green traffic lights with exactly the same `{{ ic… }}` placeholder technique the Windows/Linux cards use for minimize/square/close, and nobody reads the macOS card as "hand-draw the traffic lights". #60's "lucide icons" came from this misreading. Relying on native decorations, which is what the app already did, **is** the conforming behaviour. Issue #60 closed as not-planned rather than implemented. |
| Windows/Linux/macOS: native title bar reads `git-branch-manager` | ~~(not audited)~~ → **符合** (Tier 5, `0bf8971`) | `windows/runner/main.cpp:30`, `linux/runner/my_application.cc:48,52`, `macos/Runner/MainFlutterWindow.swift`, `macos/Runner/Base.lproj/MainMenu.xib:333` | **A real page-01 gap this audit missed entirely** while chasing the imaginary one above: all three mockup cards title the window `git-branch-manager`, but every platform still carried Flutter's scaffold default `gbm_flutter`. `lib/app.dart:14`'s `MaterialApp.title` does not reach the OS window title on desktop, so this could only be fixed in native runner code. **Stated honestly, so this row does not repeat the mistake above**: the title *text* is evidenced only by the mockups — no page-01 prose names it — so the reason to change it is that `gbm_flutter` is an unedited scaffold leftover while every other surface in the project (`MaterialApp.title`, the Info.plist usage descriptions, the README, the repo itself) already says `git-branch-manager`. `PRODUCT_NAME`/`BINARY_NAME` were deliberately left alone: they are also the built artifact names and `release.yml:161,204,226,254` hardcodes `gbm_flutter.app`/`.exe`. macOS additionally needs a deferred (next main-queue turn) re-assignment — measured, not defensive: a synchronous set in `awakeFromNib`, in the xib, or in `applicationDidFinishLaunching` is all reverted to `CFBundleName` before the window is on screen. Covered by `test/platform/window_title_test.dart`, which asserts the runner sources directly because no Dart test tier can reach them and PR CI never builds Windows at all. **Still not addressed**: macOS's Apple-menu/About/Quit app name remains `gbm_flutter` (it comes from `CFBundleName = $(PRODUCT_NAME)`, i.e. the artifact name); that is a different surface and page 01's macOS card does not show it — tracked as #67. The CI hole that made the runner-source test necessary is tracked as #69 (it is one platform wider than stated above: PR CI runs no `flutter build macos` either). |

## Page 09 — Splitters (8 entries, `GbmSplitPane` + `tokens.dart`)

All 8 conform: default extent/ratio, minimum size, axis direction, and
double-click-to-reset all match the SPLITTERS table, backed by a single
`GbmSplitPane` widget with a `spec` parameter keyed to each `storageId`
(`main.sidebar`, `main.detail`, `main.files`, `wc.columns`, `wc.diff`,
`main.log`, `cw.files`, `cw.panes`). `main.log` defaults to
collapsed/zero-extent as specified; `cw.panes` uses the `[1, 1.12, 1]`
flex ratio verbatim. Persistence goes through
`panelLayoutRepositoryProvider`, and `View → Reset panel sizes` clears it.
**符合**, all 8 — no orphaned or extra splitters found.

---

## Page 02 — History (16 numbered items)

| # | Item | Verdict | Evidence | Reason |
|---|---|---|---|---|
| 1 | Menu bar (Alt/Ctrl+F2 opens first menu) | 符合 | `workspace_screen.dart:385` | — |
| 2 | Fetch/Pull/Push disabled during conflict | 符合 | `gbm_action_availability.dart:33-45` | All 3 gated on `!conflictActive`. |
| 3 | Search commits (Ctrl/Cmd+F) | 符合 | `commit_search.dart:8-28` | message/author/hash-prefix. |
| 4 | Sidebar: 3 sections, branches merged into ONE tree | 符合 | `sidebar_panel.dart:32-38,417-420`, `branch_tree_builder.dart:127-171` | `mergeLocalAndRemoteBranches()`. |
| 5 | Splitter A | 符合 | `workspace_screen.dart:326-331` | — |
| 6 | Commit list — lane rendering + ref chips | **部分符合 (缺少 the chip-merge rule)** | `commit_row.dart`, `graph_ref_chips.dart:1-16` | Lane/curve rendering exists. But `refChipsForCommit()` returns **every** ref pointing at a commit as its own chip with no logic to (a) merge a synced local+origin pair into one cloud-icon chip, or (b) render a separate dashed chip only when diverged. A synced branch currently shows two chips where spec wants one. Confirmed by direct read, not just the agent's grep. Classification **(i)** — data is already available (`RefSnapshot`), this is a pure rendering-logic gap. |
| 7 | Splitter B | 符合 | `workspace_screen.dart:318-323` | — |
| 8 | Commit detail panel | 符合 | `commit_detail_panel.dart` | monospace, subject+body. |
| 9 | Splitter C | 符合 | `workspace_screen.dart:318-323` | — |
| 10 | Changed files (arrow-key nav, dedicated 05-K menu) | 符合 | `changed_files_panel.dart` | Note: 05-K's own item content has separate gaps — see page 05 section above. |
| 11 | Status bar (branch/ahead-behind/counts) | 符合 | `status_bar.dart:178-214` | — |
| 12 | Branches — single tree, Prune required to remove gone refs | 符合 | `branch_tree_builder.dart:127-171` | — |
| 13 | Tab row: 2 persistent tabs + badge | 符合 (see F-A above for the *extra* surface) | `workspace_tab.dart:56-61` | Badge hides at 0, matches. The base 2-tab structure is spec-conformant; the problem is what else got attached to the same row (F-A). |
| 14 | Branch filter (Ctrl/Cmd+Shift+E) | 符合 | `branch_tree_builder.dart:174-191`, `sidebar_panel.dart:532-574` | — |
| 15 | Repo switcher popover | 符合 | `repo_switcher_popover.dart` | — |
| 16 | Graph column picker, Date hybrid format + ISO tooltip | 符合 | `graph_columns_selector.dart:56,61`, `graph_date_format.dart:5-26` | Graph/Message locked; relative/absolute date switch + full-ISO tooltip both present. |

**15/16 符合, 1 real rendering gap (item 6's chip-merge rule).**

---

## Page 03 — Working Copy (10 items + 7 SCOPES rows)

All 10 P3 items and all 7 SCOPES granularities (single file / multi-select
/ range-select / column tri-state / folder tri-state / hunk / arbitrary
lines) are implemented — including the 50-char summary hint, the 72-column
description ruler, and multi-select staging (Ctrl/Cmd-click, Shift-click),
which matters because it's what makes the "Stage N files" pluralized
context-menu labels (05-F) reachable at all.

**One real gap**, item 10 (List/Tree toggle):

| Item | Verdict | Evidence | Reason |
|---|---|---|---|
| 10. List/Tree toggle — spec requires ONE shared preference across Working Copy / History / Compare / Conflict window | **缺少 (partial)** | `file_list_view_mode_repository.dart:19-25` declares global scope; only `working_copy_view.dart:104` actually reads the provider | The preference genuinely persists globally (one `SharedPreferences` key), and folder-chaining (`file_tree.dart:198-219`) works correctly where it's used — but History, Compare, and the Conflict window never read this provider, so switching to tree mode in Working Copy has no effect on the other three views despite the spec's explicit "one shared preference" requirement. Classification **(i)** — the provider and folder-chaining logic already exist; the other 3 views just need to consume the same provider instead of (presumably) defaulting to flat/list mode unconditionally. |

---

## Page 07 — Clean/Conflict STATES (8 rows) + MSGS (4 rows)

| STATES row | Verdict | Evidence | Reason |
|---|---|---|---|
| 判定條件 | 符合 | `repo_session_repository.dart`'s `conflictActive` getter (documented in CLAUDE.md) | — |
| Banner | 符合 | `workspace_screen.dart:289-296` | `ConflictBanner` shown only when `conflictActive`. |
| Toolbar Fetch/Pull/Push disabled | 符合 | `gbm_action_availability.dart:33-45` | — |
| 切分支 disabled | 符合 | `gbm_action_availability.dart:40` | `branchCheckout` gated same way. |
| Working copy gains a Conflicted section | **符合 — corrected** | `working_copy_view.dart:136-138,171-245` | The discovery agent initially reported this as missing. Direct spot-check disproves that: `_buildConflictedSection()` exists, is pinned at the top, rendered only `if (status.conflicted.isNotEmpty)`, capped-height scrolling list with a count badge — matches spec exactly. Recorded here as a concrete example of why this audit spot-checks agent output rather than transcribing it verbatim. |
| Commit disabled until resolved | 符合 | `gbm_action_availability.dart:37` | — |
| Status bar danger styling + op/count | 符合 | `status_bar.dart:118-168` | — |
| 解衝突入口 (Resolve… / double-click) | 符合 | `conflict_resolve_window.dart:1161-1172` | — |

**8/8 符合** once the corrected row is applied.

| MSGS row | Verdict | Reason |
|---|---|---|
| Merge / Rebase / Cherry-pick / Revert message formats | **待查 (unverifiable at this layer)** | The discovery agent flagged these as "缺少/多出" but its own evidence says the opposite: message construction happens on the **native C++ core side** (`originalOperationMessage`, filled by `MergeOps.cpp`/`RebaseOps.cpp`/etc. per `CLAUDE.md`), which was out of this agent's Flutter-only read scope. A verdict of 缺少 is not supportable without reading `src/core/git/ops/*Ops.cpp`. Downgraded to 待查 (pending) rather than asserted as a gap — flagging for a follow-up pass that reads the core, not the Flutter layer, before this row can be closed out. One partial confirmation: the cherry-pick attribution line's Preferences toggle (`cherryPickAddsSourceLine`) does exist client-side (`app_preferences_repository.dart:31,59`), matching that part of the spec. |

---

## Page 08 — Conflict resolution window (11 items)

All 11 P8 items are implemented in `conflict_resolve_window.dart`: the
red-dot/green-check/count file rail, the 120px-min file-list/panes
splitter, both side panes with hover-fade apply buttons, the directly-
editable result pane (a real `TextField`, not apply-only), the ①②
order badges (Unicode circled digits, auto-renumbering), per-line discard
+ drag-out, and the bottom action bar (Previous/Next/Mark
resolved/Abort/Continue). The `[1, 1.12, 1]` three-pane ratio is
confirmed in `tokens.dart:543-544`. **11/11 符合.**

---

## Page 10 — Log & background status (5 items) + LOGRULES

| # | Item | Verdict | Evidence | Reason |
|---|---|---|---|---|
| 1 | Status bar repo-status region never displaced | 符合 | `status_bar.dart:152-217` | — |
| 2 | "+N task" chip expands on click | **缺少 — confirmed** | `status_bar.dart:279-286` | `'+$extraCount more'` is a plain `Text` widget with no `GestureDetector`/`InkWell`/`onTap` wrapping it — spot-checked directly, confirming the agent's finding. It displays the count but cannot be expanded into the task list the spec requires. |
| 3 | Persistent red error summary → jumps to log entry | 符合 | `status_bar.dart:224-230` | `hasUnreadLog` badge. |
| 4 | Log drawer (draggable height, zero when collapsed, filter/copy/save) | 符合 | `log_drawer.dart:20-70` | — |
| 5 | Error DIALOG window (Esc closes, next-action button, duplicate→counter) | **缺少 — confirmed** | `workspace_screen.dart:297-316` | Errors surface as an inline, persistent `GbmWarningBanner` (`if (session.lastError case final error? when error.codeName != 'Conflict')`), not a modal dialog window. This does satisfy the spec's *intent* ("no auto-dismissing toast — must stay until the user has seen it") but not the *mechanism* — there is no dialog with a "what failed / why / raw git output (collapsed, monospace)" 3-section layout, no primary-button-as-next-action, and no repeated-error counter (searched for and found no such field). Classification **(i)** — the underlying `GitError` model already carries the needed fields (per `git_error.dart`); this is a missing dialog widget, not a missing data path. |

**Additional finding — LOGRULES retention number:** spec says "記憶體中保留最近 2,000 筆" (in-memory keeps last 2,000 entries). Code caps `operationLog` at `_kMaxOperationLogEntries = 500` (`repo_session_repository.dart:243`). **措辭不符/缺少** — the retention mechanism (cap + sublist eviction) is correctly implemented, but the number is 500, not 2,000.

---

## Page 11 — Preferences (6 tabs + 9 items)

All 6 PREFNAV tabs (General / Repository sources / Git / Appearance /
Shortcuts / Advanced) render and are correctly scoped as app-level
config, separate from per-repo Repository Settings. **The
`manageBaseFoldersDialog` question is resolved**: it is a deliberate,
documented compact secondary view (path-only, no depth/scan-dir columns)
reachable independently, not a duplicate of the Preferences tab — no
same-surface duplication bug here (unlike the Log drawer/Operation Log
dialog pair in F-B).

| # | Item | Verdict | Evidence | Reason |
|---|---|---|---|---|
| 1 | Preferences tabs | 符合 | `preferences_dialog.dart:20-27,86-92` | — |
| 2 | Base folders list: path + depth + count + **offline marker** | **缺少** | `preferences_dialog.dart:564-572`, `manage_base_folders_dialog.dart:68-75` | Path/depth/count all present; the `BaseFolderRecord` model has no `isOnline`/offline field at all, so an unmounted-disk row cannot be distinguished from a healthy one. Classification **(i)** if the scan already detects the failure — needs confirming against `discovery_repository.dart`, but the UI-side field is clearly absent. |
| 3 | Add folder… (native picker) | 符合 (documented exception) | `preferences_dialog.dart:378-452` | Uses a text field, not a native OS picker — already recorded in CLAUDE.md as a platform limitation, not a new finding. |
| 4 | Auto-scan toggle + **per-folder depth** | **缺少** | `preferences_dialog.dart:472-494`, `discovery_repository.dart:129` | Toggle exists; depth is hardcoded to 3 at folder-add time with no UI to edit it per-folder afterward, though the spec explicitly calls out independent per-folder depth as the reason two different folder types need different values. |
| 5 | Scan result summary: repo count + folders + **last scan time + duration** + **skipped-folder report** | **缺少** | `preferences_dialog.dart:455-463` | Repo count and enabled-folder count show; last-scan-time, duration, and "folders skipped due to depth cap" are all absent from the summary, even though the underlying `BaseFolderRecord` has `lastScanStarted`/`lastScanFinished` fields to source them from. |
| 6 | Remember manually-opened locations (default ON) | 符合 | `preferences_dialog.dart:344-354` | — |
| 7 | Manual-open history: **individual entry removal** | **缺少** | `preferences_dialog.dart:497-528` | Only a "Clear list" (clear-all) button exists; `recents_repository.dart:88-94` already has a per-entry `remove(workDir)` method with no UI call site. |
| 8 | Global gitignore: toggle/path/editor + **imported-value source label** | **缺少** | `preferences_dialog.dart:603-622`, `app_preferences_repository.dart:29-30` | Toggle, path field, and editor all present; the model has no field to track and label *where* an existing value came from when imported from the user's own `.gitconfig`, so the spec's "must not silently overwrite, must label the source" requirement isn't representable yet. |
| 9 | Auto-fetch: per-repo scope, timer resets on switch | 符合 | `preferences_dialog.dart:299-341` | — |

**4/9 符合, 5 real gaps, all classification (i) or needing one more read to confirm (i) vs (ii).**

---

## Page 12 — Compare (4 CHANGEVIEWS + 5 COMPARES rows)

| Item | Verdict | Evidence | Reason |
|---|---|---|---|
| CHANGEVIEWS 1: Commit | 符合 | `history_page.dart:13-52` | — |
| CHANGEVIEWS 2: Stash — inline expand on click | **缺少** | `sidebar_panel.dart:896-960` | Stash rows are not expandable in place; right-click "View diff" opens a dialog instead of the spec's inline-expand-then-click-file flow. |
| CHANGEVIEWS 3: Working copy | 符合 | `working_copy_view.dart` | — |
| CHANGEVIEWS 4: Between two refs — read-only 3-part view | 符合 | `compare_page.dart:209-403` | ref pickers / file list / diff pane, all present. |
| COMPARES 1: Branch ↔ Branch (multi-select → right-click → Compare) | **缺少** | `commit_row.dart:25,229` | No multi-select path in History; consistent with the page-05 finding that 05-E's context menu is also missing "Compare with…" at the branch/commit level. |
| COMPARES 2: Branch ↔ Tag | 符合 | `sidebar_panel.dart:201-207` | `_compareTag()`. |
| COMPARES 3: Commit ↔ Commit (Ctrl/Cmd-click multi-select, merge-base + 2-dot/3-dot toggle) | **缺少 (entry point) / 符合 (once reached)** | no multi-select mechanism found in `history_graph/`; but `compare_page.dart:262-321` implements the 2-dot/3-dot toggle and merge-base labeling once a Compare tab IS open | The comparison *engine* correctly implements the harder half of this spec row (merge-base detection, 2-dot/3-dot); what's missing is entirely the *entry point* — there's no way to Ctrl/Cmd-click two commits in History to reach it. Same root cause as COMPARES 1 and 05-E. |
| COMPARES 4: Stash ↔ any ref, stash forced to the right side | 符合 | `sidebar_panel.dart:175-181`, `compare_page.dart:31-61` | `_compareStash()` places stash OID correctly. |
| COMPARES 5: any ref ↔ Working copy, checkout-to-overwrite is the only writable path | 符合 | `compare_page.dart:143-175,342-349,536-600` | Confirmed as the sole writable comparison, with a confirmation dialog before `restorePaths()`. |

**6/9 符合, 3 gaps that are all the SAME underlying cause**: History has no
multi-select mechanism, so every Compare flow that depends on selecting
two commits (branch↔branch via commits, commit↔commit) has a working
back-end but no front-door. This corroborates 05-E's finding that
"Compare with…" is missing from the commit context menu — fixing
multi-select + wiring 05-E's `Compare with…` item likely closes both
COMPARES 1 and COMPARES 3's entry-point gaps at once.

---

## Cross-cutting synthesis

Counting every row across all 12 pages plus the shortcuts/dialogs audits:
roughly **78 items checked**, **~53 符合** (including 2 corrected after
spot-check disproved an agent's initial claim, and 05-G's gap shrinking
from "5 items missing" to "1 item missing" after a full read replaced the
grep-derived first pass), **~19 real gaps** (mostly classification (i) —
capi/service already exists, only the Flutter-side wiring is missing, and
several of those "(i)" gaps turned out to need a small prerequisite —
name resolution, a not-yet-built per-branch UI — rather than being pure
copy-paste wiring), **2 (ii)** (need new capi: `Open file at this
revision`, `Save this revision as…`), and a handful of spec-internal
inconsistencies (two shortcut-key collisions, one MENUS-table omission)
that are not code defects. **Three** rows were materially wrong in this
report's first draft and were corrected in place once their real source was
read instead of grepped or eyeballed. 05-F and 05-G are described in the
Page 05 correction note. The third — page 01's title bar — is the worst of
the three and a different failure mode from the other two: those two
undercounted a real gap, whereas page 01 invented one that does not exist,
by reading a mockup's *illustration of native OS decoration* as a
requirement to draw custom chrome. It would have cost a third-party window
package, Windows and Linux platform-project changes, and a new widget, all
to move the app **away** from what the spec asks for. The lesson generalises
past this report: a mockup shows what the user sees, not who draws it, so a
verdict must rest on the spec's prose — and page 01's prose was explicit.

The gaps cluster into a small number of root causes rather than being 24
independent problems:
1. **F1**: the context-menu catalog file is dead code — 7 of 11 groups
   drifted from spec because nothing enforces they match it.
2. **History has no multi-select** — this alone explains 05-E's missing
   `Compare with…`/`Merge into current`, and both Compare-page entry-point
   gaps (COMPARES 1 and 3).
3. **F-A**: `tab_row.dart`'s 18-item overflow menu is a spec-unsanctioned
   third entry surface for otherwise-legitimate features.
4. **F-B**: the Log drawer and Operation Log dialog are two competing
   implementations of the same spec concept.
5. Preferences (page 11) has 5 gaps that are all "field exists in the
   data model / backing repository, but no UI surfaces it yet" — the
   cheapest category to close.

See `docs/reports/code-review-2026-08.md` for the architectural review
that follows from these patterns (Phase 2).
