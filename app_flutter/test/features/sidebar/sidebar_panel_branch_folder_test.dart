// Verifies SidebarPanel's 05-J (Branch folder) context menu wiring, and
// the row-tap-to-toggle it gained alongside the menu, reach the real
// repoSessionProvider/GoRouter seam -- see CLAUDE.md's Testing tiers.
// branch_folder_menu_items_test.dart already covers the item list itself
// in isolation; this covers the SidebarPanel-level dispatch that tier
// structurally cannot, the same gap closed for 05-C/05-H/05-D.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _testIdentity = RepoIdentity.forWorkDir('/test/repo');
final String _repoIdParam = Uri.encodeComponent(_testIdentity.workDir);

RefInfo _localBranch(
  String name, {
  bool isHead = false,
  String worktreePath = '',
  String upstream = '',
}) {
  return RefInfo(
    fullName: 'refs/heads/$name',
    shortName: name,
    kind: RefKind.localBranch,
    target: 'a' * 40,
    upstream: upstream,
    ahead: 0,
    behind: 0,
    hasTrackingInfo: upstream.isNotEmpty,
    isGone: false,
    isHead: isHead,
    isSymbolic: isHead,
    worktreePath: worktreePath,
  );
}

final RefSnapshot _testRefs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[
    _localBranch('main', isHead: true),
    _localBranch('release/v1'),
    _localBranch('release/v2'),
    _localBranch('feature/auth'),
    _localBranch('feature/nested/deep'),
  ],
  refCountGuardTripped: false,
  totalRefCount: 5,
);

/// One branch nested deeper than [_kMaxIndentedDepth] (3), so its row gets
/// no indent at all: a/b/c/d/leaf puts `leaf` at depth 4.
final RefSnapshot _tooDeepRefs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[
    _localBranch('main', isHead: true),
    _localBranch('a/b/c/d/leaf'),
  ],
  refCountGuardTripped: false,
  totalRefCount: 2,
);

// Same shape, but every "release/*" branch tracks an "origin" upstream --
// used by the enabled-fetch tests below, since fetchableRefsInFolder()
// requires every leaf's upstream to resolve to the same single remote.
final RefSnapshot _testRefsWithUpstream = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[
    _localBranch('main', isHead: true),
    _localBranch('release/v1', upstream: 'refs/remotes/origin/release/v1'),
    _localBranch('release/v2', upstream: 'refs/remotes/origin/release/v2'),
    _localBranch('feature/auth'),
    _localBranch('feature/nested/deep'),
  ],
  refCountGuardTripped: false,
  totalRefCount: 5,
);

class _Harness {
  _Harness({required this.fake});
  final FakeRepoSessionController fake;
}

Future<_Harness> _pump(WidgetTester tester, {RefSnapshot? refs}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _testIdentity,
    const RepoSessionState(),
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
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_testIdentity).overrideWithValue(refs ?? _testRefs),
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

