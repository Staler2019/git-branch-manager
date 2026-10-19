// Zone 3 of the status bar (P10 #3, open-with-apps-spec.html screen 3): a
// red summary of the newest error the user has not seen, and a `Log` entry.
// It used to be a `!` badge for any unread line, compared by the log's
// *length* at first -- a running row replaced in place by its outcome does
// not change the length, so 執行中 → TIMEOUT with the drawer shut lit
// nothing. That case is kept below, now as an error summary.
//
// Integration tier because the halves live above StatusBar: what
// WorkspaceScreen remembers on opening the log, what it compares against,
// and what it tells the drawer to jump to.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';
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

GbmEvent _info(int id) => GbmEvent(
  GbmEventType.operationLogRecord,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'id': id,
      'running': false,
      'whenEpochMs': 2,
      'repoDir': '/test/repo',
      'argv': <String>['git', 'status'],
      'commandLine': 'git status $id',
      'exitCode': 0,
      'durationMs': 3,
      'stderrText': '',
      'cancelled': false,
      'timedOut': false,
      'benignExit': false,
      'timeoutMs': 120000,
      'idleTimeoutMs': 0,
    }),
  ),
);

Finder _summary() => find.descendant(
  of: find.byType(StatusBar),
  matching: find.text('git diff --numstat'),
);

Finder _logEntry() =>
    find.descendant(of: find.byType(StatusBar), matching: find.text('Log'));

double _drawerHeight(WidgetTester tester) =>
    tester.getSize(find.byType(LogDrawer)).height;

void main() {
  testWidgets('a running row lights nothing; its TIMEOUT outcome does', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );

    pumped.controller.debugHandleEvent(_record(running: true));
    await tester.pump();
    expect(_summary(), findsNothing, reason: 'a running row is not an error');

    pumped.controller.debugHandleEvent(_record(running: false));
    await tester.pump();
    expect(_summary(), findsOneWidget);
    expect(
      find.descendant(of: find.byType(StatusBar), matching: find.text('!')),
      findsNothing,
    );
  });

  testWidgets('the summary opens the log at that row and is then seen', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    pumped.controller.debugHandleEvent(_record(running: false));
    await tester.pump();
    expect(_drawerHeight(tester), 0);

    await tester.tap(_summary());
    await tester.pumpAndSettle();

    expect(_drawerHeight(tester), greaterThan(0));
    expect(_summary(), findsNothing, reason: 'opening marks it seen');
    final LogDrawer drawer = tester.widget<LogDrawer>(find.byType(LogDrawer));
    expect(
      identical(drawer.focusEntry, pumped.controller.state.operationLog.last),
      isTrue,
    );
    expect(find.byKey(const ValueKey<String>('log-row-focus')), findsOneWidget);
  });

  testWidgets('a newer info line after a seen error lights nothing', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    pumped.controller.debugHandleEvent(_record(running: false));
    await tester.pump();
    await tester.tap(_summary());
    await tester.pumpAndSettle();

    pumped.controller.recordAppLog(
      const AppLogEntry(
        whenEpochMs: 2,
        level: OperationLogLevel.error,
        message: 'No terminal emulator was found',
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.text('No terminal emulator was found'),
      ),
      findsOneWidget,
      reason: 'a new error is unread again',
    );
  });

  testWidgets('info and warning lines alone light nothing', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    pumped.controller.recordDraftNotSaved();
    await tester.pump();
    expect(
      pumped.controller.state.operationLog.single.level,
      OperationLogLevel.warning,
    );
    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.byWidgetPredicate(
          (Widget w) => w.key == const ValueKey<String>('status-error-summary'),
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('Log toggles the drawer, and opening it marks errors seen', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    pumped.controller.debugHandleEvent(_record(running: false));
    await tester.pump();

    await tester.tap(_logEntry());
    await tester.pumpAndSettle();
    expect(_drawerHeight(tester), greaterThan(0));
    expect(_summary(), findsNothing);

    await tester.tap(_logEntry());
    await tester.pumpAndSettle();
    expect(_drawerHeight(tester), 0);
  });

  // The drawer has no session; Save as… logs through the sink it is handed,
  // and that sink has to be this session's.
  testWidgets('the drawer logs Save as… into this session', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    expect(
      tester.widget<LogDrawer>(find.byType(LogDrawer)).sink,
      pumped.controller.recordAppLog,
    );
  });

  testWidgets('closing the log drops the jumped-to ground', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    pumped.controller.debugHandleEvent(_record(running: false));
    await tester.pump();
    await tester.tap(_summary());
    await tester.pumpAndSettle();
    expect(
      tester.widget<LogDrawer>(find.byType(LogDrawer)).focusEntry,
      isNotNull,
    );

    await tester.tap(_logEntry());
    await tester.pumpAndSettle();
    expect(tester.widget<LogDrawer>(find.byType(LogDrawer)).focusEntry, isNull);
  });

  // Ruling R3: a drag that shuts the drawer drops the ground the same moment,
  // or the next open shows a highlight for a jump the user has left behind.
  testWidgets('dragging the log shut drops the jumped-to ground', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    pumped.controller.debugHandleEvent(_record(running: false));
    await tester.pump();
    await tester.tap(_summary());
    await tester.pumpAndSettle();
    expect(
      tester.widget<LogDrawer>(find.byType(LogDrawer)).focusEntry,
      isNotNull,
    );

    // The log pane's divider is the one sitting on the drawer's top edge;
    // the workspace above holds other split panes with the same key.
    final double drawerTop = tester.getTopLeft(find.byType(LogDrawer)).dy;
    final Finder divider = find.byKey(const Key('gbm-split-divider-0'));
    final Element logDivider = divider.evaluate().reduce(
      (Element a, Element b) =>
          (tester.getCenter(find.byElementPredicate((e) => e == a)).dy -
                      drawerTop)
                  .abs() <=
              (tester.getCenter(find.byElementPredicate((e) => e == b)).dy -
                      drawerTop)
                  .abs()
          ? a
          : b,
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byElementPredicate((e) => e == logDivider)),
    );
    await tester.pump();
    for (int i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_drawerHeight(tester), 0);
    expect(tester.widget<LogDrawer>(find.byType(LogDrawer)).focusEntry, isNull);
  });

  // git keeps refreshing after a failure, so the error is rarely the newest
  // line; the jump has to scroll the drawer to it, not only paint it.
  testWidgets('the jump scrolls a far-up error into the drawer', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
    );
    pumped.controller.debugHandleEvent(_record(running: false));
    for (int i = 0; i < 200; i++) {
      pumped.controller.debugHandleEvent(_info(100 + i));
    }
    await tester.pump();

    await tester.tap(_summary());
    await tester.pumpAndSettle();

    // A drawer opened from collapsed is at its 90px minimum, which leaves
    // the list a viewport shorter than one row; "in view" here means the
    // focused row overlaps the list's viewport.
    final Finder row = find.byKey(const ValueKey<String>('log-row-focus'));
    expect(row, findsOneWidget);
    final Rect list = tester.getRect(
      find.descendant(
        of: find.byType(LogDrawer),
        matching: find.byType(ListView),
      ),
    );
    expect(tester.getRect(row).overlaps(list), isTrue);
  });
}
