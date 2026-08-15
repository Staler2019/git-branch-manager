import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/repo_state.dart' as model;
import '../../data/models/working_copy_status.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_badge.dart';
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
  });

  final String currentBranch;
  final int ahead;
  final int behind;
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

  String _getOperationName() {
    final repoState = widget.repoState;
    if (repoState == null) return '';

    if (repoState.isMerging) return 'MERGE';
    if (repoState.isCherryPicking) return 'CHERRY-PICK';
    if (repoState.isReverting) return 'REVERT';
    if (repoState.isRebasing) return 'REBASE';

    return '';
  }

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
                        const SizedBox(width: GbmSpacing.space2),
                        Text(
                          '${widget.commitCount}c',
                          style: TextStyle(
                            fontSize: GbmTypography.textXs,
                            color: colors.textTertiary,
                          ),
                        ),
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
          Text(
            '+$extraCount more',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
            ),
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
