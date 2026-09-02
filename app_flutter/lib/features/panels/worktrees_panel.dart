import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
/// **Both halves of the old 「待提交數 is absent」 note are now false, and the
/// note is struck rather than deleted** (the #45/#50/#51/#60 precedent): it
/// said `WorktreeInfo` carried no count and `gbm_capi.h` had no per-worktree
/// status call, because a status read was scoped to the session's own work
/// dir. `gbm_worktree_request_pending_counts()` is that call, and
/// `WorktreeInfo.pendingChanges` is that count. Leaving the note standing
/// would invite a later round to re-file the field as unimplementable on
/// grounds already overruled.
class WorktreesPanel extends ConsumerStatefulWidget {
  const WorktreesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<WorktreesPanel> createState() => _WorktreesPanelState();
}

/// One worktree's answer to "how many uncommitted changes?", as cached by
/// the panel. [count] is null unless [state] is
/// [WorktreePendingCountState.measured].
typedef _CountAnswer = ({int? count, WorktreePendingCountState state});

class _WorktreesPanelState extends ConsumerState<WorktreesPanel> {
  /// Which `path@headOid` keys have already been asked about.
  ///
  /// **This, not "which counts are still null", is the request gate**, and
  /// the difference is the whole of this cache's loop safety. A measurement
  /// that fails leaves no count, so a null-based gate re-asks on every
  /// republish -- including the one the failed request itself triggers --
  /// for as long as the panel stays open. A key is asked about once and
  /// then never again, whichever of the four answers comes back, and a
  /// request that produces no reply at all still leaves its key here.
  final Set<String> _askedCountKeys = <String>{};

  /// The answers, so a republish that says `unmeasured` does not blank a
  /// number the user is looking at.
  ///
  /// [CULT-cache-documents-three-things]:
  /// - **Key**: `path@headOid`. A worktree moved to a new commit is exactly
  ///   when its count must be re-measured; lock/unlock change neither, so
  ///   the count survives them, which is the point.
  /// - **Invalidated by**: *no event at all*. The key is the invalidation --
  ///   the same shape as `UntrackedLineCountCache` in the core, and for the
  ///   same reason: nothing emits an event when the answer goes stale.
  /// - **Symptom if missed**: the count blinks back to 「未量測」 every time
  ///   anything republishes the worktree list, which the focus sweep does
  ///   at most every 2 seconds while the user alt-tabs.
  final Map<String, _CountAnswer> _countAnswers = <String, _CountAnswer>{};

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

  static String _countKey(WorktreeInfo w) => '${w.path}@${w.headOid}';

  /// Files every answer that arrived, then asks once for any key never
  /// asked about. Called from `build`, which is why the *request* is
  /// deferred: dispatching to the controller from inside a build is the
  /// provider write [FLU-never-write-provider-in-build] forbids, and its
  /// guard is `assert`-wrapped, so release would let it land mid-frame.
  ///
  /// The bookkeeping is not deferred: `_askedCountKeys` is written
  /// synchronously so a second build in the same frame cannot queue a
  /// second request for the same keys.
  void _harvestAndRequestCounts(List<WorktreeInfo> worktrees) {
    for (final WorktreeInfo w in worktrees) {
      if (w.pendingCountState == WorktreePendingCountState.unmeasured) {
        continue;
      }
      _countAnswers[_countKey(w)] = (
        count: w.pendingChanges,
        state: w.pendingCountState,
      );
    }

    final Iterable<String> keys = worktrees.map(_countKey);
    if (keys.every(_askedCountKeys.contains)) return;
    _askedCountKeys.addAll(keys);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session.requestWorktreePendingCounts();
    });
    // addPostFrameCallback does not itself ask for a frame
    // ([FLU-postframe-no-frame]): it registers for the end of the *next*
    // one, and if nothing else schedules one it simply never runs.
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The cached answer for [w], falling back to whatever the live snapshot
  /// says. Reading the cache first is what survives an `unmeasured`
  /// republish.
  _CountAnswer _answerFor(WorktreeInfo w) =>
      _countAnswers[_countKey(w)] ??
      (count: w.pendingChanges, state: w.pendingCountState);

  /// P19's 待提交數 value. All four states read differently to a user, so
  /// this switches on the state rather than on `count == null`.
  static String _describePendingCount(_CountAnswer answer) =>
      switch (answer.state) {
        WorktreePendingCountState.measured => '${answer.count} 個未提交變更',
        WorktreePendingCountState.unmeasured => '未量測',
        WorktreePendingCountState.notApplicable => '不適用',
        WorktreePendingCountState.failed => '量測失敗',
      };

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
    _harvestAndRequestCounts(worktrees);
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
              pendingCount: _describePendingCount(_answerFor(selected)),
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

/// P19 detail column: 路徑、HEAD、鎖定原因. 待提交數 is now available on
/// [WorktreeInfo] and is not drawn here **yet** -- the P19 rewrite of this
/// column is a later commit in the same round. "Not yet rendered" and "not
/// obtainable" are different claims; see the class doc on [WorktreesPanel]
/// for the one this replaces.
class _WorktreeDetail extends StatelessWidget {
  const _WorktreeDetail({
    required this.worktree,
    required this.pendingCount,
    required this.onToggleLock,
  });

  final WorktreeInfo worktree;

  /// Already resolved to a sentence by the panel, because the panel is what
  /// holds the cache -- a count read straight off [worktree] would blink
  /// back to 「未量測」 on the next plain refresh.
  final String pendingCount;
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
        PanelDetailField(label: '待提交數', value: pendingCount),
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
