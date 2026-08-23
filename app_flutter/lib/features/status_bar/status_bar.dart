import 'dart:async';

import 'package:flutter/material.dart';

import '../../actions/gbm_sequencer_operation.dart';
import '../../data/models/repo_state.dart' as model;
import '../../data/models/working_copy_status.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_badge.dart';
import '../../widgets/gbm_panel.dart';
import 'background_task.dart';

/// A horizontal status bar with three zones:
/// 1. **Repo status**: branch name, ahead/behind, commit count, scan duration, lane cap
/// 2. **Progress**: foreground task (icon + label + progress + Cancel), "+N task" fold
/// 3. **Error/log**: persistent danger badge, visible when unread entries exist
///
/// Presentational widget (no Riverpod/FFI dependency) taking data as constructor
/// params and callbacks. Completed tasks linger for 3 seconds before removal.
/// Non-cancellable tasks (checkout, merge, rebase) show a disabled Cancel button
/// with tooltip.
///
/// StatefulWidget (not StatelessWidget) solely to manage the 3-second linger timer
/// for task completion, matching the architectural pattern in workspace_screen.dart.
class StatusBar extends StatefulWidget {
  const StatusBar({
    super.key,
    required this.currentBranch,
    required this.ahead,
    required this.behind,
    this.upstreamGone = false,
    required this.commitCount,
    required this.lastScanDuration,
    required this.graphLaneCapacity,
    required this.backgroundTasks,
    required this.hasUnreadLog,
    required this.onOpenLog,
    required this.onCancelTask,
    this.repoState,
    this.workingCopyStatus,
    this.conflictActive = false,
    this.selectionSummary,
  });

  final String currentBranch;
  final int ahead;
  final int behind;

  /// Whether the current branch's upstream no longer exists on the remote --
  /// either git already reports `[gone]`, or a post-fetch
  /// `git remote prune --dry-run` says it will once pruned. Computed by
  /// `workspace_screen.dart` through `gone_marking.dart`'s
  /// `isEffectivelyGone`, keeping this widget presentational.
  ///
  /// Spec page 02: 「status bar 的 ahead/behind 改顯示 `upstream gone`」.
  /// It *replaces* the counts rather than sitting beside them -- [ahead] and
  /// [behind] are distances measured against a ref that is not there, so
  /// rendering both would state a distance from nothing. It also matters
  /// most in the case that renders nothing today: a branch that was exactly
  /// in sync when its upstream vanished reports 0 and 0.
  final bool upstreamGone;
  final int commitCount;
  final Duration lastScanDuration;
  final int graphLaneCapacity;
  final List<BackgroundTask> backgroundTasks;
  final bool hasUnreadLog;
  final VoidCallback onOpenLog;
  final ValueChanged<String> onCancelTask;
  final model.RepoState? repoState;
  final WorkingCopyStatus? workingCopyStatus;
  final bool conflictActive;

  /// Spec page 13's selection summary (「狀態列改為顯示 selection 摘要」),
  /// already formatted by whoever owns the selected list — this widget stays
  /// presentational and does not know what a commit or a branch is.
  ///
  /// Null both when nothing is multi-selected and when the selected list is
  /// not the visible one: only [WorkspaceScreen] knows which tab is showing,
  /// so it decides, rather than this widget guessing from a route.
  ///
  /// Loses to [conflictActive]: a conflict takes zone 1 outright. A stopped
  /// sequencer is the one thing that must be readable at a glance, and a
  /// selection is recoverable information (the rows are still highlighted).
  final String? selectionSummary;

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  late Timer? _lingerTimer;
  BackgroundTask? _completedTask;

  @override
  void initState() {
    super.initState();
    _lingerTimer = null;
  }

