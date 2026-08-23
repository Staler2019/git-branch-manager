import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';

/// A record with every field defaulted except the three the level machine
/// reads, so a test that names `cancelled`/`timedOut`/`exitCode` is naming
/// the whole input.
OperationRecord record({
  bool cancelled = false,
  bool timedOut = false,
  int exitCode = 0,
}) {
  return OperationRecord(
    whenEpochMs: 0,
    repoDir: '/repo',
    argv: const <String>['git', 'status'],
    commandLine: 'git status',
    exitCode: exitCode,
    durationMs: 1,
    stderrText: '',
    cancelled: cancelled,
    timedOut: timedOut,
  );
}

void main() {
  group('OperationRecord.level', () {
    test('a clean exit is info', () {
      expect(record().level, OperationLogLevel.info);
    });

    test('a cancelled read is warning, not error -- even with exit 143', () {
      // The reported case: Session::refreshHistory() SIGTERMs the in-flight
      // for-each-ref before posting a newer one, so the superseded read is
      // recorded as cancelled with 128 + SIGTERM = 143. Classifying that as
      // an error is what made a healthy refresh look like a failure.
      expect(
        record(cancelled: true, exitCode: 143).level,
        OperationLogLevel.warning,
      );
    });

    test('cancelled wins over a non-zero exit code', () {
      // Not redundant with the case above: it pins the *ordering*. A
      // terminated child always carries a non-zero exit code, so checking
      // exitCode first would make the cancelled branch unreachable.
      expect(
        record(cancelled: true, exitCode: 1).level,
        OperationLogLevel.warning,
      );
    });

    test('a timeout is error', () {
      expect(
        record(timedOut: true, exitCode: 143).level,
        OperationLogLevel.error,
      );
    });

    test('a non-zero exit with no cancel or timeout is error', () {
      expect(record(exitCode: 1).level, OperationLogLevel.error);
    });

    test('cancelled wins over timedOut', () {
      expect(
        record(cancelled: true, timedOut: true, exitCode: 143).level,
        OperationLogLevel.warning,
      );
    });
  });

  group('OperationRecord.levelLabel', () {
    test('matches the level for every combination', () {
      for (final bool cancelled in <bool>[false, true]) {
        for (final bool timedOut in <bool>[false, true]) {
          for (final int exitCode in <int>[0, 1, 143]) {
            final OperationRecord r = record(
              cancelled: cancelled,
              timedOut: timedOut,
              exitCode: exitCode,
            );
            final String expected = switch (r.level) {
              OperationLogLevel.info => 'INFO',
              OperationLogLevel.warning => 'CANCELLED',
              OperationLogLevel.error => timedOut ? 'TIMEOUT' : 'ERROR',
            };
            expect(
              r.levelLabel,
              expected,
              reason:
                  'cancelled=$cancelled timedOut=$timedOut exitCode=$exitCode',
            );
          }
        }
      }
    });

    test('the reported for-each-ref row reads CANCELLED', () {
      expect(record(cancelled: true, exitCode: 143).levelLabel, 'CANCELLED');
    });

    test('a timeout reads TIMEOUT, not ERROR', () {
      expect(record(timedOut: true, exitCode: 143).levelLabel, 'TIMEOUT');
    });
  });

  group('the three levels partition every record', () {
    test('no record can satisfy two levels at once', () {
      // The defect this replaces: LogDrawer's warning filter was
      // `failed && !cancelled && !timedOut` while its error filter was
      // `cancelled || timedOut || exitCode != 0` -- warning was a strict
      // subset of error, so selecting Error also showed every warning.
      for (final bool cancelled in <bool>[false, true]) {
        for (final bool timedOut in <bool>[false, true]) {
          for (final int exitCode in <int>[0, 1, 143]) {
            final OperationLogLevel level = record(
              cancelled: cancelled,
              timedOut: timedOut,
              exitCode: exitCode,
            ).level;
            expect(OperationLogLevel.values.where((l) => l == level).length, 1);
          }
        }
      }
    });
  });
}
