// TabRow is presentational (no Riverpod/FFI dependency, same split as
// MenuBarRow -- see its doc comment), so this drives it directly with
// GoRouter + a plain pendingChangeCount int: History/Working Copy tabs
// navigate to the expected route, and the Working Copy tab shows a
// change-count badge only when there is something to show.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
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
  List<CompareTabSpec> compareTabs = const <CompareTabSpec>[],
  ValueChanged<String>? onCloseCompareTab,
  bool conflictActive = false,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: initialLocation.isEmpty
        ? RoutePaths.historyFor(_repoId)
        : initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: TabRow(
            repoId: _repoId,
            pendingChangeCount: pendingChangeCount,
            compareTabs: compareTabs,
            onCloseCompareTab: onCloseCompareTab,
            conflictActive: conflictActive,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.workingCopy,
        builder: (context, state) => Scaffold(
          body: TabRow(
            repoId: _repoId,
            pendingChangeCount: pendingChangeCount,
            compareTabs: compareTabs,
            onCloseCompareTab: onCloseCompareTab,
            conflictActive: conflictActive,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.compare,
        builder: (context, state) => Scaffold(
          body: TabRow(
            repoId: _repoId,
            pendingChangeCount: pendingChangeCount,
            compareTabs: compareTabs,
            onCloseCompareTab: onCloseCompareTab,
            conflictActive: conflictActive,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.mergeDialog,
        builder: (context, state) => const Scaffold(body: Text('merge-dialog')),
      ),
      GoRoute(
        path: RoutePaths.cherryPickDialog,
        builder: (context, state) =>
            const Scaffold(body: Text('cherry-pick-dialog')),
      ),
      GoRoute(
        path: RoutePaths.resetBranchDialog,
        builder: (context, state) =>
            const Scaffold(body: Text('reset-branch-dialog')),
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

  testWidgets('Cherry-pick button pushes the cherry-pick dialog route', (
    tester,
  ) async {
    await _pump(tester, pendingChangeCount: 0);
    await tester.tap(find.text('Cherry-pick…'));
    await tester.pumpAndSettle();
    expect(find.text('cherry-pick-dialog'), findsOneWidget);
  });

  testWidgets('Reset button pushes the reset-branch dialog route', (
    tester,
  ) async {
    await _pump(tester, pendingChangeCount: 0);
    await tester.tap(find.text('Reset…'));
    await tester.pumpAndSettle();
    expect(find.text('reset-branch-dialog'), findsOneWidget);
  });

  group('conflictActive gates Merge/Cherry-pick/Reset', () {
    testWidgets('Merge/Cherry-pick/Reset render as disabled TextButtons '
        '(onPressed null) while conflictActive is true', (tester) async {
      await _pump(tester, pendingChangeCount: 0, conflictActive: true);

      for (final String label in const <String>[
        'Merge…',
        'Cherry-pick…',
        'Reset…',
      ]) {
        final TextButton button = tester.widget<TextButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(TextButton),
          ),
        );
        expect(button.onPressed, isNull, reason: label);
      }
    });

    testWidgets(
      'tapping Merge/Cherry-pick/Reset while conflictActive is true does '
      'not navigate',
      (tester) async {
        final GoRouter router = await _pump(
          tester,
          pendingChangeCount: 0,
          conflictActive: true,
        );
        final String startLocation = router
            .routerDelegate
            .currentConfiguration
            .uri
            .toString();

        for (final String label in const <String>[
          'Merge…',
          'Cherry-pick…',
          'Reset…',
        ]) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          startLocation,
        );
      },
    );

    testWidgets('Merge/Cherry-pick/Reset are enabled again once conflictActive '
        'flips back to false', (tester) async {
      await _pump(tester, pendingChangeCount: 0);

      final TextButton button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Merge…'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });
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

  testWidgets('renders an open Compare tab after the two fixed tabs', (
    tester,
  ) async {
    await _pump(
      tester,
      pendingChangeCount: 0,
      compareTabs: const <CompareTabSpec>[
        CompareTabSpec(id: 'compare-0', left: 'main', right: 'feature'),
      ],
    );
    expect(find.text('main vs feature'), findsOneWidget);
  });

  testWidgets('tapping a Compare tab navigates to its route', (tester) async {
    final GoRouter router = await _pump(
      tester,
      pendingChangeCount: 0,
      compareTabs: const <CompareTabSpec>[
        CompareTabSpec(id: 'compare-0', left: 'main', right: 'feature'),
      ],
    );
    await tester.ensureVisible(find.text('main vs feature'));
    await tester.tap(find.text('main vs feature'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      RoutePaths.compareFor(_repoId, 'compare-0'),
    );
  });

  testWidgets('tapping a Compare tab close icon calls onCloseCompareTab '
      'with its id', (tester) async {
    String? closedId;
    await _pump(
      tester,
      pendingChangeCount: 0,
      compareTabs: const <CompareTabSpec>[
        CompareTabSpec(id: 'compare-0', left: 'main', right: 'feature'),
      ],
      onCloseCompareTab: (String id) => closedId = id,
    );
    await tester.ensureVisible(find.byIcon(Icons.close));
    await tester.tap(find.byIcon(Icons.close));
    expect(closedId, 'compare-0');
  });

  testWidgets(
    'History/Working Copy tabs have no close icon even with Compare tabs '
    'open',
    (tester) async {
      await _pump(
        tester,
        pendingChangeCount: 0,
        compareTabs: const <CompareTabSpec>[
          CompareTabSpec(id: 'compare-0', left: 'main', right: 'feature'),
        ],
        onCloseCompareTab: (_) {},
      );
      // Exactly one close icon: the Compare tab's, not History/Working Copy.
      expect(find.byIcon(Icons.close), findsOneWidget);
    },
  );
}
