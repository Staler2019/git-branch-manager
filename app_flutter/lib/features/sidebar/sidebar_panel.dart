import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_action_availability.dart';
import '../../actions/gbm_action_id.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/models/remote_info.dart';
import '../../data/models/stash_entry.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_menu.dart';
import '../../widgets/prompt_text_dialog.dart';
import '../repo_switcher/repo_switcher_popover.dart';
import 'branch_tree_builder.dart';
import 'widgets/branch_folder_menu_items.dart';
import 'widgets/branch_tree_item.dart';
import 'widgets/stash_menu_items.dart';

/// Local branches for the open repository, with checkout-on-tap, plus
/// create/rename/delete and the multi-select "gone" bulk-delete flow (see
/// docs/FEATURES.md's "Branch sync hygiene" entry). The Dart analog of
/// `SidebarPanel`/`RefTreeModel` (src/app/views/SidebarPanel.cpp,
/// src/app/models/RefTreeModel.cpp). Tags/stashes/worktrees still have
/// their own manage-* dialogs (see workspace_screen.dart's "⋯" menu) rather
/// than a sidebar tree -- but branches do not: local and remote-only
/// branches are merged into one tree via `branch_tree_builder.dart`'s
/// `mergeLocalAndRemoteBranches`, matching Flutter Desktop Spec page 02
/// items 4/12 ("Local 與 remote 不再分兩段，同一條分支只出現一次"). This
/// used to say "local branches only... unlike the Qt original" -- that was
/// the pre-merge state; the Qt original's single-tree design is what this
/// now (re)implements.
class SidebarPanel extends ConsumerStatefulWidget {
  const SidebarPanel({
    super.key,
    required this.identity,
    this.filterFocusNode,
    this.switcherController,
  });

  final RepoIdentity identity;

  /// Lets `WorkspaceScreen`'s `fileSwitchRepository` handler (Cmd/Ctrl+R)
  /// open the repository popover hanging off the button at the top of this
  /// panel -- see [RepoSwitcherController].
  final RepoSwitcherController? switcherController;

  /// Focused by `WorkspaceScreen`'s `editFilterBranches` action handler
  /// (Cmd/Ctrl+Shift+E) to jump the caret into the filter field below. Owned
  /// by the caller, not this widget, since the shortcut is registered above
  /// this widget in the tree -- mirrors `GbmSplitPaneController`'s
  /// attach/external-trigger rationale in split_pane.dart, but a plain
  /// `FocusNode` is enough here since "focus this field" needs no state of
  /// its own beyond what `Focus`/`TextField` already track.
  final FocusNode? filterFocusNode;

  @override
  ConsumerState<SidebarPanel> createState() => _SidebarPanelState();
}

class _SidebarPanelState extends ConsumerState<SidebarPanel> {
  final Set<String> _selected = <String>{};
  final Set<String> _expandedFolders = <String>{};
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  bool _isBulkSelectable(RefInfo branch) => !branch.isHead;

  bool _isGoneAndBulkSelectable(RefInfo branch) =>
      branch.isGone && !branch.isHead && branch.worktreePath.isEmpty;

  void _pruneSelection(List<RefInfo> branches) {
    final Set<String> names = branches.map((b) => b.shortName).toSet();
    _selected.removeWhere((name) => !names.contains(name));
  }

  Future<void> _createBranch() async {
    final String? name = await promptText(
      context,
      title: 'New Branch',
      label: 'Branch name',
    );
    if (name == null || !mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .createBranch(name: name);
  }

  Future<void> _createBranchFrom(RefInfo branch) async {
    final String? name = await promptText(
      context,
      title: 'New Branch from ${branch.shortName}',
      label: 'Branch name',
    );
    if (name == null || !mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .createBranch(name: name, startPoint: branch.shortName);
  }

  void _openMergeDialog() {
    context.push(
      RoutePaths.mergeDialogFor(Uri.encodeComponent(widget.identity.workDir)),
    );
  }

  /// 05-B's "Rename branch". Unlike the Branch menu and F2, this names the
  /// clicked branch rather than letting the dialog fall back to HEAD.
  void _renameBranch(RefInfo branch) {
    context.push(
      RoutePaths.renameBranchDialogFor(
        Uri.encodeComponent(widget.identity.workDir),
        branch: branch.shortName,
      ),
    );
  }

  void _deleteSingle(RefInfo branch) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteBranch(names: <String>[branch.shortName]);
  }

  void _applyStash(StashEntry stash) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .applyStash(stash.index);
  }

