// OperationRecord.isAutoFetch: core marks a background fetch only by its
// argv (`RemoteOps.cpp` adds `--no-auto-maintenance --no-write-fetch-head`
// when `FetchRequest.background`; pinned by RemoteOpsTest's
// BackgroundFetchSkipsMaintenanceAndFetchHead).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';

OperationRecord _record(List<String> args) => OperationRecord(
  whenEpochMs: 0,
  repoDir: '/repo',
  argv: <String>['git', '-C', '/repo', ...args],
  commandLine: '',
  exitCode: 0,
  durationMs: 0,
  stderrText: '',
  cancelled: false,
  timedOut: false,
  id: 1,
  running: true,
  queuedOperationId: 1,
);

void main() {
  test('a fetch carrying the background flags is an auto fetch', () {
    expect(
      _record(<String>[
        'fetch',
        '--no-auto-maintenance',
        '--no-write-fetch-head',
        '--all',
      ]).isAutoFetch,
      isTrue,
    );
  });

  test('a manual fetch is not', () {
    expect(_record(<String>['fetch', '--all']).isAutoFetch, isFalse);
  });

  test('each flag alone is not enough', () {
    expect(
      _record(<String>['fetch', '--no-write-fetch-head']).isAutoFetch,
      isFalse,
    );
    expect(
      _record(<String>['fetch', '--no-auto-maintenance']).isAutoFetch,
      isFalse,
    );
  });

  test('another command carrying the flags is not', () {
    expect(
      _record(<String>[
        'pull',
        '--no-auto-maintenance',
        '--no-write-fetch-head',
      ]).isAutoFetch,
      isFalse,
    );
  });
}
