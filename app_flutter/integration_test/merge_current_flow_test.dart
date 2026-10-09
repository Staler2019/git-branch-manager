// Device-tier E2E for 05-B "Merge into current" (merge-rebase-dialogs-spec
// 02-B): the clicked branch is the source, locked, and the message box
// carries git's own default -- then a real `gbm_merge_branch` writes the
// merge commit.
//
// Why at this tier: the widget tests (`merge_dialog_test.dart`,
// `dialog_target_prefill_test.dart`) run on FakeRepoSessionController, so
// they prove the dialog *dispatches* `mergeBranch(source, noFastForward,
// message:)`. Only a real session proves the source survives the route's
// query parameter into the native call and that git records the message
// the user saw.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_shell.dart';
import 'package:gbm_flutter/widgets/gbm_ref_picker.dart';
import 'package:gbm_flutter/widgets/gbm_ref_read_only_field.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// Flat, with no `/`: a `feature/x` name would sit under a collapsible
/// folder row (see rename_branch_flow_test.dart's `_branch`).
const String _source = 'topic';

/// The sidebar row for local branch [name] -- by its ref, not its text, since
/// the history graph's ref badges draw the same name.
Finder _branchRow(String name) => find.byWidgetPredicate(
  (Widget w) => w is BranchTreeItem && w.ref.fullName == 'refs/heads/$name',
);

/// 05-B through the row's ⋮ button -- the entry the user reported.
Future<void> _openRowMenuItem(
  WidgetTester tester,
  String branch,
  String item,
) async {
  await tester.tap(
    find.descendant(
      of: _branchRow(branch),
      matching: find.byTooltip('Branch actions'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

String _git(String repoPath, List<String> args) =>
    runGit(repoPath, args).stdout.toString().trim();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    runGit(repoPath, <String>['checkout', '-b', _source]);
    runGit(repoPath, <String>[
      'commit',
      '--allow-empty',
      '-m',
      'Add topic work',
    ]);
    runGit(repoPath, <String>['checkout', 'main']);
    runGit(repoPath, <String>['commit', '--allow-empty', '-m', 'Main moves']);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    '05-B Merge into current: the clicked branch is locked, the message is '
    "git's default, and the merge commit carries it",
    (tester) async {
      await pumpRealAppOn(tester, repoPath);
      await _openRowMenuItem(tester, _source, 'Merge into current');

      expect(find.text('Merge Branch'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is GbmRefReadOnlyField && w.name == _source,
        ),
        findsOneWidget,
        reason: 'the source is the clicked branch, drawn read-only',
      );
      expect(
        find.byType(GbmRefPicker),
        findsNothing,
        reason: 'a locked source offers no picker to change it',
      );
      final TextField message = tester.widget<TextField>(
        find.descendant(
          of: find.byType(GbmDialogShell),
          matching: find.byType(TextField),
        ),
      );
      expect(
        message.controller!.text,
        "Merge branch '$_source'",
        reason: "git omits ' into main' when the destination is main",
      );

      final String before = _git(repoPath, <String>['rev-parse', 'HEAD']);
      // Inside the dialog: the toolbar may carry a Merge button of its own.
      await tester.tap(
        find.descendant(
          of: find.byType(GbmDialogShell),
          matching: find.text('Merge'),
        ),
      );
      await pumpUntil(
        tester,
        () => _git(repoPath, <String>['rev-parse', 'HEAD']) != before,
      );
      await tester.pumpAndSettle();

      expect(
        _git(repoPath, <String>['log', '-1', '--format=%s']),
        "Merge branch '$_source'",
      );
      expect(
        _git(repoPath, <String>[
          'rev-list',
          '--parents',
          '-1',
          'HEAD',
        ]).split(' ').length,
        3,
        reason: 'a merge commit: itself plus two parents',
      );
      expect(
        _git(repoPath, <String>['rev-parse', 'HEAD^2']),
        _git(repoPath, <String>['rev-parse', _source]),
        reason: 'the second parent is the branch that was clicked',
      );
    },
  );
}