// A leaf under a folder prints only its last segment (P02 item 12: 「名稱中的
// 斜線自動摺成資料夾」), so rows are found by segment -- `alpha`, not
// `feature/sub/alpha`. The folder row above carries the prefix.
RefSnapshot _refsWithHead(String headBranch, List<String> names) => RefSnapshot(
  head: HeadInfo(
    kind: headBranch.isEmpty ? HeadKind.detached : HeadKind.branch,
    branchName: headBranch,
    fullRef: headBranch.isEmpty ? '' : 'refs/heads/$headBranch',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[
    for (final String name in names)
      _localBranch(name, isHead: name == headBranch),
  ],
  refCountGuardTripped: false,
  totalRefCount: names.length,
);

/// Like [_pump], but hands back the container so a test can swap the refs
/// override and simulate a checkout.
Future<ProviderContainer> _pumpWithContainer(
  WidgetTester tester,
  RefSnapshot refs,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_testIdentity).overrideWithValue(refs),
      repoSessionProvider(_testIdentity).overrideWith(
        (ref) =>
            FakeRepoSessionController(_testIdentity, const RepoSessionState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: SidebarPanel(identity: _testIdentity, filterFocusNode: null),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _setRefs(
  WidgetTester tester,
  ProviderContainer container,
  RefSnapshot refs,
) async {
  container.updateOverrides(<Override>[
    sharedPreferencesProvider.overrideWithValue(
      await SharedPreferences.getInstance(),
    ),
    repoRefsProvider(_testIdentity).overrideWithValue(refs),
    repoSessionProvider(_testIdentity).overrideWith(
      (ref) =>
          FakeRepoSessionController(_testIdentity, const RepoSessionState()),
    ),
  ]);
  await tester.pumpAndSettle();
}

void main() {
  // Every folder starts collapsed *except* the ones on the way to the current
  // branch. This is how the sidebar answers 「where am I」 now that the branch
  // list carries no sort pin -- see docs/ledger.md.
  group('the folders leading to the current branch open by default', () {
    testWidgets('a one-level current branch is on screen with no clicks', (
      tester,
    ) async {
      await _pumpWithContainer(
        tester,
        _refsWithHead('feature/zeta', <String>[
          'feature/alpha',
          'feature/zeta',
          'chore/docs',
        ]),
      );

      // The leaf prints its last segment, so `zeta` visible == `feature` open.
      expect(find.text('zeta'), findsOneWidget);
      // And only the folders on the way: `chore` stays shut.
      expect(find.text('docs'), findsNothing);
    });

    testWidgets('every level of a nested current branch opens', (tester) async {
      await _pumpWithContainer(
        tester,
        _refsWithHead('a/b/c', <String>['a/b/c', 'a/other']),
      );

      expect(find.text('c'), findsOneWidget);
    });

    testWidgets('a root-level current branch opens nothing', (tester) async {
      await _pumpWithContainer(
        tester,
        _refsWithHead('main', <String>['main', 'feature/alpha']),
      );

      expect(find.text('main'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
    });

    testWidgets('a detached HEAD opens nothing', (tester) async {
      await _pumpWithContainer(
        tester,
        _refsWithHead('', <String>['feature/alpha', 'chore/docs']),
      );

      expect(find.text('alpha'), findsNothing);
      expect(find.text('docs'), findsNothing);
    });

    testWidgets('a checkout opens the new folder and collapses nothing', (
      tester,
    ) async {
      final ProviderContainer container = await _pumpWithContainer(
        tester,
        _refsWithHead('feature/zeta', <String>['feature/zeta', 'chore/docs']),
      );
      expect(find.text('zeta'), findsOneWidget);

      await _setRefs(
        tester,
        container,
        _refsWithHead('chore/docs', <String>['feature/zeta', 'chore/docs']),
      );

      expect(find.text('docs'), findsOneWidget);
      // 「不自動收合」: the folder the user was in stays open.
      expect(find.text('zeta'), findsOneWidget);
    });

    testWidgets('a folder the user collapsed is not forced back open', (
      tester,
    ) async {
      await _pumpWithContainer(
        tester,
        _refsWithHead('feature/zeta', <String>['feature/zeta', 'chore/docs']),
      );
      expect(find.text('zeta'), findsOneWidget);

      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();

      // HEAD has not moved, so nothing re-seeds the set -- a rebuild that
      // re-expanded every frame would make this row reappear.
      expect(find.text('zeta'), findsNothing);
      await tester.pump();
      expect(find.text('zeta'), findsNothing);
    });
  });

  group('folder identity is the path, not the display segment', () {
    // Two folders that share a *segment* under different parents. The panel
    // used to key `_expandedFolders` on `folderName` ('sub') while
    // `buildBranchTree` keyed `isExpanded` on the full path ('feature/sub'),
    // so the two agreed only at depth one. Found when making the builder the
    // single source of truth broke five unrelated tests -- not by reading.
    final RefSnapshot refs = RefSnapshot(
      head: HeadInfo(
        kind: HeadKind.branch,
        branchName: 'main',
        fullRef: 'refs/heads/main',
        target: 'a' * 40,
      ),
      refs: <RefInfo>[
        _localBranch('main', isHead: true),
        _localBranch('feature/sub/alpha'),
        _localBranch('chore/sub/beta'),
      ],
      refCountGuardTripped: false,
      totalRefCount: 3,
    );

    testWidgets('opening one sub does not open the other', (tester) async {
      await _pump(tester, refs: refs);

      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sub'));
      await tester.pumpAndSettle();

      expect(find.text('alpha'), findsOneWidget);

      await tester.tap(find.text('chore'));
      await tester.pumpAndSettle();

      // `chore/sub` was never opened. Keyed on the segment, it inherited
      // `feature/sub`'s state and its child appeared unasked.
      expect(find.text('chore/sub/beta'), findsNothing);
      expect(find.text('sub'), findsNWidgets(2));
    });

    testWidgets('Copy folder prefix copies the path, not the segment', (
      tester,
    ) async {
      await _pump(tester, refs: refs);
      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _rightClick(tester, find.text('sub'));
      await tester.tap(find.text('Copy folder prefix'));
      await tester.pumpAndSettle();

      // 'sub/' would be useless: it is not a prefix of any branch name.
      expect(copied, 'feature/sub/');
    });
  });

  group('SidebarPanel branch folder context menu (05-J)', () {
    testWidgets('right-clicking a folder row opens its 05-J menu', (
      tester,
    ) async {
      await _pump(tester);

      await _rightClick(tester, find.text('release'));

      expect(find.text('Expand all'), findsOneWidget);
      expect(find.text('Fetch branches in folder'), findsOneWidget);
      expect(find.text('Copy folder prefix'), findsOneWidget);
      expect(find.text('Delete merged branches…'), findsOneWidget);
    });

    testWidgets('clicking the folder name toggles it open, revealing its '
        'children', (tester) async {
      await _pump(tester);

      // BranchTreeItem renders a leaf's full shortName, not a
      // folder-stripped segment (see branch_tree_item.dart's `ref.shortName`
      // usage) -- so "release/v1" is the actual rendered text, not "v1".
      expect(find.text('v1'), findsNothing);

      await tester.tap(find.text('release'));
      await tester.pumpAndSettle();

      expect(find.text('v1'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
    });

    testWidgets(
      'Expand all opens the folder and reveals a nested subfolder\'s own '
      'children too, not just the top level',
      (tester) async {
        await _pump(tester);

        expect(find.text('deep'), findsNothing);

        await _rightClick(tester, find.text('feature'));
        await tester.tap(find.text('Expand all'));
        await tester.pumpAndSettle();

        expect(find.text('auth'), findsOneWidget);
        // "nested" is itself a subfolder under "feature" -- Expand all
        // should open it too, revealing "deep" without a second click.
        expect(find.text('deep'), findsOneWidget);
      },
    );

    testWidgets('Copy folder prefix copies "<folderName>/" to the clipboard', (
      tester,
    ) async {
      final List<Object?> clipboardCalls = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardCalls.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pump(tester);
      await _rightClick(tester, find.text('release'));
      await tester.tap(find.text('Copy folder prefix'));
      await tester.pumpAndSettle();

      expect(clipboardCalls, hasLength(1));
      expect((clipboardCalls.single as Map)['text'], 'release/');
    });

    testWidgets(
      'Delete merged branches… reaches deleteBranch with every branch in '
      'the folder',
      (tester) async {
        final _Harness h = await _pump(tester);

        await _rightClick(tester, find.text('release'));
        await tester.tap(find.text('Delete merged branches…'));
        await tester.pumpAndSettle();

        final FakeCommand cmd = h.fake.commandLog.singleWhere(
          (c) => c.name == 'deleteBranch',
        );
        expect(cmd.args['names'], <String>['release/v1', 'release/v2']);
      },
    );

    testWidgets(
      'Fetch branches in folder is disabled when the folder\'s branches '
      'have no upstream -- no single unambiguous remote to fetch from',
      (tester) async {
        final _Harness h = await _pump(tester);

        await _rightClick(tester, find.text('release'));
        await tester.tap(find.text('Fetch branches in folder'));
        await tester.pumpAndSettle();

        expect(h.fake.commandLog.any((c) => c.name == 'fetchRemote'), isFalse);
      },
    );

    testWidgets(
      'Fetch branches in folder reaches fetchRemote with the folder\'s '
      'single remote and its branch names, when every leaf tracks it',
      (tester) async {
        final _Harness h = await _pump(tester, refs: _testRefsWithUpstream);

        await _rightClick(tester, find.text('release'));
        await tester.tap(find.text('Fetch branches in folder'));
        await tester.pumpAndSettle();

        final FakeCommand cmd = h.fake.commandLog.singleWhere(
          (c) => c.name == 'fetchRemote',
        );
        expect(cmd.args['remoteName'], 'origin');
        expect(cmd.args['refs'], <String>['release/v1', 'release/v2']);
      },
    );
  });

  group('leaf labels past the indent cap', () {
    testWidgets('a row deeper than the indent cap prints its full name '
        'again', (tester) async {
      await _pump(tester, refs: _tooDeepRefs);
      for (final String folder in <String>['a', 'b', 'c', 'd']) {
        await tester.tap(find.text(folder));
        await tester.pumpAndSettle();
      }

      // Depth 4 gets no indent (see _kMaxIndentedDepth), so the prefix is the
      // only thing left that can place the row. Shortening it to `leaf` would
      // leave the row with neither.
      expect(find.text('a/b/c/d/leaf'), findsOneWidget);
      expect(find.text('leaf'), findsNothing);
    });

    testWidgets('a row inside the indent cap prints only its last segment', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();

      expect(find.text('auth'), findsOneWidget);
      expect(find.text('feature/auth'), findsNothing);
    });
  });
}
