import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ref_snapshot.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/prompt_text_dialog.dart';
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

  bool _isBulkSelectable(RefInfo branch) => !branch.isHead;

  bool _isGoneAndBulkSelectable(RefInfo branch) => branch.isGone && !branch.isHead && branch.worktreePath.isEmpty;

  void _pruneSelection(List<RefInfo> branches) {
    final Set<String> names = branches.map((b) => b.shortName).toSet();
    _selected.removeWhere((name) => !names.contains(name));
  }

  Future<void> _createBranch() async {
    final String? name = await promptText(context, title: 'New Branch', label: 'Branch name');
    if (name == null || !mounted) return;
    ref.read(repoSessionProvider(widget.identity).notifier).createBranch(name: name);
  }

  Future<void> _renameBranch(RefInfo branch) async {
    final String? newName = await promptText(
      context,
      title: 'Rename Branch',
      label: 'New name',
      initialValue: branch.shortName,
    );
    if (newName == null || newName == branch.shortName || !mounted) return;
    ref.read(repoSessionProvider(widget.identity).notifier).renameBranch(from: branch.shortName, to: newName);
  }

  void _deleteSingle(RefInfo branch) {
    ref.read(repoSessionProvider(widget.identity).notifier).deleteBranch(names: <String>[branch.shortName]);
  }

  void _deleteSelected() {
    if (_selected.isEmpty) return;
    ref.read(repoSessionProvider(widget.identity).notifier).deleteBranch(names: _selected.toList(growable: false));
    setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final RefSnapshot refs = ref.watch(repoRefsProvider(widget.identity));
    final GbmColors colors = context.gbmColors;
    final List<RefInfo> branches = refs.localBranches;
    _pruneSelection(branches);
    final bool anyGoneSelectable = branches.any(_isGoneAndBulkSelectable);

    return Container(
      width: 240,
      decoration: BoxDecoration(color: colors.surfacePanel, border: Border(right: BorderSide(color: colors.borderSubtle))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(GbmSpacing.space3, GbmSpacing.space3, GbmSpacing.space1, GbmSpacing.space1),
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
                    icon: Icon(Icons.playlist_add_check, size: 16, color: anyGoneSelectable ? colors.textSecondary : colors.textTertiary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: anyGoneSelectable
                        ? () => setState(() {
                            _selected
                              ..clear()
                              ..addAll(branches.where(_isGoneAndBulkSelectable).map((b) => b.shortName));
                          })
                        : null,
                  ),
                ),
                Tooltip(
                  message: 'New branch…',
                  child: IconButton(
                    icon: Icon(Icons.add, size: 16, color: colors.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: _createBranch,
                  ),
                ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3, vertical: GbmSpacing.space1),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${_selected.length} selected',
                      style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: Text('Clear', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textSecondary)),
                  ),
                  TextButton(
                    onPressed: _deleteSelected,
                    child: Text('Delete', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.danger)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: branches.isEmpty
                ? Center(child: Text('No branches', style: TextStyle(color: colors.textTertiary, fontSize: GbmTypography.textSm)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space1),
                    itemCount: branches.length,
                    itemBuilder: (context, index) {
                      final RefInfo branch = branches[index];
                      return BranchTreeItem(
                        ref: branch,
                        onCheckout: () => checkoutBranch(ref, widget.identity, branch.shortName),
                        selected: _selected.contains(branch.shortName),
                        onSelectedChanged: _isBulkSelectable(branch)
                            ? (value) => setState(() {
                                if (value) {
                                  _selected.add(branch.shortName);
                                } else {
                                  _selected.remove(branch.shortName);
                                }
                              })
                            : null,
                        onRename: () => _renameBranch(branch),
                        onDelete: branch.isHead ? null : () => _deleteSingle(branch),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
