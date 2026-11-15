// Device-tier repro for 「新增 worktree 後清單沒有更新」 (macOS report).
//
// Every link of the chain is wired on paper -- `Session::addWorktree`'s
// onSuccess refreshes, `WORKTREES_UPDATED` reaches `_readWorktrees`, and the
// panel watches `state.worktrees` -- so only a real core, a real `git
// worktree add` and the real dialog can say which link drops the new row.
//
// Run it as `flutter test integration_test/worktree_add_refresh_test.dart
// -d macos`, one file at a time ([TEST-device-runs-one-file]).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_action_shortcuts.dart';
import 'package:gbm_flutter/widgets/gbm_ref_picker.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

const String _addedName = 'wt-added';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;
  late String added;

  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_e2e_wtadd_');
    // A sibling, not a child -- see worktree_pending_counts_test.dart.
    added = '$repo-added/$_addedName';
    runGit(repo, <String>['branch', 'feature/existing']);
  });

  tearDown(() {
    deleteTempGitRepo(repo);
    final Directory parent = Directory('$repo-added');
    if (parent.existsSync()) parent.deleteSync(recursive: true);
    final Directory origin = Directory('$repo-origin.git');
    if (origin.existsSync()) origin.deleteSync(recursive: true);
  });

  testWidgets('a worktree added from the panel appears in its list', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repo);

    Actions.invoke(
      tester.element(find.byType(StatusBar)),
      const GbmActionIntent(GbmActionId.toolsWorktrees),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PanelListRow), findsOneWidget);

    await tester.tap(find.text('Add worktree…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('建立新分支'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-worktree-new-branch-name-field')),
      'feature/added',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('add-worktree-path-field')),
      added,
    );
    await tester.pump();
    await tester.tap(find.text('Add worktree'));
    await tester.pump();

    // Fixed steps, not pumpAndSettle: the add and the refresh both run on
    // background threads ([TEST-no-pumpandsettle-with-spinner]).
    final Finder row = find.descendant(
      of: find.byType(PanelListRow),
      matching: find.text(_addedName),
    );
    for (int i = 0; i < 40 && row.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(
      Directory(added).existsSync(),
      isTrue,
      reason: 'git worktree add itself never ran or failed',
    );
    expect(
      row,
      findsOneWidget,
      reason: 'the worktree exists on disk but the panel never listed it',
    );
  });

  // 使用者回報的路徑: 「checkout 既有分支」, not 建立新分支.
  testWidgets('a worktree checked out from an existing branch appears too', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repo);

    Actions.invoke(
      tester.element(find.byType(StatusBar)),
      const GbmActionIntent(GbmActionId.toolsWorktrees),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PanelListRow), findsOneWidget);

    await tester.tap(find.text('Add worktree…'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(GbmRefPicker),
        matching: find.text('feature/existing'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-worktree-path-field')),
      added,
    );
    await tester.pump();
    await tester.tap(find.text('Add worktree'));
    await tester.pump();

    final Finder row = find.descendant(
      of: find.byType(PanelListRow),
      matching: find.text(_addedName),
    );
    for (int i = 0; i < 40 && row.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(
      Directory(added).existsSync(),
      isTrue,
      reason: 'git worktree add itself never ran or failed',
    );
    expect(
      row,
      findsOneWidget,
      reason: 'the worktree exists on disk but the panel never listed it',
    );
  });

  // Whether the new branch tracks anything crosses `gbm_worktree_add`'s
  // `track` parameter, which only a real library can attest
  // ([TEST-ffi-matches-symbol-only]). git runs only before the app opens;
  // afterwards the upstream is read from `.git/config` as a file
  // ([TEST-no-dart-process-while-core-runs-git]).
  group('upstream of the branch the worktree holds', () {
    testWidgets('a new branch does not inherit its start point\'s upstream', (
      tester,
    ) async {
      _seedOrigin(repo);
      runGit(repo, <String>['push', '--set-upstream', 'origin', 'main']);
      // `inherit` hands even a local start point's upstream on, so this
      // fails for any `-b` sent without an explicit `--no-track`.
      runGit(repo, <String>['config', 'branch.autoSetupMerge', 'inherit']);
      await pumpRealAppOn(tester, repo);

      await _openAddWorktree(tester);
      await tester.tap(find.text('建立新分支'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add-worktree-new-branch-name-field')),
        'feature/added',
      );
      await tester.pump();
      await _submitAndAwaitRow(tester, added);

      expect(
        File('$repo/.git/config').readAsStringSync(),
        isNot(contains('[branch "feature/added"]')),
        reason: 'the new branch was given an upstream it never asked for',
      );
    });

    testWidgets('a remote-only branch checked out still tracks its remote', (
      tester,
    ) async {
      _seedOrigin(repo);
      runGit(repo, <String>['push', 'origin', 'main:topic']);
      await pumpRealAppOn(tester, repo);

      await _openAddWorktree(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(GbmRefPicker),
          matching: find.text('origin/topic'),
        ),
      );
      await tester.pumpAndSettle();
      await _submitAndAwaitRow(tester, added);

      expect(
        File('$repo/.git/config').readAsStringSync(),
        contains(
          '[branch "topic"]\n\tremote = origin\n\tmerge = refs/heads/topic',
        ),
        reason: 'the local topic was created without tracking origin/topic',
      );
    });
  });
}

/// A bare sibling as `origin`, so the app's own fetches find a real remote.
void _seedOrigin(String repo) {
  final String origin = '$repo-origin.git';
  runGit(repo, <String>['init', '--bare', '--initial-branch=main', origin]);
  runGit(repo, <String>['remote', 'add', 'origin', origin]);
}

Future<void> _openAddWorktree(WidgetTester tester) async {
  Actions.invoke(
    tester.element(find.byType(StatusBar)),
    const GbmActionIntent(GbmActionId.toolsWorktrees),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add worktree…'));
  await tester.pumpAndSettle();
}

/// Types [path], submits, and waits on fixed steps -- not pumpAndSettle,
/// since the add and the refresh run on background threads
/// ([TEST-no-pumpandsettle-with-spinner]) -- until the panel lists it.
Future<void> _submitAndAwaitRow(WidgetTester tester, String path) async {
  await tester.enterText(
    find.byKey(const Key('add-worktree-path-field')),
    path,
  );
  await tester.pump();
  await tester.tap(find.text('Add worktree'));
  await tester.pump();

  final Finder row = find.descendant(
    of: find.byType(PanelListRow),
    matching: find.text(_addedName),
  );
  for (int i = 0; i < 40 && row.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(row, findsOneWidget, reason: 'git worktree add never finished');
}
