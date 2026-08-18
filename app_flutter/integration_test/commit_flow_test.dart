// Device-tier E2E (Phase 4): modify a tracked file, stage it, type a commit
// summary, commit -- against the real gbm_capi.dylib/.so and a real temp
// git repo. Verifies both through the UI and by shelling back into the same
// repo with `git log`, so a false-positive from stale widget state can't
// pass silently.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/working_copy/widgets/commit_message_box.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    File(
      '$repoPath/README.md',
    ).writeAsStringSync('# gbm e2e fixture\n\nmodified by commit_flow_test.\n');
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    'modify -> stage -> commit -> new commit lands in History and on disk',
    (tester) async {
      await pumpRealAppOn(tester, repoPath);

      // Working Copy tab: the modified README should be listed unstaged.
      await tester.tap(find.text('Working Copy'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('README.md'), findsOneWidget);

      // Type the commit summary first (see this repo's H2 finding in
      // docs/reports/code-review-2026-08.md: the Commit button only
      // recomputes on an unrelated rebuild, not on the controller's own
      // text changes) -- staging the file below is that rebuild trigger.
      final Finder summaryField = find
          .descendant(
            of: find.byType(CommitMessageBox),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(summaryField, 'E2E commit');
      await tester.pump();

      // Stage the file via its row checkbox.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final Finder commitButton = find.widgetWithText(GbmButton, 'Commit');
      expect(commitButton, findsOneWidget);
      final GbmButton commit = tester.widget<GbmButton>(commitButton);
      expect(
        commit.onPressed,
        isNotNull,
        reason: 'staged.isNotEmpty && summary.isNotEmpty should enable Commit',
      );

      await tester.tap(commitButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final ProcessResult log = runGit(repoPath, <String>[
        'log',
        '-1',
        '--pretty=%s',
      ]);
      expect(log.stdout.toString().trim(), 'E2E commit');

      final ProcessResult status = runGit(repoPath, <String>[
        'status',
        '--porcelain',
      ]);
      expect(
        status.stdout.toString().trim(),
        isEmpty,
        reason: 'the working tree should be clean after the real commit',
      );

      // History reflects the new commit once switched back.
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('E2E commit'), findsOneWidget);
    },
  );
}
