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
}
