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

> **Audit baseline moved on 260820 (commit `fc3bfb3`).** The spec this
> matrix was written against had 12 pages; it now has **21** (this banner
> said 16 until Tier 6a — the count was wrong, not just stale). Nine pages
> were added — **P13** Branch rename dialog + branch/commit multi-select,
> **P14** entry-point IA for the 24 already-shipped advanced screens,
> **P15** empty states and error windows, **P16** the revision log itself,
> **P17/P18** dialog 版面 (流程類 12 + 修復類 8), **P19** 管理面板樣版,
> **P20** 未實作功能, **P21** Pull 流程與錯誤 — and P16's
> `REVISIONS` table also *changes* rules the rows below were judged against.
> Rows affected by that table are corrected in place and marked
> "(260820 修訂)"; the nine new pages are **not** audited here, with two
> exceptions closed since: **P14** (entry-point IA) by Tier 6b, and **P19**
> (管理面板樣版) by Tier 6c, which implemented every `PANELSPEC` row it had
> data for and recorded the rest on #76. Anything
> below without that marker was judged against the original 12 pages and
> may have drifted. See the Tier 0c PR for the rename rows, which are the
> only ones this round implemented.
>
> **P13 section B is now implemented** (Tier 2+3, issues #54–#57): the
> `MULTIKEYS` / `MULTIACTS` / `MULTIBRANCHMENU` selection rules, the History
> status-bar selection summary, and both `Edit → Select all` and the two
> Compare entry points that depended on them. Rows it touched (Edit → Select
> all, 05-B, 05-E, COMPARES 1, COMPARES 3) are corrected in place below.
> **P13 section A** (the rename dialog) shipped earlier in Tier 0c. P14–P16
> remain unaudited, and section B was not audited row-by-row before being
> implemented — it was read from the source spec directly, so no matrix rows
> exist for `MULTIKEYS`/`MULTIACTS`/`MULTIBRANCHMENU` themselves.
>
> **`MULTIKEYS` is now partially audited row-by-row** (fix/sidebar-p02-branch-rows): the four selection paths 單擊 / Ctrl-Cmd＋單擊 / Ctrl-Cmd＋A / Shift＋↑↓ were each read against the spec and given a counting test, and the 單擊 rule was found **inverted** in the code (single click ran checkout). `BRANCH_STATES`' 「點兩下即 checkout」 and 「整列以 selected 底色標示」 were audited with it. `BRANCH_STATES`' 「永遠置頂於所屬資料夾內」 was audited and **fixed** in the same branch (see row 12). Still unaudited in section B: `MULTIACTS` and `MULTIBRANCHMENU`. Carried to **#76**. **The same 「範圍用畫成的順序量」 rule was then found broken on a second surface** (feat/p03-working-copy-redesign C18): the Working Copy board measured ranges in tree order while list mode — the default — painted entry order. See the Page 03 row. Worth noting for the audit method: this is two independent surfaces failing the same `MULTIKEYS` clause, so a per-surface audit is what finds it and a per-clause verdict would not have.

---

## Page 04 — Menu bar & shortcuts (`gbm_menu_model.dart`, `gbm_shortcuts.dart`)

**Menu bar (`gbmMenus`, 7 menus, 52 items) (260820 修訂):** matches spec's
MENUS table verbatim across all 7 menus (File 8 / Edit 8 / View 11 /
Repository 10 / Branch 7 / Remote 4 / Help 4) **as that table stood at
audit time**. P16's `REVISIONS` changes two things about this paragraph:

- **`Stage selected lines` is no longer an app-side addition.** It was
  logged here as "the spec's own table missing a row it documents
  elsewhere" (page-03 prose, SCOPES row 7 / P3 item 5), with the verdict
  **符合** on the grounds that the code sided with the prose. REVISIONS
  now puts it *in* the MENUS table — "已加入 Repository 選單" — so the
  spec-internal inconsistency is resolved in the code's favour and the
  item itself stays 符合. But the same revision assigns it
  **`Ctrl/Cmd+Alt+S`**, and `gbm_shortcuts.dart` binds it to
  `Ctrl/Cmd+Shift+Enter` (the shift group's `LogicalKeyboardKey.enter`
  entry). That is a **real shortcut mismatch** that did not exist when
  this row was written — the audit had no shortcut to compare against.
  ~~**措辭不符** on the binding.~~ → **符合** (feat/p03-working-copy-redesign,
  #75-3): rebound to `Ctrl/Cmd+Alt+S`. **And its subject now exists** — at
  the time of the rebinding the action had no implementation, because the
  「selected lines」 it names had no representation; the temporary scope
  (a text selection over the diff) is that representation, published
  through `temporaryScopeSubmitProvider`, whose `null` is the disabled
  state so all three dispatch paths still read one handler map. **Both
  readings of the key are honoured**, as #75's closing comment promised:
  `Ctrl/Cmd+Alt+S` globally (REVISIONS) and `Ctrl/Cmd+Shift+Enter` inside
  `ScopedDiffView`'s own focus scope (P03-5 / `SCOPES` row 7). Scoped, not
  global, for the same reason `Ctrl/Cmd+A` is: a binding closer to a focused
  editor than `DefaultTextEditingShortcuts` steals that editor's Enter.
- ~~**`Edit → Select all` is missing entirely.**~~ → **符合** (fixed,
  Tier 2 / #54). REVISIONS adds it with `Ctrl/Cmd+A` ("搭 P13 多選"), so
  the Edit menu now has 9 items and the app-wide total is 53. The
  sequencing note below held: it shipped *with* the multi-select work, in
  the same branch, because `Ctrl/Cmd+A` is also `MULTIKEYS`' "全選當前清
  單" and binding it first would have given it nothing to select.
  `GbmActionId.editSelectAll`'s handler follows `_invokeTextIntent`'s
  existing shape — non-null in the handler map (so all three dispatch
  paths stay in agreement) and forwarding by focus: it invokes
  `GbmSelectAllIntent` first and falls back to `SelectAllTextIntent`, so
  the same key still selects text when a `TextField` holds focus. The
  commit list and the branch tree each register their own
  `GbmSelectAllIntent` action inside their own focus scope, which is also
  what keeps the list binding from stealing `DefaultTextEditingShortcuts`'
  select-all.

**Keyboard shortcuts (`gbmActionShortcuts()`, 36/52 ids bound — 35/52 at audit time; F2 is the one added since, see the rename row below):**

| Spec item | Verdict | Evidence | Reason |
|---|---|---|---|
| Edit → Find in files, `Ctrl/Cmd+Shift+H` (260820 修訂) | **缺少** | `gbm_shortcuts.dart` has no `editFindInFiles` entry | Originally logged as a spec defect: the 12-page MENUS table assigned `Ctrl/Cmd+Shift+F` to BOTH "Find in files" and "Repository → Fetch", so the code kept `repositoryFetch` and left this unbound. **P16's REVISIONS resolves it** — Fetch keeps `Shift+F` ("工具列 F / P / P 三顆同組，不能拆") and Find in files moves to `Ctrl/Cmd+Shift+H`. The collision excuse is therefore gone; this is now an ordinary unbound shortcut. ~~Needs its own issue.~~ **Bound** in feat/p03-working-copy-redesign (#75-1). |
| Branch → Stash changes, `Ctrl/Cmd+Shift+S` (260820 修訂) | **缺少** | `gbm_shortcuts.dart` has no `branchStashChanges` entry | Same story: the original table double-assigned `Ctrl/Cmd+Shift+T` to both this and "View → File list as tree", and the code kept the latter. **P16's REVISIONS moves Stash changes to `Ctrl/Cmd+Shift+S`** and keeps `Shift+T` for the tree toggle. Note `Ctrl/Cmd+Shift+S` is currently bound to `repositoryStageAll` here, so honouring the revision means re-deciding that binding, not just adding one. ~~Needs its own issue.~~ **Bound** in feat/p03-working-copy-redesign (#75-2); the re-decision it called for is recorded as a deviation — the spec assigns Stage all no key, and the user ratified moving it to `Ctrl/Cmd+Alt+A`. The fix's mechanism was itself the repo's recurring shape: `GbmKeyboardShortcut.alt` existed and **no caller had ever passed it**. |
| Branch → Rename branch…, `F2` (from DIALOGS table + CTX 05-B) | **符合** (fixed, Tier 0c) | `gbm_shortcuts.dart`'s bare-key group | Was the one shortcut gap not explained by a spec-internal collision, and it compounded with the missing dialog route below. Now bound, as the only entry in the map with no Ctrl/Cmd at all — it is constructed directly rather than through `_makeShortcut()`, which always adds one. P16's REVISIONS confirms the binding ("Branch → Rename branch… = F2"). Label also corrected from `Rename current branch…` to spec's `Rename branch…`. |
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
see its row.

**Update (Tier 4, branch `fix/tier-4-file-at-revision`, issues #58 + #59).**
05-K's remaining four items landed, so its parity assertion is no longer
skipped either — seven of eleven groups are now catalog-checked. 05-K's
render site stays a private `_buildMenuItems` inside
`changed_files_panel.dart` rather than becoming a `*_menu_items.dart` pure
function, because its items need the container's commit oid and its
in-flight export state, which that template has nowhere to hold. **05-B and
05-E are the only drifted groups left.**

**Update (Tier 2+3, branch `feat/tier-2-3-multi-select-compare`, issues #54,
#55, #56, #57).** 05-B and 05-E both landed, so **no group is skipped any
more**. Both rows' premises were wrong in the same direction — each named a
prerequisite that did not exist — and both are corrected in place below
rather than edited away, since the correction is what moved the work.

Two premises in the rows below were **wrong** and are corrected in place
rather than silently edited away, because both changed where the fix had to
go: 05-F pointed at a widget nothing in `lib/` ever built, and 05-G's
"only Discard is missing" undercounted the drift. Details in each row.

| Group | Verdict | Evidence | Detail |
|---|---|---|---|
| 05-A Repository | 符合 (deliberate reduction) + 1 minor 多出 | `repo_switcher_popover.dart:740-877` `RepoSwitcherRow._openContextMenu()` | Omits Fetch/Pull/Push vs. the catalog's 7 items — documented in the catalog's own comment: a repo row in the switcher list has no open session to act on. Renders: Open / Open in file manager / Open in terminal / Settings… / [separator] / Remove from list (5 items). The leading `Open` item is not in spec's 05-A list at all — low-severity addition (mirrors the row's own double-click action, a reasonable convenience), noted for completeness rather than flagged as something to remove. |
| 05-B Local branch | ~~**缺少**~~ → **符合** (Tier 3 / #57) | `sidebar/widgets/local_branch_menu_items.dart`, rendered by `branch_tree_item.dart` | **This row's premise — and #57's — was wrong about `Compare with…`.** It read as needing a new picker UI; it does not. `sidebar_panel.dart`'s `_compareStash()`/`_compareTag()` had already established the convention: open a Compare tab with only the left side filled (`compareTabsProvider.open(left: <ref>)`) and let `CompareRefPicker`, which the Compare page already renders, take the right. A branch copies that verbatim — zero new dialogs. `Rebase current onto here` was likewise not blocked on Dart-side plumbing: `RoutePaths.rebaseOntoDialogFor` gained a `target` query parameter (template: `renameBranchDialogFor`) and the existing dialog pre-selects it. **Fixed**: all 8 items now render with spec's exact labels — the render site is a pure `*_menu_items.dart` function asserted for **exact equality**, replacing the parity test's previous `startsWith` comparison, which is what let the two wording drifts (`Rename branch`, `Merge into current branch`) sit unreported. The `skip: true` is gone. Also closed while there: `New branch from here`, `Merge into current` and `Delete branch` were ungated mid-conflict despite spec page 07 disabling all three; they now go through `isActionEnabled()` like the rest. |
| 05-C Remote-only / gone branch | 符合 (verify) | `branch_tree_item.dart` | CLAUDE.md's "Known gaps" section documents this as fixed (`_buildGoneMenuItems()`), matching spec's 05-C note that a gone row keeps only Prune+Copy. The *catalog file's* doc comment still says "not yet wired" — that comment is stale, not the implementation; flagged for correction in Phase 5. |
| 05-D Tag | 符合 | `tag_menu_items.dart` | Labels and order match spec exactly (5 items). Reference-quality implementation. |
| 05-E Commit | ~~**缺少**~~ → **符合** (Tier 3 / #56) | `history_graph/widgets/commit_menu_items.dart`, rendered by `commit_row.dart` | **The premise this row and #56 shared was wrong.** Both said `Merge into current` needed an oid→branch-name resolution step because `mergeBranch` takes a name. It does not: `gbm_merge_branch`'s `target` is pushed straight into `git merge <target>` (`src/core/git/ops/MergeOps.cpp:59,82`) and only an empty string is rejected — an oid is a perfectly legal committish, and `startRebase(upstream)` behaves the same way. So there was no prerequisite, only wiring. **Fixed**: all 7 top-level items plus the full `More actions` submenu of 5 now render, with `Revert commit` back inside the submenu where spec puts it. The submenu could only be built because Tier 4 had already made `GbmMenuItem.submenu`'s flyout actually open — before that its trigger row carried a permanently-null `onTap`. Multi-select changes the labels rather than the item set (`Cherry-pick 3 commits`, following 05-F's counted-label pattern), and the contiguity-gated trio (`Cherry-pick`/`Revert`, plus `Squash` which this app does not offer at all) renders `enabled: false` **and** `onTap: null` with spec's own tooltip 「選取需為連續 commit」 when the range has a gap. Contiguity is judged against the **unfiltered** snapshot, so three rows that look adjacent under a search filter are correctly refused. The `skip: true` is gone. |
| 05-F Working copy file | ~~缺少~~ → **符合** (Tier 1 / #51) | `working_copy_view.dart:576` `_openContextMenu()` → `working_copy/widgets/working_copy_file_menu_items.dart` | **This row audited the wrong file — twice.** The first pass grepped `label: '...'` and so missed ternary-labelled items; the "corrected" second pass fixed that but still pointed at `changed_file_row.dart`, which **no file under `lib/` ever constructed**. `WorkingCopyBoard` (commit `39d6303`) replaced that row widget and commit `5581538` moved the 05-F menu into `working_copy_view.dart`; `ChangedFileRow` had been orphaned since, referenced only by `test/`. So the live menu already had `Open terminal here` and full multi-select pluralization, and the real gap was two items, not three. **Fixed**: `Open file` and `Show in file manager` added (`DesktopLauncher.openFile()` is new; `openInFileManager()` already existed, and both now normalize `/`→`\` on Windows, without which `explorer.exe /select,` silently opens Documents instead of revealing). The orphaned widget and its test file were deleted in their own commit. **Deliberate reduction**: `Blame…`/`File History…`/`Line History…` were dropped from this menu — they are beyond-spec, and 6 spec items + 3 extras is 9, over `showGbmContextMenu`'s asserted 8-item cap (spec page 05's own "最多 8 項"); `GbmMenuItem.submenu`'s flyout does not render yet, so nesting them was not available. All three stay reachable from `tab_row.dart`'s overflow menu, minus the pre-filled path. |
| 05-G Diff line | ~~缺少~~ → **符合** (Tier 1 / #52) | `diff_line.dart:140` `_showContextMenu()` → `diff/widgets/diff_line_menu_items.dart` | **The gap was larger than the corrected second pass reported.** Reading spec's own 05-G block verbatim (`{ label: 'Stage 12 lines' }, { 'Stage hunk' }, { 'Unstage hunk' }, { 'Copy lines' }, { sep }, { 'Discard 12 lines…', danger }`) shows four differences, not one: the missing `Discard`, plus `Stage line` vs `Stage`/`Stage N lines`, `Copy line` vs `Copy lines`, and spec listing **both** hunk directions as separate entries where the code ternaried between them. **Fixed, all four.** Both hunk items now always render with the inapplicable direction disabled (`enabled: false` *and* `onTap: null` — `enabled` alone is a visual signal only, see `gbm_menu.dart`); the count comes from `_DiffHunkSection`'s checkbox selection using 05-F's own "right-click inside the selection keeps the batch" rule. `Discard` needed a **new capi** — `gbm_stage_lines`/`gbm_unstage_lines` are `git apply --cached` (index only), so `gbm_discard_lines` was added (`git apply --reverse` without `--cached`, patch built with `unstaging=true` since that flag means "will be reverse-applied, check the new side"). It is offered only on the unstaged side and always routes through the discard-changes dialog's new line mode, never straight to the controller. **Follow-up defect, found by writing the missing coverage rather than by reading the diff**: that new line mode reaches the dialog through a URL, and the router's inline parsing cross-nulled `hunk` against `line`, so a half-parsed line selection silently degraded to *whole-file* discard behind the same danger button. Parsing moved to `DiscardChangesRequest.fromQuery` (`features/dialogs/discard_changes/discard_changes_request.dart`); an unhonourable line request is now `isMalformed` and the dialog offers `Close` and no destructive button. |
| 05-H Stash entry | 符合 | `stash_menu_items.dart` | Labels and order match spec exactly (6 items). Reference-quality. |
| 05-I Conflict hunk | 符合 | `conflict_hunk_menu_items.dart` | Labels and order match spec exactly (5 items). Reference-quality. |
| 05-J Branch folder | 符合 | `branch_folder_menu_items.dart` | Matches spec's 4 items (aside from a possible deliberate omission — see pending device/widget-tier note in Phase 3). |
| 05-K Commit file | ~~**部分修復**~~ → **符合** (Tier 4 / #58 + #59) | `changed_files_panel.dart` menu build | **Fixed in two rounds.** Tier 1 (#53) wired the two (i)-classified top-level items — `Compare with working copy` (opens a Compare tab via `compareTabsProvider.open(left: <oid>)` with a null `right`, then `context.go`, mirroring `sidebar_panel.dart`'s `_compareStash`; `push` would stack the tab over History rather than switch to it) and `Open terminal here` (the repository work dir, like 05-A/05-F — a historical commit's file has no directory of its own). Tier 4 closed the rest, and **both of that round's premises needed correcting**. (1) `Open file at this revision` / `Save this revision as…` were classified **(ii)** "no blob-read entry point", which was true, but the entry point they needed is not the one #58 sketched: neither displays content in-app, so `gbm_export_file_at_revision(session, revision, path, destPath)` writes raw bytes to a destination instead of returning content inline — binary-safe by construction, where a JSON string payload could not have carried an image at all. (2) `Restore and stage` / `Export as patch…` were blocked on `GbmMenuItem.submenu`'s flyout, which was the *real* blocker for the whole group and turned out to be a `gbm_menu.dart` change, not a 05-K one: the trigger row had a permanently-null `onTap`. Both landed; the parity test's 05-K group is now asserted against the full catalog with **no `skip`**. Two documented deliberate outcomes: `Restore file to this state` and `Restore and stage` open the same dialog (`restore_file_dialog.dart` has always offered both as two buttons, because the confirmation text is identical), and `Export as patch…` writes the whole commit's patch, since `gbm_patch_export` is `git format-patch -1 <commit>`. Remaining, not fixed: the *catalog's* own 05-K submenu lists four children where spec lists five — `Restore file to before this state` is absent from `gbm_context_menus.dart`. Left alone on purpose, since that catalog is this test's acceptance baseline — tracked as **#71**, which also notes that this audit's method (render site vs. catalog) could not have caught a catalog-vs-spec drift in any group. |

**Net**: after Tier 3, **all 11 groups are checked against the catalog with
no `skip`** — the parity test has no skipped assertions left, so H1's root
cause (a catalog nothing under `lib/` imports) can no longer drift
unnoticed in any group. Eight of the eleven are now pure
`*_menu_items.dart` functions; 05-A, 05-C and 05-K keep private render-site
builders for reasons recorded in their own rows. The post-Tier-4 text
follows: 7 of 11 groups (05-D/F/G/H/I/J/K) are checked against the catalog
with no `skip`; six of those are also reference-quality pure
`*_menu_items.dart` functions and remain the template for the rest. 05-B and
05-E are the only unfixed groups left. The original
post-Tier-1 text follows: 6 of 11 groups (05-D/F/G/H/I/J) are
reference-quality … 05-K is partially fixed (its two wireable items landed;
the other four need capi or a submenu flyout).
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
| **Rename branch** | **符合** (fixed, Tier 0c) | `RoutePaths.renameBranchDialog`, `features/dialogs/rename_branch/` | Built against **P13 section A**, the design added on 260820 — which is why this was deliberately deferred in Tier 0 rather than built blind (see issue #45's history). All three spec entry points now reach it: 05-B context menu (naming the clicked branch), Branch menu, and F2 (both falling back to HEAD). The classification was optimistic: `gbm_branch_rename` did exist, but P13's "遠端連帶處理" needed it extended with `renameRemote`/`remoteName`/`askpassDir` plus a `--unset-upstream` step, since `git branch -m` carries tracking config across. |
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

**15/16 present, 1 documented absence (Clone).** Rename branch was the one
real gap and is fixed (Tier 0c).

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

### F-A. `tab_row.dart`'s `_MoreMenu` is a third, spec-unsanctioned entry surface (**largely fixed, Tier 6b / #62**)

> **Resolved in Tier 6b**, and the resolution was already written down: this
> finding was logged as needing a design decision, but spec **page 14**
> (`進階功能的入口與載體`, added 260820) *is* that decision. It was missed
> because this matrix's own banner said the spec had 16 pages when it has 21.
> The overflow menu is now **2 items** and the standalone buttons **1**; a
> new **Tools** menu (page 14's `TOOLSMENU`, placed between Remote and Help)
> takes nine, the file context menu's new `History ▸` flyout takes three,
> `Stash changes…` returns to the Branch menu, two duplicates are dropped and
> `Operation Log…` went with F-B. What remains is what spec assigns no home
> to (`Create tag…` → #84, `Undo last operation…` → #85) and `Cherry-pick…`,
> whose dialog has no other entry point and whose spec is self-contradictory
> (#86). Page 14 also routes the twelve management panels to **tabs** —
> **all twelve are now ported (Tier 6c)**, their dialogs and routes deleted,
> so the repo-scoped dialog count is 22 rather than 34. Each panel's
> `PANELSPEC` fields that had no backing data are listed on #76 rather than
> faked; see CLAUDE.md's "Tier 6c" section for the per-panel reasoning.

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

### F-B. Log panel has two competing implementations (260820 修訂 — verdict hardened)

Spec page 10 defines Log as a bottom drawer (`main.log` splitter,
draggable height, zero space when collapsed). The code has both
`lib/features/log_drawer/` (matches the spec) and a separate
`operationLogDialog` modal route, reachable only from `_MoreMenu`. Same
concept, two surfaces — full detail in the page-10 pass below.

**P16's REVISIONS settles which one is wrong.** At audit time this was
logged as an ambiguity: the spec described a drawer, the app had both, and
nothing said the dialog was forbidden. REVISIONS now states it outright —
「只留抽屜；**operation-log dialog 從規格中刪除**（LOGRULES 新增「只有一
套」一列）」. So this is no longer "two implementations of one concept,
pick a winner" but a **named removal**: `operationLogDialog`, its route
constant, its `_MoreMenu` entry and `features/operation_log/` are now
非規格內容 and should go, with the drawer keeping the feature. That also
answers the open question tracked on **#61**, which was waiting for
exactly this ruling.

**Done in Tier 6a (#61).** The route constant, its `app_router.dart`
registration, the `_MoreMenu` entry and `features/operation_log/` are all
removed, along with the now-orphaned `RepoSessionController
.clearOperationLog()`. One deliberate capability loss: the dialog's `Clear`
button was not ported, because LOGRULES' 匯出 row lists only
`Copy all、Save as…` and its 保留 row already bounds the list (500 entries,
2,000 via Preferences, 7-day file rotation). The drawer's reachability was
proved *before* the deletion by
`test/integration/workspace_log_drawer_reachability_test.dart`, which
asserts View → Log (`Ctrl/Cmd+Shift+L`) expands the `main.log` pane — a
size assertion, since `LogDrawer` is always mounted and only its height
distinguishes open from collapsed.

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
| 2 | Toolbar: Fetch/Pull/Push (Push primary) + Branch/Stash, all disabled during conflict | ~~符合~~ → **符合** (feat/p02-action-toolbar) | `features/workspace/widgets/action_toolbar.dart`, `workspace_screen.dart`, `gbm_action_availability.dart:33-45` | **This row checked the gate and passed for it, while the surface being gated did not exist.** The old verdict's title ("Fetch/Pull/Push disabled during conflict") is not what item 2 says: item 2 *is* the toolbar row under the menu bar (`spec_raw.html:1245-1255`), and 「三顆同組。Push 為主要樣式。」describes buttons, not a permission rule. Nothing under `lib/` rendered them — Fetch/Pull/Push had exactly two entry points, the keyboard shortcut and the Repository menu — so `gbm_action_availability.dart` was greying out a bar that was never drawn. Same shape as rows 11, 12 and 14 below. `ActionToolbar` now renders all five buttons on all three platforms, wired from the same `Map<GbmActionId, VoidCallback?>` the keyboard/system-menu/in-window-menu paths dispatch through, so the conflict gate arrives through `isActionEnabled()` with no second source. Branch/Stash are mockup-only (no prose names them) but the spec's own icon choices — `git-branch-plus`, `inbox` — name their actions, and no prose contradicts them, so the prose-wins rule had nothing to overrule. **Recorded reduction**: P17 wants Alt+click on toolbar Pull to open a Pull dialog with the apply mode pre-selected; `route_paths.dart` has no pull dialog route, so only the plain click (「直接用 Preferences 的預設套用方式走」) is wired. **Third instance of this shape, and it is not specific to `isActionEnabled()`** _(feat/p03-working-copy-redesign)_: P03's 「all 7 `SCOPES` granularities implemented」 rested on `WorkingCopySelectionState.getCheckState()` and `FileTreeNode.getCheckState()` — existing, correct, unit-tested, and called by **nothing under `lib/`**. Any helper can stand in for the surface; the tell is that the cell names a *capability* rather than the widget that draws it. It cuts both ways, too — because the cell never named a widget, removing every checkbox from Working Copy left it looking unchanged. |
| 3 | Search commits (Ctrl/Cmd+F) | 符合 | `commit_search.dart:8-28` | message/author/hash-prefix. |
| 4 | Sidebar: 3 sections, branches merged into ONE tree | 符合 | `sidebar_panel.dart:32-38,417-420`, `branch_tree_builder.dart:127-171` | `mergeLocalAndRemoteBranches()`. |
| 5 | Splitter A | 符合 | `workspace_screen.dart:326-331` | — |
| 6 | Commit list — lane rendering + ref chips | **部分符合 (缺少 the chip-merge rule)** | `commit_row.dart`, `graph_ref_chips.dart:1-16` | Lane/curve rendering exists. But `refChipsForCommit()` returns **every** ref pointing at a commit as its own chip with no logic to (a) merge a synced local+origin pair into one cloud-icon chip, or (b) render a separate dashed chip only when diverged. A synced branch currently shows two chips where spec wants one. Confirmed by direct read, not just the agent's grep. Classification **(i)** — data is already available (`RefSnapshot`), this is a pure rendering-logic gap. |
| 7 | Splitter B | 符合 | `workspace_screen.dart:318-323` | — |
| 8 | Commit detail panel | 符合 | `commit_detail_panel.dart` | monospace, subject+body. |
| 9 | Splitter C | 符合 | `workspace_screen.dart:318-323` | — |
| 10 | Changed files (arrow-key nav, dedicated 05-K menu) | 符合 | `changed_files_panel.dart` | Note: 05-K's own item content has separate gaps — see page 05 section above. |
| 11 | Status bar (branch/ahead-behind/counts) | ~~符合~~ → **符合** (fix/fetch-gone-marking-and-log-levels) | `status_bar.dart`, `workspace_screen.dart` | **This row was wrong.** It checked that ahead/behind rendered, not that P02's own 「status bar 的 ahead/behind 改顯示 `upstream gone`」 clause did — which was absent entirely, including for a branch whose upstream had *already* been pruned (`RefInfo.isGone`), not just for this round's new pending marks. `StatusBar` now takes `upstreamGone`, which **replaces** rather than joins the counts: they are measured against a ref that no longer exists, and the case that matters most rendered nothing at all before (a branch exactly in sync reports 0/0, so neither block drew). The caller evaluates it through the shared `isEffectivelyGone()`, so the sidebar and the status bar cannot disagree. |
| 12 | Branches — single tree, Prune required to remove gone refs | ~~符合~~ → ~~符合~~ → **符合** (fix/sidebar-p02-branch-rows) | `branch_tree_builder.dart:127-171`, `sidebar/gone_marking.dart`, `repo_session_repository.dart`, `sidebar/widgets/branch_tree_item.dart`, `sidebar_panel.dart`, `test/features/sidebar/branch_tree_item_test.dart`, `.../branch_tree_item_row_chrome_test.dart`, `.../branch_actions_alignment_test.dart`, `.../sidebar_panel_multi_select_test.dart` | **This row checked the wrong half twice, and passed both times.** _(fix/sidebar-p02-branch-rows)_ Even after the gone-marking round below, this row still had **no evidence about the tree rows themselves** — only about `isGone`. P02-12's own wording is 「Branches — 單一樹狀清單 … 名稱中的斜線自動摺成資料夾」, and the spec's `BRANCH_TREE` mock draws the folded leaves as **末段名稱** (`graph-lanes`, not `feature/graph-lanes`); the code printed `ref.shortName`, i.e. the full path, so the folder row and its child both spelled the prefix. Four further defects sat in the same rows, three of them P13 `MULTIKEYS` / `BRANCH_STATES` rather than P02: a `Checkbox` the selection model does not contain; single-click bound to checkout where `MULTIKEYS` says 「單擊 ＝ 只選這一項」 and `BRANCH_STATES` says 「點兩下即 checkout」; a hand-rolled `InkWell` that never received `surfaceHover`, so hover was the ~4% `ThemeData` default and invisible on a real display; and an actions button rendered only when it had a callback, so the column it should form was broken by every row without one. **Removing the checkbox is not a deletion**: `value: selected` was the *only* consumer of `selected`, so the row is routed through `GbmRow` and paints `surfaceSelected` first — the commits are ordered so no intermediate revision has invisible selection. Alignment is asserted by measuring `getRect().right` of two buttons at **different folder depths**, not by a pixel constant. **Found while doing it**: Shift-range read `_selectableBranchNames()` (git ref order) while its own doc comment claimed 「the rows as rendered」 — a real latent bug whose first visible symptom is Compare greying out, since `COMPARES` enables it only at exactly 2. The old test passed because it used `containsAll`, a superset check. **`BRANCH_STATES`' 「永遠置頂於所屬資料夾內」 was then fixed in the same branch**, on request, after this row was first written: the pin is now first among its *siblings* at every depth (`branch_tree_builder.dart`'s comparator) and applies with or without a query, instead of being hoisted above the whole tree only while filtering. The filter half stopped being a special case — HEAD is added back into the builder's input rather than prepended above the tree, which is what gives it a folder to sit in. **The reading this commits to**: where P02-14 rule 7's bare 「永遠置頂顯示」 and `BRANCH_STATES`' folder-scoped clause disagree, the specific rule wins, so a matching folder sorting before HEAD's folder renders *above* HEAD and that is conformant — `sidebar_current_branch_pin_test.dart` asserts exactly that row order, and every fixture there puts HEAD inside a folder because a root-level HEAD cannot tell the two readings apart. _Below, the previous round's finding, unchanged:_ **This row checked the wrong half and passed for it.** "Prune required to remove" was true — nothing auto-pruned — but P02's three-stage 〈遠端分支被刪除時怎麼看得到〉 had **no source of truth for stages 1 and 2 at all**, so a deleted remote branch was invisible until the user pruned it manually and thereby skipped straight to stage 3. Root cause: `RefInfo.isGone` comes solely from git's `%(upstream:track)` `[gone]`, which git only reports **after** the remote-tracking ref is already deleted locally, and `FetchOperation` deliberately does not pass `--prune`. The fix supplies the missing fact from `git remote prune --dry-run` (the existing `gbm_remote_prune_preview`), fired automatically after a successful fetch for exactly the remotes that fetch touched, and accumulated into `RepoSessionState.gonePendingByRemote`. Nothing is deleted — stage 3 stays the user's call, asserted by a test that the whole flow dispatches no prune/delete command. **Deliberately not `fetch --prune`**: P10's mockup shows `git fetch --prune origin` but the same panel then says 「標記為 gone（尚未 prune）」, contradicting itself; per the Tier 5 precedent the prose wins. |
| 13 | Tab row: 2 persistent tabs + badge, **中央區最上方** | ~~符合~~ → **符合** (feat/p03-working-copy-redesign) | `workspace_screen.dart`'s `_centreColumn()`, `workspace_tab.dart:56-61`, `test/integration/` tab-row placement group | **This row checked the tabs, never where the row was.** P02-13 and P03-9 both say 「中央區最上方」 and both mockups draw `gbm-tabs` inside the pane right of the sidebar; the implementation put `TabRow` in `WorkspaceScreen`'s outermost `Column`, so it spanned the whole window **on top of the sidebar**. The badge/2-tab half was and is conformant. The bug shipped because **all 2039 tests stayed green across the fix** — not one asserted a position, and `find.byType(TabRow)` finds it just as well in the wrong place. The three new tests therefore assert `getRect()` against a *neighbour's* rect, never a pixel constant. Both layout branches (sidebar shown/hidden) share one `TabRow` instance rather than building two that can drift. |
| 14 | Branch filter (Ctrl/Cmd+Shift+E) | ~~符合~~ → **符合** (fix/history-density-and-branch-filter) | `branch_filter.dart`, `branch_tree_builder.dart`, `sidebar_panel.dart`, `branch_filter_repository.dart` | **This row was wrong: it checked that a filter box existed, not that it obeyed P02-14's nine rules.** Six of the nine were gaps. #3 failed on spec's *own* example — `"feature/graph-lanes".contains("gl")` is false — now `matchesBranchFilter()` (substring, then initials over `/ - _ . space` plus camelCase), shared with Tags and Stashes. #4 (expand all while filtering) exposed a pre-existing bug: the panel keyed folders on the display segment while the builder keyed them on the full path, so `feature/sub` and `chore/sub` opened together; `BranchTreeFolder.folderPath` fixes it. #6 (命中/總數) and #7 (current branch pinned, never filtered out) were absent. _Rule 7's mechanism changed afterwards in fix/sidebar-p02-branch-rows_: it used to **replace** the tree row with a pinned row above the tree, which is what forced the pin outside the folder `BRANCH_STATES` wants it in; HEAD is now added back into the tree's own input, so it joins the tree and the comparator places it. The rule still holds and the row is still 符合 — but any future edit reasoning from "replacing, not joining" is reasoning about deleted code. #8 (Esc clears) and #9 (↓ enters the first result) are bound with `CallbackShortcuts` innermost so they beat `DefaultTextEditingShortcuts` without touching the tree's own Esc. #1/#2/#5 already conformed. The query now lives in `branchFilterQueryProvider`, because the History graph converges on it. **Recorded reduction**: ↓ enters the first *branch* result only. |
| 15 | Repo switcher popover | 符合 | `repo_switcher_popover.dart` | Also now the only place the repository name is shown — see the `TopBar` row below. |
| — | **`TopBar`: a row the spec never asked for** | **removed** (feat/p03-working-copy-redesign) | `top_bar.dart` (deleted), CLAUDE.md's 〈Working Copy (spec P03)〉 table | P02's component table has no row for a top bar; the implementation had grown one. Removed with all five contents rehomed and **nothing lost**: repository name → `RepoSwitcherButton` (item 15), back-to-welcome → `File → Close window` (its handler was *already* `go(welcome)`, so no new action id and no deviation from P04's `MENUS`), theme → `View → Theme`, spinner → status bar. `Refresh` was the only element with no other home — `refreshRepoHistory()` had exactly one caller in all of `lib/` — so `View → Refresh` + bare F5 was added as a **deliberate, recorded deviation** from `MENUS`. Found while doing it: repo state was *not* already on the status bar as assumed; `RepoState::describe()` is non-empty for `indexLocked` too, and nothing rendered that, so deleting blind would have silently dropped 「another git process is running」. |
| 16 | Graph column picker, Date hybrid format + ISO tooltip | 符合 | `graph_columns_selector.dart:56,61`, `graph_date_format.dart:5-26` | Graph/Message locked; relative/absolute date switch + full-ISO tooltip both present. |

**15/16 符合, 1 real rendering gap (item 6's chip-merge rule).** Item 2's original 符合 was withdrawn and re-earned by feat/p02-action-toolbar; the count is unchanged because the row was already counted as passing when it was not. **The same is true of item 13** _(feat/p03-working-copy-redesign)_: the tabs conformed, their row's placement did not, and the count never moved because the cell had only ever been asked about the tabs. Three P02 rows have now passed for the wrong half (2, 12, 13) — when re-auditing this page, check the row's *title* against the spec's own wording before reading its evidence.

---

## Page 03 — Working Copy (10 items + 7 SCOPES rows)

**Rewritten in place by feat/p03-working-copy-redesign.** Both of this
section's original claims were wrong, in opposite directions, and neither
was a footnote-sized correction — the previous text is quoted inside the
rows below rather than kept above them.

| Item / SCOPES row | Verdict | Evidence | Reason |
|---|---|---|---|
| 1, 3, 10 — per-file / column tri-state / folder tri-state checkbox | **刻意偏離（使用者裁定）** | `working_copy_board.dart`, `file_list_mode_switcher.dart`, ledger "Working Copy 重新設計" | The spec specifies a checkbox in P03-1, P03-3, P03-10 and `SCOPES` rows 1/4/5. **The user ratified removing all of them**: files move side by **dragging** (a folder row is itself draggable and carries its whole subtree), a whole column goes through `Repository → Stage all` (`Ctrl/Cmd+Alt+A`) or the context menu, and half-staged state is carried by the `+34 −12` counts — which express *more* than a tri-state box, since they distinguish "3 of 40 lines staged" from "37 of 40". **No scope lost its entry point**; each removed affordance's replacement is named in the widget's class doc. Recorded as a deviation, not as conformance and not as a gap. **A deviation moves the burden of proof onto the replacement, and the first sweep of the device tier found it unmet** (C18): the empty column drew its placeholder *instead of* the `DragTarget`, so a repository with nothing staged could not be dropped on — with every checkbox gone that meant it could not be staged at all. Nothing anywhere had ever performed a drop; the widget tests asserted only that a `Draggable` exists. Both are now covered, empty column included. |
| 7 SCOPES granularities | **符合, but this row's old evidence did not prove it** | `diff_scopes.dart`, `scoped_diff_view.dart`, `selection_touch.dart` | The old text asserted 「all 7 … implemented」 with column/folder tri-state resting on `WorkingCopySelectionState.getCheckState()` and `FileTreeNode.getCheckState()` — both of which existed, were correct, were unit-tested, and **had no caller anywhere under `lib/`**. See the new case appended to the gate-vs-surface trap below. **Both are deleted as of C18**, along with `CheckState` and `WorkingCopySelectionState`'s five other checkbox-only methods, so the row can no longer be read off a helper nobody draws. The granularities are now reachable through drag (file, multi-select, range, column, folder), the scope card (hunk-and-narrower), and a text selection (arbitrary lines), each named against the widget that draws it. **And that sentence was still wrong, in a new way** _(feat/p03-working-copy-redesign, after a user report that 「左右 diff view 沒辦法選取 line 去左或右」)_: `SCOPES` has a `how` column, and a granularity being *reachable* is not the input the spec names. Row 6's `how` is 「點 hunk 標頭列（@@ …）」 and `_HunkHeading` was a bare `Text` with no gesture on it at all — its `note` (right-click Stage hunk) was implemented and its `how` was not. Row 7's `how` is 「按住拖過多行，**或 Shift + ↑ ↓**」 and only the drag existed; Flutter's own `SelectableRegion` does not supply the other half, verified by removing the tracker's latch entirely and watching the count stay put. So every non-drag way in was missing, which is exactly what the report was. Both now exist, are covered at the widget tier, and are covered end-to-end at the device tier by `integration_test/stage_lines_flow_test.dart` — six tests: card button and text selection, in both directions, plus the heading click and Shift+↓. **Read a `how` cell as a requirement**; this row's two previous verdicts both failed by treating it as illustration. |
| Multi-select range order (P13 `MULTIKEYS`, applied to this page's two columns) | **符合** (fixed in C18) | `working_copy_board.dart`'s `_keysInRenderOrder`, `working_copy_board_test.dart` | 「範圍要用畫成的順序量」 was violated in the **default** display mode. `_keysInRenderOrder` built a `FileTree` unconditionally, on a comment asserting that both list and tree mode rendered through it; `FileListModeSwitcher.build` hands `items` straight to a `ListView.builder` in list mode and never builds a tree. Measured by pumping both modes and sorting the on-screen text by y: list paints entry order, tree paints leaf order. Shift-dragging from `lib/a.dart` to `lib/b.dart` therefore skipped a `zz.txt` painted visibly between them. The test that should have caught it pumped the default mode while asserting tree order, repeating the same wrong premise in its own comment — so it pinned the defect as correct behaviour. Now one test per mode, each mutation-checked in its own direction. |
| 2, 4 — Splitters | 符合 | `tokens.dart:529-538` | 1:1 and 46/54 match `SPLITTERS`. Unchanged, re-checked. |
| 5 — two columns, half-staged legible at a glance | 符合 | `working_copy_board.dart`, `GbmBadge` | `+N −M` per side per row; **0 draws nothing**, because 0 means "not measured" (binary, mode-only, untracked over 1 MiB), not "measured zero". |
| 6, 7 — 50-char summary hint, 72-column ruler | 符合 | `commit_message_box.dart` | Unchanged, re-checked. |
| 8 — diff area | 符合 | `working_copy_diff_pane.dart`, `scoped_diff_view.dart` | Two modes (`2 file` / `unified`). Staging is by **scope** — changes separated by ≤2 unchanged lines merge, never across a hunk — with a button at the end of each run, plus a one-shot temporary scope from an ordinary text selection. The per-line checkbox that used to serve this is gone from `DiffPage`, which is now read-only. In `2 file` mode the two sides are split by a real `GbmSplitPane` (`wc.diffSides`), added in C18: spec page 09's `SPLITTERS` table has no row for it because that table predates 變體 B's two-sided diff, so the spec is *extended* here rather than deviated from — the numbers follow `wc.columns`, the same view's other 1:1 split. |
| 9 — tab badge = deduped unstaged+staged count | 符合 | `WorkingCopyStatus.entries` | One entry per path already. |
| 10 — List/Tree toggle: ONE shared preference across Working Copy / History / Compare / Conflict window | ~~缺少 (partial)~~ → **符合** | `changed_files_panel.dart:187`, `compare_page.dart:334`, `conflict_resolve_window.dart:524`, `panel_file_diff_detail.dart:73`, `working_copy_view.dart:141` | **This row was stale, not wrong when written.** It said 「only `working_copy_view.dart:104` actually reads the provider … History, Compare, and the Conflict window never read this provider」. All four now `ref.watch(fileListViewModeProvider)`; the fix landed in an earlier round and this cell was never revisited. Re-verified by grepping every reader, not by sampling. The toggle itself is now `GbmSegmentedControl`, shared with the diff area's mode switch. |

**10/10 items accounted for**: 6 符合, 3 刻意偏離（使用者裁定, items 1/3/10's
checkbox), 1 符合-corrected (item 10's shared preference, which was stale).
Zero open gaps on this page; the deviation is not a gap and is not counted
as one.

**Deliberately absent, recorded rather than faked**: side-by-side diff. The
only occurrence of the phrase anywhere in the spec is a **fake commit message
inside a mockup**, so `side_by_side_diff.dart` / `side_by_side_diff_view.dart`
were orphaned code answering no requirement, and were deleted with their test.

---

## Page 07 — Clean/Conflict STATES (8 rows) + MSGS (4 rows)

| STATES row | Verdict | Evidence | Reason |
|---|---|---|---|
| 判定條件 | 符合 | `repo_session_repository.dart`'s `conflictActive` getter (documented in CLAUDE.md) | — |
| Banner | 符合 | `workspace_screen.dart:289-296` | `ConflictBanner` shown only when `conflictActive`. |
| Toolbar Fetch/Pull/Push disabled | ~~符合~~ → **符合** (feat/p02-action-toolbar) | `action_toolbar.dart`, `gbm_action_availability.dart:33-45` | **Same defect as P02 row 2, and for the same reason**: this row's evidence proved the three ids were gated, not that a toolbar existed to gate. It did not. The row now names the widget that renders 「三顆」, and `workspace_conflict_transition_test.dart`'s `spec P02-2 toolbar` group asserts the buttons themselves flip across the conflict↔clean transition (and back), rather than asserting the predicate that decides it. |
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
| 4 | Log drawer (draggable height, zero when collapsed, filter/copy/save) | ~~符合~~ → **符合** (fix/fetch-gone-marking-and-log-levels) | `log_drawer.dart`, `data/models/operation_record.dart` | **This row verified the controls existed, not that the filter partitioned anything.** Three defects, all reported by a user reading a real log: (a) `_filteredRecords`' warning predicate (`failed && !cancelled && !timedOut`) was a strict **subset** of its error predicate (`cancelled \|\| timedOut \|\| exitCode != 0`), so selecting *error* also showed every warning — LOGRULES' three levels were not three sets; (b) a cancelled row had no textual level at all, only a red icon, so a `for-each-ref` that `Session::refreshHistory()` had SIGTERM'd (exit **143**) read as a failure; (c) `\x1f` field separators inside `--format=%(refname)…` are invisible in a `SelectableText` and vanish entirely when copied, so a pasted command looks corrupt. Level classification is now one function (`OperationRecord.level`, checking `cancelled` **before** `exitCode` — a terminated child carries both), the row renders `levelLabel`, and `escapeControlChars()` is applied to both the row and the export. **Cancelled is warning, not error**, deliberately: a read superseded by a newer one is not a fault, and LOGRULES' own error example is a genuinely rejected `git push`. The noise's *source* — refresh cancelling refresh — ~~is untouched and tracked as #103/#104~~ **is fixed** (fix/refresh-coalescing-and-app-log-events): `Session::refreshHistory()` now folds into `RefreshCoalescer` instead of cancelling, so no `cancelled` record is produced at all in routine operation. `HistoryRefreshApiTest.ABurstOfRefreshesTerminatesNoGitProcess` reproduced the symptom deterministically first — 7 records at `exitCode: 143`. |
| 5 | Error DIALOG window (Esc closes, next-action button, duplicate→counter) | **缺少 — confirmed** | `workspace_screen.dart:297-316` | Errors surface as an inline, persistent `GbmWarningBanner` (`if (session.lastError case final error? when error.codeName != 'Conflict')`), not a modal dialog window. This does satisfy the spec's *intent* ("no auto-dismissing toast — must stay until the user has seen it") but not the *mechanism* — there is no dialog with a "what failed / why / raw git output (collapsed, monospace)" 3-section layout, no primary-button-as-next-action, and no repeated-error counter (searched for and found no such field). Classification **(i)** — the underlying `GitError` model already carries the needed fields (per `git_error.dart`); this is a missing dialog widget, not a missing data path. |

**Additional finding — LOGRULES 記什麼, second half:** the row asks for
「每一次實際執行的 git 指令原文、工作目錄、結束代碼、耗時；**以及應用層事件
（開啟 repo、切分支、prune 掉哪些 ref）**」, and only the first half existed —
`OperationRecord` is git-invocation-shaped and has no way to say "the user
opened this repository". Page 10's own mockup draws one of the missing kind as
a warning row: 「origin/graph-lanes 已不存在於遠端，標記為 gone（尚未 prune）」.
**Fixed** (fix/refresh-coalescing-and-app-log-events): `GbmLogEntry` is now the
sealed supertype of `OperationRecord` and a new `AppLogEntry`, and all four
named events are emitted (`AppLogEvents`). **The gap was never a capi gap** —
`src/core/base/Logging.{h,cpp}` has sinks and no storage at all, so the whole
log lives in `RepoSessionState.operationLog` and the fix is Dart-only; issue
#105's "需要 capi 改動" premise is corrected there. Note `LOGRULES` 保留 caps
the *log*, not each kind separately, so app events and git records share the
same 500 slots.

**Additional finding — LOGRULES retention number (260820 修訂):** originally logged as a mismatch — spec said "記憶體中保留最近 2,000 筆" while the code capped `operationLog` at 500. **P16's REVISIONS reverses the direction**: the default is now 500 with Preferences able to raise it to 2,000 ("預設 500，Preferences 可調到 2,000"), which is what Tier 0h already built (the cap reads `AppPreferences.logMemoryLimit`). **符合** — no longer a gap; the spec moved to the code, not the other way round.

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
| COMPARES 1: Branch ↔ Branch (multi-select → right-click → Compare) | ~~**缺少**~~ → **符合** (Tier 3 / #55) | `sidebar_panel.dart` `_multiBranchMenuItems()` → `sidebar/widgets/multi_branch_menu_items.dart`; second entry point `GbmActionId.repositoryCompare` | **This row was partly out of date when written**: the *second* entry point for a branch↔branch compare — `Repository → Compare…`, `Ctrl/Cmd+Shift+C` — already existed and worked. Only spec's literal reading (「同時選兩個分支 → 右鍵 Compare」) was missing, and it needed sidebar branch multi-select, not History's. **Fixed** on the user's explicit "照字面做" ruling: `branchSelectionProvider` gives the branch tree the same `ListSelection` model History uses, and `MULTIBRANCHMENU` gained a `Compare` item that opens a tab with **both** sides filled. It is disabled with a stated reason for any count other than two, since a comparison has exactly two ends. |
| COMPARES 2: Branch ↔ Tag | 符合 | `sidebar_panel.dart:201-207` | `_compareTag()`. |
| COMPARES 3: Commit ↔ Commit (Ctrl/Cmd-click multi-select, merge-base + 2-dot/3-dot toggle) | ~~**缺少 (entry point)**~~ → **符合** (Tier 2+3 / #54 + #55) | `commit_graph_view.dart` (MULTIKEYS gestures) → `commit_menu_items.dart`'s `Compare with…`; engine unchanged in `compare_page.dart:262-321` | The engine half was already right, as this row said. The entry point now exists: Ctrl/Cmd-click two commit rows, right-click either one, `Compare with…`. **left = the older side, right = the newer**, taken from the snapshot's own order rather than click order — the same direction convention `_compareStash()` set by always putting the stash on the right. A single selection still opens the tab with only `left` filled and leaves the right to `CompareRefPicker`, so the one-commit and two-commit cases share one item rather than two. |
| COMPARES 4: Stash ↔ any ref, stash forced to the right side | 符合 | `sidebar_panel.dart:175-181`, `compare_page.dart:31-61` | `_compareStash()` places stash OID correctly. |
| COMPARES 5: any ref ↔ Working copy, checkout-to-overwrite is the only writable path | 符合 | `compare_page.dart:143-175,342-349,536-600` | Confirmed as the sole writable comparison, with a confirmation dialog before `restorePaths()`. |

**Now 8/9 符合** (CHANGEVIEWS 2's inline stash expand is the one gap left).
The prediction below held exactly: multi-select plus 05-E's `Compare with…`
closed COMPARES 1 and COMPARES 3 together, in one branch. The one thing it
got wrong is *which* multi-select COMPARES 1 needed — the branch tree's, not
History's — which is why Tier 3 had to build both. Original text: **6/9
符合, 3 gaps that are all the SAME underlying cause**: History has no
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
   drifted from spec because nothing enforces they match it. *(Closed after
   Tier 3: every group is now parity-asserted with no `skip`. The catalog is
   still imported only by `test/`, which is the point — it is the acceptance
   baseline, and eight render sites are now pure functions checked against
   it for exact label equality.)*
2. **History has no multi-select** — this alone explains 05-E's missing
   `Compare with…`/`Merge into current`, and both Compare-page entry-point
   gaps (COMPARES 1 and 3). *(Closed in Tier 2+3. One correction to the
   diagnosis: COMPARES 1 needed the **sidebar branch tree's** multi-select,
   not History's, so the root cause was one mechanism short of what this
   line claims — both were built.)*
3. ~~**F-A**: `tab_row.dart`'s 18-item overflow menu is a spec-unsanctioned
   third entry surface for otherwise-legitimate features.~~ **Largely fixed
   (Tier 6b / #62)** — down to 2 items plus 1 button, all three of which are
   things spec has not assigned a home to (#84/#85/#86). See F-A above.
4. **F-B**: the Log drawer and Operation Log dialog are two competing
   implementations of the same spec concept — and as of 260820 this is no
   longer a judgement call: P16's REVISIONS deletes the dialog from the
   spec by name and keeps the drawer (see F-B above, and #61).
5. Preferences (page 11) has 5 gaps that are all "field exists in the
   data model / backing repository, but no UI surfaces it yet" — the
   cheapest category to close.

See `docs/reports/code-review-2026-08.md` for the architectural review
that follows from these patterns (Phase 2).
