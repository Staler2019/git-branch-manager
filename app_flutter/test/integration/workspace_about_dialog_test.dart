// Help → About driven through the real WorkspaceScreen, on both of the
// dispatch paths that can render a menu: the in-window MenuBarRow that
// Windows and Linux draw, and the macOS system menu bar.
//
// The bug this file exists for is *not* a null handler. `helpAbout` was
// wired in `_buildActionHandlers()` all along -- but on macOS
// `PlatformMenuBarHost` listed it as system-provided and appended a
// `PlatformProvidedMenuItem(type: about)` instead, which opens the native
// macOS About panel. So the same action id rendered two different windows,
// and every existing assertion stayed green: the in-window path really did
// open the dialog, and no test called the macOS item's handler.
//
// Hence the shape below -- a handler is *invoked* and what it renders is
// asserted. `onSelected != null` cannot tell one route from another, which
// is exactly how a system-provided item slipped past.
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

// App-level dialog routes, so they are siblings of the repo ShellRoute
// rather than children of it -- topLevelRoutes, not extraRoutes.
//
// Built with the real `dialogRoute()` rather than a plain GoRoute: that one
// is a transparent barrier route, so WorkspaceScreen stays on stage beneath
// it. A plain opaque GoRoute pushes the shell offstage, where `find` skips
// it -- which reads as "the navigation did not happen" and is a property of
// the stand-in, not of the code under test.
//
// The keyboard-shortcuts route is here only as a *decoy*: it is the other
// dialog the Help menu opens, so a handler pointing at the wrong one still
// finds a route and still renders something. Without it, mis-wiring About
// would fail on a missing route rather than on the wrong content, and the
// assertions below would be proving less than they look like they prove.
final List<RouteBase> _dialogRoutes = <RouteBase>[
  dialogRoute(
    path: RoutePaths.aboutDialog,
    builder: (BuildContext context, GoRouterState state) =>
        const Text('about-dialog'),
  ),
  dialogRoute(
    path: RoutePaths.keyboardShortcutsDialog,
    builder: (BuildContext context, GoRouterState state) =>
        const Text('shortcuts-dialog'),
  ),
];

void main() {
  group('Help → About', () {
    test('the menu model declares it under Help', () {
      final GbmMenuModel help = gbmMenus.firstWhere(
        (GbmMenuModel m) => m.title == 'Help',
      );

      expect(
        help.items.map((GbmMenuItemModel i) => i.id),
        contains(GbmActionId.helpAbout),
      );
    });

    testWidgets('the in-window menu opens the Flutter dialog', (
      WidgetTester tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        topLevelRoutes: _dialogRoutes,
      );
      expect(find.text('about-dialog'), findsNothing);

      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      // Asserted on what is rendered, not on the router's reported location:
      // `currentConfiguration.uri` tracks the last `go`, so an imperative
      // `push` of a dialog route leaves it reading the shell's own path.
      expect(find.text('about-dialog'), findsOneWidget);
      expect(find.text('shortcuts-dialog'), findsNothing);
    });

    // The macOS half. Two assertions, and the second is the load-bearing
    // one: a system-provided item has no `onSelected` to invoke at all, so
    // the first line below is what catches About being handed back to the
    // OS, and the second is what catches it being handed to the wrong
    // route.
    testWidgets('the macOS system menu opens the same Flutter dialog', (
      WidgetTester tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        isMacOS: true,
        topLevelRoutes: _dialogRoutes,
      );

      final PlatformMenuBar bar = tester.widget<PlatformMenuBar>(
        find.byType(PlatformMenuBar),
      );
      final PlatformMenuItem item = _findItem(bar.menus, 'About');

      expect(
        item.onSelected,
        isNotNull,
        reason:
            'a null handler is how macOS greys an item out, and a '
            'system-provided About has no handler here at all',
      );

      item.onSelected!();
      await tester.pumpAndSettle();

      expect(find.text('about-dialog'), findsOneWidget);
      expect(find.text('shortcuts-dialog'), findsNothing);
    });
  });
}

/// Walks the PlatformMenu tree for a leaf with [label], since
/// `PlatformMenuItem` is not a Widget and no finder reaches it.
PlatformMenuItem _findItem(List<PlatformMenuItem> menus, String label) {
  final PlatformMenuItem? found = _tryFind(menus, label);
  if (found == null) throw StateError('no menu item labelled "$label"');
  return found;
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
