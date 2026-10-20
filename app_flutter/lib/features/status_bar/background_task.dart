/// A background task in progress: the history scan, a sequencer operation
/// stopped on the user, or a running git command. Immutable DTO following the
/// project's DDD + factory pattern convention.
class BackgroundTask {
  const BackgroundTask({
    required this.id,
    required this.label,
    required this.current,
    required this.total,
    required this.cancellable,
    this.finishedAt,
    this.waitingOnUser = false,
    this.queuedOperationId = 0,
    this.phase = '',
  });

  /// A running clone job (`backgroundTasksFromCloneJobs`). Cancel stops git
  /// and removes the folder the job made (TASKS 「可取消」).
  factory BackgroundTask.cloneJob({
    required String id,
    required String label,
    required String phase,
    required int current,
    required int total,
  }) => BackgroundTask(
    id: id,
    label: label,
    phase: phase,
    current: current,
    total: total,
    cancellable: true,
  );

  /// A sequencer operation (merge/rebase/cherry-pick/revert) stopped part-way,
  /// waiting for the user to resolve, continue, skip or abort. Nothing is
  /// running, so its bar stays still rather than animating -- an animated bar
  /// would claim work that is not happening (and never settles in a test).
  factory BackgroundTask.stoppedSequencer({
    required String id,
    required String label,
    required int current,
    required int total,
  }) => BackgroundTask(
    id: id,
    label: label,
    current: current,
    total: total,
    cancellable: false,
    waitingOnUser: true,
  );

  /// A running git invocation of one of this session's queued operations
  /// (`backgroundTasksFromOperationLog`). Its Cancel is always enabled:
  /// whether the unit can stop part-way is core's decision, not this DTO's
  /// (使用者裁定 2026-10-15: 「實作不是用 cancellable…capi不行cancel會拋錯」).
  /// The six per-kind factories this replaced (fetch/pull/push/clone with
  /// cancellable true, checkout/merge/rebase false) had no caller under lib/
  /// and encoded the opposite of that ruling.
  factory BackgroundTask.gitCommand({
    required String id,
    required String label,
    required int queuedOperationId,
  }) => BackgroundTask(
    id: id,
    label: label,
    current: 0,
    total: 0,
    cancellable: true,
    queuedOperationId: queuedOperationId,
  );

  final String id;
  final String label;
  final int current;
  final int total;

  /// What [current] / [total] count, when the task has more than one phase
  /// -- `receiving objects`, then `resolving deltas` (W-D7); else empty.
  final String phase;

  /// Whether the status bar offers Cancel. For a git command it is always
  /// true and core decides ([BackgroundTask.gitCommand]); the stopped
  /// sequencer is false because nothing is running to stop.
  final bool cancellable;

  /// The queued operation a git command's Cancel names
  /// (`RepoSessionController.cancelOperation`); 0 for every other task.
  final int queuedOperationId;

  /// When the task completed, or null if still running.
  final DateTime? finishedAt;

  /// True when the task is paused on the user rather than running; see
  /// [BackgroundTask.stoppedSequencer].
  final bool waitingOnUser;

  /// Progress as a fraction [0.0, 1.0], clamped at 1.0. `total <= 0` means
  /// the operation hasn't reported a step count yet (indeterminate), so this
  /// reads as 0.0 rather than the NaN/Infinity `current / total` would
  /// otherwise produce.
  double get progress => total <= 0 ? 0.0 : (current / total).clamp(0.0, 1.0);

  /// Immutable copy-with pattern.
  BackgroundTask copyWith({
    String? id,
    String? label,
    int? current,
    int? total,
    bool? cancellable,
    DateTime? finishedAt,
    bool? waitingOnUser,
    int? queuedOperationId,
    String? phase,
  }) => BackgroundTask(
    id: id ?? this.id,
    label: label ?? this.label,
    current: current ?? this.current,
    total: total ?? this.total,
    cancellable: cancellable ?? this.cancellable,
    finishedAt: finishedAt ?? this.finishedAt,
    waitingOnUser: waitingOnUser ?? this.waitingOnUser,
    queuedOperationId: queuedOperationId ?? this.queuedOperationId,
    phase: phase ?? this.phase,
  );
}
