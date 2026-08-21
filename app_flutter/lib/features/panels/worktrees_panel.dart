import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/worktree_info.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/services/desktop_launcher.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_row.dart';
import 'gbm_panel_tab_shell.dart';

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
                ? Center(
                    child: Text(
                      'No worktrees',
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: context.gbmColors.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: worktrees.length,
                    itemBuilder: (context, index) {
                      final WorktreeInfo w = worktrees[index];
                      return _WorktreeListRow(
                        worktree: w,
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

/// P19 list column: worktree 名稱 + 分支 + 狀態.
class _WorktreeListRow extends StatelessWidget {
  const _WorktreeListRow({
    required this.worktree,
    required this.selected,
    required this.onTap,
  });

  final WorktreeInfo worktree;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String name = worktree.path.split('/').last;
    final String status = <String>[
      if (worktree.isMain) 'main',
      if (worktree.isLocked) 'locked',
      if (worktree.isPrunable) 'prunable',
      if (worktree.isBare) 'bare',
    ].join(' · ');

    return GbmRow(
      selected: selected,
      onTap: onTap,
      // Two stacked lines (name over branch·status) do not fit
      // rowHeightComfortable, which is sized for one -- a widget test caught
      // this as a 2px RenderFlex overflow rather than it shipping as a
      // clipped second line.
      height: GbmSpacing.rowHeightComfortable + GbmSpacing.space3,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              name,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
                fontWeight: GbmTypography.weightMedium,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              <String>[
                worktree.isDetached ? 'detached' : worktree.branch,
                if (status.isNotEmpty) status,
              ].join(' · '),
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
    final GbmColors colors = context.gbmColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GbmSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _field(colors, 'Path', worktree.path, mono: true),
          _field(
            colors,
            'HEAD',
            worktree.isDetached
                ? '${worktree.headOid} (detached)'
                : '${worktree.branch} · ${worktree.headOid}',
            mono: true,
          ),
          if (worktree.isLocked)
            _field(
              colors,
              'Lock reason',
              worktree.lockReason.isEmpty
                  ? 'Locked, no reason recorded'
                  : worktree.lockReason,
            ),
          if (worktree.isPrunable)
            _field(
              colors,
              'Prunable',
              worktree.prunableReason.isEmpty
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
      ),
    );
  }

  Widget _field(
    GbmColors colors,
    String label,
    String value, {
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GbmSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}
