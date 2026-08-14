import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/ref_snapshot.dart';
import '../../data/models/stash_entry.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/prompt_text_dialog.dart';
import 'branch_tree_builder.dart';
import 'widgets/branch_tree_item.dart';

/// Local branches for the open repository, with checkout-on-tap, plus
/// create/rename/delete and the multi-select "gone" bulk-delete flow (see
/// docs/FEATURES.md's "Branch sync hygiene" entry). The Dart analog of
/// `SidebarPanel`/`RefTreeModel` (src/app/views/SidebarPanel.cpp,
/// src/app/models/RefTreeModel.cpp) -- local branches only; remote
/// branches/tags/stashes/worktrees have their own manage-* dialogs (see
/// workspace_screen.dart's "⋯" menu) rather than a sidebar tree, unlike the
/// Qt original.
class SidebarPanel extends ConsumerStatefulWidget {
  const SidebarPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<SidebarPanel> createState() => _SidebarPanelState();
}

class _SidebarPanelState extends ConsumerState<SidebarPanel> {
  final Set<String> _selected = <String>{};
  final Set<String> _expandedFolders = <String>{};

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

  Future<void> _renameBranch(RefInfo branch) async {
    final String? newName = await promptText(
      context,
      title: 'Rename Branch',
      label: 'New name',
      initialValue: branch.shortName,
    );
    if (newName == null || newName == branch.shortName || !mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .renameBranch(from: branch.shortName, to: newName);
  }

  void _deleteSingle(RefInfo branch) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteBranch(names: <String>[branch.shortName]);
  }

  void _deleteSelected() {
    if (_selected.isEmpty) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteBranch(names: _selected.toList(growable: false));
    setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final RefSnapshot refs = ref.watch(repoRefsProvider(widget.identity));
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final GbmColors colors = context.gbmColors;
    final List<RefInfo> branches = refs.localBranches;
    _pruneSelection(branches);
    final bool anyGoneSelectable = branches.any(_isGoneAndBulkSelectable);

    final List<BranchTreeNode> branchTree = buildBranchTree(
      branches,
      _expandedFolders,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(right: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
                                branches
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
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildTreeNodes(branchTree, context),
                        if (refs.tags.isNotEmpty) ...<Widget>[
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
                          ...refs.tags.map((tag) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: GbmSpacing.space1,
                              ),
                              child: BranchTreeItem(
                                ref: tag,
                                onCheckout: () => checkoutBranch(
                                  ref,
                                  widget.identity,
                                  tag.shortName,
                                ),
                              ),
                            );
                          }),
                        ],
                        if (session.stashes.isNotEmpty) ...<Widget>[
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
                          ...session.stashes.map((stash) {
                            return _buildStashRow(stash, colors);
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
    if (node is BranchTreeLeaf) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space1),
        child: BranchTreeItem(
          ref: node.ref,
          onCheckout: () =>
              checkoutBranch(ref, widget.identity, node.ref.shortName),
          selected: _selected.contains(node.ref.shortName),
          onSelectedChanged: _isBulkSelectable(node.ref)
              ? (value) => setState(() {
                  if (value) {
                    _selected.add(node.ref.shortName);
                  } else {
                    _selected.remove(node.ref.shortName);
                  }
                })
              : null,
          onRename: () => _renameBranch(node.ref),
          onDelete: node.ref.isHead ? null : () => _deleteSingle(node.ref),
          onNewBranchFromHere: () => _createBranchFrom(node.ref),
          onMerge: node.ref.isHead ? null : _openMergeDialog,
        ),
      );
    } else if (node is BranchTreeFolder) {
      return _buildFolderNode(node, context);
    }
    return const SizedBox.shrink();
  }

  Widget _buildFolderNode(BranchTreeFolder folder, BuildContext context) {
    final colors = context.gbmColors;
    final isExpanded = _expandedFolders.contains(folder.folderName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
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
                onPressed: () => setState(() {
                  if (isExpanded) {
                    _expandedFolders.remove(folder.folderName);
                  } else {
                    _expandedFolders.add(folder.folderName);
                  }
                }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Expanded(
                child: Text(
                  folder.folderName,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
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

  Widget _buildStashRow(StashEntry stash, GbmColors colors) {
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

    return Container(
      height: GbmSpacing.rowHeightCompact,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
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
    );
  }
}
