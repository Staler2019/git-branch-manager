import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart'
    show RepoSessionState;
import 'package:gbm_flutter/features/workspace/workspace_screen.dart'
    show ConflictBanner;
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

WorkingCopyStatus _conflictedStatus(int count) {
  final entries = List<WorkingCopyEntry>.generate(
    count,
    (i) => WorkingCopyEntry(
      path: 'file$i.dart',
      oldPath: '',
      untracked: false,
      staged: false,
      indexStatus: FileChangeKind.modified,
      hasUnstagedChange: false,
      worktreeStatus: FileChangeKind.modified,
      conflict: ConflictKind.bothModified,
      ancestorBlob: '',
      oursBlob: '',
      theirsBlob: '',
      similarity: 0,
      isSubmodule: false,
      isConflicted: true,
    ),
  );
  return WorkingCopyStatus(entries: entries);
}

Future<void> _pump(
  WidgetTester tester, {
  required RepoSessionState session,
  VoidCallback? onAbort,
  VoidCallback? onSkip,
  VoidCallback? onContinue,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: ConflictBanner(
          repoId: 'repo1',
          session: session,
          onAbort: onAbort ?? () {},
          onSkip: onSkip ?? () {},
          onContinue: onContinue ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('ConflictBanner', () {
    testWidgets('merge: shows status text, Abort enabled, Skip disabled', (
      tester,
    ) async {
      int abortCount = 0;
      final session = RepoSessionState(
        repoState: RepoState(
          flags: RepoStateFlags.merge,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 0,
          rebaseTotal: 0,
          rebaseOntoLabel: '',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: 'merging',
        ),
        workingCopyStatus: _conflictedStatus(2),
      );

      await _pump(tester, session: session, onAbort: () => abortCount++);

      expect(
        find.text('Merge in progress: 2 files conflicted'),
        findsOneWidget,
      );

      await tester.tap(find.text('Abort'));
      expect(abortCount, 1);

      final skipButton = tester.widget<TextButton>(
        find.ancestor(of: find.text('Skip'), matching: find.byType(TextButton)),
      );
      expect(skipButton.onPressed, isNull);

      // Merge has no backend "continue" (a plain commit finishes a merge;
      // see gbm_capi.h -- there is no gbm_merge_continue()).
      final continueButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(TextButton),
        ),
      );
      expect(continueButton.onPressed, isNull);

      // Resolve… must stay reachable during a real conflict, not just the
      // no-sequencer-state edge case -- this is the actual route into
      // ConflictResolveWindow's three-pane editor.
      expect(find.text('Resolve…'), findsOneWidget);
    });

    testWidgets('cherry-pick: Abort and Continue enabled, Skip enabled', (
      tester,
    ) async {
      int abortCount = 0;
      int skipCount = 0;
      int continueCount = 0;
      final session = RepoSessionState(
        repoState: RepoState(
          flags: RepoStateFlags.cherryPick,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 0,
          rebaseTotal: 0,
          rebaseOntoLabel: '',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: 'cherry-picking',
        ),
        workingCopyStatus: _conflictedStatus(1),
      );

      await _pump(
        tester,
        session: session,
        onAbort: () => abortCount++,
        onSkip: () => skipCount++,
        onContinue: () => continueCount++,
      );

      expect(
        find.text('Cherry-pick in progress: 1 file conflicted'),
        findsOneWidget,
      );

      await tester.tap(find.text('Abort'));
      expect(abortCount, 1);
      await tester.tap(find.text('Skip'));
      expect(skipCount, 1);
      await tester.tap(find.text('Continue'));
      expect(continueCount, 1);

      expect(find.text('Resolve…'), findsOneWidget);
    });

    testWidgets('rebase: shows step/total, Skip and Continue both work', (
      tester,
    ) async {
      int skipCount = 0;
      int continueCount = 0;
      final session = RepoSessionState(
        repoState: RepoState(
          flags: RepoStateFlags.rebaseMerge,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 3,
          rebaseTotal: 8,
          rebaseOntoLabel: 'main',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: 'rebasing',
        ),
        workingCopyStatus: _conflictedStatus(1),
      );

      await _pump(
        tester,
        session: session,
        onSkip: () => skipCount++,
        onContinue: () => continueCount++,
      );

      expect(
        find.text('Rebase in progress (3/8): 1 file conflicted'),
        findsOneWidget,
      );

      await tester.tap(find.text('Skip'));
      expect(skipCount, 1);
      await tester.tap(find.text('Continue'));
      expect(continueCount, 1);

      expect(find.text('Resolve…'), findsOneWidget);
    });

    testWidgets('revert: Abort, Skip, and Continue all disabled', (
      tester,
    ) async {
      final session = RepoSessionState(
        repoState: RepoState(
          flags: RepoStateFlags.revert,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 0,
          rebaseTotal: 0,
          rebaseOntoLabel: '',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: 'reverting',
        ),
        workingCopyStatus: _conflictedStatus(1),
      );

      await _pump(tester, session: session);

      final abortButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Abort'),
          matching: find.byType(TextButton),
        ),
      );
      final skipButton = tester.widget<TextButton>(
        find.ancestor(of: find.text('Skip'), matching: find.byType(TextButton)),
      );
      final continueButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(TextButton),
        ),
      );
      expect(abortButton.onPressed, isNull);
      expect(skipButton.onPressed, isNull);
      // Revert has no backend continue either -- see RevertOps.h: "Continue/
      // skip/abort for an in-progress revert have no UI entry point yet".
      expect(continueButton.onPressed, isNull);

      // Revert's only path to actually resolve anything is the window.
      expect(find.text('Resolve…'), findsOneWidget);
    });

    testWidgets(
      'no sequencer op (e.g. git apply --3way): only count and Resolve… shown',
      (tester) async {
        final session = RepoSessionState(
          workingCopyStatus: _conflictedStatus(5),
        );

        await _pump(tester, session: session);

        expect(find.text('5 files conflicted'), findsOneWidget);
        expect(find.text('Resolve…'), findsOneWidget);
        expect(find.text('Abort'), findsNothing);
        expect(find.text('Skip'), findsNothing);
        expect(find.text('Continue'), findsNothing);
      },
    );

    testWidgets('merge with zero conflicted files omits the count suffix', (
      tester,
    ) async {
      final session = RepoSessionState(
        repoState: RepoState(
          flags: RepoStateFlags.merge,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 0,
          rebaseTotal: 0,
          rebaseOntoLabel: '',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: 'merging',
        ),
        workingCopyStatus: WorkingCopyStatus.empty,
      );

      await _pump(tester, session: session);

      expect(find.text('Merge in progress'), findsOneWidget);
      // Nothing to resolve yet -- no conflicted files, so no Resolve… link.
      expect(find.text('Resolve…'), findsNothing);
    });

    testWidgets(
      'rebase + cherry-pick flags both set: shows Rebase, not Cherry-pick '
      '(SequencerOperationKind priority order)',
      (tester) async {
        // A conflicted `git rebase` using the merge backend can leave
        // CHERRY_PICK_HEAD on disk mid-step, so isRebasing and
        // isCherryPicking can both be true at once -- Rebase is the correct
        // label and control set then, not Cherry-pick. See
        // gbm_sequencer_operation.dart's doc comment.
        int skipCount = 0;
        int continueCount = 0;
        final session = RepoSessionState(
          repoState: RepoState(
            flags: RepoStateFlags.rebaseMerge | RepoStateFlags.cherryPick,
            isClean: false,
            isSequencerOperation: true,
            rebaseStep: 2,
            rebaseTotal: 5,
            rebaseOntoLabel: 'main',
            indexLocked: false,
            indexLockAgeSeconds: null,
            describe: 'rebasing',
          ),
          workingCopyStatus: _conflictedStatus(1),
        );

        await _pump(
          tester,
          session: session,
          onSkip: () => skipCount++,
          onContinue: () => continueCount++,
        );

        expect(
          find.text('Rebase in progress (2/5): 1 file conflicted'),
          findsOneWidget,
        );
        expect(find.text('Cherry-pick in progress'), findsNothing);

        // Skip/Continue are enabled for both rebase and cherry-pick, so this
        // doesn't distinguish which was dispatched on its own -- the label
        // assertion above is what proves the priority order.
        await tester.tap(find.text('Skip'));
        expect(skipCount, 1);
        await tester.tap(find.text('Continue'));
        expect(continueCount, 1);
      },
    );
  });
}
