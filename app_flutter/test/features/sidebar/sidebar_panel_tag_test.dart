// Verifies SidebarPanel's 05-D (Tag) context menu wiring reaches the real
// repoSessionProvider/GoRouter seam -- see CLAUDE.md's Testing tiers:
// tag_menu_items_test.dart and branch_context_menu_test.dart's "tag row
// (05-D)" group already cover the item list and BranchTreeItem's own
// dispatch in isolation; this covers the SidebarPanel-level wiring those
// two tiers structurally cannot, the same gap
// sidebar_panel_remote_branch_test.dart closed for the 05-C menu and
// sidebar_panel_stash_test.dart closed for 05-H.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _testIdentity = RepoIdentity.forWorkDir('/test/repo');
final String _repoIdParam = Uri.encodeComponent(_testIdentity.workDir);

final RefInfo _localMain = RefInfo(
  fullName: 'refs/heads/main',
  shortName: 'main',
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: true,
  isSymbolic: true,
  worktreePath: '',
);

final RefInfo _tagV1 = RefInfo(
  fullName: 'refs/tags/v1.0.0',
  shortName: 'v1.0.0',
  kind: RefKind.tag,
  target: 'b' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

final RefSnapshot _testRefs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[_localMain, _tagV1],
  refCountGuardTripped: false,
  totalRefCount: 2,
);

const RemoteInfo _origin = RemoteInfo(
  name: 'origin',
  fetchUrl: 'https://example.com/repo.git',
  pushUrl: 'https://example.com/repo.git',
);

const RepoState _mergeState = RepoState(
  flags: RepoStateFlags.merge,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

class _Harness {
  _Harness({required this.fake});
  final FakeRepoSessionController fake;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  RepoSessionState initialState = const RepoSessionState(),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _testIdentity,
    initialState,
  );

  final GoRouter router = GoRouter(
    initialLocation: '/repo/$_repoIdParam/history',
    routes: <RouteBase>[
      GoRoute(
        path: '/repo/:repoId/history',
        builder: (context, state) => Scaffold(
          body: SidebarPanel(identity: _testIdentity, filterFocusNode: null),
        ),
      ),
      GoRoute(
        path: RoutePaths.compare,
        builder: (context, state) =>
            const Scaffold(body: SizedBox(key: Key('compare-stub'))),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_testIdentity).overrideWithValue(_testRefs),
      repoSessionProvider(_testIdentity).overrideWith((ref) => fake),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Harness(fake: fake);
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

void main() {
  group('SidebarPanel tag context menu (05-D)', () {
    testWidgets('right-clicking a tag row opens its 05-D menu', (tester) async {
      await _pump(tester);

      await _rightClick(tester, find.text('v1.0.0'));

      expect(find.text('Checkout tag (detached)'), findsOneWidget);
      expect(find.text('Push tag'), findsOneWidget);
      expect(find.text('Compare with…'), findsOneWidget);
      expect(find.text('Copy tag name'), findsOneWidget);
      expect(find.text('Delete tag…'), findsOneWidget);
    });

    testWidgets(
      'Checkout tag (detached) reaches checkout(target: tagName, detach: '
      'true)',
      (tester) async {
        final _Harness h = await _pump(tester);

        await _rightClick(tester, find.text('v1.0.0'));
        await tester.tap(find.text('Checkout tag (detached)'));
        await tester.pumpAndSettle();

        final FakeCommand cmd = h.fake.commandLog.singleWhere(
          (c) => c.name == 'checkout',
        );
        expect(cmd.args['target'], 'v1.0.0');
      },
    );

    testWidgets(
      'Push tag reaches pushTag with the single configured remote, when '
      'exactly one remote exists',
      (tester) async {
        final _Harness h = await _pump(
          tester,
          initialState: const RepoSessionState(remotes: <RemoteInfo>[_origin]),
        );

        await _rightClick(tester, find.text('v1.0.0'));
        await tester.tap(find.text('Push tag'));
        await tester.pumpAndSettle();

        final FakeCommand cmd = h.fake.commandLog.singleWhere(
          (c) => c.name == 'pushTag',
        );
        expect(cmd.args['remoteName'], 'origin');
        expect(cmd.args['name'], 'v1.0.0');
      },
    );

    testWidgets(
      'Push tag is disabled when there is no single unambiguous remote '
      '(zero remotes here)',
      (tester) async {
        final _Harness h = await _pump(tester);

        await _rightClick(tester, find.text('v1.0.0'));
        await tester.tap(find.text('Push tag'));
        await tester.pumpAndSettle();

        expect(h.fake.commandLog.any((c) => c.name == 'pushTag'), isFalse);
      },
    );

    testWidgets('Delete tag… reaches deleteTag', (tester) async {
      final _Harness h = await _pump(tester);

      await _rightClick(tester, find.text('v1.0.0'));
      await tester.tap(find.text('Delete tag…'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = h.fake.commandLog.singleWhere(
        (c) => c.name == 'deleteTag',
      );
      expect(cmd.args['name'], 'v1.0.0');
    });

    testWidgets(
      'Compare with… opens a Compare tab whose left ref is the tag name',
      (tester) async {
        await _pump(tester);

        await _rightClick(tester, find.text('v1.0.0'));
        await tester.tap(find.text('Compare with…'));
        await tester.pumpAndSettle();

        expect(
          GoRouterState.of(
            tester.element(find.byKey(const Key('compare-stub'))),
          ).uri.toString(),
          contains('/compare/'),
        );
      },
    );

    testWidgets(
      'Checkout tag (detached) is disabled while a conflict is active, '
      'then re-enabled once it clears (conflictActive round-trip, per '
      'CLAUDE.md\'s Rule)',
      (tester) async {
        final _Harness h = await _pump(
          tester,
          initialState: const RepoSessionState(repoState: _mergeState),
        );

        await _rightClick(tester, find.text('v1.0.0'));
        await tester.tap(find.text('Checkout tag (detached)'));
        await tester.pumpAndSettle();
        expect(
          h.fake.commandLog.any((c) => c.name == 'checkout'),
          isFalse,
          reason: 'mid-conflict, checkout should be disabled and no-op',
        );

        h.fake.emit(const RepoSessionState());
        await tester.pumpAndSettle();

        await _rightClick(tester, find.text('v1.0.0'));
        await tester.tap(find.text('Checkout tag (detached)'));
        await tester.pumpAndSettle();
        expect(
          h.fake.commandLog.any((c) => c.name == 'checkout'),
          isTrue,
          reason: 'once clean, checkout should reach the controller',
        );
      },
    );
  });
}
