import '../../data/models/ref_snapshot.dart';

/// Whether [ref] should render with spec page 02's "gone" treatment, given
/// the set of remote-tracking refs a `git remote prune --dry-run` says no
/// longer exist upstream ([RepoSessionState.gonePendingRefs]).
///
/// Two sources, deliberately OR'd rather than kept apart:
///
/// * [RefInfo.isGone] -- git's own `%(upstream:track)` reporting `[gone]`,
///   which only happens *after* the remote-tracking ref has been deleted
///   locally (spec's stage 3, an explicit Remote -> Prune remote branches).
/// * [gonePendingRefs] -- the dry-run's answer, which is how stages 1 and 2
///   can mark a row without deleting anything.
///
/// A row therefore stays marked continuously across a real prune: the
/// pending entry is dropped as `isGone` starts reporting true, and callers
/// never have to know which source is currently supplying the truth.
///
/// The two row shapes carry the ref name in different fields, which is the
/// part that is easy to get wrong:
///
/// * A **local branch** is matched on [RefInfo.upstream] -- git's
///   `%(upstream)`, the tracked ref's *full* name.
/// * A **remote-only** row is matched on [RefInfo.fullName], never on
///   `shortName`: `mergeLocalAndRemoteBranches` strips the `<remote>/`
///   prefix off a remote-only leaf's `shortName` for tree grouping, so
///   `origin/vanished` arrives here as `vanished`.
///
/// Both are full ref names, matching what
/// `RemotePrunePreviewEntry.fullRefName` normalises to.
///
/// [remoteCounterpart] is the local branch's counterpart resolved by the
/// caller -- `RemoteBranchIndex.counterpartOf`, which returns
/// [RefInfo.upstream] verbatim when git recorded one and falls back to an
/// unambiguous same-named remote ref when it did not. It is required rather
/// than defaulted because a caller that forgets it would silently get the
/// old behaviour back, and the old behaviour is the bug: this function used
/// to read `ref.upstream` itself and return false the moment it was empty,
/// so a branch pushed with `git push origin HEAD` (no tracking config at
/// all) could never be marked -- while after `mergeLocalAndRemoteBranches`
/// claims its same-named remote row, this row is the only one left to carry
/// the mark. Ignored for a remote-only row, which is matched on its own
/// `fullName`.
///
/// Note the resolution never consults `hasTrackingInfo`: that mirrors
/// `%(upstream:track)`, which is an *empty string* for a branch exactly in
/// sync with its upstream, so it is false for the single most common case
/// of "does track a remote".
bool isEffectivelyGone(
  RefInfo ref,
  Set<String> gonePendingRefs, {
  required String remoteCounterpart,
}) {
  if (ref.isGone) return true;
  if (gonePendingRefs.isEmpty) return false;
  if (ref.kind == RefKind.remoteBranch) {
    return gonePendingRefs.contains(ref.fullName);
  }
  if (remoteCounterpart.isEmpty) return false;
  return gonePendingRefs.contains(remoteCounterpart);
}

/// How many rows in [branches] the pending set actually marks -- spec page
/// 02's "在區塊標題右邊顯示待清理數量".
///
/// An intersection with the rows on screen, **not** `gonePendingRefs.length`.
/// The set outlives the snapshot: pruning in a terminal, or removing a whole
/// remote, deletes the refs while `gonePendingByRemote` still lists them, and
/// a raw count would then claim "3 pending" over a tree with nothing marked.
///
/// Rows git already reports as [RefInfo.isGone] are excluded: their
/// remote-tracking ref is already deleted, so there is nothing left for
/// Prune to clean up and counting them would never reach zero.
///
/// [remoteCounterpartOf] resolves one row's counterpart -- pass
/// `RemoteBranchIndex.counterpartOf` as a tear-off so the whole list costs
/// one index build rather than a scan per row. A function rather than the
/// index itself only so this file does not have to import
/// `branch_tree_builder.dart`, which already imports the file that imports
/// this one.
int gonePendingCount(
  List<RefInfo> branches,
  Set<String> gonePendingRefs,
  String Function(RefInfo ref) remoteCounterpartOf,
) {
  if (gonePendingRefs.isEmpty) return 0;
  return branches
      .where(
        (RefInfo b) =>
            !b.isGone &&
            isEffectivelyGone(
              b,
              gonePendingRefs,
              remoteCounterpart: remoteCounterpartOf(b),
            ),
      )
      .length;
}
