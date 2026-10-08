// merge-rebase-dialogs-spec.html 02-A / 02-B: a source handed in by 05-B's
// "Merge into current" is drawn read-only, never as a picker the user has
// to answer again; with no source the dialog offers GbmRefPicker (local and
// remote, ruling ②). The commit message is pre-filled with git's own default
// title (ruling ⑦), measured on git 2.56.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/merge/merge_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_field_kinds.dart';
import 'package:gbm_flutter/widgets/gbm_ref_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/tmp/repo',
  gitDir: '/tmp/repo/.git',
);

RefInfo _ref(String shortName, {bool remote = false, bool isHead = false}) =>
    RefInfo(
      fullName: remote ? 'refs/remotes/$shortName' : 'refs/heads/$shortName',
      shortName: shortName,
      kind: remote ? RefKind.remoteBranch : RefKind.localBranch,
      target: 'a' * 40,
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: isHead,
      isSymbolic: false,
      worktreePath: '',
    );

RepoSessionState _state(String head) => RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: HeadInfo(
      kind: HeadKind.branch,
      branchName: head,
      fullRef: 'refs/heads/$head',
      target: 'aaaa',
    ),
    refs: <RefInfo>[
      _ref(head, isHead: true),
      _ref('feature'),
      _ref('release/0.5'),
      _ref('origin/feat', remote: true),
    ],
    refCountGuardTripped: false,
    totalRefCount: 4,
  ),
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  String head = 'main',
  String? source,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    _state(head),
  );
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (_, _) =>
            MergeDialogContent(identity: _identity, source: source),
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

String _message(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!.text;

FakeCommand _merged(FakeRepoSessionController fake) =>
    fake.commandLog.singleWhere((FakeCommand c) => c.name == 'mergeBranch');

void main() {
  // A tap that misses (row scrolled out of view) must fail, not pass for
  // the wrong reason -- it once hid a surviving mutation here.
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  group('opened with a source (05-B)', () {
    testWidgets('draws the source read-only and offers no picker', (
      tester,
    ) async {
      await _pump(tester, source: 'feature');

      expect(find.byType(GbmRefPicker), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GbmDialogReadOnlyField),
          matching: find.text('feature'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('draws the current branch as the read-only 合入 row', (
      tester,
    ) async {
      await _pump(tester, source: 'feature');
      expect(
        find.descendant(
          of: find.byType(GbmDialogReadOnlyField),
          matching: find.text('main'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Merge is enabled at once and dispatches that source with '
        "git's default title", (tester) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        source: 'feature',
      );
      await tester.tap(find.text('Merge'));
      await tester.pump();

      final FakeCommand call = _merged(fake);
      expect(call.args['target'], 'feature');
      expect(call.args['message'], "Merge branch 'feature'");
    });
  });

  group('opened with no source (Branch menu)', () {
    testWidgets('offers local and remote branches but not the current one', (
      tester,
    ) async {
      await _pump(tester);
      final GbmRefPicker picker = tester.widget(find.byType(GbmRefPicker));
      expect(
        picker.entries.map((GbmRefPickerEntry e) => e.name),
        unorderedEquals(<String>['feature', 'release/0.5', 'origin/feat']),
      );
      expect(
        picker.entries
            .singleWhere((GbmRefPickerEntry e) => e.name == 'origin/feat')
            .kind,
        GbmRefKind.remoteBranch,
      );
    });

    testWidgets('Merge stays disabled until a source is picked', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await tester.tap(find.text('Merge'));
      await tester.pump();
      expect(fake.commandLog.where((c) => c.name == 'mergeBranch'), isEmpty);

      await tester.tap(find.text('feature'));
      await tester.pump();
      await tester.tap(find.text('Merge'));
      await tester.pump();
      expect(_merged(fake).args['target'], 'feature');
    });

    testWidgets('picking a source pre-fills the message, and a new pick '
        'replaces it while the user has not edited it', (tester) async {
      await _pump(tester);
      expect(_message(tester), isEmpty);

      await tester.tap(find.text('feature'));
      await tester.pump();
      expect(_message(tester), "Merge branch 'feature'");

      await tester.tap(find.text('release/0.5'));
      await tester.pump();
      expect(_message(tester), "Merge branch 'release/0.5'");
    });

    testWidgets('a message the user typed survives a new pick', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('feature'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'my own words');
      // Typing scrolled the dialog down to the message box.
      await tester.ensureVisible(find.text('release/0.5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('release/0.5'));
      await tester.pump();
      // The pick must have landed, or this would pass for the wrong reason.
      expect(
        tester.widget<GbmRefPicker>(find.byType(GbmRefPicker)).selected,
        'release/0.5',
      );
      expect(_message(tester), 'my own words');
    });

    testWidgets('a remote source is titled as a remote-tracking branch', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('origin/feat'));
      await tester.pump();
      expect(_message(tester), "Merge remote-tracking branch 'origin/feat'");
    });
  });

  group("git's default title names the destination", () {
    testWidgets('omitted for master', (tester) async {
      await _pump(tester, head: 'master', source: 'feature');
      expect(_message(tester), "Merge branch 'feature'");
    });

    testWidgets('appended for any other branch', (tester) async {
      await _pump(tester, head: 'dev', source: 'feature');
      expect(_message(tester), "Merge branch 'feature' into dev");
    });

    testWidgets('appended for a remote source too', (tester) async {
      await _pump(tester, head: 'dev', source: 'origin/feat');
      expect(
        _message(tester),
        "Merge remote-tracking branch 'origin/feat' into dev",
      );
    });
  });
}
