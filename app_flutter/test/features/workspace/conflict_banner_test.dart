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
        find.ancestor(
          of: find.text('Skip'),
          matching: find.byType(TextButton),
        ),
      );
      expect(skipButton.onPressed, isNull);
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
    });

    testWidgets('revert: Abort and Skip both disabled, Continue enabled', (
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
        find.ancestor(
          of: find.text('Skip'),
          matching: find.byType(TextButton),
        ),
      );
      final continueButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(TextButton),
        ),
      );
      expect(abortButton.onPressed, isNull);
      expect(skipButton.onPressed, isNull);
      expect(continueButton.onPressed, isNotNull);
    });

    testWidgets(
      'no sequencer op (e.g. git apply --3way): only count and Resolve… shown',
      (tester) async {
        final session = RepoSessionState(workingCopyStatus: _conflictedStatus(5));

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
    });
  });
}
