// COMPARES 3's entry point: 「History 內 Ctrl/Cmd 點選兩個 commit → 右鍵
// Compare」. The comparison engine (merge-base detection, 2-dot/3-dot) was
// already complete in compare_page.dart; what was missing, and what this
// covers, is reaching it from History at all.
//
// Asserts the CompareTabSpec that gets opened and the route navigated to,
// not just that a callback fired: the older/newer side assignment is the
// part a wiring mistake would silently invert.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

/// Newest first, as History renders.
final List<String> _oids = <String>[
  for (final String seed in <String>['a', 'b', 'c']) seed * 40,
];
String _oid(String seed) => seed * 40;

final LogicalKeyboardKey _toggleKey =
    defaultTargetPlatform == TargetPlatform.macOS
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

CommitMeta _meta(String oid) {
  const Signature author = Signature(
    name: 'Tester',
    email: 't@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  );
  return CommitMeta(
    oid: oid,
    tree: '',
    parents: const <String>[],
    author: author,
    committer: author,
    subject: 'subject ${oid.substring(0, 4)}',
    body: '',
    signedCommit: false,
  );
}

late ProviderContainer _container;
late GoRouter _router;

Future<void> _pump(WidgetTester tester) async {
  // CommitGraphView reads the column picker's setting
  // (graphColumnVisibilityProvider -> graphColumnsRepositoryProvider ->
  // sharedPreferencesProvider), so this override is now mandatory for
  // anything that pumps the commit list. Without it the unoverridden
  // sharedPreferencesProvider throws UnimplementedError while building the
  // list's LayoutBuilder -- which is the fake-provider seam working as
  // designed: a forgotten override fails loudly instead of reaching a real
  // preferences store.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  _container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(_identity).overrideWith(
        (ref) => FakeRepoSessionController(
          _identity,
          RepoSessionState(
            isOpen: true,
            graph: GraphSnapshotView(
              rows: <GraphRow>[
                for (final _ in _oids)
                  const GraphRow(
                    parentOffset: 0,
                    edgeOffset: 0,
                    commitTime: 0,
                    lane: 0,
                    color: 0,
                    flags: 0,
                  ),
              ],
              oidsHex: _oids,
              parentPool: const <int>[],
              laneCount: 1,
              complete: true,
              truncated: false,
            ),
            commitMetaCache: <String, CommitMeta>{
              for (final String oid in _oids) oid: _meta(oid),
            },
          ),
        ),
      ),
    ],
  );
  addTearDown(_container.dispose);

  _router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: CommitGraphView(identity: _identity)),
      ),
      GoRoute(
        path: RoutePaths.compare,
        builder: (_, _) => const Scaffold(body: Text('compare-page')),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: _router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _rowFor(String oid) =>
    find.byWidgetPredicate((Widget w) => w is CommitRow && w.oidHex == oid);

Future<void> _openMenuOn(WidgetTester tester, String oid) async {
  await tester.tap(_rowFor(oid), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

List<CompareTabSpec> get _tabs =>
    _container.read(compareTabsProvider(_identity));

void main() {
  testWidgets('two selected commits open a Compare tab with both sides '
      'filled, older on the left', (tester) async {
    await _pump(tester);

    await tester.tap(_rowFor(_oid('a')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(_toggleKey);
    await tester.tap(_rowFor(_oid('c')));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(_toggleKey);

    // Right-click one of the selected rows: per MULTIKEYS this must not
    // change the selection, so Compare still sees both.
    await _openMenuOn(tester, _oid('a'));
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();

    expect(_tabs, hasLength(1));
    expect(_tabs.single.left, _oid('c'), reason: 'older side goes left');
    expect(_tabs.single.right, _oid('a'), reason: 'newer side goes right');
    expect(find.text('compare-page'), findsOneWidget);
  });

  testWidgets('one selected commit opens a Compare tab with only the left '
      'side, leaving the right to the ref picker', (tester) async {
    await _pump(tester);

    await _openMenuOn(tester, _oid('b'));
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();

    expect(_tabs.single.left, _oid('b'));
    expect(
      _tabs.single.right,
      isNull,
      reason:
          'null right is what CompareTabSpec models as Working Copy '
          'until the picker chooses a ref',
    );
  });

  testWidgets('"Compare with working copy" opens a working-copy tab', (
    tester,
  ) async {
    await _pump(tester);

    await _openMenuOn(tester, _oid('b'));
    await tester.tap(find.text('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with working copy'));
    await tester.pumpAndSettle();

    expect(_tabs.single.left, _oid('b'));
    expect(_tabs.single.rightIsWorkingCopy, isTrue);
  });

  testWidgets('three selected commits leave Compare disabled and open '
      'nothing', (tester) async {
    await _pump(tester);

    await tester.tap(_rowFor(_oid('a')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(_rowFor(_oid('c')));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    await _openMenuOn(tester, _oid('a'));
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();

    expect(_tabs, isEmpty);
  });
}
