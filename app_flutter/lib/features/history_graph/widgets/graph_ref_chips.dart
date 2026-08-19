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

  final String label;
  final RefKind kind;

  /// True for the branch HEAD currently points at -- unrelated to
  /// [showCloudIcon]/[isDashed], which are purely about local/remote sync.
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
        label: ref.shortName,
        kind: ref.kind,
        isCurrent: ref.isHead,
        showCloudIcon: showCloudIcon,
        isDashed: isDashed,
      ),
    );
  }
  return chips;
}
