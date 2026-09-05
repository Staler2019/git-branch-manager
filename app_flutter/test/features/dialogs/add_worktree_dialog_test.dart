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
import 'package:gbm_flutter/widgets/gbm_dialog_field_kinds.dart';
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

/// A primary worktree at an arbitrary path -- [WorktreeInfo] has no
/// `copyWith`, and the collision test needs two repositories that differ in
/// nothing but where they sit on disk.
WorktreeInfo _primaryAt(String path) => WorktreeInfo(
  path: path,
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
      // Three remote rows, one per measured case of `worktree add` against
      // a remote pick -- see the 'remote branch' group. A fixture carrying
      // only one of them cannot tell the three apart
      // ([TEST-fixture-cannot-disagree]), which is how the -b-always bug
      // shipped: the one remote row it had *did* have a local counterpart,
      // and the test asserting `-b` was named 'remote-only'.
      _ref('origin/release/0.5', RefKind.remoteBranch), // local exists, free
      _ref('origin/feature/lfs', RefKind.remoteBranch), // local occupied
      _ref('origin/hotfix/9', RefKind.remoteBranch), // genuinely remote-only
      _ref('v0.5.0', RefKind.tag),
    ],
    refCountGuardTripped: false,
    totalRefCount: 7,
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
    _ensureAndEnterText(
      tester,
      find.byKey(const Key('add-worktree-new-branch-name-field')),
      value,
    );

