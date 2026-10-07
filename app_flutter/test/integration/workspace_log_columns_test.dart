// The two Developer → LOG switches reach the drawer the workspace draws.
// Integration tier: the preference, WorkspaceScreen's read of it and
// LogDrawer's parameter are three hops, and a unit test of either end proves
// nothing about the hop between them.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

GbmEvent _record() => GbmEvent(
  GbmEventType.operationLogRecord,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'id': 5,
      'running': false,
      'whenEpochMs': 1,
      'repoDir': '/test/repo',
      'argv': <String>['git', 'status'],
      'commandLine': 'git status',
      'exitCode': 0,
      'durationMs': 12,
      'stderrText': '',
      'cancelled': false,
      'timedOut': false,
      'benignExit': false,
      'timeoutMs': 120000,
      'idleTimeoutMs': 0,
    }),
  ),
);

LogDrawer _drawer(WidgetTester tester) =>
    tester.widget<LogDrawer>(find.byType(LogDrawer));

void main() {
  testWidgets('the drawer follows the two preferences, each on its own', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    pumped.controller.debugHandleEvent(_record());
    await tester.pump();

    expect(_drawer(tester).showTimeouts, isFalse);
    expect(_drawer(tester).showColumnHeaders, isFalse);

    await pumped.container
        .read(appPreferencesProvider.notifier)
        .update((AppPreferences p) => p.copyWith(showLogTimeouts: true));
    await tester.pump();
    expect(_drawer(tester).showTimeouts, isTrue);
    expect(_drawer(tester).showColumnHeaders, isFalse);

    await pumped.container
        .read(appPreferencesProvider.notifier)
        .update((AppPreferences p) => p.copyWith(showLogColumnHeaders: true));
    await tester.pump();
    expect(_drawer(tester).showTimeouts, isTrue);
    expect(_drawer(tester).showColumnHeaders, isTrue);
  });
}
