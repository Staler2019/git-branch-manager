// A read that fails inside a panel shows 「面板內一行失敗訊息」 with an
// `Open log` button (read-failure-states-spec.html). That button has to do
// what the status bar's red summary does -- open the drawer at the newest
// error, never close it -- so WorkspaceScreen hands the very same method to
// its subtree through [WorkspaceLogScope].
//
// Integration tier: the scope is provided by WorkspaceScreen and read from a
// ShellRoute child, which is where every panel page lives.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/workspace_log_scope.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

const String _probePath = '/scope-probe';

final List<RouteBase> _probeRoute = <RouteBase>[
  GoRoute(
    path: _probePath,
    builder: (BuildContext context, GoRouterState state) => Builder(
      builder: (BuildContext context) => GestureDetector(
        key: const ValueKey<String>('scope-probe'),
        behavior: HitTestBehavior.opaque,
        onTap: WorkspaceLogScope.maybeOf(context)?.openLogAtNewestError,
        child: const SizedBox(width: 100, height: 40),
      ),
    ),
  ),
];

double _drawerHeight(WidgetTester tester) =>
    tester.getSize(find.byType(LogDrawer)).height;

void main() {
  testWidgets('a ShellRoute child opens the log at the newest error', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      extraRoutes: _probeRoute,
    );
    pumped.controller.recordAppLog(
      const AppLogEntry(
        whenEpochMs: 1,
        level: OperationLogLevel.error,
        message: 'blame failed',
      ),
    );
    pumped.router.go(_probePath);
    await tester.pumpAndSettle();
    expect(_drawerHeight(tester), 0);

    await tester.tap(find.byKey(const ValueKey<String>('scope-probe')));
    await tester.pumpAndSettle();

    expect(_drawerHeight(tester), greaterThan(0));
    final LogDrawer drawer = tester.widget<LogDrawer>(find.byType(LogDrawer));
    expect(
      identical(drawer.focusEntry, pumped.controller.state.operationLog.last),
      isTrue,
    );
  });

  testWidgets('pressing it again leaves an open drawer open', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      extraRoutes: _probeRoute,
    );
    pumped.router.go(_probePath);
    await tester.pumpAndSettle();

    final Finder probe = find.byKey(const ValueKey<String>('scope-probe'));
    await tester.tap(probe);
    await tester.pumpAndSettle();
    expect(_drawerHeight(tester), greaterThan(0));

    await tester.tap(probe);
    await tester.pumpAndSettle();
    expect(_drawerHeight(tester), greaterThan(0));
  });
}
