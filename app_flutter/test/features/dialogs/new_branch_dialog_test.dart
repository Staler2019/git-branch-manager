// The New branch dialog's 從哪裡分出 field.
//
// The recorded defect this file exists for: the start point was a three-way
// dropdown plus a second, free-text `TextField` that had **no controller and
// no initialValue**. An `initialStartPoint` handed in from a commit row was
// held in `_startRef` and drawn nowhere, so the dialog showed two empty boxes
// and then created the branch at a start point the user never saw.
//
// A test for that has to assert what is *on screen*, not what the widget was
// constructed with -- constructing it with the value is exactly what the
// broken version did.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/new_branch/new_branch_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_ref_picker.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';
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

RepoSessionState _session({
  String head = 'main',
  List<RemoteInfo> remotes = const <RemoteInfo>[],
}) => RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: HeadInfo(
      kind: head.isEmpty ? HeadKind.detached : HeadKind.branch,
      branchName: head,
      fullRef: head.isEmpty ? '' : 'refs/heads/$head',
      target: 'a' * 40,
    ),
    refs: <RefInfo>[
      _ref('main', RefKind.localBranch),
      _ref('release/0.5', RefKind.localBranch),
      _ref('origin/main', RefKind.remoteBranch),
      _ref('v0.5.0', RefKind.tag),
    ],
    refCountGuardTripped: false,
    totalRefCount: 4,
  ),
  remotes: remotes,
);

const RemoteInfo _origin = RemoteInfo(
  name: 'origin',
  fetchUrl: 'git@example.com:x/y.git',
  pushUrl: 'git@example.com:x/y.git',
);
const RemoteInfo _upstream = RemoteInfo(
  name: 'upstream',
  fetchUrl: 'git@example.com:a/b.git',
  pushUrl: 'git@example.com:a/b.git',
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  String? initialStartPoint,
  RepoSessionState? state,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    state ?? _session(),
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
        builder: (context, state) => NewBranchDialogContent(
          identity: _identity,
          initialStartPoint: initialStartPoint,
        ),
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

/// The name of the row the picker is drawing as selected.
///
/// Read off the tint rather than off the widget's own field, because the
/// whole defect was a value the widget held and never showed
/// ([SPEC-cell-names-capability] one level down: the state is not evidence
/// for the surface).
String? _highlighted(WidgetTester tester) {
  for (final Element element in find.byType(GbmRow).evaluate()) {
    if (!(element.widget as GbmRow).selected) continue;
    final Finder text = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byType(Text),
    );
    return tester.widget<Text>(text.first).data;
  }
  return null;
}

Future<void> _name(WidgetTester tester, String value) async {
  await tester.enterText(find.widgetWithText(TextField, '名稱'), value);
  await tester.pumpAndSettle();
}

Future<void> _create(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(GbmButton, 'Create branch'));
  await tester.pumpAndSettle();
}

FakeCommand _created(FakeRepoSessionController fake) =>
    fake.commandLog.singleWhere((FakeCommand c) => c.name == 'createBranch');

