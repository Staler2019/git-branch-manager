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

  // A successful clone's lines move to the new repository's Log (R12), so
  // the window that started it takes them back.
  group('retractLogEntries', () {
    test('removes the records with those ids, keeps everything else', () {
      final List<GbmLogEntry> log = retractLogEntries(
        <GbmLogEntry>[_git(1), _app(2), _git(3), _git(4, running: true)],
        <int>{1, 4},
      );
      expect(log.map((GbmLogEntry e) => e.whenEpochMs), <int>[2, 3]);
    });

    test('never matches id 0, nor an app line', () {
      final List<GbmLogEntry> log = <GbmLogEntry>[_git(0), _app(0)];
      expect(retractLogEntries(log, <int>{0}), hasLength(2));
    });
  });

  // W-D7 / P10's Log mock: a running clone row reads
  // 「git clone https://…/design-tokens — receiving objects 12,480 / 31,206」.
  group('OperationRecord progress', () {
    test('a running row carries its progress after the command', () {
      expect(
        _git(1, running: true).withProgress('receiving objects 1 / 2').message,
        'git clone — receiving objects 1 / 2',
      );
    });

    test('no progress, or a finished row, is the command alone', () {
      expect(_git(1, running: true).message, 'git clone');
      expect(
        _git(1).withProgress('receiving objects 1 / 2').message,
        'git clone',
      );
    });

    test('withProgress keeps the identity the outcome replaces by', () {
      final OperationRecord r = _git(9, running: true).withProgress('x');
      expect(r.id, 9);
      expect(r.running, isTrue);
      final List<GbmLogEntry> log = appendLogEntry(
        <GbmLogEntry>[_git(9, running: true)],
        r,
        maxEntries: 10,
      );
      expect(log.single, same(r));
    });
  });
}
