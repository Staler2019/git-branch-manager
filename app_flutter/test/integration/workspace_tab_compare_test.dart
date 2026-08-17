// Integration coverage for the Compare tab's open/close navigation order --
// `workspace_screen.dart`'s `_openCompareTab`/`_closeCompareTab` doc
// comments state the invariant ("navigates away first when closing the
// currently active Compare tab, so GoRouter never renders ComparePage for a
// tabId that's about to stop existing in compareTabsProvider"), but nothing
// previously drove it through the real WorkspaceScreen + GoRouter + Riverpod
// stack together to prove it holds -- compareTabsProvider is real (not
// faked) here, exactly as it is in production.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

final List<RouteBase> _compareRoute = <RouteBase>[
  GoRoute(
    path: RoutePaths.compare,
    builder: (context, state) =>
        const Scaffold(body: SizedBox(key: Key('compare-stub'))),
  ),
];

String _location(WidgetTester tester) => GoRouterState.of(
  tester.element(find.byType(WorkspaceScreen)),
).uri.toString();

Future<void> _openCompareTab(WidgetTester tester) async {
  await tester.tap(find.text('Repository'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Compare…'));
  await tester.pumpAndSettle();
}

void main() {
  group('workspace Compare tab open/close navigation', () {
    testWidgets(
      'Repository > Compare… opens a Compare tab and navigates to it',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          extraRoutes: _compareRoute,
        );

        expect(find.text('HEAD vs Working Copy'), findsNothing);

        await _openCompareTab(tester);

        expect(find.text('HEAD vs Working Copy'), findsOneWidget);
        expect(find.byKey(const Key('compare-stub')), findsOneWidget);
        expect(_location(tester), contains('/compare/'));
      },
    );

    testWidgets(
      'closing the active Compare tab navigates to History before removing '
      'it from compareTabsProvider',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          extraRoutes: _compareRoute,
        );

        await _openCompareTab(tester);
        expect(_location(tester), contains('/compare/'));

        await tester.tap(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text('HEAD vs Working Copy'),
                  matching: find.byType(InkWell),
                )
                .first,
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          _location(tester),
          RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
          reason:
              'Must navigate away from the closing tab before it stops '
              'existing in compareTabsProvider, not after.',
        );
        expect(find.text('HEAD vs Working Copy'), findsNothing);
      },
    );

    testWidgets(
      'closing a non-active Compare tab does not navigate away from the '
      'current tab',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          extraRoutes: _compareRoute,
        );

        await _openCompareTab(tester);
        final String repoId = Uri.encodeComponent(_identity.workDir);

        // Switch back to History, leaving the Compare tab open but inactive.
        await tester.tap(find.text('History'));
        await tester.pumpAndSettle();
        expect(_location(tester), RoutePaths.historyFor(repoId));

        await tester.tap(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text('HEAD vs Working Copy'),
                  matching: find.byType(InkWell),
                )
                .first,
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          _location(tester),
          RoutePaths.historyFor(repoId),
          reason:
              'Closing a Compare tab that is not the current route must not '
              'trigger any navigation.',
        );
        expect(find.text('HEAD vs Working Copy'), findsNothing);
      },
    );
  });
}
