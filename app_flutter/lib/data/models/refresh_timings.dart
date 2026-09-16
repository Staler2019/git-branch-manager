/// One focus-regain sweep's timing readout: how long each stage of
/// `RepoSessionController.refreshRepoStatus()` took to land.
///
/// Reset to a fresh instance (only [focusAt] set) at the start of every
/// sweep -- see `RepoSessionController.refreshRepoStatus()`. Each later
/// stamp is written through `stamp*IfAbsent`, which only fills a still-null
/// field: a sweep's *first* refs/status/diff reply is what the user
/// actually waited on, and a later reply from the same sweep (a second
/// file's diff, a retried request) must not push the number around.
class RefreshTimings {
  const RefreshTimings({
    this.focusAt,
    this.refsAt,
    this.statusAt,
    this.firstDiffAt,
    this.backgroundDoneAt,
  });

  /// The instant `refreshRepoStatus()` was called -- t0 of the sweep.
  final DateTime? focusAt;

  /// `GBM_EVENT_REFS_UPDATED` landed -- the current branch is now correct.
  final DateTime? refsAt;

  /// `GBM_EVENT_WORKING_COPY_STATUS_UPDATED` landed.
  final DateTime? statusAt;

  /// The first `GBM_EVENT_WORKING_COPY_DIFF_READY` of this sweep landed --
  /// the money number: how long until the diff pane is readable again.
  final DateTime? firstDiffAt;

  /// The deferred (tier 2) half of the sweep finished -- see
  /// `RepoSessionController`'s tiering. Null until tiering lands.
  final DateTime? backgroundDoneAt;

  RefreshTimings copyWith({
    DateTime? focusAt,
    DateTime? refsAt,
    DateTime? statusAt,
    DateTime? firstDiffAt,
    DateTime? backgroundDoneAt,
  }) {
    return RefreshTimings(
      focusAt: focusAt ?? this.focusAt,
      refsAt: refsAt ?? this.refsAt,
      statusAt: statusAt ?? this.statusAt,
      firstDiffAt: firstDiffAt ?? this.firstDiffAt,
      backgroundDoneAt: backgroundDoneAt ?? this.backgroundDoneAt,
    );
  }

  RefreshTimings stampRefsIfAbsent(DateTime at) =>
      refsAt == null ? copyWith(refsAt: at) : this;

  RefreshTimings stampStatusIfAbsent(DateTime at) =>
      statusAt == null ? copyWith(statusAt: at) : this;

  RefreshTimings stampFirstDiffIfAbsent(DateTime at) =>
      firstDiffAt == null ? copyWith(firstDiffAt: at) : this;

  RefreshTimings stampBackgroundDoneIfAbsent(DateTime at) =>
      backgroundDoneAt == null ? copyWith(backgroundDoneAt: at) : this;

  /// The span the user actually experiences as "the diff pane came back" --
  /// null until both ends of it are known.
  Duration? get statusToFirstDiff => (statusAt == null || firstDiffAt == null)
      ? null
      : firstDiffAt!.difference(statusAt!);
}

/// Renders [t] as `refs 7ms · status 32ms · diff 118ms` -- one segment per
/// stamp that has landed so far, each an offset from [RefreshTimings.focusAt],
/// in stage order. `''` before the first stamp lands (nothing to show yet).
///
/// This is what `showRefreshTimings` paints on the status bar
/// (`StatusBar`'s repo-status zone) and what the `debugPrint` line in
/// `RepoSessionController` logs, so the two read identically.
String refreshTimingsLabel(RefreshTimings t) {
  final DateTime? focus = t.focusAt;
  if (focus == null) return '';

  final List<String> segments = <String>[
    if (t.refsAt case final DateTime at)
      'refs ${at.difference(focus).inMilliseconds}ms',
    if (t.statusAt case final DateTime at)
      'status ${at.difference(focus).inMilliseconds}ms',
    if (t.firstDiffAt case final DateTime at)
      'diff ${at.difference(focus).inMilliseconds}ms',
    if (t.backgroundDoneAt case final DateTime at)
      'bg ${at.difference(focus).inMilliseconds}ms',
  ];
  return segments.join(' · ');
}
