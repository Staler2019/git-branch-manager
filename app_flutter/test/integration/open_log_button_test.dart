// The `Open log` button on a panel's failure banner
// (read-failure-states-spec.html) opens the drawer the way the status bar's
// red summary does, and -- unlike View → Log, which toggles -- never closes a
// drawer the user is already reading.
//
// Integration tier: the button reads WorkspaceLogScope, which only the real
// WorkspaceScreen provides, from a ShellRoute child like every panel page.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

const String _bannerPath = '/banner-probe';

final List<RouteBase> _bannerRoute = <RouteBase>[
  GoRoute(
    path: _bannerPath,
    builder: (BuildContext context, GoRouterState state) =>
        const GbmWarningBanner(
          message: 'blame failed',
          action: GbmOpenLogButton(),
        ),
  ),
];

double _drawerHeight(WidgetTester tester) =>
    tester.getSize(find.byType(LogDrawer)).height;

Future<void> _showBanner(WidgetTester tester) async {
  final PumpedWorkspace pumped = await pumpWorkspace(
    tester,
    identity: _identity,
    extraRoutes: _bannerRoute,
  );
  pumped.router.go(_bannerPath);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with the drawer closed, Open log opens it', (tester) async {
    await _showBanner(tester);
    expect(_drawerHeight(tester), 0);

    await tester.tap(find.text('Open log'));
    await tester.pumpAndSettle();

    expect(_drawerHeight(tester), greaterThan(0));
  });

  testWidgets('with the drawer already open, Open log keeps it open', (
    tester,
  ) async {
    await _showBanner(tester);
    await tester.tap(find.text('Open log'));
    await tester.pumpAndSettle();
    expect(_drawerHeight(tester), greaterThan(0));

    await tester.tap(find.text('Open log'));
    await tester.pumpAndSettle();

    expect(_drawerHeight(tester), greaterThan(0));
  });
}
