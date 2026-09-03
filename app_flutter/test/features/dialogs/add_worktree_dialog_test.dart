// The Worktrees panel's Add worktree… dialog (D1).
//
// The recorded defect: the inline form it replaces hardcoded
// `createBranch: true`, so it could only ever create a new branch even
// though its own hint text promised the opposite ("leave empty to check
// out an existing one"). This file exercises the three git operations the
// new dialog can actually dispatch, plus the two derived-until-touched
// fields (the default path, and the create-new mode's default start point).
//
// Every interaction helper below routes through `_ensureAndTap`/
// `_ensureAndEnterText` rather than a bare `tester.tap`/`enterText`: the
// dialog's content genuinely exceeds `GbmDialogShell`'s 560px cap (that is
// why it is wrapped in a `SingleChildScrollView` at all), and focusing a
// field further down auto-scrolls the view -- which can carry an
// already-decided tap target (the radio group, near the top) out of the
// viewport for a *later* interaction. `tester.ensureVisible` before every
// tap/enterText is what keeps this file's interactions independent of
// whatever the previous one happened to scroll to.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/services/file_save_picker.dart';
import 'package:gbm_flutter/features/dialogs/add_worktree/add_worktree_dialog.dart';
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

const WorktreeInfo _primary = WorktreeInfo(
  path: '/src/git-branch-manager',
  headOid: 'a1b2c3d',
  branch: 'main',
  isMain: true,
  isBare: false,
  isDetached: false,
  isLocked: false,
  lockReason: '',
  isPrunable: false,
  prunableReason: '',
  isPrimary: true,
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

const WorktreeInfo _linked = WorktreeInfo(
  path: '/src/wt/gbm-lfs',
  headOid: 'b2c3d4e',
  branch: 'feature/lfs',
  isMain: false,
  isBare: false,
  isDetached: false,
  isLocked: false,
  lockReason: '',
  isPrunable: false,
  prunableReason: '',
  isPrimary: false,
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
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
  List<WorktreeInfo> worktrees = const <WorktreeInfo>[_primary, _linked],
}) => RepoSessionState(
  isOpen: true,
  worktrees: worktrees,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[
      _ref('main', RefKind.localBranch),
      _ref('feature/lfs', RefKind.localBranch),
      _ref('release/0.5', RefKind.localBranch),
      _ref('origin/release/0.5', RefKind.remoteBranch),
      _ref('v0.5.0', RefKind.tag),
    ],
    refCountGuardTripped: false,
    totalRefCount: 5,
  ),
);

/// Records what it was asked and returns a canned directory (or none, to
/// stand in for the user cancelling the native picker).
class _FakePicker implements FileSavePicker {
  _FakePicker({this.directory});

  final String? directory;
  int pickDirectoryCalls = 0;

  @override
  Future<String?> pickDirectory() async {
    pickDirectoryCalls++;
    return directory;
  }

  @override
  Future<List<String>> openFiles({
    List<String> extensions = const <String>[],
  }) => throw UnimplementedError();

  @override
  Future<String?> saveFile({required String suggestedName}) =>
      throw UnimplementedError();
}

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  RepoSessionState? state,
  List<RouteBase> extraRoutes = const <RouteBase>[],
  FileSavePicker? picker,
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
        builder: (context, state) =>
            const AddWorktreeDialogContent(identity: _identity),
      ),
      ...extraRoutes,
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        repoSessionProvider(_identity).overrideWith((ref) => controller),
        fileSavePickerProvider.overrideWithValue(picker ?? _FakePicker()),
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

/// The name of the row [GbmRefPicker] is drawing as selected.
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

/// Scrolls [finder] into view before tapping it -- see the file header.
Future<void> _ensureAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view before typing into it -- see the file header.
Future<void> _ensureAndEnterText(
  WidgetTester tester,
  Finder finder,
  String value,
) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

Future<void> _pickCreateNew(WidgetTester tester) =>
    _ensureAndTap(tester, find.text('建立新分支'));

Future<void> _pick(WidgetTester tester, String name) =>
    _ensureAndTap(tester, find.text(name));

Future<void> _typeNewBranchName(WidgetTester tester, String value) =>
    _ensureAndEnterText(tester, find.widgetWithText(TextField, '新分支名'), value);

Future<void> _typePath(WidgetTester tester, String value) =>
    _ensureAndEnterText(tester, find.widgetWithText(TextField, '位置'), value);

Future<void> _submit(WidgetTester tester) =>
    _ensureAndTap(tester, find.widgetWithText(GbmButton, 'Add worktree'));

