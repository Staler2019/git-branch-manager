// TabRow is presentational (no Riverpod/FFI dependency, same split as
// MenuBarRow -- see its doc comment), so this drives it directly with
// GoRouter + a plain pendingChangeCount int: History/Working Copy tabs
// navigate to the expected route, and the Working Copy tab shows a
// change-count badge only when there is something to show.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/workspace/widgets/tab_row.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

const String _repoId = 'repo1';

Future<GoRouter> _pump(
  WidgetTester tester, {
  required int pendingChangeCount,
  String initialLocation = '',
}) async {
  final GoRouter router = GoRouter(
    initialLocation: initialLocation.isEmpty
        ? RoutePaths.historyFor(_repoId)
        : initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: TabRow(repoId: _repoId, pendingChangeCount: pendingChangeCount),
        ),
      ),
      GoRoute(
        path: RoutePaths.workingCopy,
        builder: (context, state) => Scaffold(
          body: TabRow(repoId: _repoId, pendingChangeCount: pendingChangeCount),
        ),
      ),
      GoRoute(
        path: RoutePaths.mergeDialog,
        builder: (context, state) => const Scaffold(body: Text('merge-dialog')),
      ),
      GoRoute(
        path: RoutePaths.manageStashesDialog,
        builder: (context, state) =>
            const Scaffold(body: Text('manage-stashes-dialog')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      routerConfig: router,
    ),
  );
  return router;
}

void main() {
  testWidgets(
    'shows no badge on Working Copy when there are no pending changes',
    (tester) async {
      await _pump(tester, pendingChangeCount: 0);
      expect(find.text('Working Copy'), findsOneWidget);
      expect(find.byKey(const Key('tab-row-pending-badge')), findsNothing);
    },
  );

  testWidgets('shows the pending change count as a badge on Working Copy', (
    tester,
  ) async {
    await _pump(tester, pendingChangeCount: 3);
    expect(find.byKey(const Key('tab-row-pending-badge')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping Working Copy navigates to the working-copy route', (
    tester,
  ) async {
    final GoRouter router = await _pump(tester, pendingChangeCount: 1);
    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      RoutePaths.workingCopyFor(_repoId),
    );
  });

  testWidgets('Merge button pushes the merge dialog route', (tester) async {
    await _pump(tester, pendingChangeCount: 0);
    await tester.tap(find.text('Merge…'));
    await tester.pumpAndSettle();
    expect(find.text('merge-dialog'), findsOneWidget);
  });

  testWidgets(
    'More menu lists all 18 items via showGbmMenu (not Material PopupMenuButton chrome)',
    (tester) async {
      await _pump(tester, pendingChangeCount: 0);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      // Not a Material PopupMenuButton overlay -- see tab_row.dart's
      // _MoreMenu doc comment on why this must go through showGbmMenu.
      expect(find.byType(PopupMenuButton<String>), findsNothing);

      for (final String label in const <String>[
        'Stash Changes…',
        'Manage Stashes…',
        'Create Tag…',
        'Manage Worktrees…',
        'Remotes…',
        'Operation Log…',
        'Blame…',
        'File History…',
        'Line History…',
        'Reflog…',
        'Undo Last Operation…',
        'Interactive Rebase…',
        'Submodules…',
        'Bisect…',
        'Git LFS…',
        'Patches…',
        'Clean Untracked…',
        'Preferences…',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    },
  );

  testWidgets('More menu > Manage Stashes… pushes the manage-stashes route', (
    tester,
  ) async {
    await _pump(tester, pendingChangeCount: 0);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Stashes…'));
    await tester.pumpAndSettle();
    expect(find.text('manage-stashes-dialog'), findsOneWidget);
  });
}
