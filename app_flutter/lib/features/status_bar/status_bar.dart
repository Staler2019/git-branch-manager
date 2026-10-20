import 'dart:async';

import 'package:flutter/material.dart';

import '../../actions/gbm_sequencer_operation.dart';
import '../../data/models/count_format.dart';
import '../../data/models/operation_record.dart';
import '../../data/models/refresh_timings.dart';
import '../../data/models/repo_state.dart' as model;
import '../../data/models/working_copy_status.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_panel.dart';
import '../../widgets/lucide_icon.dart';
import 'background_task.dart';

/// A horizontal status bar with three zones:
/// 1. **Repo status**: branch name, ahead/behind, commit count, scan duration, lane cap
/// 2. **Progress**: foreground task (icon + label + progress + Cancel), "+N task" fold
/// 3. **Error/log**: a red summary of the newest unread error, then a
///    persistent `Log` entry (P10 #3)
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
    this.unreadError,
    required this.onOpenError,
    required this.onToggleLog,
    required this.onCancelTask,
    this.repoState,
    this.workingCopyStatus,
    this.conflictActive = false,
    this.selectionSummary,
    this.showRefreshTimings = false,
    this.refreshTimings = const RefreshTimings(),
  }) : windowSummary = null;

  /// The bar of a window with no repository open (spec page 15 A #5): zone 1
  /// states [windowSummary] -- the scan result -- in place of a branch; the
  /// progress zone and zone 3 are the same as a repository's.
  const StatusBar.window({
    super.key,
    required String this.windowSummary,
    required this.backgroundTasks,
    this.unreadError,
    required this.onOpenError,
    required this.onToggleLog,
    required this.onCancelTask,
  }) : currentBranch = '',
       ahead = 0,
       behind = 0,
       upstreamGone = false,
       commitCount = 0,
       lastScanDuration = Duration.zero,
       graphLaneCapacity = 0,
       repoState = null,
       workingCopyStatus = null,
       conflictActive = false,
       selectionSummary = null,
       showRefreshTimings = false,
       refreshTimings = const RefreshTimings();

  /// Set only by [StatusBar.window]; when set, zone 1 is this text alone.
  final String? windowSummary;

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

  /// The newest error-level log line the user has not seen, or null. Only
  /// an error lights zone 3 (P10 #3 「有 error 未讀時」; LOGRULES 「error
  /// 會同時在 status bar 亮紅點，直到使用者開過 log 面板才熄」). The `!`
  /// badge that lit for any unread line is gone (使用者裁定：「紅色badge
  /// 亮起來不符合spec，要移除」). [WorkspaceScreen] decides what is unread.
  final GbmLogEntry? unreadError;

  /// The summary was clicked: open the log at [unreadError] (「可點開直接
  /// 跳到該筆 log」).
  final VoidCallback onOpenError;

  /// The `Log` entry was clicked: the same toggle as View → Log
  /// (Ctrl/Cmd+Shift+L), ruling Q6.
  final VoidCallback onToggleLog;
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

  /// `appPrefs.showRefreshTimings` (Preferences → Developer). Not from the
  /// spec -- a debugging aid for fix/refresh-ui-first-tiering.
  final bool showRefreshTimings;

  /// The current focus-regain sweep's stamps -- see
  /// [RepoSessionState.refreshTimings]. Rendered through
  /// [refreshTimingsLabel] so the status bar and the controller's
  /// `debugPrint` read identically.
  final RefreshTimings refreshTimings;

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
    // it finished. Show it lingering for 3 seconds -- the latest one, so a
    // task that started and finished during an earlier linger replaces it.
    if (oldWidget.backgroundTasks.isNotEmpty &&
        widget.backgroundTasks.isEmpty) {
      // All tasks finished; use the last one from the old list as the completed task
      _completedTask = oldWidget.backgroundTasks.last.copyWith(
        finishedAt: DateTime.now(),
      );
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
    // A finished task lingers only while nothing else runs: a task that starts
    // during the linger (a pull's `stash push` then `pull`) is shown at once.
    final List<BackgroundTask> visibleTasks = widget.backgroundTasks.isNotEmpty
        ? widget.backgroundTasks
        : <BackgroundTask>[?_completedTask];

    final conflictLabel = _buildConflictLabel();

    // P10's mock, taken whole (open-with-apps-spec.html screen 3, rulings
    // Q2 and Q7). Its container, verbatim: `gap:9px;height:26px;padding:0
    // 10px;border-top:1px solid var(--border-subtle);background:
    // var(--surface-panel);font-size:10.5px;color:var(--text-tertiary)`.
    // Zone 1 and the progress zone share the space left of zone 3, each
    // loose, so zone 3 stays at the right edge (`<span style="flex:1">`).
    return Container(
      height: _kBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: _kBarPadding),
      decoration: BoxDecoration(
        color: widget.conflictActive
            ? colors.danger.withValues(alpha: 0.15)
            : colors.surfacePanel,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: GbmTypography.statusBarText,
          color: colors.textTertiary,
        ),
        child: Row(
          spacing: _kGap,
          children: <Widget>[
            Expanded(
              child: Row(
                spacing: _kGap,
                children: <Widget>[
                  Flexible(
                    child: widget.windowSummary == null
                        ? _buildRepoZone(colors, conflictLabel)
                        : Text(
                            widget.windowSummary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  if (visibleTasks.isNotEmpty) ...<Widget>[
                    const _Rule(),
                    Flexible(child: _buildProgressZone(context, visibleTasks)),
                  ],
                ],
              ),
            ),

            // Zone 3, the mock's order: summary, then Log.
            if (widget.unreadError case final GbmLogEntry error)
              _ErrorSummary(entry: error, onTap: widget.onOpenError),
            _LogEntryButton(onTap: widget.onToggleLog),
          ],
        ),
      ),
    );
  }

  /// Zone 1. The mock's own run is `<span>main ↑2 ↓0</span>`: arrows lead
  /// and a zero is still written (P10 #1 「永遠顯示分支與 ahead/behind」).
  /// What the mock does not draw -- the repo state label, `upstream gone`,
  /// the commit count, the selection summary, refresh timings, the conflict
  /// label -- comes from other pages and stays, at the bar's own size.
  Widget _buildRepoZone(GbmColors colors, String conflictLabel) {
    if (widget.conflictActive) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          conflictLabel,
          style: TextStyle(
            fontWeight: GbmTypography.weightMedium,
            color: colors.danger,
          ),
        ),
      );
    }
    final TextStyle separator = TextStyle(color: colors.borderDefault);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _kGap,
        children: <Widget>[
          // Replaces the counts rather than sitting beside them: they are
          // distances from an upstream that is not there (spec page 02).
          Text(
            widget.upstreamGone
                ? widget.currentBranch
                : '${widget.currentBranch} ↑${widget.ahead} ↓${widget.behind}',
          ),
          // RepoState.describe used to be rendered by TopBar. It is empty
          // for an ordinary repository; it is the only surface that says
          // `indexLocked` ("another Git process appears to be running"),
          // which ConflictBanner does not cover.
          if (widget.repoState?.describe case final String label
              when label.isNotEmpty)
            Text(label, style: TextStyle(color: colors.warning)),
          if (widget.upstreamGone)
            Text('upstream gone', style: TextStyle(color: colors.warning)),
          Text('${widget.commitCount}c'),
          if (widget.selectionSummary case final summary?) ...<Widget>[
            Text('·', style: separator),
            Text(summary, style: TextStyle(color: colors.textSecondary)),
          ],
          if (widget.showRefreshTimings)
            if (refreshTimingsLabel(widget.refreshTimings)
                case final String label when label.isNotEmpty) ...<Widget>[
              Text('·', style: separator),
              Text(label, style: TextStyle(color: colors.textSecondary)),
            ],
        ],
      ),
    );
  }

  /// Zone 2, one line as the mock draws it: `{{ icLoader }}`, the label
  /// with its count (`Cloning design-tokens — 12,480 / 31,206`), a 74×4
  /// bar, `Cancel` in `--text-link`, then a rule and `+N task`.
  Widget _buildProgressZone(BuildContext context, List<BackgroundTask> tasks) {
    final GbmColors colors = context.gbmColors;
    final BackgroundTask foregroundTask = tasks.first;
    final int extraCount = tasks.length - 1;

    return Row(
      spacing: _kGap,
      children: <Widget>[
        LucideIcon('loader-circle', size: 12, color: colors.accent),
        Flexible(
          child: Text(
            _progressLabel(foregroundTask),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // `width:74px;height:4px;border-radius:999px;
        // background:var(--surface-sunken)`, filled with `--accent`.
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 74,
            height: 4,
            child: LinearProgressIndicator(
              value: _barValue(foregroundTask),
              minHeight: 4,
              backgroundColor: colors.surfaceSunken,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            ),
          ),
        ),
        Tooltip(
          message: foregroundTask.cancellable
              ? 'Cancel this operation'
              : 'Cannot cancel ${foregroundTask.label.toLowerCase()} operation',
          child: TextButton(
            onPressed: foregroundTask.cancellable
                ? () => widget.onCancelTask(foregroundTask.id)
                : null,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: GbmTypography.statusBarText,
                color: foregroundTask.cancellable
                    ? colors.textLink
                    : colors.textTertiary,
              ),
            ),
          ),
        ),
        if (extraCount > 0) ...<Widget>[
          const _Rule(),
          _ExtraTasksChip(
            extraTasks: tasks.skip(1).toList(growable: false),
            onCancelTask: widget.onCancelTask,
          ),
        ],
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
        // Spec page 10 P10 #2: 「其餘作業摺疊成 +N task」; the mock draws it
        // `color:var(--text-tertiary)` (S7), no underline.
        '+${extraTasks.length} task',
        style: TextStyle(
          fontSize: GbmTypography.statusBarText,
          color: colors.textTertiary,
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
                    value: _barValue(task),
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

/// `{{ icErr }}Push rejected`: `display:inline-flex;align-items:center;
/// gap:5px;color:var(--danger);cursor:pointer`, `icErr` being Lucide
/// `x-circle` 12px danger. The text is the log line itself, one line --
/// one source, so the summary cannot disagree with the row it jumps to.
/// 320 wide at most, the rest on hover (both inferred, spec screen 3).
/// No hover ground: the mock gives only `cursor:pointer`.
class _ErrorSummary extends StatelessWidget {
  const _ErrorSummary({required this.entry, required this.onTap});

  final GbmLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Tooltip(
      message: entry.message,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: ConstrainedBox(
            key: const ValueKey<String>('status-error-summary'),
            constraints: const BoxConstraints(maxWidth: 320),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 5,
              children: <Widget>[
                LucideIcon('circle-x', size: 12, color: colors.danger),
                Flexible(
                  child: Text(
                    entry.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.danger),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `{{ icTerminal }}Log`: `gap:4px;cursor:pointer`, `icTerminal` being
/// Lucide `terminal` 12px textTertiary. Always present: P10 #3 names the
/// zone 「錯誤與 Log 入口」 and #4 opens the log 「從 status bar」.
class _LogEntryButton extends StatelessWidget {
  const _LogEntryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: <Widget>[
            LucideIcon('terminal', size: 12, color: colors.textTertiary),
            const Text('Log'),
          ],
        ),
      ),
    );
  }
}

/// P10 mock geometry (open-with-apps-spec.html screen 3).
const double _kBarHeight = 26;
const double _kBarPadding = 10;
const double _kGap = 9;

/// `<span style="width:1px;height:12px;background:var(--border-subtle)">`,
/// between zone 1 and the progress zone and before `+N task`.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey<String>('status-rule'),
    width: 1,
    height: 12,
    color: context.gbmColors.borderSubtle,
  );
}

/// The foreground task's label with its count, as the mock writes it:
/// `Cloning design-tokens — 12,480 / 31,206`. A task that knows no total
/// writes the count alone; one that has counted nothing writes no count,
/// since a lone "0" reads as a stuck object count (a git task never counts:
/// 計數「改spec，沒有計畫」).
String _progressLabel(BackgroundTask task) {
  if (task.total > 0) {
    return '${task.label} — ${formatCount(task.current)} / '
        '${formatCount(task.total)}';
  }
  if (task.current > 0) return '${task.label} — ${formatCount(task.current)}';
  return task.label;
}

/// What a task's bar draws. A finished task lingers as a full bar; a task
/// waiting on the user (a sequencer stopped at a conflict) is still; a running
/// one with no known total (`total <= 0`) is indeterminate (`null`), because
/// `value: 0.0` is a static empty track that reads as "nothing is happening"
/// -- the reported symptom. The indeterminate bar animates forever, so a test
/// must not `pumpAndSettle()` while one is on screen
/// ([TEST-no-pumpandsettle-with-spinner]).
double? _barValue(BackgroundTask task) {
  if (task.finishedAt != null) return 1.0;
  if (task.waitingOnUser) return task.progress;
  if (task.total <= 0) return null;
  return task.progress;
}
