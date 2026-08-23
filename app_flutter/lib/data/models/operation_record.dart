/// Which of spec page 10's three `LOGRULES` severity levels an
/// [OperationRecord] belongs to.
///
/// Deliberately three values, matching the drawer's filter buttons, rather
/// than one per outcome shape: `CANCELLED` and `TIMEOUT` are both outcome
/// *causes*, and conflating "which cause" with "how bad" is what let the
/// drawer's warning filter become a strict subset of its error filter.
enum OperationLogLevel { info, warning, error }

/// Mirrors `gbm::OperationRecord` (src/core/base/Logging.h) as serialized by
/// `capi::toJson(const OperationRecord&)` -- one `git` invocation, for an
/// operation-log panel.
class OperationRecord {
  const OperationRecord({
    required this.whenEpochMs,
    required this.repoDir,
    required this.argv,
    required this.commandLine,
    required this.exitCode,
    required this.durationMs,
    required this.stderrText,
    required this.cancelled,
    required this.timedOut,
  });

  factory OperationRecord.fromJson(Map<String, dynamic> json) {
    return OperationRecord(
      whenEpochMs: json['whenEpochMs'] as int,
      repoDir: json['repoDir'] as String,
      argv: (json['argv'] as List<dynamic>).cast<String>(),
      commandLine: json['commandLine'] as String,
      exitCode: json['exitCode'] as int,
      durationMs: json['durationMs'] as int,
      stderrText: json['stderrText'] as String,
      cancelled: json['cancelled'] as bool,
      timedOut: json['timedOut'] as bool,
    );
  }

  final int whenEpochMs;
  final String repoDir;
  final List<String> argv;
  final String commandLine;
  final int exitCode;
  final int durationMs;
  final String stderrText;
  final bool cancelled;
  final bool timedOut;

  bool get failed => exitCode != 0 || cancelled || timedOut;

  /// The single source of truth for how severely this record should read --
  /// the drawer's filter, its row styling, and the plain-text export all go
  /// through here rather than re-deriving the conditions locally.
  ///
  /// [cancelled] must be tested *first*: a child killed by
  /// `ProcessRunner::execute()`'s cancel path also carries a non-zero exit
  /// code (SIGTERM leaves 128 + 15 = 143), so checking [exitCode] first
  /// makes the cancelled branch unreachable and reports a superseded read as
  /// a failure. That is exactly the misreport this getter was added to fix:
  /// `Session::refreshHistory()` terminates the in-flight `for-each-ref`
  /// whenever a newer refresh is posted, and the abandoned one is not an
  /// error -- it is work that was replaced. Spec's `LOGRULES` reserves
  /// error for an action that was actually refused (`git push … exit 1`).
  OperationLogLevel get level {
    if (cancelled) return OperationLogLevel.warning;
    if (timedOut || exitCode != 0) return OperationLogLevel.error;
    return OperationLogLevel.info;
  }

  /// The level word shown on a log row and written into the plain-text
  /// export, so the two cannot drift apart.
  ///
  /// Switches on [level] and nothing else -- a second, independent condition
  /// tree over [cancelled]/[exitCode] is how the drawer's filter and its
  /// export came to disagree in the first place. `TIMEOUT` is a refinement
  /// *within* error, so it cannot contradict the level.
  ///
  /// `warning` maps to `CANCELLED` because cancellation is currently its
  /// only cause; a second warning cause must split this arm rather than
  /// widen the word.
  String get levelLabel => switch (level) {
    OperationLogLevel.info => 'INFO',
    OperationLogLevel.warning => 'CANCELLED',
    OperationLogLevel.error => timedOut ? 'TIMEOUT' : 'ERROR',
  };
}
