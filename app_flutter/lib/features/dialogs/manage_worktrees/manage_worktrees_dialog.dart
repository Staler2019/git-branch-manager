import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/worktree_info.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `ManageWorktreesDialog` (src/app/dialogs/
/// ManageWorktreesDialog.cpp). Routed as
/// `/repo/:repoId/dialogs/manage-worktrees`.
class ManageWorktreesDialogContent extends ConsumerStatefulWidget {
  const ManageWorktreesDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ManageWorktreesDialogContent> createState() => _ManageWorktreesDialogContentState();
}

class _ManageWorktreesDialogContentState extends ConsumerState<ManageWorktreesDialogContent> {
  bool _addExpanded = false;
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(repoSessionProvider(widget.identity).notifier).refreshWorktrees());
  }

  @override
  void dispose() {
    _pathController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<WorktreeInfo> worktrees = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.worktrees),
    );

    return GbmDialogShell(
      title: 'Manage Worktrees',
      width: 640,
      actions: <Widget>[
        GbmButton(
          label: 'Prune',
          onPressed: () => ref.read(repoSessionProvider(widget.identity).notifier).pruneWorktrees(),
        ),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: _addExpanded ? 'Cancel Add' : 'Add…',
          onPressed: () => setState(() => _addExpanded = !_addExpanded),
        ),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(label: 'Close', kind: GbmButtonKind.primary, onPressed: () => context.pop()),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_addExpanded) ...<Widget>[
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(hintText: 'New worktree path', isDense: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: GbmSpacing.space2),
            TextField(
              controller: _branchController,
              decoration: const InputDecoration(
                hintText: 'New branch name (leave empty to check out an existing branch)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            Align(
              alignment: Alignment.centerRight,
              child: GbmButton(
                label: 'Create',
                kind: GbmButtonKind.primary,
                onPressed: () {
                  final String path = _pathController.text.trim();
                  if (path.isEmpty) return;
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .addWorktree(path, createBranch: true, newBranchName: _branchController.text.trim());
                  setState(() {
                    _addExpanded = false;
                    _pathController.clear();
                    _branchController.clear();
                  });
                },
              ),
            ),
            const Divider(height: GbmSpacing.space4 * 2),
          ],
          SizedBox(
            height: 280,
            child: worktrees.isEmpty
                ? Center(child: Text('No worktrees', style: TextStyle(color: colors.textTertiary)))
                : ListView(
                    children: <Widget>[
                      for (final worktree in worktrees)
                        _WorktreeRow(
                          worktree: worktree,
                          onRemove: worktree.isMain
                              ? null
                              : () => ref
                                    .read(repoSessionProvider(widget.identity).notifier)
                                    .removeWorktree(worktree.path),
                          onToggleLock: worktree.isMain
                              ? null
                              : () {
                                  final notifier = ref.read(repoSessionProvider(widget.identity).notifier);
                                  if (worktree.isLocked) {
                                    notifier.unlockWorktree(worktree.path);
                                  } else {
                                    notifier.lockWorktree(worktree.path);
                                  }
                                },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorktreeRow extends StatelessWidget {
  const _WorktreeRow({required this.worktree, required this.onRemove, required this.onToggleLock});

  final WorktreeInfo worktree;
  final VoidCallback? onRemove;
  final VoidCallback? onToggleLock;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space1, vertical: GbmSpacing.space2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      worktree.path,
                      style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textPrimary, fontWeight: GbmTypography.weightMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (worktree.isMain) ...<Widget>[
                      const SizedBox(width: GbmSpacing.space1),
                      Text('(main)', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary)),
                    ],
                    if (worktree.isLocked) ...<Widget>[
                      const SizedBox(width: GbmSpacing.space1),
                      Text('🔒', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary)),
                    ],
                  ],
                ),
                Text(
                  worktree.isDetached ? 'detached @ ${worktree.headOid}' : worktree.branch,
                  style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary),
                ),
              ],
            ),
          ),
          if (onToggleLock != null)
            TextButton(
              onPressed: onToggleLock,
              child: Text(worktree.isLocked ? 'Unlock' : 'Lock', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textSecondary)),
            ),
          if (onRemove != null)
            TextButton(
              onPressed: onRemove,
              child: Text('Remove', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.danger)),
            ),
        ],
      ),
    );
  }
}
