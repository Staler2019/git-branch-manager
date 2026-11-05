import 'dart:async';

import 'native_error_report.dart';

/// Keeps a failing loop from flooding the Log: the first of a run of identical reports
/// goes out at once, the repeats as one line with a count. A run counts as over after
/// [quietGap] without a repeat, and its count goes out at least every [maxWait], so a
/// report that never stops is still seen to continue. Both durations are proposed
/// figures, not measured ones.
class NativeErrorCoalescer {
  NativeErrorCoalescer({
    required this._emit,
    Timer Function(Duration, void Function())? startTimer,
  }) : _startTimer = startTimer ?? Timer.new;

  static const Duration quietGap = Duration(milliseconds: 500);
  static const Duration maxWait = Duration(milliseconds: 2000);

  final void Function(NativeErrorReport) _emit;
  final Timer Function(Duration, void Function()) _startTimer;

  NativeErrorReport? _latest;
  int _repeats = 0;
  Timer? _quietTimer;
  Timer? _maxTimer;
  bool _disposed = false;

  void add(NativeErrorReport report) {
    if (_disposed) return;
    final NativeErrorReport? latest = _latest;
    if (latest != null &&
        latest.where == report.where &&
        latest.summary == report.summary) {
      _latest = report;
      _repeats++;
      _maxTimer ??= _startTimer(maxWait, _onMaxWait);
    } else {
      _endRun();
      _latest = report;
      _emit(report);
    }
    _quietTimer?.cancel();
    _quietTimer = _startTimer(quietGap, _endRun);
  }

  /// Emits the count and leaves the run going.
  void _onMaxWait() {
    _maxTimer = null;
    _flushCount();
  }

  void _endRun() {
    _quietTimer?.cancel();
    _quietTimer = null;
    _maxTimer?.cancel();
    _maxTimer = null;
    _flushCount();
    _latest = null;
  }

  void _flushCount() {
    final NativeErrorReport? latest = _latest;
    if (latest == null || _repeats == 0) return;
    final int repeats = _repeats;
    _repeats = 0;
    _emit(
      NativeErrorReport(
        when: latest.when,
        where: latest.where,
        summary: '${latest.summary} (repeated x$repeats)',
        logPath: latest.logPath,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _endRun();
  }
}
