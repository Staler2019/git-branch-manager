// The status bar's `!` says the log holds something not yet seen. It used to
// compare the log's *length* with the length when the drawer was last
// opened, and a running row replaced in place by its outcome does not change
// the length -- so 執行中 → TIMEOUT with the drawer shut lit nothing.
//
// Integration tier because both halves live above StatusBar: what
// WorkspaceScreen remembers on opening the log, and what it compares against.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

GbmEvent _record({required bool running}) => GbmEvent(
  GbmEventType.operationLogRecord,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'id': 41,
      'running': running,
      'whenEpochMs': 1,
      'repoDir': '/test/repo',
      'argv': <String>['git', 'diff', '--numstat'],
      'commandLine': 'git diff --numstat',
      'exitCode': running ? 0 : 1,
      'durationMs': running ? 0 : 120000,
      'stderrText': '',
      'cancelled': false,
      'timedOut': !running,
      'benignExit': false,
      'timeoutMs': 120000,
      'idleTimeoutMs': 0,
    }),
  ),
);

Finder _badge() =>
    find.descendant(of: find.byType(StatusBar), matching: find.text('!'));

void main() {
  testWidgets('a running row turning into TIMEOUT lights the badge again', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );

    pumped.controller.debugHandleEvent(_record(running: true));
    await tester.pump();
    expect(_badge(), findsOneWidget);

    await tester.tap(_badge());
    await tester.pump();
    expect(_badge(), findsNothing, reason: 'opening the log marks it seen');

    pumped.controller.debugHandleEvent(_record(running: false));
    await tester.pump();
    expect(_badge(), findsOneWidget);
  });
}
