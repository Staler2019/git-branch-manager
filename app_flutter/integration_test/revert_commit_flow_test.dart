// Device-tier E2E for 05-E "Revert commit": a real `gbm_revert` commits with
// git's default `Revert "<subject>"` message and never waits on an editor
// (使用者回報 2026-10-08：「revert現在會開editor編輯revert訊息，應該用預設就好」).
//
// What this file can and cannot prove. The editor opened on Windows because
// the git child inherited the app's stdin; on POSIX that stdin is already
// /dev/null and git edits only when it sees a terminal, so removing
// `--no-edit` does not redden this test on macOS (RevertOpsTest.cpp pins the
// flag itself). `core.editor` is set to `false` so that, wherever an editor
// *would* be launched, the revert fails fast instead of hanging the run.
// What it does prove on every OS: the 05-E row reaches the native revert,
// and git records its own message.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

const String _subject = 'Add feature';

String _git(String repoPath, List<String> args) =>
    runGit(repoPath, args).stdout.toString().trim();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    File('$repoPath/feature.txt').writeAsStringSync('f\n');
    runGit(repoPath, <String>['add', 'feature.txt']);
    runGit(repoPath, <String>['commit', '-m', _subject]);
    runGit(repoPath, <String>['config', 'core.editor', 'false']);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    "05-E Revert commit commits git's default message without an editor",
    (tester) async {
      final String reverted = _git(repoPath, <String>['rev-parse', 'HEAD']);

      await pumpRealAppOn(tester, repoPath);
      await tester.tap(
        // The row, not the details pane: HEAD is selected on open, so its
        // subject is drawn twice.
        find.descendant(
          of: find.byType(CommitRow),
          matching: find.text(_subject),
        ),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      // 05-E keeps Revert under its "More actions" submenu.
      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revert commit'));
      await pumpUntil(
        tester,
        () => _git(repoPath, <String>['rev-parse', 'HEAD']) != reverted,
      );
      await tester.pumpAndSettle();

      expect(
        _git(repoPath, <String>['log', '-1', '--format=%s']),
        'Revert "$_subject"',
      );
      expect(
        _git(repoPath, <String>['log', '-1', '--format=%b']),
        'This reverts commit $reverted.',
      );
      expect(_git(repoPath, <String>['rev-parse', 'HEAD^']), reverted);
      expect(
        File('$repoPath/feature.txt').existsSync(),
        isFalse,
        reason: "the reverted commit's file is gone",
      );
    },
  );
}
