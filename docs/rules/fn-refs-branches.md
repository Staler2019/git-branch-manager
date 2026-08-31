# Refs, branches and remote counterparts

Pin prefix `REF-`. Format: [README.md](README.md).

Every *comparison* in this codebase is on the **full** ref name; short names are display
only. Normalise with `fullRemoteRefName()` / `shortRemoteRefName()` at the boundary.

## [REF-upstream-is-full-name] `RefInfo.upstream` is the full ref name

- **Rule**: `refs/remotes/origin/x`, from `%(upstream)` not `%(upstream:short)`.
- **Consequence**: splitting on the first slash yields `"refs"`.
- **Do**: use `remoteBranchParts()`. That was **#74**, now closed.

## [REF-remote-name-is-not-local-name] A branch's name on the remote is not its local name

- **Consequence**: `feature/x` tracking `origin/renamed-x` said 「Also delete renamed-x」 and
  ran `git push origin --delete feature/x` — it printed the upstream's branch name while
  dispatching the local one.
- **Do**: resolve both from the counterpart in one place (`deleteBranchRemoteTarget()`).
- **Do**: **every fixture in which the two names coincide is blind to this**, which is
  nearly all of them.
- **Evidence**: surfaced only once the sidebar's prune entries were removed and the delete
  dialog became the only path to a remote delete.

## [REF-remote-side-not-upstream] 「Does this local branch have a remote side?」 is not answered by `upstream`

- **Rule**: `git push origin HEAD` and most PR flows leave `branch.<name>.merge` empty while
  putting the branch on the remote, so a same-named remote ref is a real counterpart with no
  tracking config behind it.
- **Consequence**: `mergeLocalAndRemoteBranches()` matched on the config alone and drew such
  a branch **twice** — a duplicate leaf for a nested name (a `List`), or losing the local row
  entirely for a root name (a `Map`, last write wins). That is the whole of the reported
  「剛進來灰雲、fetch 後黃雲斜線」 symptom; prune was innocent.
- **Do**: read it through `RemoteBranchIndex` (`data/models/remote_counterpart.dart`), never
  by re-deriving the match. Explicit tracking first, then an *unambiguous* same-name match,
  and **nothing at all when two remotes share the name** — a counterpart cannot be inferred
  from a name, and guessing wrong is worse than not guessing.
- **Do**: it is an index rather than a scan because the per-branch scan measured **14ms at
  500×500** and runs every sidebar build.
- **Evidence**: ledger: prune 壞掉的表象下有六個缺陷

## [REF-has-tracking-info-is-not-has-upstream] `RefInfo.hasTrackingInfo` does not mean "has an upstream"

- **Rule**: it mirrors `%(upstream:track)`, which is *empty* for a branch exactly in sync.
- **Do**: ask "does this track a remote?" with `upstream`; reserve `hasTrackingInfo` for
  "did git report ahead/behind numbers".

## [REF-ahead-meaningless-without-upstream] `RefInfo.ahead` means nothing when `upstream` is empty

- **Consequence**: a branch that never had one reports `0`, which rendered literally claims
  the opposite of the truth.

## [REF-head-has-no-sidebar-privilege] The current branch has no sorting or filtering privilege in the sidebar

- **Rule**: **user-ratified deviation — do not "fix" it back.** `BRANCH_STATES`
  (「永遠置頂於所屬資料夾內，且不受 filter 影響」), P02-14 rule 7
  (「即使不符合條件也不會被濾掉」) and `BRANCH_TREE`'s mock (which draws `main` above the
  folders at its own depth) all specify otherwise, and all three were implemented and
  passing before the user ruled against them.
- **Consequence**: a pin makes the first row of every level jump around depending on where
  HEAD happens to be, and an exempt row makes a filtered sidebar draw a folder with no
  matching child in it.
- **Rule**: what is left is `_compareTreeNodes`' plain 「folders (alphabetically) → leaves
  (alphabetically)」. Folders-before-leaves stays because it is tree *structure*, not branch
  priority — the distinction the user drew.
- **Rule**: **the visual half of `BRANCH_STATES` survives untouched** (bold name + full-row
  `surfaceSelected`) and is now the only thing marking HEAD, which is what keeps
  `branch_selection_rules.dart`'s 「HEAD is never bulk-selectable」 rationale intact.
- **Do**: 「Where am I」 is answered by `sidebar_panel.dart` seeding `_expandedFolders` with
  `ancestorFolderPaths(refs.head.branchName)` — on mount *and* on every checkout through one
  `_seededExpansionForHead` gate, `addAll`-only so nothing the user collapsed is forced open.
- **Evidence**: ledger: 側邊欄目前分支不再置頂

