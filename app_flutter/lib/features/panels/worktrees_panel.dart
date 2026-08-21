import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/worktree_info.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/services/desktop_launcher.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_widgets.dart';

/// `manage-worktrees` as a tab, and spec page 19's **reference instance**:
/// the other eleven panels "只換欄位不換造型", so this is the one to copy.
///
/// P19's `PANELSPEC` row for this panel:
/// - list: worktree 名稱 + 分支 + 狀態
/// - detail: 路徑、HEAD、待提交數、鎖定原因
/// - toolbar: Add、Prune、Open、Remove
///
/// **待提交數 is not shown**, because `WorktreeInfo` (data/models/
/// worktree_info.dart) carries no pending-change count and `gbm_capi.h` has
/// no per-worktree status call — a status read is scoped to the session's
/// own work dir. Absent rather than faked, the same convention Tier 2+3
/// used for `MULTIACTS`' Squash. Everything else in the row is present.
class WorktreesPanel extends ConsumerStatefulWidget {
  const WorktreesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<WorktreesPanel> createState() => _WorktreesPanelState();
}

class _WorktreesPanelState extends ConsumerState<WorktreesPanel> {
  String? _selectedPath;
  bool _addExpanded = false;
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(repoSessionProvider(widget.identity).notifier)
          .refreshWorktrees(),
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  /// The 分支 + 狀態 half of P19's list row (the 名稱 half is the path's base
  /// name). Every flag git reports is shown rather than only the first, so a
  /// worktree that is both locked and prunable does not look like one that
  /// is merely locked.
  String _describe(WorktreeInfo w) {
    final String status = <String>[
      if (w.isMain) 'main',
      if (w.isLocked) 'locked',
      if (w.isPrunable) 'prunable',
      if (w.isBare) 'bare',
    ].join(' · ');
    return <String>[
      w.isDetached ? 'detached' : w.branch,
      if (status.isNotEmpty) status,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final List<WorktreeInfo> worktrees = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.worktrees),
    );
    // Selection is held by path rather than index so a refresh that reorders
    // or removes rows can't silently point the detail pane at a different
    // worktree than the one the user clicked.
    final WorktreeInfo? selected = worktrees
        .where((WorktreeInfo w) => w.path == _selectedPath)
        .firstOrNull;

    return GbmPanelTabShell(
      storageId: 'panel.worktrees',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a worktree to see its details',
      toolbar: <Widget>[
        GbmButton(
          label: _addExpanded ? 'Cancel add' : 'Add…',
          onPressed: () => setState(() => _addExpanded = !_addExpanded),
        ),
        GbmButton(label: 'Prune', onPressed: _session.pruneWorktrees),
        GbmButton(
          label: 'Open',
          onPressed: selected == null
              ? null
              : () => ref
                    .read(desktopLauncherProvider)
                    .openInFileManager(selected.path),
        ),
        // The main worktree cannot be removed -- it is the repository.
        GbmButton(
          label: 'Remove',
          kind: GbmButtonKind.danger,
          onPressed: selected == null || selected.isMain
              ? null
              : () {
                  _session.removeWorktree(selected.path);
                  setState(() => _selectedPath = null);
                },
        ),
      ],
      list: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_addExpanded) _buildAddForm(),
          Expanded(
            child: worktrees.isEmpty
                ? const PanelEmptyList(message: 'No worktrees')
                : ListView.builder(
                    itemCount: worktrees.length,
                    itemBuilder: (context, index) {
                      final WorktreeInfo w = worktrees[index];
                      return PanelListRow(
                        title: w.path.split('/').last,
                        subtitle: _describe(w),
                        selected: w.path == _selectedPath,
                        onTap: () => setState(() => _selectedPath = w.path),
                      );
                    },
                  ),
          ),
        ],
      ),
      detail: selected == null
          ? const SizedBox.shrink()
          : _WorktreeDetail(
              worktree: selected,
              onToggleLock: selected.isMain
                  ? null
                  : () => selected.isLocked
                        ? _session.unlockWorktree(selected.path)
                        : _session.lockWorktree(selected.path),
            ),
    );
  }

  Widget _buildAddForm() {
    return Padding(
      padding: const EdgeInsets.all(GbmSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              hintText: 'New worktree path',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          TextField(
            controller: _branchController,
            decoration: const InputDecoration(
              hintText: 'New branch name (empty checks out an existing one)',
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
                _session.addWorktree(
                  path,
                  createBranch: true,
                  newBranchName: _branchController.text.trim(),
                );
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
      ),
    );
  }
}

/// P19 detail column: 路徑、HEAD、鎖定原因 (待提交數 unavailable -- see the
/// class doc on [WorktreesPanel]).
class _WorktreeDetail extends StatelessWidget {
  const _WorktreeDetail({required this.worktree, required this.onToggleLock});

  final WorktreeInfo worktree;
  final VoidCallback? onToggleLock;

  @override
  Widget build(BuildContext context) {
    return PanelDetailColumn(
      children: <Widget>[
        PanelDetailField(label: 'Path', value: worktree.path, mono: true),
        PanelDetailField(
          label: 'HEAD',
          value: worktree.isDetached
              ? '${worktree.headOid} (detached)'
              : '${worktree.branch} · ${worktree.headOid}',
          mono: true,
        ),
        if (worktree.isLocked)
          PanelDetailField(
            label: 'Lock reason',
            value: worktree.lockReason.isEmpty
                ? 'Locked, no reason recorded'
                : worktree.lockReason,
          ),
        if (worktree.isPrunable)
          PanelDetailField(
            label: 'Prunable',
            value: worktree.prunableReason.isEmpty
                ? 'Prunable'
                : worktree.prunableReason,
          ),
        if (onToggleLock != null) ...<Widget>[
          const SizedBox(height: GbmSpacing.space3),
          GbmButton(
            label: worktree.isLocked ? 'Unlock' : 'Lock',
            onPressed: onToggleLock,
          ),
        ],
      ],
    );
  }
}
