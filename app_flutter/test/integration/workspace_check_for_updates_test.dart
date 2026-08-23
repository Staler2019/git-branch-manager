// Help → Check for updates… driven through the real WorkspaceScreen, not a
// hand-fed handler map.
//
// CLAUDE.md records a shipped bug where menu ids were wired only via
// MenuBarRow's named params, leaving the keyboard and macOS system-menu
// paths silently dead — both of those read
// `_buildActionHandlers()`'s map directly. A widget test on MenuBarRow
// cannot see that; this can.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_menu_model.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

// An app-level dialog route, so it is a sibling of the repo ShellRoute
// rather than a child of it -- topLevelRoutes, not extraRoutes.
//
// Built with the real `dialogRoute()` rather than a plain GoRoute: that one
// is a transparent barrier route, so WorkspaceScreen stays on stage beneath
// it. A plain opaque GoRoute pushes the shell offstage, where `find` skips
// it -- which reads as "the navigation did not happen" and is a property of
// the stand-in, not of the code under test.
final List<RouteBase> _updateRoute = <RouteBase>[
  dialogRoute(
    path: RoutePaths.updateDialog,
    builder: (BuildContext context, GoRouterState state) =>
        const Text('update-dialog'),
  ),
];

void main() {
  group('Help → Check for updates…', () {
    test('the menu model declares it under Help', () {
      final GbmMenuModel help = gbmMenus.firstWhere(
        (GbmMenuModel m) => m.title == 'Help',
      );

      expect(
        help.items.map((GbmMenuItemModel i) => i.id),
        contains(GbmActionId.helpCheckForUpdates),
      );
    });

    testWidgets('clicking it opens the update dialog', (
      WidgetTester tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        topLevelRoutes: _updateRoute,
      );
      expect(find.text('update-dialog'), findsNothing);

      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates…'));
      await tester.pumpAndSettle();

      // Asserted on what is rendered, not on the router's reported location:
      // `currentConfiguration.uri` tracks the last `go`, so an imperative
      // `push` of a dialog route leaves it reading the shell's own path.
      // Measuring that instead would have failed here against working code
      // -- and does for the pre-existing About item too.
      expect(find.text('update-dialog'), findsOneWidget);
    });

    // The macOS system menu reads `_buildActionHandlers()`'s map directly,
    // where the in-window MenuBarRow can reach a handler the map does not
    // have. A null here is the exact shape of the shipped bug this file
    // exists for -- and the click test above would still pass with it.
    // `onSelected: null` is also what makes macOS grey the item out.
    testWidgets('the macOS system menu resolves it to a real handler', (
      WidgetTester tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        isMacOS: true,
        topLevelRoutes: _updateRoute,
      );

      final PlatformMenuBar bar = tester.widget<PlatformMenuBar>(
        find.byType(PlatformMenuBar),
      );
      final PlatformMenuItem item = _findItem(bar.menus, 'Check for updates…');

      expect(item.onSelected, isNotNull);
    });
  });
}

/// Walks the PlatformMenu tree for a leaf with [label], since
/// `PlatformMenuItem` is not a Widget and no finder reaches it.
PlatformMenuItem _findItem(List<PlatformMenuItem> menus, String label) {
  for (final PlatformMenuItem item in menus) {
    if (item is PlatformMenu) {
      final PlatformMenuItem? found = _tryFind(item.menus, label);
      if (found != null) return found;
    } else if (item.label == label) {
      return item;
    }
  }
  throw StateError('no menu item labelled "$label"');
}

PlatformMenuItem? _tryFind(List<PlatformMenuItem> menus, String label) {
  for (final PlatformMenuItem item in menus) {
    if (item is PlatformMenu) {
      final PlatformMenuItem? found = _tryFind(item.menus, label);
      if (found != null) return found;
    } else if (item.label == label) {
      return item;
    }
  }
  return null;
}