void main() {
  group('the start point is visible', () {
    testWidgets('a commit handed in from a row is drawn and selected', (
      tester,
    ) async {
      await _pump(tester, initialStartPoint: 'a1b2c3d');

      // Both halves matter. `findsOneWidget` alone was true of nothing in
      // the broken version, and the highlight is what says the dialog will
      // actually use it.
      expect(find.text('a1b2c3d'), findsOneWidget);
      expect(_highlighted(tester), 'a1b2c3d');
    });

    testWidgets('a commit start point files itself under COMMIT', (
      tester,
    ) async {
      await _pump(tester, initialStartPoint: 'a1b2c3d');
      expect(find.text('COMMIT'), findsOneWidget);
    });

    testWidgets('a branch handed in from a row is selected in place', (
      tester,
    ) async {
      await _pump(tester, initialStartPoint: 'release/0.5');

      expect(_highlighted(tester), 'release/0.5');
      // Not duplicated into a COMMIT group: it already names a ref.
      expect(find.text('COMMIT'), findsNothing);
      expect(find.text('release/0.5'), findsOneWidget);
    });

    testWidgets('with nothing handed in, the current branch is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(_highlighted(tester), 'main');
      expect(find.text('目前分支'), findsOneWidget);
    });

    // 「目前分支」 is annotated, not removed -- branching from where you
    // stand is the commonest case there is. Checkout, whose list this shares,
    // drops the same row instead, because switching to it is a no-op, and
    // that difference is a constructor argument rather than a condition
    // inside the picker.
    testWidgets('the current branch is offered, unlike in Checkout', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        initialStartPoint: 'v0.5.0',
      );
      await _name(tester, 'feature/x');
      await tester.tap(find.text('main'));
      await tester.pumpAndSettle();
      await _create(tester);

      expect(_created(fake).args['startPoint'], 'main');
    });
  });

  group('what gets dispatched', () {
    testWidgets('the visible start point is the one git is given', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        initialStartPoint: 'a1b2c3d',
      );
      await _name(tester, 'feature/x');
      await _create(tester);

      expect(_created(fake).args['name'], 'feature/x');
      expect(_created(fake).args['startPoint'], 'a1b2c3d');
    });

    testWidgets('picking another ref changes the start point', (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _name(tester, 'feature/x');
      await tester.tap(find.text('v0.5.0'));
      await tester.pumpAndSettle();
      await _create(tester);

      expect(_created(fake).args['startPoint'], 'v0.5.0');
    });

    // The default used to be an empty start point, which `git branch` reads
    // as HEAD. Naming the branch explicitly is the same commit and says so
    // on screen, which the empty string could not.
    testWidgets('the default start point is the current branch by name', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _name(tester, 'feature/x');
      await _create(tester);

      expect(_created(fake).args['startPoint'], 'main');
    });

    testWidgets('a detached HEAD falls back to HEAD itself', (tester) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        state: _session(head: ''),
      );
      await _name(tester, 'feature/x');
      await _create(tester);

      expect(_created(fake).args['startPoint'], 'HEAD');
    });

    testWidgets('checkout-after defaults on and is passed through', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _name(tester, 'feature/x');
      await _create(tester);

      expect(_created(fake).args['checkoutAfter'], isTrue);
    });
  });

  group('name validation still gates the primary button', () {
    testWidgets('a duplicate name disables Create', (tester) async {
      await _pump(tester);
      await _name(tester, 'main');

      final GbmButton create = tester.widget<GbmButton>(
        find.widgetWithText(GbmButton, 'Create branch'),
      );
      expect(create.onPressed, isNull);
    });

    testWidgets('an empty name disables Create', (tester) async {
      await _pump(tester);

      final GbmButton create = tester.widget<GbmButton>(
        find.widgetWithText(GbmButton, 'Create branch'),
      );
      expect(create.onPressed, isNull);
    });
  });

  group('the picker is the shared one', () {
    testWidgets('there is exactly one, and no free-text second box', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byType(GbmRefPicker), findsOneWidget);
      // Two TextFields: the branch name and the picker's own search. A third
      // is the old free-text start-point box, the one with no controller.
      expect(find.byType(TextField), findsExactly(2));
    });
  });

  group('push and set upstream', () {
    // `RepoSessionState.remotes` is not populated at session open
    // (`RepoSessionController._open()` never calls `refreshRemotes()`), so
    // the dialog has to ask for it itself, the same way the manage-remotes
    // panel does in its own initState.
    testWidgets('the dialog asks for remotes on mount', (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);
      expect(
        fake.commandLog.any((FakeCommand c) => c.name == 'refreshRemotes'),
        isTrue,
      );
    });

    testWidgets('with no remote configured, the checkbox is absent', (
      tester,
    ) async {
      await _pump(tester, state: _session(remotes: const <RemoteInfo>[]));
      expect(find.text('同時 push 並設為 upstream'), findsNothing);
    });

    // Ambiguous, not absent: `soleRemoteName()`'s established rule
    // (`branch_bulk_actions.dart`) is "none or several" both decline to
    // guess, and this dialog reuses that rule rather than inventing a
    // second one.
    testWidgets('with two remotes configured, the checkbox is absent', (
      tester,
    ) async {
      await _pump(
        tester,
        state: _session(remotes: const <RemoteInfo>[_origin, _upstream]),
      );
      expect(find.text('同時 push 並設為 upstream'), findsNothing);
    });

    testWidgets('with exactly one remote, the checkbox names it', (
      tester,
    ) async {
      await _pump(
        tester,
        state: _session(remotes: const <RemoteInfo>[_origin]),
      );
      expect(find.textContaining('origin'), findsWidgets);
    });

    testWidgets('unchecked by default', (tester) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        state: _session(remotes: const <RemoteInfo>[_origin]),
      );
      await _name(tester, 'feature/x');
      await _create(tester);

      expect(
        fake.commandLog.any((FakeCommand c) => c.name == 'pushChanges'),
        isFalse,
      );
    });

    testWidgets('checking it pushes the new branch with setUpstream', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        state: _session(remotes: const <RemoteInfo>[_origin]),
      );
      await _name(tester, 'feature/x');
      await tester.tap(find.text('同時 push 並設為 upstream'));
      await tester.pumpAndSettle();
      await _create(tester);

      final FakeCommand push = fake.commandLog.singleWhere(
        (FakeCommand c) => c.name == 'pushChanges',
      );
      expect(push.args['remoteName'], 'origin');
      expect(push.args['branches'], <String>['feature/x']);
      expect(push.args['setUpstream'], isTrue);
    });

    // createBranch's own setUpstream/upstream params stay unused by this
    // dialog on purpose -- they run `git branch --track <upstream>`, which
    // needs the remote-tracking ref to already exist. A first push has no
    // such ref yet, so that path is the wrong tool; pushChanges'
    // --set-upstream is what actually publishes the branch.
    testWidgets('createBranch itself is dispatched with setUpstream false', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        state: _session(remotes: const <RemoteInfo>[_origin]),
      );
      await _name(tester, 'feature/x');
      await tester.tap(find.text('同時 push 並設為 upstream'));
      await tester.pumpAndSettle();
      await _create(tester);

      expect(_created(fake).args['setUpstream'], isFalse);
    });
  });
}