Future<void> _typePath(WidgetTester tester, String value) =>
    _ensureAndEnterText(
      tester,
      find.byKey(const Key('add-worktree-path-field')),
      value,
    );

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
        find.byKey(const Key('add-worktree-new-branch-name-field')),
      );
      expect(nameField.enabled, isFalse);
    });

    testWidgets('switching to create-new enables the name field', (
      tester,
    ) async {
      await _pump(tester);
      await _pickCreateNew(tester);

      final TextField nameField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-new-branch-name-field')),
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

  group('位置 row', () {
    // 使用者回報:「隔壁的瀏覽button畫面與瀏覽textbox高度不同，所以spec你沒
    // 有照做」-- measured on a real macOS screenshot at 23px against the
    // button's 30.
    //
    // Asserted against the button rather than against the constant, because
    // 「一樣高」is the claim; and measured on the *painted* box, because the
    // TextField's own rect was 30 throughout the defect
    // ([TEST-fixture-cannot-disagree] row 14, and see the same group in
    // gbm_input_decoration_test.dart).
    testWidgets('the box and 瀏覽… are the same height, and aligned', (
      tester,
    ) async {
      await _pump(tester);

      final Finder field = find.byKey(const Key('add-worktree-path-field'));
      final Rect box = tester.getRect(
        find
            .descendant(
              of: find.descendant(
                of: field,
                matching: find.byType(InputDecorator),
              ),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final Rect button = tester.getRect(find.widgetWithText(GbmButton, '瀏覽…'));

      expect(box.height, GbmSpacing.inputHeight);
      expect(box.height, button.height);
      expect(box.top, button.top);
    });
  });

  group('位置 is gated on having a branch to derive it from', () {
    // 使用者裁定:「我沒選分支之前，應該把選位置那邊鎖起來，我剛剛一直以為
    // 可以直接選位置用了」-- the field sat enabled and permanently empty
    // before a branch was picked, because _computeDefaultPath returns null
    // on an empty branch name. Both halves of the row are gated on that
    // same condition, since the reported reach was for 瀏覽…, not the box.
    testWidgets('both the box and 瀏覽… are disabled before a branch is picked', (
      tester,
    ) async {
      await _pump(tester);

      final TextField pathField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-path-field')),
      );
      expect(pathField.enabled, isFalse);

      final GbmButton browse = tester.widget<GbmButton>(
        find.widgetWithText(GbmButton, '瀏覽…'),
      );
      expect(browse.onPressed, isNull);
    });

    testWidgets('picking a branch enables both', (tester) async {
      await _pump(tester);
      await _pick(tester, 'release/0.5');

      final TextField pathField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-path-field')),
      );
      expect(pathField.enabled, isTrue);

      final GbmButton browse = tester.widget<GbmButton>(
        find.widgetWithText(GbmButton, '瀏覽…'),
      );
      expect(browse.onPressed, isNotNull);
    });

    testWidgets(
      'create-new gates on the typed name, not on the picker default',
      (tester) async {
        await _pump(tester);
        await _pickCreateNew(tester);

        // The picker defaults to HEAD here, so _picked is non-null -- but
        // the path is derived from the *typed* name in this mode, and that
        // is still empty.
        TextField pathField = tester.widget<TextField>(
          find.byKey(const Key('add-worktree-path-field')),
        );
        expect(pathField.enabled, isFalse);

        await _typeNewBranchName(tester, 'feature/z');

        pathField = tester.widget<TextField>(
          find.byKey(const Key('add-worktree-path-field')),
        );
        expect(pathField.enabled, isTrue);
      },
    );
  });

  group('occupied branches', () {
    // 使用者回報:「i can select origin worktree, but cannot create worktree
    // from it」-- the local row for an occupied branch was greyed out and
    // its remote counterpart, which resolves to that same local branch, was
    // not. Picking it produced `fatal: a branch named '…' already exists`.
    testWidgets(
      'a remote branch whose local counterpart is checked out elsewhere is '
      'disabled and named too',
      (tester) async {
        await _pump(tester);

        final GbmRefPickerEntry entry = tester
            .widget<GbmRefPicker>(find.byType(GbmRefPicker))
            .entries
            .singleWhere(
              (GbmRefPickerEntry e) => e.name == 'origin/feature/lfs',
            );

        expect(entry.enabled, isFalse);
        expect(entry.annotation, '已在 gbm-lfs');
      },
    );

    testWidgets('a remote branch whose local counterpart is free stays '
        'selectable', (tester) async {
      await _pump(tester);

      final GbmRefPicker picker = tester.widget<GbmRefPicker>(
        find.byType(GbmRefPicker),
      );
      for (final String name in <String>[
        'origin/release/0.5',
        'origin/hotfix/9',
      ]) {
        final GbmRefPickerEntry entry = picker.entries.singleWhere(
          (GbmRefPickerEntry e) => e.name == name,
        );
        expect(entry.enabled, isTrue, reason: name);
        expect(entry.annotation, '', reason: name);
      }
    });

    testWidgets(
      'a branch already checked out elsewhere is disabled and named',
      (tester) async {
        await _pump(tester);
        // Scoped to the local row, not counted app-wide: `origin/feature/lfs`
        // legitimately carries the same annotation now, and bumping 1 to 2
        // would be satisfied by the remote row alone
        // ([TEST-fixture-cannot-disagree] row 12).
        final GbmRefPickerEntry local = tester
            .widget<GbmRefPicker>(find.byType(GbmRefPicker))
            .entries
            .singleWhere((GbmRefPickerEntry e) => e.name == 'feature/lfs');
        expect(local.annotation, '已在 gbm-lfs');
        expect(local.enabled, isFalse);

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
    testWidgets('carries the repository\'s own name, not only its parent', (
      tester,
    ) async {
      await _pump(tester);
      await _pick(tester, 'release/0.5');

      final TextField pathField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-path-field')),
      );
      expect(
        pathField.controller?.text,
        '/src/worktrees/git-branch-manager/release-0.5',
      );
    });

    // The other half of the reported defect: two repositories checked out
    // side by side under one parent both defaulted to
    // `/src/worktrees/release-0.5`, so whichever the user opened second met
    // 「已存在且不是空的」 before touching anything. The pair of tests is
    // what pins that, deliberately rather than one test pumping twice --
    // a second `pumpWidget` of the same dialog reuses the element, so its
    // `State` (and with it `_pathController`) survives and answers with the
    // *first* repository's path. That is the same State-reuse shape as the
    // second Compare tab's spinner, and testing it here would be testing it.
    testWidgets('a repository beside it gets a different default', (
      tester,
    ) async {
      await _pump(
        tester,
        state: _session(
          worktrees: <WorktreeInfo>[
            _primaryAt('/src/some-other-repo'),
            _linked,
          ],
        ),
      );
      await _pick(tester, 'release/0.5');

      final TextField pathField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-path-field')),
      );
      expect(
        pathField.controller?.text,
        '/src/worktrees/some-other-repo/release-0.5',
      );
    });

    testWidgets('a manual edit stops the automatic default', (tester) async {
      await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, '/somewhere/else');
      await _pickCreateNew(tester);
      await _typeNewBranchName(tester, 'ignored-name');

      final TextField pathField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-path-field')),
      );
      expect(pathField.controller?.text, '/somewhere/else');
      final TextField nameField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-new-branch-name-field')),
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
        find.byKey(const Key('add-worktree-path-field')),
      );
      expect(pathField.controller?.text, '/picked/by/user');
    });

    testWidgets('a browsed path counts as manually edited', (tester) async {
      await _pump(tester, picker: _FakePicker(directory: '/picked/by/user'));
      await _pick(tester, 'release/0.5');
      await _ensureAndTap(tester, find.widgetWithText(GbmButton, '瀏覽…'));
      await _pick(tester, 'feature/lfs');

      final TextField pathField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-path-field')),
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
          .widget<TextField>(find.byKey(const Key('add-worktree-path-field')))
          .controller!
          .text;

      await _ensureAndTap(tester, find.widgetWithText(GbmButton, '瀏覽…'));

      expect(picker.pickDirectoryCalls, 1);
      final TextField pathField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-path-field')),
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

    // G8b: the path-conflict warning now draws inside GbmDialogWarnField,
    // not a bare GbmWarningBanner call.
    testWidgets('the warning is a GbmDialogWarnField (G8b)', (tester) async {
      final Directory nonEmpty = Directory.systemTemp.createTempSync(
        'gbm-add-worktree-nonempty-g8b-',
      );
      addTearDown(() => nonEmpty.deleteSync(recursive: true));
      File('${nonEmpty.path}/marker').writeAsStringSync('x');

      await _pump(tester);
      await _pick(tester, 'release/0.5');
      await _typePath(tester, nonEmpty.path);

      expect(find.byType(GbmDialogWarnField), findsOneWidget);
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

    // Measured on git 2.55 (scratch repo, three runs):
    //
    //   local feat/x         | `add -b feat/x <p> origin/feat/x` | `add <p> feat/x`
    //   ---------------------|-----------------------------------|-----------------
    //   does not exist       | creates a tracking branch, exit 0 | n/a
    //   exists, free         | fatal: a branch named … already   | exit 0
    //   exists, checked out  | fatal: a branch named … already   | fatal: already used
    //
    // The dialog used to send `-b` for every remote pick, so the middle row
    // was `fatal` and the bottom row was `fatal` with a message naming the
    // wrong problem. 使用者回報 the bottom row verbatim.
    testWidgets('a genuinely remote-only branch creates a tracking local', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await _pick(tester, 'origin/hotfix/9');
      await _typePath(tester, '/src/worktrees/hotfix-9');
      await _submit(tester);

      final FakeCommand added = _added(fake);
      expect(added.args['branch'], 'origin/hotfix/9');
      expect(added.args['createBranch'], isTrue);
      expect(added.args['newBranchName'], 'hotfix/9');
    });

    testWidgets(
      'a remote branch whose local counterpart already exists checks that '
      'local out instead of trying to create it again',
      (tester) async {
        final FakeRepoSessionController fake = await _pump(tester);
        await _pick(tester, 'origin/release/0.5');
        await _typePath(tester, '/src/worktrees/release-0.5');
        await _submit(tester);

        final FakeCommand added = _added(fake);
        expect(added.args['branch'], 'release/0.5');
        expect(added.args['createBranch'], isFalse);
      },
    );

    // The default path names the branch that will actually be checked out,
    // which for a remote pick is the *local* one. The reported command line
    // shows the old behaviour: it proposed
    // `…/worktrees/gbm/origin-feat-worktree-dialogs-shell-redesign` for a
    // worktree whose branch is `feat/worktree-dialogs-shell-redesign`.
    testWidgets('the default path drops the remote prefix', (tester) async {
      await _pump(tester);
      await _pick(tester, 'origin/hotfix/9');

      final TextField pathField = tester.widget<TextField>(
        find.byKey(const Key('add-worktree-path-field')),
      );
      expect(
        pathField.controller!.text,
        '/src/worktrees/git-branch-manager/hotfix-9',
      );
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

  group('「來源」group label (G2)', () {
    testWidgets('labels the radio group, sitting above it', (tester) async {
      await _pump(tester);

      expect(find.text('來源'), findsOneWidget);
      final double labelTop = tester.getTopLeft(find.text('來源')).dy;
      final double radioTop = tester
          .getTopLeft(find.byType(RadioGroup<WorktreeSource>))
          .dy;
      // A finder proves existence, never position
      // ([FLU-finder-proves-existence-not-position]) -- the label text
      // could exist anywhere in the tree and this assertion would still
      // pass without the position check.
      expect(labelTop, lessThan(radioTop));
    });

    testWidgets('uses the same P6 style as the other field labels', (
      tester,
    ) async {
      await _pump(tester);
      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

      final Text label = tester.widget<Text>(find.text('來源'));
      expect(label.style?.color, colors.textSecondary);
      expect(label.style?.fontSize, GbmTypography.textXs);
      expect(label.style?.fontWeight, isNot(GbmTypography.weightSemibold));
    });
  });

  group('input height and radius (G4)', () {
    testWidgets('新分支名 and 位置 are both 30px tall with r6 borders', (
      tester,
    ) async {
      await _pump(tester);

      for (final MapEntry<String, Key> entry in <String, Key>{
        '新分支名': const Key('add-worktree-new-branch-name-field'),
        '位置': const Key('add-worktree-path-field'),
      }.entries) {
        final Finder finder = find.byKey(entry.value);
        expect(
          tester.getSize(finder).height,
          GbmSpacing.inputHeight,
          reason: entry.key,
        );
        final TextField field = tester.widget<TextField>(finder);
        final OutlineInputBorder border =
            field.decoration!.border! as OutlineInputBorder;
        expect(
          border.borderRadius,
          BorderRadius.circular(GbmSpacing.radiusMd),
          reason: entry.key,
        );
      }
    });

    testWidgets(
      'a duplicate new-branch name does not overflow the fixed-height field',
      (tester) async {
        // The name field is now wrapped in a fixed SizedBox(height: 30) --
        // errorText renders inside that same box, so this is the case
        // that would overflow if the fixed height ever clips it
        // ([FLU-renderflex-non-flex-first]).
        await _pump(tester);
        await _pickCreateNew(tester);
        await _typeNewBranchName(tester, 'main');

        expect(tester.takeException(), isNull);
      },
    );

    // Regression: gbmInputDecoration() used to take labelText, and
    // Material's floating label does not fit inside this fixed 30px box --
    // measured (scratch probe, not committed) the label painting from
    // y=14.9 against the box's own y=20, overlapping the value's leading
    // ~6px. This is the field the user actually reported as "位置 沒有預設
    // 了" -- the value was there all along, just visually garbled by the
    // overlapping label. Both fields now carry no labelText at all, with
    // their label an external Text sitting fully above the field's box.
    testWidgets('新分支名 and 位置 have no floating label -- both labels sit '
        'externally, above their field, not overlapping it', (tester) async {
      await _pump(tester);

      for (final MapEntry<String, Key> entry in <String, Key>{
        '新分支名': const Key('add-worktree-new-branch-name-field'),
        '位置': const Key('add-worktree-path-field'),
      }.entries) {
        final Finder fieldFinder = find.byKey(entry.value);
        final TextField field = tester.widget<TextField>(fieldFinder);
        expect(field.decoration?.labelText, isNull, reason: entry.key);

        final Rect labelRect = tester.getRect(find.text(entry.key));
        final Rect fieldRect = tester.getRect(fieldFinder);
        expect(
          labelRect.bottom,
          lessThanOrEqualTo(fieldRect.top),
          reason: entry.key,
        );
      }
    });
  });

  group('field label style (G3)', () {
    testWidgets(
      '分支 uses the P6 field-label treatment, not the old pane-header one',
      (tester) async {
        await _pump(tester);
        final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

        final Text label = tester.widget<Text>(find.text('分支'));
        expect(label.style?.color, colors.textSecondary);
        expect(label.style?.fontSize, GbmTypography.textXs);
        // Not semibold and not letter-spaced -- that pair is what made this
        // read as an uppercase pane header ([FLU-hand-rolled-inkwell-hover]'s
        // "assert the token by identity" lesson applies here too: comparing
        // against the *old* token would pass even after a correct rewrite
        // that happened to reuse textTertiary by coincidence).
        expect(label.style?.fontWeight, isNot(GbmTypography.weightSemibold));
        expect(label.style?.letterSpacing, isNot(0.5));
      },
    );

    testWidgets('新分支名 and 位置 use the same P6 field-label treatment', (
      tester,
    ) async {
      await _pump(tester);
      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

      for (final String text in <String>['新分支名', '位置']) {
        final Text label = tester.widget<Text>(find.text(text));
        expect(label.style?.color, colors.textSecondary, reason: text);
        expect(label.style?.fontSize, GbmTypography.textXs, reason: text);
      }
    });
  });
}
