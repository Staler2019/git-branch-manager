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
      unstagedAdded: 0,
      unstagedRemoved: 0,
      stagedAdded: 0,
      stagedRemoved: 0,
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
  double? width,
}) {
  final Widget banner = ConflictBanner(
    repoId: 'repo1',
    session: session,
    onAbort: onAbort ?? () {},
    onSkip: onSkip ?? () {},
    onContinue: onContinue ?? () {},
  );
  return tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: width == null
            ? banner
            : Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, child: banner),
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

    // The banner's four controls are non-flex children, and RenderFlex lays
    // non-flex children out *first* -- so the Expanded on the status text
    // could never rescue an overflow the buttons caused.
    //
    // The overflow at 440px measured **27px** here, not the 6.3px the audit
    // recorded: that earlier figure was taken from a different session
    // shape, and it mattered, because 6.3px is small enough that moving the
    // controls to their own run would obviously fix it while 27px is not.
    // The controls are 435px wide on their own at this font, against a
    // 408px content box -- so the fix had to be a Wrap *within* the controls
    // as well, not only between them and the text.
    //
    // The ruling was to wrap, not to shrink the controls: the status text
    // takes one run and the controls take the next (and, at this width in
    // the test font, split across two runs of their own).
    testWidgets('at 440px the controls drop to their own row', (tester) async {
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

      await _pump(tester, session: session, width: 440);

      expect(tester.takeException(), isNull);

      final Rect status = tester.getRect(
        find.text('Rebase in progress (3/8): 1 file conflicted'),
      );
      final Rect abort = tester.getRect(find.text('Abort'));

      // Two runs, not one squeezed row: the controls start below the text.
      expect(
        abort.top,
        greaterThanOrEqualTo(status.bottom),
        reason:
            'the controls are still on the status text\'s row, so 440px is '
            'either overflowing again or the text has been crushed',
      );

      // Everything still fits horizontally on its own run. Asserting
      // visibility, not merely the absence of an exception: a child collapsed
      // to zero width throws nothing.
      final Rect resolve = tester.getRect(find.text('Resolve…'));
      expect(resolve.width, greaterThan(0));
      expect(resolve.right, lessThanOrEqualTo(440));
    });

    // The wrap must be a *narrow-width* behaviour, not the new normal: a
    // banner that always spends two rows costs vertical space on every
    // window, and the same assertion shape is the only thing that can tell
    // the two apart.
    //
    // The canvas is set explicitly for two reasons. The default is 800x600
    // and a wider SizedBox is silently clamped to it, so `width: 1280` alone
    // would have measured 768. And the widths here are in *test-font* terms:
    // flutter_test's font draws every glyph fontSize wide, so this status
    // text measures 548px where the real app's proportional font is far
    // narrower. That makes the pair of tests conservative in the right
    // direction -- the real banner wraps at a narrower window than 440px
    // suggests, and shares a run at a narrower window than this one does.
    testWidgets('with room for both, the status text and controls share one '
        'row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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

      await _pump(tester, session: session, width: 1280);

      final Rect status = tester.getRect(
        find.text('Rebase in progress (3/8): 1 file conflicted'),
      );
      final Rect abort = tester.getRect(find.text('Abort'));

      expect(abort.top, lessThan(status.bottom));

      // Controls stay pinned to the trailing edge, as they were before the
      // wrap. `right` against the outer Wrap's own right edge, not merely
      // "to the right of the status text" -- that weaker form is true under
      // WrapAlignment.start too, so it could not tell the two apart. (It
      // was written that way first, and the mutation stayed green.)
      final Rect outer = tester.getRect(find.byType(Wrap).first);
      final Rect controls = tester.getRect(find.byType(Wrap).last);
      expect(controls.right, outer.right);
    });
  });
}
