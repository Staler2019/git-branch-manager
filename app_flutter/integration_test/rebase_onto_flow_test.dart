// Device-tier E2E for 05-B "Rebase current onto here" (merge-rebase-dialogs-
// spec 03-B, 使用者裁定 「不應該可以選」): the clicked branch is the target,
// locked, and a real `gbm_start_rebase` replays the current branch on it.
//
// Why at this tier: the widget tests prove the dialog dispatches
// `startRebase(target, ...)` on FakeRepoSessionController; only a real
// session proves the route's `target` reaches git.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_shell.dart';
import 'package:gbm_flutter/widgets/gbm_ref_picker.dart';
import 'package:gbm_flutter/widgets/gbm_ref_read_only_field.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// The checked-out branch, replayed onto `main`.
const String _current = 'topic';

Finder _branchRow(String name) => find.byWidgetPredicate(
  (Widget w) => w is BranchTreeItem && w.ref.fullName == 'refs/heads/$name',
);

String _git(String repoPath, List<String> args) =>
    runGit(repoPath, args).stdout.toString().trim();

bool _isAncestor(String repoPath, String ancestor, String of) =>
    Process.runSync('git', <String>[
      'merge-base',
      '--is-ancestor',
      ancestor,
      of,
    ], workingDirectory: repoPath).exitCode ==
    0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    runGit(repoPath, <String>['checkout', '-b', _current]);
    File('$repoPath/topic.txt').writeAsStringSync('t\n');
    runGit(repoPath, <String>['add', 'topic.txt']);
    runGit(repoPath, <String>['commit', '-m', 'Add topic work']);
    runGit(repoPath, <String>['checkout', 'main']);
    File('$repoPath/main.txt').writeAsStringSync('m\n');
    runGit(repoPath, <String>['add', 'main.txt']);
    runGit(repoPath, <String>['commit', '-m', 'Main moves']);
    runGit(repoPath, <String>['checkout', _current]);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    '05-B Rebase current onto here: the clicked branch is locked and the '
    'current branch is replayed on it',
    (tester) async {
      expect(_isAncestor(repoPath, 'main', _current), isFalse);

      await pumpRealAppOn(tester, repoPath);
      await tester.tap(
        find.descendant(
          of: _branchRow('main'),
          matching: find.byTooltip('Branch actions'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rebase current onto here'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is GbmRefReadOnlyField && w.label == '基於' && w.name == 'main',
        ),
        findsOneWidget,
        reason: 'the target is the clicked branch, drawn read-only',
      );
      expect(
        find.byType(GbmRefPicker),
        findsNothing,
        reason: '「不應該可以選」: a locked target offers no picker',
      );

      await tester.tap(
        find.descendant(
          of: find.byType(GbmDialogShell),
          matching: find.text('Start rebase'),
        ),
      );
      await pumpUntil(tester, () => _isAncestor(repoPath, 'main', _current));
      await tester.pumpAndSettle();

      expect(
        _git(repoPath, <String>['rev-parse', '--abbrev-ref', 'HEAD']),
        _current,
        reason: 'the rebase finished on the branch it started on',
      );
      expect(
        _git(repoPath, <String>['rev-parse', 'HEAD^']),
        _git(repoPath, <String>['rev-parse', 'main']),
        reason: "the topic commit now sits directly on main's tip",
      );
      expect(
        _git(repoPath, <String>['log', '-1', '--format=%s']),
        'Add topic work',
      );
    },
  );
}
