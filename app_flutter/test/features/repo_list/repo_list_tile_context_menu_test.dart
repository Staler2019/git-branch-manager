// Verifies RepoListTile's right-click menu against the design doc's
// `ctxItemsFor('repo')`: full item set, danger styling on "Remove from
// list", and that "Repository settings" pushes the real preferences route
// (the two items with no backing implementation -- "Open in file manager",
// "Remove from list" -- are asserted present-but-inert, per this widget's
// doc comment).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/features/repo_list/widgets/repo_list_tile.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

RepoRecord _repo() {
  return const RepoRecord(
    id: 1,
    baseFolderId: 1,
    workDir: '/home/dev/gbm',
    gitDir: '/home/dev/gbm/.git',
    commonDir: '/home/dev/gbm/.git',
    kind: RepoKind.normal,
    name: 'gbm',
    parentRepoId: null,
    depth: 0,
    discoveredAt: 0,
    missingSince: null,
  );
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(finder));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, {required VoidCallback onTap}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: RepoListTile(repo: _repo(), onTap: onTap),
        ),
      ),
      GoRoute(
        path: RoutePaths.preferencesDialog,
        builder: (context, state) => const Text('preferences-dialog'),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('right-click shows the full repo context menu', (tester) async {
    await _pump(tester, onTap: () {});
    await _rightClick(tester, find.byType(RepoListTile));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Open in file manager'), findsOneWidget);
    expect(find.text('Repository settings'), findsOneWidget);
    expect(find.text('Remove from list'), findsOneWidget);
  });

  testWidgets('Remove from list is styled danger', (tester) async {
    await _pump(tester, onTap: () {});
    await _rightClick(tester, find.byType(RepoListTile));
    final Text label = tester.widget<Text>(find.text('Remove from list'));
    expect(label.style?.color, tokensFor(GbmThemeVariant.darkTechnical).danger);
  });

  testWidgets('tapping Open invokes onTap', (tester) async {
    bool opened = false;
    await _pump(tester, onTap: () => opened = true);
    await _rightClick(tester, find.byType(RepoListTile));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets(
    'tapping Repository settings pushes the preferences dialog route',
    (tester) async {
      await _pump(tester, onTap: () {});
      await _rightClick(tester, find.byType(RepoListTile));
      await tester.tap(find.text('Repository settings'));
      await tester.pumpAndSettle();
      expect(find.text('preferences-dialog'), findsOneWidget);
    },
  );
}
