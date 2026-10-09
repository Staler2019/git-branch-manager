// Device-tier E2E for the commit box's prepared message
// (prepared-commit-message-spec.html section 04, rulings ①②③⑨⑪).
//
// Why at this tier: the chain crosses three seams no lower tier joins --
// RepoState's `preparedMessagePending` is computed by core from files git
// writes, the message arrives through a new capi request/event
// (`gbm_request_prepared_message`, event 37) and core strips the comment
// lines with a real `git stripspace`. Only a real repo shows that the box
// ends up holding what git prepared, minus the `# Conflicts:` block.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/features/working_copy/widgets/commit_message_box.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_shell.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

const String _source = 'topic';

Finder _branchRow(String name) => find.byWidgetPredicate(
  (Widget w) => w is BranchTreeItem && w.ref.fullName == 'refs/heads/$name',
);

String _git(String repoPath, List<String> args) =>
    runGit(repoPath, args).stdout.toString().trim();

bool _merging(String repoPath) =>
    Process.runSync('git', <String>[
      'rev-parse',
      '-q',
      '--verify',
      'MERGE_HEAD',
    ], workingDirectory: repoPath).exitCode ==
    0;

final Finder _fields = find.descendant(
  of: find.byType(CommitMessageBox),
  matching: find.byType(TextField),
);

String _summary(WidgetTester tester) =>
    tester.widget<TextField>(_fields.at(0)).controller!.text;
String _description(WidgetTester tester) =>
    tester.widget<TextField>(_fields.at(1)).controller!.text;

/// [_source] and main each rewrite the same line of README.md.
void _conflictingBranches(String repoPath) {
  runGit(repoPath, <String>['checkout', '-b', _source]);
  File('$repoPath/README.md').writeAsStringSync('# fixture\n\ntopic line.\n');
  runGit(repoPath, <String>['commit', '-am', 'Topic edit']);
  runGit(repoPath, <String>['checkout', 'main']);
  File('$repoPath/README.md').writeAsStringSync('# fixture\n\nmain line.\n');
  runGit(repoPath, <String>['commit', '-am', 'Main edit']);
}

Future<void> _openWorkingCopy(WidgetTester tester) async {
  await tester.tap(find.text('Working Copy'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> _mergeFromRow(WidgetTester tester, {bool squash = false}) async {
  await tester.tap(
    find.descendant(
      of: _branchRow(_source),
      matching: find.byTooltip('Branch actions'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Merge into current'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  if (squash) {
    await tester.tap(find.text('Squash 成一筆'));
    await tester.pump();
    // The dialog waits for its own SQUASH_MSG preview before Merge enables.
    await pumpUntil(
      tester,
      () => tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(GbmDialogShell),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text
          .isNotEmpty,
    );
  }
  await tester.tap(
    find.descendant(
      of: find.byType(GbmDialogShell),
      matching: find.text('Merge'),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() => repoPath = createTempGitRepo());
  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    'a conflicted merge overwrites the typed text with git\'s message, and '
    'Abort puts the typed text back',
    (tester) async {
      _conflictingBranches(repoPath);
      await pumpRealAppOn(tester, repoPath);
      await _openWorkingCopy(tester);
      await tester.enterText(_fields.at(0), 'mine');
      await tester.enterText(_fields.at(1), 'my body');
      await tester.pump();

      await _mergeFromRow(tester);
      await pumpUntil(
        tester,
        () => _merging(repoPath) && _summary(tester) == "Merge branch 'topic'",
      );
      await tester.pumpAndSettle();

      expect(_summary(tester), "Merge branch 'topic'");
      expect(
        _description(tester),
        isNot(contains('#')),
        reason: "git's `# Conflicts:` block is stripped by core",
      );

      await tester.tap(
        find.descendant(
          of: find.byType(ConflictBanner),
          matching: find.text('Abort'),
        ),
      );
      await pumpUntil(
        tester,
        () => !_merging(repoPath) && _summary(tester) == 'mine',
      );
      await tester.pumpAndSettle();

      expect(_summary(tester), 'mine');
      expect(_description(tester), 'my body');
    },
  );

  testWidgets(
    'resolving and committing the prepared message writes no comment lines',
    (tester) async {
      _conflictingBranches(repoPath);
      await pumpRealAppOn(tester, repoPath);
      await _openWorkingCopy(tester);

      await _mergeFromRow(tester);
      await pumpUntil(
        tester,
        () => _merging(repoPath) && _summary(tester) == "Merge branch 'topic'",
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resolve…'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();
      File('$repoPath/README.md').writeAsStringSync('# fixture\n\nresolved.\n');
      await tester.tap(find.text('Mark resolved'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        _summary(tester),
        "Merge branch 'topic'",
        reason: 'leaving for the resolve window does not refill or clear it',
      );

      final String before = _git(repoPath, <String>['rev-parse', 'HEAD']);
      await pumpUntil(
        tester,
        () =>
            tester
                .widget<GbmButton>(find.widgetWithText(GbmButton, 'Commit'))
                .onPressed !=
            null,
      );
      await tester.tap(find.widgetWithText(GbmButton, 'Commit'));
      await pumpUntil(
        tester,
        () => _git(repoPath, <String>['rev-parse', 'HEAD']) != before,
      );
      await tester.pumpAndSettle();

      expect(_merging(repoPath), isFalse);
      final String message = _git(repoPath, <String>[
        'log',
        '-1',
        '--format=%B',
      ]);
      expect(message, "Merge branch 'topic'");
      expect(message, isNot(contains('#')));
    },
  );

  testWidgets(
    'a squash that only stages leaves SQUASH_MSG in the box on arrival',
    (tester) async {
      // Fast-forward-able with a staged change of the user's own: the one
      // shape where the squash stages and does not commit, so SQUASH_MSG
      // stays on disk.
      runGit(repoPath, <String>['checkout', '-b', _source]);
      File('$repoPath/topic.txt').writeAsStringSync('one\n');
      runGit(repoPath, <String>['add', 'topic.txt']);
      runGit(repoPath, <String>['commit', '-m', 'Add topic']);
      runGit(repoPath, <String>['checkout', 'main']);
      File('$repoPath/README.md').writeAsStringSync('# mine\n');
      runGit(repoPath, <String>['add', 'README.md']);

      await pumpRealAppOn(tester, repoPath);
      await _mergeFromRow(tester, squash: true);
      await pumpUntil(
        tester,
        () => File('$repoPath/.git/SQUASH_MSG').existsSync(),
      );
      await tester.pumpAndSettle();

      // Mounting the view is the only trigger here: the merge happened while
      // History was on screen.
      await _openWorkingCopy(tester);
      await pumpUntil(tester, () => _summary(tester).isNotEmpty);

      expect(_summary(tester), 'Squashed commit of the following:');
      expect(_description(tester), contains('Add topic'));
    },
  );
}
