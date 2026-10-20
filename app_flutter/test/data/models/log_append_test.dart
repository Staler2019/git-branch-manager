import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';

OperationRecord _git(int id, {bool running = false, int exitCode = 0}) =>
    OperationRecord(
      whenEpochMs: id,
      repoDir: '',
      argv: const <String>['clone'],
      commandLine: 'git clone',
      exitCode: exitCode,
      durationMs: 0,
      stderrText: '',
      cancelled: false,
      timedOut: false,
      id: id,
      running: running,
    );

AppLogEntry _app(int n) => AppLogEntry(
  whenEpochMs: n,
  level: OperationLogLevel.info,
  message: 'line $n',
);

void main() {
  group('appendLogEntry', () {
    test('appends to the end', () {
      final List<GbmLogEntry> log = appendLogEntry(
        <GbmLogEntry>[_app(1)],
        _app(2),
        maxEntries: 10,
      );
      expect(log.map((GbmLogEntry e) => e.whenEpochMs), <int>[1, 2]);
    });

    test('evicts the oldest once over the cap', () {
      final List<GbmLogEntry> log = appendLogEntry(
        <GbmLogEntry>[_app(1), _app(2)],
        _app(3),
        maxEntries: 2,
      );
      expect(log.map((GbmLogEntry e) => e.whenEpochMs), <int>[2, 3]);
    });

    test('an outcome replaces its own running row where it stands', () {
      final List<GbmLogEntry> log = appendLogEntry(
        <GbmLogEntry>[_git(7, running: true), _app(8)],
        _git(7, exitCode: 128),
        maxEntries: 10,
      );
      expect(log.length, 2);
      expect((log.first as OperationRecord).running, isFalse);
      expect((log.first as OperationRecord).exitCode, 128);
    });

    test('id 0 never replaces anything', () {
      final List<GbmLogEntry> log = appendLogEntry(
        <GbmLogEntry>[_git(0, running: true)],
        _git(0),
        maxEntries: 10,
      );
      expect(log.length, 2);
    });
  });
}
