import '../../../data/models/ref_snapshot.dart';

/// A single ref chip's render data for one commit row -- what
/// [refChipsForCommit] hands to [CommitRow] instead of a bare [RefInfo], so
/// the merge/divergence rule below (spec page 02: "local 與 origin 在同一個
/// commit 時只出一個 chip，尾端加一個雲朵圖示…虛線外框＝只有在分歧時才會
/// 出現") is computed once here rather than re-derived at render time.
class RefChipData {
  const RefChipData({
    required this.label,
    required this.kind,
    this.isCurrent = false,
    this.showCloudIcon = false,
    this.isDashed = false,
  });

  /// What the chip prints. For the HEAD chip this is already the composed
  /// `HEAD → <branch>` (spec page 02's `CHIP_HEAD`, `spec_logic.js:439`),
  /// not the bare branch name -- composing it here rather than at render
  /// time is the same rule this class's doc comment states for the merge
  /// and divergence flags.
  final String label;
  final RefKind kind;

  /// True for the branch HEAD currently points at, and for the standalone
  /// `HEAD` chip a detached HEAD gets. Unrelated to
  /// [showCloudIcon]/[isDashed], which are purely about local/remote sync:
  /// spec's own prose separates them too, defining the glow-without-cloud
  /// chip as "目前 HEAD，且遠端不在這裡" -- so HEAD *with* the remote here is
  /// the glow and the cloud together, not a third style.
  final bool isCurrent;

  /// A local branch chip whose upstream remote branch points at the same
  /// commit: the remote branch's own chip is suppressed and this flag adds
  /// a cloud icon to the local chip instead, per spec's "同一件事寫兩遍只
  /// 是佔寬度".
  final bool showCloudIcon;

  /// A remote branch chip whose tracking local branch exists but points at
  /// a *different* commit (diverged) -- spec's dashed-outline chip marking
  /// where the remote actually sits. Never true for a local branch chip, and
  /// never true for a remote branch with no local branch tracking it at all
  /// (that's the sidebar's distinct "Remote only" state, not this rule).
  final bool isDashed;
}

/// Groups refs pointing to a single commit into chip data, applying spec
/// page 02's local/origin merge rule: a local branch synced with its
/// upstream renders as one chip with a cloud icon instead of two chips, and
/// a diverged upstream renders as its own dashed chip on the commit it
/// actually points at.
///
/// HEAD is one of these chips and has no other representation in the row --
/// the standalone `HEAD` text label that used to sit beside the graph column
/// is gone, because the mockup draws HEAD as a chip and only as a chip
/// (`spec_logic.js:439`, and the annotated panel at `spec_raw.html:1392`).
/// Two consequences follow, both deliberate:
///
///  * The HEAD chip is returned **first**. `_RefChipStrip` clips left-aligned
///    at the Refs column's width, so position decides which chips survive a
///    narrow column, and HEAD is the one thing in the row that says where you
///    are. Without this the surviving chip would be whatever order
///    `git for-each-ref` happened to return.
///  * A detached HEAD gets a standalone chip labelled `HEAD`, since no
///    [RefInfo] carries `isHead` in that state. Deleting the text label
///    without this would replace a visible state with an invisible hole.
List<RefChipData> refChipsForCommit(RefSnapshot refs, String targetOid) {
  // fullName -> RefInfo, for resolving a local branch's `upstream` (which is
  // the tracked ref's *full* name, confirmed against real `git for-each-ref`
  // output -- see branch_tree_builder.dart's mergeLocalAndRemoteBranches(),
  // whose upstream-matching semantics this reuses) back to the remote
  // branch it names.
  final Map<String, RefInfo> remoteByFullName = <String, RefInfo>{
    for (final RefInfo r in refs.refs)
      if (r.kind == RefKind.remoteBranch && !r.isSymbolic) r.fullName: r,
  };

  // Every local branch with a resolvable upstream, keyed by that upstream's
  // fullName -- used below to tell a "diverged, still tracked" remote chip
  // apart from a true remote-only ref with no local branch tracking it.
  final Map<String, RefInfo> localByUpstream = <String, RefInfo>{
    for (final RefInfo r in refs.refs)
      if (r.kind == RefKind.localBranch && r.upstream.isNotEmpty) r.upstream: r,
  };

  final List<RefInfo> refsAtRow = refs.refs
      .where((RefInfo r) => r.target == targetOid)
      .toList(growable: false);

  // A local branch at this row is "synced" when its upstream remote branch
  // also points here -- that remote's chip gets suppressed below in favor
  // of a cloud icon on the local chip.
  final Set<String> syncedRemoteFullNames = <String>{};
  for (final RefInfo ref in refsAtRow) {
    if (ref.kind != RefKind.localBranch || ref.upstream.isEmpty) continue;
    final RefInfo? remote = remoteByFullName[ref.upstream];
    if (remote != null && remote.target == targetOid) {
      syncedRemoteFullNames.add(remote.fullName);
    }
  }

  final List<RefChipData> chips = <RefChipData>[];
  for (final RefInfo ref in refsAtRow) {
    if (ref.kind == RefKind.remoteBranch &&
        syncedRemoteFullNames.contains(ref.fullName)) {
      continue; // Merged into its tracking local branch's cloud chip.
    }

    final bool showCloudIcon =
        ref.kind == RefKind.localBranch &&
        syncedRemoteFullNames.contains(ref.upstream);
    final bool isDashed =
        ref.kind == RefKind.remoteBranch &&
        localByUpstream.containsKey(ref.fullName);

    chips.add(
      RefChipData(
        // Spec's own label for this chip is `HEAD → main`, not `main` with a
        // different fill: the arrow form is what `GRAPH_ROWS` writes.
        label: ref.isHead ? 'HEAD → ${ref.shortName}' : ref.shortName,
        kind: ref.kind,
        isCurrent: ref.isHead,
        showCloudIcon: showCloudIcon,
        isDashed: isDashed,
      ),
    );
  }

  // Detached HEAD points at a commit rather than a branch, so nothing in
  // `refs.refs` reports `isHead` and the loop above produced no HEAD chip.
  // git's own `HEAD` label is what this mirrors. Typed as a local branch
  // because that is the kind `refChipColorsFor` gives the current-branch
  // fill to; it is a styling channel, not a claim that a branch exists.
  if (refs.head.kind == HeadKind.detached && refs.head.target == targetOid) {
    chips.insert(
      0,
      const RefChipData(
        label: 'HEAD',
        kind: RefKind.localBranch,
        isCurrent: true,
      ),
    );
    return chips;
  }

  final int headIndex = chips.indexWhere((RefChipData c) => c.isCurrent);
  if (headIndex > 0) chips.insert(0, chips.removeAt(headIndex));
  return chips;
}
