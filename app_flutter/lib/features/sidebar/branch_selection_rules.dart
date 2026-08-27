import '../../data/models/list_selection.dart';
import '../../data/models/ref_snapshot.dart';
import 'branch_tree_builder.dart';
import 'gone_marking.dart';

/// The pure rules behind spec page 13's branch selection: which rows a bulk
/// selection may contain, which right-click menu a row gets, and what a
/// selection becomes when the branches under it stop existing.
///
/// Free functions rather than `_SidebarPanelState` methods so they can be
/// exercised without a widget, and so every call site reads the same rule --
/// the panel had four separate places asking "is this row selectable" in
/// slightly different words.

/// HEAD is deliberately never bulk-selectable.
///
/// Visually this is now the load-bearing half: the current branch already
/// paints `surfaceSelected` permanently (BRANCH_STATES), so if it could also
/// be *selected* the two states would draw identically and be impossible to
/// tell apart. It matches git, too -- the current branch cannot be deleted.
bool isBulkSelectable(RefInfo branch) => !branch.isHead;

/// Whether right-clicking [branch] should open `MULTIBRANCHMENU` rather
/// than the per-row 05-B menu: it must be a bulk-selectable local row that
/// is *already* part of a selection of more than one.
bool isInMultiSelection(
  RefInfo branch, {
  required bool isRemoteOnly,
  required ListSelection<String> selection,
}) =>
    !isRemoteOnly &&
    isBulkSelectable(branch) &&
    selection.length > 1 &&
    selection.items.contains(branch.shortName);

/// Whether "Select all branches with a gone upstream" should take [branch].
///
/// [gonePendingRefs] is threaded in rather than read from the session here
/// so this stays a pure predicate over one row -- a branch whose upstream
/// the dry-run preview reports as gone belongs in the bulk-delete selection
/// exactly as much as one git already reports `[gone]` for.
///
/// `RefKind` is not widened: a remote-only row is not a local branch and
/// "delete gone branches" deletes local branches. [isEffectivelyGone] would
/// return true for one, so the `!branch.isHead` / `worktreePath.isEmpty`
/// guards are joined by the kind check here rather than at each call site.
///
/// [remoteCounterpart] is threaded through to [isEffectivelyGone] for the
/// same reason it exists there: a branch pushed without `-u` has no tracking
/// config, so resolving gone-ness from `upstream` alone left exactly the
/// rows this button is for out of the selection.
bool isGoneAndBulkSelectable(
  RefInfo branch,
  Set<String> gonePendingRefs, {
  required String remoteCounterpart,
}) =>
    isEffectivelyGone(
      branch,
      gonePendingRefs,
      remoteCounterpart: remoteCounterpart,
    ) &&
    branch.kind == RefKind.localBranch &&
    !branch.isHead &&
    branch.worktreePath.isEmpty;

/// Every branch name a selection may legitimately still hold: the merged
/// local + remote-only list, by short name.
///
/// The same keys the selection uses, which is why it is the merged list and
/// not `refs.localBranches` -- a remote-only row is selectable too.
Set<String> liveBranchNames(RefSnapshot refs) => mergeLocalAndRemoteBranches(
  refs.localBranches,
  refs.remoteBranches,
).map((RefInfo b) => b.shortName).toSet();

/// [current] with names that no longer exist dropped, or null when every
/// selected name is still live.
///
/// The null return is not a convenience: the caller writes the result into a
/// provider from a post-frame callback, so returning an equal-but-new value
/// on every build would rebuild forever.
///
/// [names] is the *short* names of the merged local + remote-only list, the
/// same keys the selection itself uses.
ListSelection<String>? prunedSelection(
  ListSelection<String> current,
  Set<String> names,
) {
  final List<String> survivors = <String>[
    for (final String name in current.items)
      if (names.contains(name)) name,
  ];
  if (survivors.length == current.length) return null;
  final String? anchor = current.anchor;
  return ListSelection<String>(
    items: survivors,
    anchor: survivors.isEmpty
        ? null
        : (anchor != null && names.contains(anchor) ? anchor : survivors.last),
  );
}

/// `MULTIKEYS`' Shift+↑/↓ applied to [current], or null when there is
/// nothing to extend (no rows, no anchor, or an anchor that is no longer in
/// the list).
///
/// The edge that moves is the one *opposite* the anchor, which is what makes
/// Shift+↑ after Shift+↓ shrink the range back instead of growing it the
/// other way.
///
/// [all] must be the rows in the order they are **painted**, not the order
/// the refs happen to arrive in -- the tree sorts folders before leaves and
/// pins the current branch, so the two disagree the moment a folder exists.
ListSelection<String>? extendedSelection(
  ListSelection<String> current,
  List<String> all,
  int delta,
) {
  final String? anchor = current.anchor;
  if (all.isEmpty || anchor == null) return null;
  final int anchorIndex = all.indexOf(anchor);
  if (anchorIndex < 0) return null;
  final List<int> indices = <int>[
    for (final String name in current.items)
      if (all.contains(name)) all.indexOf(name),
  ]..sort();
  if (indices.isEmpty) return null;
  final int movingEdge = indices.first == anchorIndex
      ? indices.last
      : indices.first;
  final int next = (movingEdge + delta).clamp(0, all.length - 1);
  return current.range(all[next], all);
}
