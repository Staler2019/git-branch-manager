/// A background task in progress (fetch, pull, push, clone, checkout,
/// merge/rebase). Immutable DTO following the project's DDD + factory pattern
/// convention.
///
/// Non-cancellable tasks (checkout, merge, rebase) show a disabled Cancel
/// button with a tooltip explaining why, per the design spec. All others
/// default to cancellable.
class BackgroundTask {
  const BackgroundTask({
    required this.id,
    required this.label,
    required this.current,
    required this.total,
    required this.cancellable,
    this.finishedAt,
    this.waitingOnUser = false,
  });

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

  // Factory constructors for each task kind, auto-setting cancellable flag
  factory BackgroundTask.fetch({
    required String id,
    required String label,
    required int current,
    required int total,
  }) => BackgroundTask(
    id: id,
    label: label,
    current: current,
    total: total,
    cancellable: true,
  );

  factory BackgroundTask.pull({
    required String id,
    required String label,
    required int current,
    required int total,
  }) => BackgroundTask(
    id: id,
    label: label,
    current: current,
    total: total,
    cancellable: true,
  );

  factory BackgroundTask.push({
    required String id,
    required String label,
    required int current,
    required int total,
  }) => BackgroundTask(
    id: id,
    label: label,
    current: current,
    total: total,
    cancellable: true,
  );

  factory BackgroundTask.clone({
    required String id,
    required String label,
    required int current,
    required int total,
  }) => BackgroundTask(
    id: id,
    label: label,
    current: current,
    total: total,
    cancellable: true,
  );

  factory BackgroundTask.checkout({
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
  );

  factory BackgroundTask.merge({
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
  );

  factory BackgroundTask.rebase({
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
  );

  final String id;
  final String label;
  final int current;
  final int total;

  /// Whether this task can be safely cancelled. Checkout, merge, and rebase
  /// operations are not cancellable for safety reasons.
  final bool cancellable;

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
  }) => BackgroundTask(
    id: id ?? this.id,
    label: label ?? this.label,
    current: current ?? this.current,
    total: total ?? this.total,
    cancellable: cancellable ?? this.cancellable,
    finishedAt: finishedAt ?? this.finishedAt,
    waitingOnUser: waitingOnUser ?? this.waitingOnUser,
  );
}
