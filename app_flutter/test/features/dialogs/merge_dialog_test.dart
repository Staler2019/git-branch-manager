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
import 'package:gbm_flutter/widgets/gbm_button.dart';
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

  // 02-C / rulings ⑧⑨: choosing Squash asks core for git's own SQUASH_MSG and
  // shows it, multi-line, as the message. A reply is used only while it is
  // current (SquashMessagePreview.isCurrentFor); otherwise it is asked again.
  group('squash (02-C)', () {
    const String headTarget = 'aaaa';
    final String sourceTarget = 'a' * 40;
    const String squashMsg =
        'Squashed commit of the following:\n\ncommit 1234\n\n    Add g\n';

    SquashMessagePreview preview({
      String source = 'feature',
      String head = headTarget,
      String? tip,
      String message = squashMsg,
    }) => SquashMessagePreview(
      source: source,
      headOid: head,
      sourceOid: tip ?? sourceTarget,
      message: message,
      failed: false,
    );

    Future<void> pickSquash(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Squash 成一筆'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Squash 成一筆'));
      await tester.pumpAndSettle();
    }

    int requests(FakeRepoSessionController fake) => fake.commandLog
        .where((FakeCommand c) => c.name == 'requestSquashMessage')
        .length;

    bool mergeEnabled(WidgetTester tester) =>
        tester
            .widget<GbmButton>(find.widgetWithText(GbmButton, 'Merge'))
            .onPressed !=
        null;

    testWidgets('choosing Squash asks for the preview of the source', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        source: 'feature',
      );
      await pickSquash(tester);
      final FakeCommand call = fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestSquashMessage',
      );
      expect(call.args['source'], 'feature');
    });

    testWidgets('a current preview fills a multi-line message and is what '
        'Merge dispatches', (tester) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        source: 'feature',
      );
      await pickSquash(tester);
      fake.publishSquashMessagePreview(preview());
      await tester.pumpAndSettle();

      expect(_message(tester), squashMsg);
      final TextField field = tester.widget(find.byType(TextField).last);
      expect(field.enabled, isNot(false));
      expect(field.maxLines, greaterThan(2));

      await tester.ensureVisible(find.text('Merge'));
      await tester.tap(find.text('Merge'));
      await tester.pump();
      final FakeCommand call = _merged(fake);
      expect(call.args['mode'], MergeMode.squash);
      expect(call.args['message'], squashMsg);
    });

    testWidgets('until a current preview arrives, Merge is disabled', (
      tester,
    ) async {
      await _pump(tester, source: 'feature');
      await pickSquash(tester);
      expect(mergeEnabled(tester), isFalse);
    });

    testWidgets('a preview built for another HEAD is not used, and is asked '
        'for again', (tester) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        source: 'feature',
      );
      await pickSquash(tester);
      final int before = requests(fake);
      fake.publishSquashMessagePreview(preview(head: 'bbbb'));
      await tester.pumpAndSettle();

      expect(_message(tester), isNot(squashMsg));
      expect(mergeEnabled(tester), isFalse);
      expect(requests(fake), greaterThan(before));
    });

    testWidgets('a preview built for an older source tip is not used, HEAD '
        'unchanged', (tester) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        source: 'feature',
      );
      await pickSquash(tester);
      final int before = requests(fake);
      fake.publishSquashMessagePreview(preview(tip: 'c' * 40));
      await tester.pumpAndSettle();

      expect(_message(tester), isNot(squashMsg));
      expect(requests(fake), greaterThan(before));
    });

    testWidgets('nothing to squash disables Merge', (tester) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        source: 'feature',
      );
      await pickSquash(tester);
      fake.publishSquashMessagePreview(preview(message: ''));
      await tester.pumpAndSettle();
      expect(mergeEnabled(tester), isFalse);
    });

    testWidgets('a message the user typed is kept when the preview arrives', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        source: 'feature',
      );
      await pickSquash(tester);
      await tester.enterText(find.byType(TextField).last, 'my squash');
      fake.publishSquashMessagePreview(preview());
      await tester.pumpAndSettle();
      expect(_message(tester), 'my squash');
    });

    testWidgets('leaving Squash brings back the merge title', (tester) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        source: 'feature',
      );
      await pickSquash(tester);
      fake.publishSquashMessagePreview(preview());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Merge commit（保留分支形狀）'));
      await tester.tap(find.text('Merge commit（保留分支形狀）'));
      await tester.pumpAndSettle();
      expect(_message(tester), "Merge branch 'feature'");
    });

    testWidgets('the squash subtitle says it becomes one ordinary commit', (
      tester,
    ) async {
      await _pump(tester, source: 'feature');
      expect(
        find.text('把來源的變更合成一筆一般 commit，不記錄 merge commit。'),
        findsOneWidget,
      );
    });
  });
}
