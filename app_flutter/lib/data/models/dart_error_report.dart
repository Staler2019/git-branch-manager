import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'url_credential_redaction.dart';

/// A Dart error on its way to the native error log (`gbm_report_external_error`).
///
/// [summary] reaches the Log of every open repository, so it never quotes data a type is
/// known to carry: a path, an address, an argument list or an argument's value. [detail]
/// goes to the per-user log file only, as the whole text and stack, masked by
/// [redactUrlCredentials] and capped at [maxDetailBytes]. That mask has known gaps, and a
/// Flutter diagnostic can quote widget text, so the file is the one place either reaches.
class DartErrorReport {
  const DartErrorReport({
    required this.where,
    required this.type,
    required this.summary,
    required this.detail,
  });

  factory DartErrorReport.fromError({
    required String where,
    required Object error,
    StackTrace? stack,
  }) {
    final String detail = stack == null ? '$error' : '$error\n$stack';
    return DartErrorReport(
      where: where,
      type: '${error.runtimeType}',
      summary: redactUrlCredentials(_summaryOf(error)),
      detail: _capped(redactUrlCredentials(detail)),
    );
  }

  static const int maxDetailBytes = 16 * 1024;
  static const String truncatedMarker = ' …[truncated]';

  final String where;

  /// The limiter's key: a message that differs every time (an overflow's pixel count)
  /// still repeats one type.
  final String type;
  final String summary;
  final String detail;

  DartErrorReport withSummary(String summary) => DartErrorReport(
    where: where,
    type: type,
    summary: summary,
    detail: detail,
  );

  static String _summaryOf(Object error) {
    final String type = '${error.runtimeType}';
    return switch (error) {
      FileSystemException(:final OSError? osError) => _withCode(
        type,
        osError?.errorCode,
      ),
      SocketException(:final OSError? osError) => _withCode(
        type,
        osError?.errorCode,
      ),
      TlsException(:final OSError? osError) => _withCode(
        type,
        osError?.errorCode,
      ),
      ProcessException(:final int errorCode) => _withCode(type, errorCode),
      HttpException() => type,
      ArgumentError(:final String? name) =>
        name == null ? type : '$type ($name)',
      _ => '$type: ${'$error'.split('\n').first}',
    };
  }

  static String _withCode(String type, int? code) =>
      code == null ? type : '$type (os error $code)';

  static String _capped(String detail) {
    final List<int> bytes = utf8.encode(detail);
    if (bytes.length <= maxDetailBytes) return detail;
    final int keep = maxDetailBytes - utf8.encode(truncatedMarker).length;
    int end = keep;
    // Back off continuation bytes so the cut lands on a character boundary.
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end--;
    }
    return utf8.decode(bytes.sublist(0, end)) + truncatedMarker;
  }
}

/// Keeps a failing build from flooding the file and every Log. Repeats of one [type] in one
/// place within [repeatWindow] become one count line, and at most [maxPerWindow] reports go
/// out per [capWindow], whatever their type, then one line says how many were held back.
/// The figures are proposed, not measured.
class DartErrorLimiter {
  DartErrorLimiter({
    required this._emit,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? startTimer,
  }) : _now = now ?? DateTime.now,
       _startTimer = startTimer ?? Timer.new;

  static const Duration repeatWindow = Duration(seconds: 2);
  static const Duration capWindow = Duration(seconds: 60);
  static const int maxPerWindow = 20;

  final void Function(DartErrorReport) _emit;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _startTimer;

  DartErrorReport? _latest;
  DateTime? _latestAt;
  int _repeats = 0;
  Timer? _repeatTimer;
  int _sentInWindow = 0;
  int _suppressed = 0;
  Timer? _capTimer;
  bool _disposed = false;

  void add(DartErrorReport report) {
    if (_disposed) return;
    final DateTime now = _now();
    final DartErrorReport? latest = _latest;
    final DateTime? latestAt = _latestAt;
    if (latest != null &&
        latestAt != null &&
        latest.where == report.where &&
        latest.type == report.type &&
        now.difference(latestAt) < repeatWindow) {
      _latest = report;
      _latestAt = now;
      _repeats++;
      _repeatTimer ??= _startTimer(repeatWindow, _flushRepeats);
      return;
    }
    _flushRepeats();
    _latest = report;
    _latestAt = now;
    _send(report);
  }

  void _send(DartErrorReport report) {
    _capTimer ??= _startTimer(capWindow, _endCapWindow);
    if (_sentInWindow >= maxPerWindow) {
      _suppressed++;
      return;
    }
    _sentInWindow++;
    _emit(report);
  }

  void _flushRepeats() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    final DartErrorReport? latest = _latest;
    if (latest == null || _repeats == 0) return;
    final int repeats = _repeats;
    _repeats = 0;
    _send(latest.withSummary('${latest.summary} (repeated x$repeats)'));
  }

  void _endCapWindow() {
    _capTimer = null;
    final int suppressed = _suppressed;
    _sentInWindow = 0;
    _suppressed = 0;
    if (suppressed == 0) return;
    _emit(
      DartErrorReport(
        where: 'DartErrorLimiter',
        type: 'DartErrorLimiter',
        summary: '$suppressed more errors suppressed',
        detail: '$suppressed more errors suppressed',
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _repeatTimer?.cancel();
    _capTimer?.cancel();
  }
}
