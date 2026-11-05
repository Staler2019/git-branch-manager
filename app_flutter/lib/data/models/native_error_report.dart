import 'operation_record.dart' show escapeControlChars;
import 'url_credential_redaction.dart';

/// A failure `gbm_capi` caught and could not return to anyone
/// (`gbm_set_native_error_callback`). Native text can quote a URL or repository content,
/// so what is kept here is already masked and on one line.
class NativeErrorReport {
  const NativeErrorReport({
    required this.when,
    required this.where,
    required this.summary,
    required this.logPath,
  });

  /// Throws [TypeError] when a field is missing or of another type, [RangeError] when
  /// the time is out of range.
  factory NativeErrorReport.fromJson(Map<String, dynamic> json) {
    return NativeErrorReport(
      when: DateTime.fromMillisecondsSinceEpoch(json['whenEpochMs'] as int),
      where: _forDisplay(json['where'] as String),
      summary: _forDisplay(json['summary'] as String),
      logPath: escapeControlChars(json['logPath'] as String),
    );
  }

  /// For a payload that cannot be parsed; none of its text is kept, since nothing
  /// could mask it.
  factory NativeErrorReport.unreadable(DateTime when) => NativeErrorReport(
    when: when,
    where: 'native error channel',
    summary: 'a report could not be read',
    logPath: '',
  );

  final DateTime when;
  final String where;
  final String summary;
  final String logPath;

  static String _forDisplay(String text) =>
      escapeControlChars(redactUrlCredentials(text));
}
