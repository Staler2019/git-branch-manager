// The workspace's app-level dialogs carry `?origin=`: About and Preferences
// pass it on to Update, whose Open releases page is then logged in this
// repository's Log rather than an invisible window one (rulings R4, R13).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/origin-repo');

GoRoute _stub(String path, String name) => dialogRoute(
  path: path,
  builder: (BuildContext context, GoRouterState state) =>
      Text('$name from ${state.uri.queryParameters['origin']}'),
);

void main() {
  for (final (String menu, String item, String name)
      in <(String, String, String)>[
        ('Help', 'About', 'ABOUT'),
        ('File', 'Preferences…', 'PREFS'),
      ]) {
    testWidgets('$menu → $item names this repository as its origin', (
      tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        topLevelRoutes: <RouteBase>[
          _stub(RoutePaths.aboutDialog, 'ABOUT'),
          _stub(RoutePaths.preferencesDialog, 'PREFS'),
        ],
      );
      await tester.tap(find.text(menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();

      expect(find.text('$name from ${_identity.workDir}'), findsOneWidget);
    });
  }
}
