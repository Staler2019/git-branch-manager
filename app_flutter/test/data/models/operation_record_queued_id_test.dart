// `queuedOperationId` names the queued operation (one capi unit) a git
// invocation ran for -- what the status bar's Cancel hands to
// gbm_cancel_operation(). 0 means none, or another session's operation.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';

Map<String, dynamic> _json({Object? queuedOperationId}) => <String, dynamic>{
  'id': 3,
  'running': true,
  'whenEpochMs': 0,
  'repoDir': '/repo',
  'argv': <String>['git', 'fetch', 'origin'],
  'commandLine': 'git fetch origin',
  'exitCode': 0,
  'durationMs': 0,
  'stderrText': '',
  'cancelled': false,
  'timedOut': false,
  'benignExit': false,
  'timeoutMs': 0,
  'idleTimeoutMs': 60000,
  'queuedOperationId': ?queuedOperationId,
};

void main() {
  test('decodes the queued operation id core stamped', () {
    expect(
      OperationRecord.fromJson(_json(queuedOperationId: 41)).queuedOperationId,
      41,
    );
  });

  test('a record without the key decodes as 0 rather than throwing', () {
    // Deliberately lenient, unlike every other key: a native library built
    // before the field existed must not turn every log event into a
    // TypeError, which _onEvent does not catch.
    expect(OperationRecord.fromJson(_json()).queuedOperationId, 0);
  });
}