FakeCommand _added(FakeRepoSessionController fake) =>
    fake.commandLog.singleWhere((FakeCommand c) => c.name == 'addWorktree');

void main() {
  group('source selection', () {
    testWidgets('checkout existing is the default', (tester) async {
      await _pump(tester);
      // The new-branch-name field is disabled by default -- dimmed, not
      // hidden, per [FLU-menu-enabled-is-visual-only].
      final TextField nameField = tester.widget<TextField>(
        find.widgetWithText(TextField, '新分支名'),
      );
      expect(nameField.enabled, isFalse);
    });

    testWidgets('switching to create-new enables the name field', (
      tester,
    ) async {
      await _pump(tester);
      await _pickCreateNew(tester);

      final TextField nameField = tester.widget<TextField>(
        find.widgetWithText(TextField, '新分支名'),
      );
      expect(nameField.enabled, isTrue);
    });

    testWidgets('create-new mode defaults the branch picker to HEAD', (
      tester,
    ) async {
      await _pump(tester);
      await _pickCreateNew(tester);

      expect(_highlighted(tester), 'main');
      expect(find.text('目前分支'), findsOneWidget);
    });
  });

  group('occupied branches', () {
    testWidgets(
      'a branch already checked out elsewhere is disabled and named',
      (tester) async {
        await _pump(tester);
        expect(find.textContaining('已在 gbm-lfs'), findsOneWidget);

        // Tapping it must be a no-op -- annotation alone does not prove the
        // row actually refuses the tap ([TEST-fixture-cannot-disagree] #8:
        // an annotation-only check would stay green even with `enabled`
        // hardcoded true).
        await _pick(tester, 'feature/lfs');
        final GbmButton create = tester.widget<GbmButton>(
          find.widgetWithText(GbmButton, 'Add worktree'),
        );
        expect(create.onPressed, isNull);
      },
    );

    testWidgets('release/0.5, which is free, is not disabled or annotated', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, '/src/worktrees/release-0.5');
      await _submit(tester);

      // A pick that is genuinely free must actually go through -- the
      // complement of the disabled case above, so a mutation that disables
      // *every* row would fail this one instead of hiding behind it.
      expect(fake.commandLog.any((c) => c.name == 'addWorktree'), isTrue);
    });

    testWidgets(
      'the same branch is an ordinary, pickable start point in create-new mode',
      (tester) async {
        final FakeRepoSessionController fake = await _pump(tester);
        await _pickCreateNew(tester);
        await _pick(tester, 'feature/lfs');
        await _typeNewBranchName(tester, 'feature/y');
        await _typePath(tester, '/some/new/path');
        await _submit(tester);

        expect(_added(fake).args['branch'], 'feature/lfs');
      },
    );
  });

  group('default path', () {
    testWidgets('computed from the primary worktree\'s own dirname', (
      tester,
    ) async {
      await _pump(tester);
      await _pick(tester, 'release/0.5');

      final TextField pathField = tester.widget<TextField>(
        find.widgetWithText(TextField, '位置'),
      );
      expect(pathField.controller?.text, '/src/worktrees/release-0.5');
    });

    testWidgets('a manual edit stops the automatic default', (tester) async {
      await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, '/somewhere/else');
      await _pickCreateNew(tester);
      await _typeNewBranchName(tester, 'ignored-name');

      final TextField pathField = tester.widget<TextField>(
        find.widgetWithText(TextField, '位置'),
      );
      expect(pathField.controller?.text, '/somewhere/else');
      final TextField nameField = tester.widget<TextField>(
        find.widgetWithText(TextField, '新分支名'),
      );
      expect(nameField.controller?.text, 'ignored-name');
    });
  });

  group('browse button', () {
    testWidgets('fills the path field from the native picker', (tester) async {
      await _pump(tester, picker: _FakePicker(directory: '/picked/by/user'));
      await _pick(tester, 'release/0.5');
      await _ensureAndTap(tester, find.widgetWithText(GbmButton, '瀏覽…'));

      final TextField pathField = tester.widget<TextField>(
        find.widgetWithText(TextField, '位置'),
      );
      expect(pathField.controller?.text, '/picked/by/user');
    });

    testWidgets('a browsed path counts as manually edited', (tester) async {
      await _pump(tester, picker: _FakePicker(directory: '/picked/by/user'));
      await _pick(tester, 'release/0.5');
      await _ensureAndTap(tester, find.widgetWithText(GbmButton, '瀏覽…'));
      await _pick(tester, 'feature/lfs');

      final TextField pathField = tester.widget<TextField>(
        find.widgetWithText(TextField, '位置'),
      );
      expect(pathField.controller?.text, '/picked/by/user');
    });

    testWidgets('cancelling the native picker leaves the path untouched', (
      tester,
    ) async {
      final _FakePicker picker = _FakePicker();
      await _pump(tester, picker: picker);
      await _pick(tester, 'release/0.5');
      final String before = tester
          .widget<TextField>(find.widgetWithText(TextField, '位置'))
          .controller!
          .text;

      await _ensureAndTap(tester, find.widgetWithText(GbmButton, '瀏覽…'));

      expect(picker.pickDirectoryCalls, 1);
      final TextField pathField = tester.widget<TextField>(
        find.widgetWithText(TextField, '位置'),
      );
      expect(pathField.controller?.text, before);
    });
  });

  group('an occupied path warns and blocks submit', () {
    testWidgets('a nonexistent path has no warning', (tester) async {
      await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, '/definitely/does/not/exist/anywhere');

      expect(find.textContaining('git 會拒絕'), findsNothing);
    });

    testWidgets('an existing but empty directory has no warning', (
      tester,
    ) async {
      final Directory empty = Directory.systemTemp.createTempSync(
        'gbm-add-worktree-empty-',
      );
      addTearDown(() => empty.deleteSync(recursive: true));

      await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, empty.path);

      expect(find.textContaining('git 會拒絕'), findsNothing);
    });

    testWidgets('an existing, non-empty directory warns and disables submit', (
      tester,
    ) async {
      final Directory nonEmpty = Directory.systemTemp.createTempSync(
        'gbm-add-worktree-nonempty-',
      );
      addTearDown(() => nonEmpty.deleteSync(recursive: true));
      File('${nonEmpty.path}/marker').writeAsStringSync('x');

      await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, nonEmpty.path);

      expect(find.textContaining('git 會拒絕'), findsOneWidget);
      final GbmButton create = tester.widget<GbmButton>(
        find.widgetWithText(GbmButton, 'Add worktree'),
      );
      expect(create.onPressed, isNull);
    });
  });

  group('what gets dispatched', () {
    testWidgets('checking out a free local branch', (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, '/src/worktrees/release-0.5');
      await _submit(tester);

      final FakeCommand added = _added(fake);
      expect(added.args['path'], '/src/worktrees/release-0.5');
      expect(added.args['branch'], 'release/0.5');
      expect(added.args['createBranch'], isFalse);
    });

    testWidgets('checking out a remote-only branch creates a tracking local', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _pick(tester, 'origin/release/0.5');
      await _typePath(tester, '/src/worktrees/release-0.5');
      await _submit(tester);

      final FakeCommand added = _added(fake);
      expect(added.args['branch'], 'origin/release/0.5');
      expect(added.args['createBranch'], isTrue);
      expect(added.args['newBranchName'], 'release/0.5');
    });

    testWidgets('creating a new branch from the resolved start point', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _pickCreateNew(tester);
      await _typeNewBranchName(tester, 'feature/z');
      await _typePath(tester, '/src/worktrees/feature-z');
      await _submit(tester);

      final FakeCommand added = _added(fake);
      expect(added.args['branch'], 'main');
      expect(added.args['createBranch'], isTrue);
      expect(added.args['newBranchName'], 'feature/z');
    });
  });

  group('switch after creating', () {
    testWidgets('unchecked by default, and the dialog merely pops', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, '/src/worktrees/release-0.5');
      await _submit(tester);

      expect(fake.commandLog.any((c) => c.name == 'addWorktree'), isTrue);
      expect(find.byType(AddWorktreeDialogContent), findsNothing);
    });

    // Indistinguishable from a plain pop by `onPressed != null`
    // ([TEST-fixture-cannot-disagree] #5) -- the destination is what is
    // asserted, via a sentinel route, mirroring the panel's own "Switch to"
    // test.
    testWidgets('checked, it opens the new worktree as the repository', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        extraRoutes: <RouteBase>[
          GoRoute(
            path: '/repo/:repoId/history',
            builder: (_, _) => const Text('SWITCHED'),
          ),
        ],
      );
      await _pick(tester, 'release/0.5');
      await _typePath(tester, '/src/worktrees/release-0.5');
      await _ensureAndTap(tester, find.text('建立後切換到這個 worktree'));
      await _submit(tester);

      expect(fake.commandLog.any((c) => c.name == 'addWorktree'), isTrue);
      expect(find.text('SWITCHED'), findsOneWidget);
    });
  });
}