  @override
  void didUpdateWidget(StatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detect task completion: if a task that was in the list is now gone,
    // it finished. Show it lingering for 3 seconds.
    if (oldWidget.backgroundTasks.isNotEmpty &&
        widget.backgroundTasks.isEmpty &&
        _completedTask == null) {
      // All tasks finished; use the last one from the old list as the completed task
      _completedTask = oldWidget.backgroundTasks.last;
      _lingerTimer?.cancel();
      _lingerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _completedTask = null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _lingerTimer?.cancel();
    super.dispose();
  }

  String _getOperationName() =>
      activeSequencerOperation(widget.repoState)?.label.toUpperCase() ?? '';

  String _buildConflictLabel() {
    final repoState = widget.repoState;
    final workingCopyStatus = widget.workingCopyStatus;

    if (repoState == null || workingCopyStatus == null) {
      return '';
    }

    final operationName = _getOperationName();
    final conflictCount = workingCopyStatus.conflicted.length;
    final conflictLabel = '$conflictCount conflicted';

    // For rebase operations, include step/total
    if (operationName == 'REBASE' &&
        repoState.rebaseStep > 0 &&
        repoState.rebaseTotal > 0) {
      return '$operationName ${repoState.rebaseStep}/${repoState.rebaseTotal} · $conflictLabel';
    }

    // For other operations, show operation name and conflict count
    if (operationName.isNotEmpty) {
      return '$operationName · $conflictLabel';
    }

    // Edge case: conflict active but no operation name (e.g., git apply --3way)
    // Show just the conflict count
    return conflictLabel;
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<BackgroundTask> visibleTasks = _completedTask != null
        ? [_completedTask!]
        : widget.backgroundTasks;

    final conflictLabel = _buildConflictLabel();

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space4,
        vertical: GbmSpacing.space1,
      ),
      decoration: BoxDecoration(
        color: widget.conflictActive
            ? colors.danger.withValues(alpha: 0.15)
            : colors.surfacePanel,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          // Zone 1: Repo status or conflict status
          Expanded(
            child: widget.conflictActive
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          conflictLabel,
                          style: TextStyle(
                            fontSize: GbmTypography.textSm,
                            fontWeight: GbmTypography.weightMedium,
                            color: colors.danger,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          widget.currentBranch,
                          style: TextStyle(
                            fontSize: GbmTypography.textSm,
                            fontWeight: GbmTypography.weightMedium,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (widget.upstreamGone) ...<Widget>[
                          const SizedBox(width: GbmSpacing.space2),
                          Text(
                            'upstream gone',
                            style: TextStyle(
                              fontSize: GbmTypography.textXs,
                              color: colors.warning,
                            ),
                          ),
                        ] else ...<Widget>[
                          if (widget.ahead > 0) ...<Widget>[
                            const SizedBox(width: GbmSpacing.space2),
                            Text(
                              '${widget.ahead}↑',
                              style: TextStyle(
                                fontSize: GbmTypography.textXs,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                          if (widget.behind > 0) ...<Widget>[
                            const SizedBox(width: GbmSpacing.space2),
                            Text(
                              '${widget.behind}↓',
                              style: TextStyle(
                                fontSize: GbmTypography.textXs,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(width: GbmSpacing.space2),
                        Text(
                          '${widget.commitCount}c',
                          style: TextStyle(
                            fontSize: GbmTypography.textXs,
                            color: colors.textTertiary,
                          ),
                        ),
                        if (widget.selectionSummary case final summary?) ...[
                          const SizedBox(width: GbmSpacing.space2),
                          Text(
                            '·',
                            style: TextStyle(
                              fontSize: GbmTypography.textXs,
                              color: colors.borderDefault,
                            ),
                          ),
                          const SizedBox(width: GbmSpacing.space2),
                          Text(
                            summary,
                            style: TextStyle(
                              fontSize: GbmTypography.textXs,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),

          // Zone 2: Progress (if any task is running or lingering)
          if (visibleTasks.isNotEmpty)
            Expanded(child: _buildProgressZone(context, visibleTasks)),

          // Zone 3: Error/log badge
          if (widget.hasUnreadLog) ...<Widget>[
            const SizedBox(width: GbmSpacing.space2),
            GestureDetector(
              onTap: widget.onOpenLog,
              child: GbmBadge(label: '!', kind: GbmBadgeKind.removed),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressZone(BuildContext context, List<BackgroundTask> tasks) {
    final GbmColors colors = context.gbmColors;
    final BackgroundTask foregroundTask = tasks.first;
    final int extraCount = tasks.length - 1;

    return Row(
      children: <Widget>[
        Icon(Icons.loop, size: 14, color: colors.textSecondary),
        const SizedBox(width: GbmSpacing.space2),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                foregroundTask.label,
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: foregroundTask.progress,
                  minHeight: 2,
                  backgroundColor: colors.surfaceSunken,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: GbmSpacing.space2),
        Text(
          '${foregroundTask.current}/${foregroundTask.total}',
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(width: GbmSpacing.space2),
        if (extraCount > 0)
          _ExtraTasksChip(
            extraTasks: tasks.skip(1).toList(growable: false),
            onCancelTask: widget.onCancelTask,
          )
        else
          Tooltip(
            message: foregroundTask.cancellable
                ? 'Cancel this operation'
                : 'Cannot cancel ${foregroundTask.label.toLowerCase()} operation',
            child: TextButton(
              onPressed: foregroundTask.cancellable
                  ? () => widget.onCancelTask(foregroundTask.id)
                  : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: GbmSpacing.space2,
                ),
                minimumSize: const Size(0, 24),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: foregroundTask.cancellable
                      ? colors.textLink
                      : colors.textTertiary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The "+N task" fold (spec page 10 STATUSPARTS #2: "其餘作業摺疊成 +N
/// task，點了展開清單"). Tapping opens a small panel listing every folded
/// task's label, progress, and its own Cancel affordance, reusing
/// [onCancelTask] rather than opening a second data path to the same
/// cancellation call. Anchored to this chip's own render box (a plain tap
/// target, not a right-click point), using the same low-chrome `showMenu`
/// idiom `gbm_menu.dart`'s `showGbmMenu` establishes -- `color: transparent`
/// / `elevation: 0` / a single disabled [PopupMenuItem] wrapping a custom
/// panel -- but with this widget's own row content instead of
/// `GbmMenuItem`'s simple label+onTap shape, since a progress bar and a
/// Cancel button don't fit that model.
class _ExtraTasksChip extends StatelessWidget {
  const _ExtraTasksChip({required this.extraTasks, required this.onCancelTask});

  final List<BackgroundTask> extraTasks;
  final ValueChanged<String> onCancelTask;

  Future<void> _showExtraTasksMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    return showMenu<void>(
      context: context,
      position: position,
      color: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _ExtraTasksPanel(
            extraTasks: extraTasks,
            onCancelTask: onCancelTask,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GestureDetector(
      onTap: () => _showExtraTasksMenu(context),
      child: Text(
        '+${extraTasks.length} more',
        style: TextStyle(
          fontSize: GbmTypography.textXs,
          color: colors.textLink,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _ExtraTasksPanel extends StatelessWidget {
  const _ExtraTasksPanel({
    required this.extraTasks,
    required this.onCancelTask,
  });

  final List<BackgroundTask> extraTasks;
  final ValueChanged<String> onCancelTask;

  @override
  Widget build(BuildContext context) {
    return GbmPanel(
      padding: const EdgeInsets.symmetric(
        vertical: GbmSpacing.space1,
        horizontal: GbmSpacing.space2,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final BackgroundTask task in extraTasks)
              _ExtraTaskRow(task: task, onCancelTask: onCancelTask),
          ],
        ),
      ),
    );
  }
}

class _ExtraTaskRow extends StatelessWidget {
  const _ExtraTaskRow({required this.task, required this.onCancelTask});

  final BackgroundTask task;
  final ValueChanged<String> onCancelTask;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  task.label,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 2,
                    backgroundColor: colors.surfaceSunken,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          Tooltip(
            message: task.cancellable
                ? 'Cancel this operation'
                : 'Cannot cancel ${task.label.toLowerCase()} operation',
            child: TextButton(
              onPressed: task.cancellable ? () => onCancelTask(task.id) : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: GbmSpacing.space2,
                ),
                minimumSize: const Size(0, 24),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: task.cancellable
                      ? colors.textLink
                      : colors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
