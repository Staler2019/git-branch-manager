import 'ref_snapshot.dart';

/// Remote branches indexed by branch name -- the part after `<remote>/` --
/// so that asking "what is this local branch's remote counterpart?" is O(1)
/// per row instead of a scan.
///
/// Built once per render pass and thrown away; it holds no state and is never
/// put into [RepoSessionState]. That last part is deliberate: a freshly built
/// `Map` has no value equality, so threading one through `WorkspaceScreen`'s
/// watched record would make the record unequal on every publish and restore
/// the menu-bar rebuild storm (CLAUDE.md, "History 捲動卡頓").
///
/// A name carried by **two** remotes is left out of the index entirely rather
/// than resolved to whichever came first -- see [counterpartOf].
class RemoteBranchIndex {
  const RemoteBranchIndex._(this._unambiguousByBranchName);

  factory RemoteBranchIndex.from(List<RefInfo> remoteBranches) {
    final Map<String, String> byName = <String, String>{};
    final Set<String> ambiguous = <String>{};
    for (final RefInfo remote in remoteBranches) {
      // origin/HEAD is not a branch to show, check out or claim.
      if (remote.isSymbolic) continue;
      final String branchName = remoteBranchParts(remote.fullName).$2;
      if (byName.containsKey(branchName)) {
        ambiguous.add(branchName);
        continue;
      }
      byName[branchName] = remote.fullName;
    }
    for (final String name in ambiguous) {
      byName.remove(name);
    }
    return RemoteBranchIndex._(byName);
  }

  /// Branch name -> that branch's one remote ref, ambiguous names removed.
  final Map<String, String> _unambiguousByBranchName;

  /// The full name of [local]'s counterpart, or the empty string when it has
  /// none.
  ///
  /// Two rules, in order:
  ///
  /// 1. **An explicit upstream wins.** [RefInfo.upstream] is git's
  ///    `%(upstream)` -- the tracked ref's *full* name
  ///    (`refs/remotes/origin/main`, confirmed against real `git for-each-ref`
  ///    output, not `%(upstream:short)`). It is returned whether or not that
  ///    ref is still present, because a tracked upstream that has vanished is
  ///    exactly the gone case callers need to see.
  /// 2. **Otherwise, an unambiguous same-named remote ref.** `git push origin
  ///    HEAD` (no `-u`) and most PR flows write no `branch.NAME.merge` config
  ///    at all, so `%(upstream)` comes back blank while the remote-tracking
  ///    ref exists all the same. With nothing but the name linking the two,
  ///    matching on the tracking *config* alone let that remote ref through as
  ///    a second row for a branch that already had one.
  ///
  /// Ambiguity claims nothing. With both `origin/main` and `upstream/main`
  /// present, nothing says which one an untracked local `main` means, and
  /// guessing would hide a real branch.
  String counterpartOf(RefInfo local) {
    if (local.upstream.isNotEmpty) {
      return local.upstream;
    }
    return _unambiguousByBranchName[local.shortName] ?? '';
  }
}

/// [RemoteBranchIndex.counterpartOf] for a caller with one branch to resolve
/// (the current branch, a selected row) rather than a list to walk.
///
/// O(remoteBranches) because it builds the index to answer once. A caller
/// resolving *every* row must build a [RemoteBranchIndex] instead and reuse
/// it -- calling this per row is quadratic, which measured 14ms per merge at
/// 500 local + 500 remote branches against 0.1ms for the indexed form.
String remoteCounterpartOf(RefInfo local, List<RefInfo> remoteBranches) =>
    RemoteBranchIndex.from(remoteBranches).counterpartOf(local);
