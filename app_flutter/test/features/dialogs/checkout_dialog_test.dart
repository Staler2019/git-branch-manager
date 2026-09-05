// Checkout's list, now that it is the shared [GbmRefPicker].
//
// The commit rows are the part that never existed: spec page 06's row says
// 「可搜尋的分支 / tag / commit 清單」 and the list was built from
// `localBranches` + `remoteBranches` + `tags`, so the `how` cell named an
// input the widget could not take ([SPEC-how-column-is-a-requirement]).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/checkout/checkout_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/tmp/repo',
  gitDir: '/tmp/repo/.git',
);

RefInfo _ref(String shortName, RefKind kind) => RefInfo(
  fullName: switch (kind) {
    RefKind.localBranch => 'refs/heads/$shortName',
    RefKind.remoteBranch => 'refs/remotes/$shortName',
    _ => 'refs/tags/$shortName',
  },
  shortName: shortName,
  kind: kind,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

final RepoSessionState _state = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[
      _ref('main', RefKind.localBranch),
      _ref('release/0.5', RefKind.localBranch),
      // Two remote rows, and the difference between them is the whole
      // point: `origin/feature/lfs` has no local counterpart (so it really
      // does need `-b`), `origin/release/0.5` does (so `-b` is
      // `fatal: a branch named … already exists`). A fixture with only the
      // first cannot tell the two apart ([TEST-fixture-cannot-disagree]).
      _ref('origin/feature/lfs', RefKind.remoteBranch),
      _ref('origin/release/0.5', RefKind.remoteBranch),
      _ref('v0.5.0', RefKind.tag),
    ],
    refCountGuardTripped: false,
    totalRefCount: 5,
  ),
);

Future<FakeRepoSessionController> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    _state,
  );

  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) =>
            const CheckoutDialogContent(identity: _identity),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        repoSessionProvider(_identity).overrideWith((ref) => controller),
      ],
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/dialog');
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

/// Scoped to the list: the search field's own [EditableText] carries the
/// typed query as text too.
Finder _inList(String text) =>
    find.descendant(of: find.byType(ListView), matching: find.text(text));

FakeCommand _checkedOut(FakeRepoSessionController fake) =>
    fake.commandLog.singleWhere((FakeCommand c) => c.name == 'checkout');

void main() {
  testWidgets('the branch HEAD is on is not offered', (tester) async {
    await _pump(tester);

    expect(_inList('release/0.5'), findsOneWidget);
    expect(_inList('main'), findsNothing);
  });

  testWidgets('an abbreviated oid can now be checked out', (tester) async {
    final FakeRepoSessionController fake = await _pump(tester);
    await _search(tester, 'a1b2c3d');

    expect(find.text('COMMIT'), findsOneWidget);
    await tester.tap(_inList('a1b2c3d'));
    await tester.pumpAndSettle();
    // The dialog's own title is also the word 'Checkout'.
    await tester.tap(find.widgetWithText(GbmButton, 'Checkout'));
    await tester.pumpAndSettle();

    expect(_checkedOut(fake).args['target'], 'a1b2c3d');
    // A commit is not a remote branch, so no local branch is created for it.
    expect(_checkedOut(fake).args['createBranch'], isFalse);
  });

  // The kind, not the group heading, is what decides this -- which is why
  // the picker reports a whole entry rather than a name.
  testWidgets('a remote-only branch still checks out as a new local one', (
    tester,
  ) async {
    final FakeRepoSessionController fake = await _pump(tester);

    await tester.tap(_inList('origin/feature/lfs'));
    await tester.pumpAndSettle();
    // The dialog's own title is also the word 'Checkout'.
    await tester.tap(find.widgetWithText(GbmButton, 'Checkout'));
    await tester.pumpAndSettle();

    expect(_checkedOut(fake).args['createBranch'], isTrue);
    // Only the remote name is dropped: a branch whose own name has slashes
    // survives intact.
    expect(_checkedOut(fake).args['newBranchName'], 'feature/lfs');
  });

  // Measured on git 2.55: `git checkout -b release/0.5 origin/release/0.5`
  // with a local `release/0.5` already present is
  // `fatal: a branch named 'release/0.5' already exists`; plain
  // `git checkout release/0.5` switches to it and reports it tracking the
  // remote. Add Worktree had the identical defect and was reported first.
  testWidgets(
    'a remote branch whose local counterpart exists switches to that local, '
    'without trying to create it again',
    (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);

      await tester.tap(_inList('origin/release/0.5'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GbmButton, 'Checkout'));
      await tester.pumpAndSettle();

      expect(_checkedOut(fake).args['target'], 'release/0.5');
      expect(_checkedOut(fake).args['createBranch'], isFalse);
    },
  );

  testWidgets('the create-a-local-branch line only promises what will '
      'actually happen', (tester) async {
    await _pump(tester);

    await tester.tap(_inList('origin/feature/lfs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('建立本地分支'), findsOneWidget);

    await tester.tap(_inList('origin/release/0.5'));
    await tester.pumpAndSettle();
    expect(find.textContaining('建立本地分支'), findsNothing);
  });

  testWidgets('a tag checks out as itself', (tester) async {
    final FakeRepoSessionController fake = await _pump(tester);

    await tester.tap(_inList('v0.5.0'));
    await tester.pumpAndSettle();
    // The dialog's own title is also the word 'Checkout'.
    await tester.tap(find.widgetWithText(GbmButton, 'Checkout'));
    await tester.pumpAndSettle();

    expect(_checkedOut(fake).args['target'], 'v0.5.0');
    expect(_checkedOut(fake).args['createBranch'], isFalse);
  });
}
