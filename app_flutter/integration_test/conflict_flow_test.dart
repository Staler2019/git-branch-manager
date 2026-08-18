// Device-tier E2E (Phase 4): create a real merge conflict, see the banner,
// resolve it through ConflictResolveWindow, finish via a normal commit --
// against the real gbm_capi.dylib/.so and a real temp git repo.
//
// Per gbm_sequencer_operation.dart's doc comment, `RepoState.isSequencerOperation`
// deliberately excludes merge (a plain `git commit` finishes one, there is
// no sequencer todo-file) -- so once every conflicted path is marked
// resolved, `conflictActive` (isSequencerOperation || conflicted.isNotEmpty)
// drops back to false and the ordinary Working Copy Commit button is the
// real way to finish, not a Continue control (which the resolve window
// itself disables for merge -- see its own tooltip).
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

    // main and feature both edit the same line of README.md -> a real,
    // unresolvable-by-git merge conflict.
    runGit(repoPath, <String>['checkout', '-b', 'feature']);
    File(
      '$repoPath/README.md',
    ).writeAsStringSync('# gbm e2e fixture\n\nfeature branch line.\n');
    runGit(repoPath, <String>['commit', '-am', 'Feature edit']);

    runGit(repoPath, <String>['checkout', 'main']);
    File(
      '$repoPath/README.md',
    ).writeAsStringSync('# gbm e2e fixture\n\nmain branch line.\n');
    runGit(repoPath, <String>['commit', '-am', 'Main edit']);

    // Real conflicting merge -- exits non-zero (conflict), which is
    // expected here, so this bypasses runGit's exit-code check.
    Process.runSync('git', <String>[
      'merge',
      'feature',
    ], workingDirectory: repoPath);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    'conflict on open -> banner -> resolve window -> Mark Resolved -> '
    'commit finishes the merge',
    (tester) async {
      await pumpRealAppOn(tester, repoPath);

      expect(
        find.textContaining('Merge in progress'),
        // Both the workspace's ConflictBanner and the sidebar's own status
        // label render this text -- this assertion only needs "somewhere",
        // not a single render site.
        findsWidgets,
        reason: 'the app opened directly onto an already-conflicted repo',
      );

      await tester.tap(find.text('Resolve…'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();

      // Resolve exactly as a user editing the embedded editor would: the
      // file on disk still has conflict markers (`<<<<<<<`/`=======`/
      // `>>>>>>>`) at this point -- overwrite it with clean content, then
      // tell the app the path is resolved so it stages whatever is on disk
      // (see ConflictOps.h's MarkResolved doc comment).
      File(
        '$repoPath/README.md',
      ).writeAsStringSync('# gbm e2e fixture\n\nresolved line.\n');
      // "Mark Resolved" renders twice -- once inline on the file-list row,
      // once on the bottom action bar -- either dispatches the same
      // resolveConflict() call, so tapping the first is sufficient.
      await tester.tap(find.text('Mark Resolved').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Note: the sidebar's own status label still reads "Merge in
      // progress" here, correctly -- MERGE_HEAD is still on disk until the
      // commit below actually lands (see this file's top doc comment on
      // why `conflictActive` and `activeSequencerOperation` diverge for
      // merge specifically). Only the workspace's danger-styled
      // ConflictBanner is gone at this point; that's covered indirectly by
      // the Commit button becoming enabled next, so no separate assertion
      // for "no banner" is made here.

      // ConflictResolveWindow is a standalone window (not a WorkspaceScreen
      // tab -- see CLAUDE.md's route tree); its AppBar back button always
      // routes to Working Copy regardless of the "No conflicts remaining"
      // panel's own (locally-batched, and not necessarily rebuilt on this
      // exact frame) empty-state check.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final Finder summaryField = find
          .descendant(
            of: find.byType(CommitMessageBox),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(summaryField, 'Merge feature into main');
      await tester.pump();

      final Finder commitButton = find.widgetWithText(GbmButton, 'Commit');

      // Same H2 reason as commit_flow_test.dart: canCommit is only
      // recomputed by WorkingCopyView on *some* rebuild, not reliably on
      // the summary controller's own text change. A same-widget rebuild
      // trigger (e.g. re-tapping README's own checkbox) was observed to
      // race the real FFI stage/unstage round-trip in this merge scenario
      // specifically (the underlying session state settles correctly --
      // confirmed by reading repoSessionProvider directly -- but the
      // GbmButton already in the tree does not always pick it up). A full
      // tab-away-and-back forces WorkingCopyView to unmount and remount,
      // which re-reads both the draft provider (still holding the summary
      // just typed, since CommitMessageBox's onSummaryChanged writes it
      // through) and a fresh repoSessionProvider watch from initState --
      // sidestepping the race entirely rather than trying to out-time it.
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('Working Copy'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final GbmButton commit = tester.widget<GbmButton>(commitButton);
      expect(
        commit.onPressed,
        isNotNull,
        reason:
            'staged.isNotEmpty && summary.isNotEmpty && '
            'isActionEnabled(repositoryCommit, ...) should all hold once '
            'the merge conflict is fully resolved',
      );

      await tester.tap(commitButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final ProcessResult mergeHead = Process.runSync('git', <String>[
        'rev-parse',
        '-q',
        '--verify',
        'MERGE_HEAD',
      ], workingDirectory: repoPath);
      expect(
        mergeHead.exitCode,
        isNot(0),
        reason: 'MERGE_HEAD should be gone once the merge commit lands',
      );

      final ProcessResult mergeLog = runGit(repoPath, <String>[
        'log',
        '-1',
        '--merges',
        '--pretty=%s',
      ]);
      expect(mergeLog.stdout.toString().trim(), 'Merge feature into main');

      final ProcessResult status = runGit(repoPath, <String>[
        'status',
        '--porcelain',
      ]);
      expect(status.stdout.toString().trim(), isEmpty);
    },
  );
}
