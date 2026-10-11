// Device-tier E2E for the Merge dialog's Squash mode (merge-rebase-dialogs-
// spec 02-C, 使用者裁定 ⑨ 「用 git 的 SQUASH_MSG」 and 「merge沒conflict才可以
// 直接commit」).
//
// Why at this tier: `gbm_merge_branch`'s `message` changed meaning for squash
// -- it used to be ignored, now it commits -- and `lookupFunction` matches
// by symbol name only ([TEST-ffi-matches-symbol-only]), so nothing below
// this tier drives that meaning across `dart:ffi`. The preview itself is a
// new event (GBM_EVENT_SQUASH_MESSAGE_READY) whose text is compared here
// against the SQUASH_MSG a real `git merge --squash` writes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_shell.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

const String _source = 'topic';

Finder _branchRow(String name) => find.byWidgetPredicate(
  (Widget w) => w is BranchTreeItem && w.ref.fullName == 'refs/heads/$name',
);

String _git(String repoPath, List<String> args) =>
    runGit(repoPath, args).stdout.toString().trim();

/// [_source] with two commits that add `topic.txt`; with [mainMoves], main
/// gains a commit too, so the squash cannot fast-forward.
void _addTopic(String repoPath, {required bool mainMoves}) {
  runGit(repoPath, <String>['checkout', '-b', _source]);
  File('$repoPath/topic.txt').writeAsStringSync('one\n');
  runGit(repoPath, <String>['add', 'topic.txt']);
  runGit(repoPath, <String>['commit', '-m', 'Add topic', '-m', 'Body line.']);
  File('$repoPath/topic.txt').writeAsStringSync('one\ntwo\n');
  runGit(repoPath, <String>['commit', '-am', 'Grow topic']);
  runGit(repoPath, <String>['checkout', 'main']);
  if (mainMoves) {
    File('$repoPath/main.txt').writeAsStringSync('m\n');
    runGit(repoPath, <String>['add', 'main.txt']);
    runGit(repoPath, <String>['commit', '-m', 'Main moves']);
  }
}

/// The bytes git itself writes to `.git/SQUASH_MSG` for this squash, read
/// from a throwaway clone so the repository under test is never touched.
/// A clone keeps every oid, and SQUASH_MSG names commits, never refs.
String _gitsSquashMsg(String repoPath) {
  final String clone = Directory.systemTemp
      .createTempSync('gbm_e2e_squash_clone_')
      .resolveSymbolicLinksSync();
  addTearDown(() => deleteTempGitRepo(clone));
  Process.runSync('git', <String>['clone', '--quiet', repoPath, clone]);
  runGit(clone, <String>['merge', '--squash', 'origin/$_source']);
  return File('$clone/.git/SQUASH_MSG').readAsStringSync();
}

Future<void> _openSquashDialog(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: _branchRow(_source),
      matching: find.byTooltip('Branch actions'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Merge into current'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.tap(find.text('Squash 成一筆'));
  await tester.pump();
}

String _messageBoxText(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byType(GbmDialogShell),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

Future<void> _tapMerge(WidgetTester tester) => tester.tap(
  find.descendant(
    of: find.byType(GbmDialogShell),
    matching: find.text('Merge'),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() => repoPath = createTempGitRepo());
  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    "Squash prefills git's own SQUASH_MSG and commits it as one ordinary "
    'commit',
    (tester) async {
      _addTopic(repoPath, mainMoves: true);
      final String expected = _gitsSquashMsg(repoPath);

      await pumpRealAppOn(tester, repoPath);
      await _openSquashDialog(tester);
      await pumpUntil(tester, () => _messageBoxText(tester).isNotEmpty);

      expect(
        _messageBoxText(tester),
        expected,
        reason: 'byte-for-byte what `git merge --squash` writes',
      );

      final String before = _git(repoPath, <String>['rev-parse', 'HEAD']);
      await _tapMerge(tester);
      await pumpUntil(
        tester,
        () => _git(repoPath, <String>['rev-parse', 'HEAD']) != before,
      );
      await tester.pumpAndSettle();

      expect(
        _git(repoPath, <String>[
          'rev-list',
          '--parents',
          '-1',
          'HEAD',
        ]).split(' ').length,
        2,
        reason: 'one ordinary commit: itself plus one parent',
      );
      expect(_git(repoPath, <String>['rev-parse', 'HEAD^']), before);
      expect(
        _git(repoPath, <String>['log', '-1', '--format=%s']),
        'Squashed commit of the following:',
      );
      expect(
        File('$repoPath/topic.txt').readAsStringSync(),
        'one\ntwo\n',
        reason: "the source's changes are in the commit",
      );
      expect(
        _git(repoPath, <String>['status', '--porcelain']),
        '',
        reason: 'nothing is left staged or modified',
      );
    },
  );

  testWidgets(
    'Squash over work the user had already staged stages it and commits '
    'nothing',
    (tester) async {
      // Fast-forward-able on purpose: only then does git keep the staged
      // change, which a commit would sweep into the squash.
      _addTopic(repoPath, mainMoves: false);
      File('$repoPath/README.md').writeAsStringSync('# mine\n');
      runGit(repoPath, <String>['add', 'README.md']);
      final String before = _git(repoPath, <String>['rev-parse', 'HEAD']);

      await pumpRealAppOn(tester, repoPath);
      await _openSquashDialog(tester);
      await pumpUntil(tester, () => _messageBoxText(tester).isNotEmpty);
      expect(_messageBoxText(tester), isNotEmpty);

      await _tapMerge(tester);
      await pumpUntil(
        tester,
        () => _git(repoPath, <String>[
          'diff',
          '--cached',
          '--name-only',
        ]).contains('topic.txt'),
      );
      await tester.pumpAndSettle();

      expect(
        _git(repoPath, <String>['rev-parse', 'HEAD']),
        before,
        reason: 'no commit: it would have carried README.md too',
      );
      expect(
        _git(repoPath, <String>['diff', '--cached', '--name-only']),
        'README.md\ntopic.txt',
        reason: 'the squash and the user\'s own change both stay staged',
      );
    },
  );
}
