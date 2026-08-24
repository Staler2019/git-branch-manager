import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/ref_snapshot.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../widgets/prompt_text_dialog.dart';
import 'branch_tree_builder.dart';

/// Everything a single branch row, remote-only row or folder row can do to
/// one ref: the 05-B / 05-C / 05-J context-menu actions plus New branch.
///
/// Sibling of [BranchBulkActions], and split from it along what the spec
/// splits: that one implements page 13's `MULTIBRANCHMENU` over a selection,
/// this one implements the per-row menus. Neither holds state -- both are
/// built from `ref` and the identity at the call site.
///
/// Expand/collapse is **not** here: `_expandedFolders` is the panel's own
/// `setState` and moving it would put tree state in two places.
class BranchRowActions {
  const BranchRowActions({required this.ref, required this.identity});

  final WidgetRef ref;
  final RepoIdentity identity;

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(identity).notifier);

  String get _repoId => Uri.encodeComponent(identity.workDir);

  Future<void> createBranch(BuildContext context) async {
    final String? name = await promptText(
      context,
      title: 'New Branch',
      label: 'Branch name',
    );
    if (name == null || !context.mounted) return;
    _session.createBranch(name: name);
  }

  Future<void> createBranchFrom(BuildContext context, RefInfo branch) async {
    final String? name = await promptText(
      context,
      title: 'New Branch from ${branch.shortName}',
      label: 'Branch name',
    );
    if (name == null || !context.mounted) return;
    _session.createBranch(name: name, startPoint: branch.shortName);
  }

  void openMergeDialog(BuildContext context) =>
      context.push(RoutePaths.mergeDialogFor(_repoId));

  /// 05-B's "Rename branch". Unlike the Branch menu and F2, this names the
  /// clicked branch rather than letting the dialog fall back to HEAD.
  void renameBranch(BuildContext context, RefInfo branch) {
    context.push(
      RoutePaths.renameBranchDialogFor(_repoId, branch: branch.shortName),
    );
  }

  void deleteSingle(RefInfo branch) =>
      _session.deleteBranch(names: <String>[branch.shortName]);

  /// Spec page 13 requires a batch delete to be confirmed item by item
  /// (「逐項列出名稱與未 push 的 commit 數」), not fired straight off the
  /// action bar as this used to do.
  void deleteSelected(BuildContext context, List<String> names) {
    if (names.isEmpty) return;
    context.push(RoutePaths.deleteBranchesDialogFor(_repoId, names: names));
  }

  // 05-B "Compare with…" -- same `left: <ref string>` mechanism as the tag
  // and stash sections use. A branch name is already a valid ref, so no
  // per-branch compare dialog is needed; the Compare page's own picker
  // chooses the right-hand side.
  void compareRef(BuildContext context, String refName) {
    final String tabId = ref
        .read(compareTabsProvider(identity).notifier)
        .open(left: refName);
    context.go(RoutePaths.compareFor(_repoId, tabId));
  }

  // 05-B "Rebase current onto here" -- the repository-level rebase dialog,
  // pre-selected on this branch, rather than a second per-branch dialog
  // that would duplicate its stash-first handling and commit-count preview.
  void rebaseOnto(BuildContext context, RefInfo branch) => context.push(
    RoutePaths.rebaseOntoDialogFor(_repoId, target: branch.shortName),
  );

  /// 05-C "Checkout as new local…" / double-tap on a remote-only row --
  /// [remoteRef.fullName] is an unambiguous git ref
  /// (`refs/remotes/origin/...`), unlike its already-prefix-stripped
  /// `shortName`, so it's used as the checkout target; the stripped
  /// `shortName` becomes the new local branch's name.
  void checkoutRemoteAsNewLocal(RefInfo remoteRef) => _session.checkout(
    target: remoteRef.fullName,
    createBranch: true,
    newBranchName: remoteRef.shortName,
  );

  /// 05-C "Prune this ref" -- removes just this one remote-tracking ref
  /// locally (`git branch --delete --remotes`), independent of whether the
  /// branch is still live on the actual remote.
  void pruneRemoteRef(RefInfo remoteRef) {
    final (String remoteName, String _) = remoteBranchParts(remoteRef.fullName);
    _session.pruneRemote(remoteName, <String>[remoteRef.fullName]);
  }

  /// 05-C "Prune this ref" for a *gone* row -- [goneRef] is the local
  /// branch itself (`refs/heads/...`), so the ref to prune is its vanished
  /// upstream (`goneRef.upstream`, e.g. `refs/remotes/origin/feature`), not
  /// [goneRef.fullName]. This clears the stale remote-tracking ref and
  /// leaves the local branch untouched -- see BRANCH_STATES's note: "真正
  /// 移除 remote-tracking ref 要執行 Prune".
  void pruneGoneUpstream(RefInfo goneRef) {
    final (String remoteName, String _) = remoteBranchParts(goneRef.upstream);
    _session.pruneRemote(remoteName, <String>[goneRef.upstream]);
  }

  /// 05-C "Fetch this branch" -- a remote-only row's own ref is already an
  /// unambiguous single remote + branch (unlike 05-J's folder-wide fetch,
  /// which needs fetchableRefsInFolder()'s "single remote across every
  /// leaf" check), so this always fetches exactly the one branch.
  void fetchRemoteRef(RefInfo remoteRef) {
    final (String remoteName, String branch) = remoteBranchParts(
      remoteRef.fullName,
    );
    _session.fetchRemote(remoteName: remoteName, refs: <String>[branch]);
  }

  /// 05-C "Delete on remote…" -- opens the existing dialog
  /// (`deleteRemoteBranchDialogFor`), previously unreachable from any UI.
  void openDeleteRemoteBranchDialog(BuildContext context, RefInfo remoteRef) {
    final (String remoteName, String _) = remoteBranchParts(remoteRef.fullName);
    context.push(
      RoutePaths.deleteRemoteBranchDialogFor(
        _repoId,
        remote: remoteName,
        branch: remoteRef.shortName,
      ),
    );
  }

  // Reuses deleteBranch's existing safe-delete default (force: false,
  // i.e. plain `git branch -d`) rather than a new "is this merged" capi
  // capability: git itself refuses any branch here that isn't merged, and
  // that refusal already surfaces through the existing delete-branch-
  // recovery flow (checkoutChoices/deleteBranchChoices), the same path a
  // single unmerged branch delete goes through today. Excludes HEAD and
  // any branch checked out in a linked worktree, matching
  // _isGoneAndBulkSelectable's exclusions for the same reason -- deleting
  // either would fail loudly or move the current session's HEAD.
  void deleteMergedInFolder(BranchTreeFolder folder) {
    final List<String> names = collectFolderLeafRefs(folder.children)
        .where(
          (RefInfo r) =>
              r.kind == RefKind.localBranch &&
              !r.isHead &&
              r.worktreePath.isEmpty,
        )
        .map((RefInfo r) => r.shortName)
        .toList(growable: false);
    if (names.isEmpty) return;
    _session.deleteBranch(names: names);
  }

  // Only offered when every leaf ref in the folder resolves to the same
  // remote (see fetchableRefsInFolder's doc comment) -- there's no "default
  // remote" to fall back to for a folder mixing refs from more than one,
  // unlike a repository-level fetch.
  void fetchFolder(BranchTreeFolder folder) {
    final (String remote, List<String> branches)? fetchable =
        fetchableRefsInFolder(collectFolderLeafRefs(folder.children));
    if (fetchable == null) return;
    _session.fetchRemote(remoteName: fetchable.$1, refs: fetchable.$2);
  }
}