## [REF-origin-head-is-a-symref] `refs/remotes/<remote>/HEAD` is a symref, not a branch

- **Rule**: `RefInfo.isSymbolic` is the only thing that says so. It is populated from
  `%(symref)`, the ninth and last field of `RefStore::load()`'s `for-each-ref` format —
  appended at the end precisely so the sink's `fields.size() > N` bounds keep the other eight
  where they were.
- **Consequence**: while that field was missing, `isSymbolic` sat at its `= false` default,
  nothing in `src/` ever assigned it, and **three Dart filters written to drop the ref were
  dead code** — the sidebar drew `origin/HEAD` as a selectable, checkout-able branch row
  called `HEAD` (its shortName rewrites to the bare `HEAD`, and no local branch claims it, so
  `mergeLocalAndRemoteBranches` emits it as remote-only).
- **Note**: `BranchOps.cpp`'s `/HEAD` suffix check is **not** a second source — it reads raw
  `for-each-ref --contains` output, never a `RefInfo`.
- **Note**: **not every reader of the flag is a render site.** `graph_ref_chips.dart`'s
  `!r.isSymbolic` guards the upstream-resolution lookup map only; its chip list comes from an
  unfiltered `refsAtRow`, so History still draws an `origin/HEAD` chip — **user-ratified: it
  stays.** The flag was false for every release before this one, so leaving the chip is zero
  regression while removing it would be a fresh behaviour change nobody asked for.
- **Evidence**: ledger: 側邊欄那一列 `HEAD`

## [REF-is-gone-only-after-prune] `RefInfo.isGone` can only be true after a prune

- **Rule**: git reports `[gone]` only once the remote-tracking ref is already deleted. Gone
  *marking* comes from `git remote prune --dry-run`, deliberately not from `fetch --prune`.
- **Consequence**: **gating anything on `isGone` alone leaves it wrong for the entire window
  between the fetch that discovers the deletion and the prune that records it** — which is
  where the user actually is when they look. The delete dialog's checkbox shipped that way.
- **Do**: read gone-ness through `features/sidebar/gone_marking.dart`'s
  `isEffectivelyGone()`, never `isGone` or `gonePendingRefs` directly. It now takes a
  `remoteCounterpart`, because a branch with no tracking config still has a remote side to be
  gone from ([REF-remote-side-not-upstream]).

## [REF-fetch-auto-prunes] `fetch` prunes unclaimed refs in the background, and no menu says 「prune」

- **Rule**: **user-ratified, do not "fix" it back.** P02-12's three stages (mark → badge →
  explicit Prune) are superseded: a successful fetch auto-prunes exactly the refs the
  `--dry-run` preview calls gone **and** that no local branch claims. A claimed one keeps its
  cloud-off marking, because the user can still repush it. `Remote → Prune remote branches`
  survives as the manual fallback.
- **Do**: **only *fetch-triggered* previews may auto-prune** (`_autoPrunePreviewsInFlight`).
  The Prune dialog asks for a preview of its own, and an undiscriminated rule deletes the
  refs it is listing out from under the user.
- **Do**: an automatic prune's failure is kept out of `lastError` — nobody asked for it — but
  still reaches the operation log. Not notifying is not the same as not recording.
- **Rule**: **P11 item 9's 「可選同時 prune」 switch is deleted, not merely unwired.** The
  behaviour above is describable by no wording of an on/off switch (off would not stop it; on
  would promise the full `--prune` the ruling does not do), so `AppPreferences.autoFetchPrune`
  is gone from the model, the dialog and storage. Re-adding it re-creates a control that
  lies; `AppPreferences`' own doc rule is the precedent — absent beats present-and-ignored.

## [REF-prune-preview-ref-is-short] `RemotePrunePreviewEntry.ref` is a short name

- **Rule**: while `upstream` and a remote row's `fullName` are full.
- **Do**: normalise through `fullRemoteRefName()`.

## [REF-branch-m-keeps-upstream] `git branch -m` keeps `branch.<name>.remote/.merge`

- **Do**: a local-only rename needs an explicit `git branch --unset-upstream`.

## [REF-delete-remotes-takes-short-name] `git branch --delete --remotes` takes the short name only

- **Rule**: measured — `refs/remotes/origin/feat/x` is 「remote-tracking branch not found」,
  exit 1, while `origin/feat/x` deletes it.
- **Consequence**: `RemoteOps.h`'s contract said short all along; two Dart call sites sent
  `fullName`/`upstream` anyway, and `RemotePrunePreviewEntry`'s own comment knowingly
  documented both forms as coexisting.
- **Do**: normalise with `shortRemoteRefName()` at the boundary — but keep *comparisons* on
  the full form (`fullRemoteRefName()`).