  void _popStash(StashEntry stash) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .applyStash(stash.index, pop: true);
  }

  Future<void> _createBranchFromStash(StashEntry stash) async {
    final String? name = await promptText(
      context,
      title: 'New Branch from Stash',
      label: 'Branch name',
    );
    if (name == null || !mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .branchFromStash(stash.index, name);
  }

  void _viewStashDiff(StashEntry stash) {
    context.push(
      RoutePaths.manageStashesDialogFor(
        Uri.encodeComponent(widget.identity.workDir),
        selectIndex: stash.index,
      ),
    );
  }

  // Uses the stash's own commit oid as the Compare tab's left ref -- a
  // stash entry is a real commit (`git stash` creates one even though it
  // never gets a branch), so this is the same `left: <ref string>`
  // mechanism repositoryCompare already uses, not a new capability.
  void _compareStash(StashEntry stash) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(widget.identity).notifier)
        .open(left: stash.oid);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  void _dropStash(StashEntry stash) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .dropStash(stash.index);
  }

  void _checkoutTagDetached(RefInfo tag) {
    checkoutBranch(ref, widget.identity, tag.shortName, detach: true);
  }

  void _pushTag(RefInfo tag, RemoteInfo remote) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .pushTag(remote.name, name: tag.shortName);
  }

  // Same `left: <ref string>` mechanism as _compareStash -- a tag name is
  // already a valid ref on its own.
  void _compareTag(RefInfo tag) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(widget.identity).notifier)
        .open(left: tag.shortName);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  void _deleteTag(RefInfo tag) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteTag(tag.shortName);
  }

  List<RefInfo> _collectFolderLeafRefs(List<BranchTreeNode> nodes) {
    final List<RefInfo> refs = <RefInfo>[];
    for (final BranchTreeNode node in nodes) {
      if (node is BranchTreeLeaf) {
        refs.add(node.ref);
      } else if (node is BranchTreeFolder) {
        refs.addAll(_collectFolderLeafRefs(node.children));
      }
    }
    return refs;
  }

  Set<String> _collectFolderNames(List<BranchTreeNode> nodes) {
    final Set<String> names = <String>{};
    for (final BranchTreeNode node in nodes) {
      if (node is BranchTreeFolder) {
        names.add(node.folderName);
        names.addAll(_collectFolderNames(node.children));
      }
    }
    return names;
  }

  // "Expand all" opens this folder and every nested subfolder beneath it,
  // not just this one level -- "Collapse all" only needs to close this
  // one, since a closed ancestor already hides its descendants regardless
  // of their own recorded expand state.
  void _toggleFolderExpand(BranchTreeFolder folder) {
    setState(() {
      if (_expandedFolders.contains(folder.folderName)) {
        _expandedFolders.remove(folder.folderName);
      } else {
        _expandedFolders
          ..add(folder.folderName)
          ..addAll(_collectFolderNames(folder.children));
      }
    });
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
  void _deleteMergedInFolder(BranchTreeFolder folder) {
    final List<String> names = _collectFolderLeafRefs(folder.children)
        .where(
          (RefInfo ref) =>
              ref.kind == RefKind.localBranch &&
              !ref.isHead &&
              ref.worktreePath.isEmpty,
        )
        .map((RefInfo ref) => ref.shortName)
        .toList(growable: false);
    if (names.isEmpty) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteBranch(names: names);
  }

  // Only offered when every leaf ref in the folder resolves to the same
  // remote (see fetchableRefsInFolder's doc comment) -- there's no "default
  // remote" to fall back to for a folder mixing refs from more than one,
  // unlike a repository-level fetch.
  void _fetchFolder(BranchTreeFolder folder) {
    final (String remote, List<String> branches)? fetchable =
        fetchableRefsInFolder(_collectFolderLeafRefs(folder.children));
    if (fetchable == null) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .fetchRemote(remoteName: fetchable.$1, refs: fetchable.$2);
  }

  void _openFolderContextMenu(
    BuildContext context,
    TapDownDetails details,
    BranchTreeFolder folder,
  ) {
    final (String, List<String>)? fetchable = fetchableRefsInFolder(
      _collectFolderLeafRefs(folder.children),
    );
    showGbmContextMenu(
      context,
      details.globalPosition,
      branchFolderMenuItems(
        isExpanded: _expandedFolders.contains(folder.folderName),
        onToggleExpand: () => _toggleFolderExpand(folder),
        onCopyPrefix: () =>
            Clipboard.setData(ClipboardData(text: '${folder.folderName}/')),
        onDeleteMerged: () => _deleteMergedInFolder(folder),
        onFetchFolder: fetchable == null ? null : () => _fetchFolder(folder),
      ),
    );
  }

  void _openStashContextMenu(
    BuildContext context,
    TapDownDetails details,
    StashEntry stash,
    bool conflictActive,
  ) {
    showGbmContextMenu(
      context,
      details.globalPosition,
      stashMenuItems(
        onApply: conflictActive ? null : () => _applyStash(stash),
        onPop: conflictActive ? null : () => _popStash(stash),
        onCreateBranch: conflictActive
            ? null
            : () => _createBranchFromStash(stash),
        onViewDiff: () => _viewStashDiff(stash),
        onCompare: () => _compareStash(stash),
        onDrop: () => _dropStash(stash),
      ),
    );
  }

  void _deleteSelected() {
    if (_selected.isEmpty) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteBranch(names: _selected.toList(growable: false));
    setState(_selected.clear);
  }

  /// 05-C "Checkout as new local…" / double-tap on a remote-only row --
  /// [remoteRef.fullName] is an unambiguous git ref
  /// (`refs/remotes/origin/...`), unlike its already-prefix-stripped
  /// `shortName`, so it's used as the checkout target; the stripped
  /// `shortName` becomes the new local branch's name.
  void _checkoutRemoteAsNewLocal(RefInfo remoteRef) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .checkout(
          target: remoteRef.fullName,
          createBranch: true,
          newBranchName: remoteRef.shortName,
        );
  }

  /// 05-C "Prune this ref" -- removes just this one remote-tracking ref
  /// locally (`git branch --delete --remotes`), independent of whether the
  /// branch is still live on the actual remote.
  void _pruneRemoteRef(RefInfo remoteRef) {
    final (String remoteName, String _) = remoteBranchParts(remoteRef.fullName);
    ref.read(repoSessionProvider(widget.identity).notifier).pruneRemote(
      remoteName,
      <String>[remoteRef.fullName],
    );
  }

  /// 05-C "Prune this ref" for a *gone* row -- [goneRef] is the local
  /// branch itself (`refs/heads/...`), so the ref to prune is its vanished
  /// upstream (`goneRef.upstream`, e.g. `refs/remotes/origin/feature`), not
  /// [goneRef.fullName]. This clears the stale remote-tracking ref and
  /// leaves the local branch untouched -- see BRANCH_STATES's note: "真正
  /// 移除 remote-tracking ref 要執行 Prune".
  void _pruneGoneUpstream(RefInfo goneRef) {
    final (String remoteName, String _) = remoteBranchParts(goneRef.upstream);
    ref.read(repoSessionProvider(widget.identity).notifier).pruneRemote(
      remoteName,
      <String>[goneRef.upstream],
    );
  }

  /// 05-C "Fetch this branch" -- a remote-only row's own ref is already an
  /// unambiguous single remote + branch (unlike 05-J's folder-wide fetch,
  /// which needs fetchableRefsInFolder()'s "single remote across every
  /// leaf" check), so this always fetches exactly the one branch.
  void _fetchRemoteRef(RefInfo remoteRef) {
    final (String remoteName, String branch) = remoteBranchParts(
      remoteRef.fullName,
    );
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .fetchRemote(remoteName: remoteName, refs: <String>[branch]);
  }

  /// 05-C "Delete on remote…" -- opens the existing dialog
  /// (`deleteRemoteBranchDialogFor`), previously unreachable from any UI.
  void _openDeleteRemoteBranchDialog(RefInfo remoteRef) {
    final (String remoteName, String _) = remoteBranchParts(remoteRef.fullName);
    context.push(
      RoutePaths.deleteRemoteBranchDialogFor(
        Uri.encodeComponent(widget.identity.workDir),
        remote: remoteName,
        branch: remoteRef.shortName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RefSnapshot refs = ref.watch(repoRefsProvider(widget.identity));
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final GbmColors colors = context.gbmColors;
    final List<RefInfo> branches = mergeLocalAndRemoteBranches(
      refs.localBranches,
      refs.remoteBranches,
    );
    _pruneSelection(branches);

    // Compute filtered branches first, since we need it for both the enable
    // check AND the selection source of the "select all gone" button.
    // This ensures the button only selects branches that are currently
    // visible on screen, respecting the active filter.
    final List<RefInfo> filteredBranches = filterBranches(
      branches,
      _filterQuery,
    );
    final bool anyGoneSelectable = filteredBranches.any(
      _isGoneAndBulkSelectable,
    );
    final List<BranchTreeNode> branchTree = buildBranchTree(
      filteredBranches,
      _expandedFolders,
    );
    final List<RefInfo> filteredTags = filterBranches(refs.tags, _filterQuery);
    final String filterNeedle = _filterQuery.trim().toLowerCase();
    final List<StashEntry> filteredStashes = filterNeedle.isEmpty
        ? session.stashes
        : session.stashes
              .where((s) => s.message.toLowerCase().contains(filterNeedle))
              .toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(right: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Spec page 02 item 15: the repository button sits at the very top
          // of the sidebar, above the three per-repo sections -- the
          // repository *list* itself lives in the popover it opens, not in
          // this panel ("repository 清單已移出，改用 15 的切換彈窗").
          RepoSwitcherButton(
            currentWorkDir: widget.identity.workDir,
            controller: widget.switcherController,
          ),
          // BRANCHES section header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GbmSpacing.space3,
              GbmSpacing.space3,
              GbmSpacing.space1,
              GbmSpacing.space1,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'BRANCHES',
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      fontWeight: GbmTypography.weightSemibold,
                      color: colors.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Select all branches with a gone upstream',
                  child: IconButton(
                    icon: Icon(
                      Icons.playlist_add_check,
                      size: 16,
                      color: anyGoneSelectable
                          ? colors.textSecondary
                          : colors.textTertiary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: anyGoneSelectable
                        ? () => setState(() {
                            _selected
                              ..clear()
                              ..addAll(
                                filteredBranches
                                    .where(_isGoneAndBulkSelectable)
                                    .map((b) => b.shortName),
                              );
                          })
                        : null,
                  ),
                ),
                Tooltip(
                  message: 'New branch…',
                  child: IconButton(
                    icon: Icon(
                      Icons.add,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: _createBranch,
                  ),
                ),
              ],
            ),
          ),
          // Filter field -- Cmd/Ctrl+Shift+E (editFilterBranches) focuses
          // this via widget.filterFocusNode. Matches branches, tags and
          // stashes by substring (see filterBranches's doc comment).
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GbmSpacing.space3,
              0,
              GbmSpacing.space3,
              GbmSpacing.space2,
            ),
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _filterController,
                focusNode: widget.filterFocusNode,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
                onChanged: (value) => setState(() => _filterQuery = value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter branches',
                  hintStyle: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textTertiary,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 14,
                    color: colors.textTertiary,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  suffixIcon: _filterQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 14,
                            color: colors.textTertiary,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () => setState(() {
                            _filterController.clear();
                            _filterQuery = '';
                          }),
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: GbmSpacing.space1,
                  ),
                  filled: true,
                  fillColor: colors.surfaceSunken,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.borderFocus),
                  ),
                ),
              ),
            ),
          ),
          // Selection action bar
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GbmSpacing.space3,
                vertical: GbmSpacing.space1,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${_selected.length} selected',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _deleteSelected,
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Branch tree list
          Expanded(
            child: branches.isEmpty
                ? Center(
                    child: Text(
                      'No branches',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: GbmTypography.textSm,
                      ),
                    ),
                  )
                : filterNeedle.isNotEmpty &&
                      branchTree.isEmpty &&
                      filteredTags.isEmpty &&
                      filteredStashes.isEmpty
                ? Center(
                    child: Text(
                      'No matches',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: GbmTypography.textSm,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildTreeNodes(branchTree, context),
                        if (filteredTags.isNotEmpty) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              GbmSpacing.space3,
                              GbmSpacing.space2,
                              GbmSpacing.space1,
                              GbmSpacing.space1,
                            ),
                            child: Text(
                              'TAGS',
                              style: TextStyle(
                                fontSize: GbmTypography.textXs,
                                fontWeight: GbmTypography.weightSemibold,
                                color: colors.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          ...filteredTags.map((tag) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: GbmSpacing.space1,
                              ),
                              child: BranchTreeItem(
                                ref: tag,
                                onCheckout: () => _checkoutTagDetached(tag),
                                onPushTag: session.remotes.length == 1
                                    ? () =>
                                          _pushTag(tag, session.remotes.single)
                                    : null,
                                onCompareRef: () => _compareTag(tag),
                                onDeleteTag: () => _deleteTag(tag),
                                // Sourced from isActionEnabled(), not
                                // session.conflictActive directly -- single
                                // source of truth for checkout availability.
                                conflictActive: !isActionEnabled(
                                  GbmActionId.branchCheckout,
                                  session,
                                ),
                              ),
                            );
                          }),
                        ],
                        if (filteredStashes.isNotEmpty) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              GbmSpacing.space3,
                              GbmSpacing.space2,
                              GbmSpacing.space1,
                              GbmSpacing.space1,
                            ),
                            child: Text(
                              'STASH',
                              style: TextStyle(
                                fontSize: GbmTypography.textXs,
                                fontWeight: GbmTypography.weightSemibold,
                                color: colors.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          ...filteredStashes.map((stash) {
                            return _buildStashRow(
                              stash,
                              colors,
                              // Sourced from isActionEnabled(), not
                              // session.conflictActive directly -- same
                              // pattern as every other conflict-sensitive
                              // gate in this file. branchStashChanges is
                              // the closest existing id (stash apply/pop
                              // mutate the working tree/index the same way
                              // creating a stash would).
                              !isActionEnabled(
                                GbmActionId.branchStashChanges,
                                session,
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeNodes(List<BranchTreeNode> nodes, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes.map((node) => _buildTreeNode(node, context)).toList(),
    );
  }

  Widget _buildTreeNode(BranchTreeNode node, BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    if (node is BranchTreeLeaf) {
      final bool isRemoteOnly = node.ref.kind == RefKind.remoteBranch;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space1),
        child: BranchTreeItem(
          ref: node.ref,
          onCheckout: isRemoteOnly
              ? () => _checkoutRemoteAsNewLocal(node.ref)
              : () => checkoutBranch(ref, widget.identity, node.ref.shortName),
          selected: isRemoteOnly
              ? false
              : _selected.contains(node.ref.shortName),
          // None of the local-branch-only actions below apply to a
          // remote-only leaf -- there is no local branch to select for bulk
          // delete, rename, branch-from, or merge.
          onSelectedChanged: isRemoteOnly
              ? null
              : _isBulkSelectable(node.ref)
              ? (value) => setState(() {
                  if (value) {
                    _selected.add(node.ref.shortName);
                  } else {
                    _selected.remove(node.ref.shortName);
                  }
                })
              : null,
          onRename: isRemoteOnly ? null : () => _renameBranch(node.ref),
          onDelete: isRemoteOnly || node.ref.isHead
              ? null
              : () => _deleteSingle(node.ref),
          onNewBranchFromHere: isRemoteOnly
              ? null
              : () => _createBranchFrom(node.ref),
          onMerge: isRemoteOnly || node.ref.isHead ? null : _openMergeDialog,
          onPruneRef: isRemoteOnly
              ? () => _pruneRemoteRef(node.ref)
              : node.ref.isGone && node.ref.upstream.isNotEmpty
              ? () => _pruneGoneUpstream(node.ref)
              : null,
          onDeleteOnRemote: isRemoteOnly
              ? () => _openDeleteRemoteBranchDialog(node.ref)
              : null,
          onFetchRef: isRemoteOnly ? () => _fetchRemoteRef(node.ref) : null,
          // Sourced from isActionEnabled(), not session.conflictActive
          // directly -- single source of truth for checkout availability.
          conflictActive: !isActionEnabled(GbmActionId.branchCheckout, session),
        ),
      );
    } else if (node is BranchTreeFolder) {
      return _buildFolderNode(node, context);
    }
    return const SizedBox.shrink();
  }

  // Single-level toggle -- the chevron and clicking the folder name both
  // use this, distinct from the context menu's "Expand all" (see
  // _toggleFolderExpand's doc comment for why that one recurses).
  void _toggleFolderExpandedSingleLevel(BranchTreeFolder folder) {
    setState(() {
      if (_expandedFolders.contains(folder.folderName)) {
        _expandedFolders.remove(folder.folderName);
      } else {
        _expandedFolders.add(folder.folderName);
      }
    });
  }

  Widget _buildFolderNode(BranchTreeFolder folder, BuildContext context) {
    final colors = context.gbmColors;
    final isExpanded = _expandedFolders.contains(folder.folderName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GestureDetector(
          onSecondaryTapDown: (TapDownDetails details) =>
              _openFolderContextMenu(context, details, folder),
          child: Container(
            height: GbmSpacing.rowHeightCompact,
            padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  onPressed: () => _toggleFolderExpandedSingleLevel(folder),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleFolderExpandedSingleLevel(folder),
                    child: Text(
                      folder.folderName,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: GbmSpacing.space3),
            child: _buildTreeNodes(folder.children, context),
          ),
      ],
    );
  }

  Widget _buildStashRow(
    StashEntry stash,
    GbmColors colors,
    bool conflictActive,
  ) {
    final now = DateTime.now();
    final stashTime = DateTime.fromMillisecondsSinceEpoch(stash.timestamp);
    final diff = now.difference(stashTime);

    String timeStr;
    if (diff.inMinutes < 1) {
      timeStr = 'just now';
    } else if (diff.inHours < 1) {
      timeStr = '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      timeStr = '${diff.inHours}h ago';
    } else {
      timeStr = '${diff.inDays}d ago';
    }

    return GestureDetector(
      onSecondaryTapDown: (TapDownDetails details) =>
          _openStashContextMenu(context, details, stash, conflictActive),
      child: Container(
        // No fixed height, unlike a branch row -- this row shows two lines
        // (message + relative time) rather than one, and rowHeightCompact
        // (26px) is too short for both at GbmTypography's textSm/textXs
        // sizes, overflowing the Column below by several pixels. Vertical
        // padding gives it breathing room instead of pinning a height that
        // would need recalibrating by hand every time either text style
        // changes.
        padding: const EdgeInsets.symmetric(
          horizontal: GbmSpacing.space2,
          vertical: GbmSpacing.space1,
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: GbmSpacing.space2),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    stash.message,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
