import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart'
    show RepoSessionState, WorkingCopyDiffReply, repoSessionProvider;
import 'package:gbm_flutter/data/repositories/working_copy_draft_repository.dart'
    show workingCopyDraftProvider;
import 'package:gbm_flutter/data/repositories/working_copy_repository.dart'
    as wc;
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';

import '../../support/fake_repo_session.dart';
import '../../support/pump_app.dart';

void main() {
  group('WorkingCopyView', () {
    final identity = RepoIdentity(
      workDir: '/test/repo',
      gitDir: '/test/repo/.git',
    );

    final unstagedEntry = const WorkingCopyEntry(
      path: 'lib/main.dart',
      oldPath: '',
      untracked: false,
      staged: false,
      indexStatus: FileChangeKind.modified,
      hasUnstagedChange: true,
      worktreeStatus: FileChangeKind.modified,
      unstagedAdded: 0,
      unstagedRemoved: 0,
      stagedAdded: 0,
      stagedRemoved: 0,
      conflict: ConflictKind.none,
      ancestorBlob: '',
      oursBlob: '',
      theirsBlob: '',
      similarity: 0,
      isSubmodule: false,
      isConflicted: false,
    );

    final stagedEntry = const WorkingCopyEntry(
      path: 'pubspec.yaml',
      oldPath: '',
      untracked: false,
      staged: true,
      indexStatus: FileChangeKind.modified,
      hasUnstagedChange: false,
      worktreeStatus: FileChangeKind.modified,
      unstagedAdded: 0,
      unstagedRemoved: 0,
      stagedAdded: 0,
      stagedRemoved: 0,
      conflict: ConflictKind.none,
      ancestorBlob: '',
      oursBlob: '',
      theirsBlob: '',
      similarity: 0,
      isSubmodule: false,
      isConflicted: false,
    );

    testWidgets('renders two-column board with staged and unstaged files', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(
                WorkingCopyStatus(entries: [stagedEntry, unstagedEntry]),
              ),
          wc
              .repoWorkingCopyDiffsProvider(identity)
              .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
        ],
      );

      // Check that board renders
      expect(find.textContaining('Unstaged \u00b7'), findsOneWidget);
      expect(find.textContaining('Staged \u00b7'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);
    });

    testWidgets('renders the conflicted section without a layout exception', (
      tester,
    ) async {
      final conflictedEntry = const WorkingCopyEntry(
        path: 'lib/conflicted.dart',
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
      );

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(WorkingCopyStatus(entries: [conflictedEntry])),
          wc
              .repoWorkingCopyDiffsProvider(identity)
              .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
        ],
      );

      // The conflicted-section Column (header + Expanded(ListView)) sits
      // in a MainAxisSize.min Column with no bounded-height wrapper --
      // without one, RenderFlex gets unbounded height constraints from
      // its unconstrained-height ancestor and the framework throws
      // during layout/paint instead of the file list actually rendering.
      expect(tester.takeException(), isNull);
      expect(find.text('CONFLICTED'), findsOneWidget);
      expect(find.text('lib/conflicted.dart'), findsOneWidget);

      // The three actions are design-system buttons, not a private
      // hand-rolled one. The row used a local `_MiniButton` whose bare
      // InkWell carried no hoverColor at all -- so the only three buttons in
      // the conflict banner were also the only three in the app with no
      // hover, while duplicating GbmButton(secondary, sm)'s border, text
      // size and padding by hand.
      for (final String label in const <String>[
        'Take Ours',
        'Take Theirs',
        'Mark Resolved',
      ]) {
        final Finder button = find.ancestor(
          of: find.text(label),
          matching: find.byType(GbmButton),
        );
        expect(button, findsOneWidget, reason: '$label must be a GbmButton');
        expect(tester.widget<GbmButton>(button).size, GbmButtonSize.sm);
        expect(tester.widget<GbmButton>(button).kind, GbmButtonKind.secondary);
      }
    });

    // Measured, not guessed: the banner's three buttons are non-flex, so the
    // Expanded path beside them cannot rescue an overflow they cause (the
    // RenderFlex rule this repo has hit six times). The three fit down to
    // 500px and start overflowing at ~440. 500 is far below any width the
    // Working Copy pane can actually be given -- the point of pinning it is
    // that a wider button, or a fourth one, has to be a deliberate decision
    // rather than a silent overflow at the app's own default window size.
    //
    // The overflow below 440 predates this test and is not fixed here: the
    // hand-rolled buttons it replaced overflowed by 17px at 440 where these
    // overflow by 6.3, so the round narrowed it. Making it disappear needs a
    // design answer (icons? an overflow menu?), not a layout tweak.
    testWidgets('the conflict banner still fits at 500px wide', (tester) async {
      const WorkingCopyEntry conflicted = WorkingCopyEntry(
        path: 'lib/conflicted.dart',
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
      );

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 500,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(
                const WorkingCopyStatus(entries: [conflicted]),
              ),
          wc
              .repoWorkingCopyDiffsProvider(identity)
              .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
        ],
      );

      expect(tester.takeException(), isNull);
      // Visibility, not just absence of exception: an Expanded satisfies
      // "no overflow" while collapsing its child to nothing.
      for (final String label in const <String>[
        'Take Ours',
        'Take Theirs',
        'Mark Resolved',
      ]) {
        expect(tester.getSize(find.text(label)).width, greaterThan(0));
      }
    });

    testWidgets('commit message box is visible', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(WorkingCopyStatus(entries: [stagedEntry])),
          wc
              .repoWorkingCopyDiffsProvider(identity)
              .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
        ],
      );

      // Check for commit box elements
      expect(find.text('Commit summary'), findsOneWidget);
      expect(find.text('Commit'), findsOneWidget);
      expect(find.text('Amend\u2026'), findsOneWidget);
    });

    testWidgets('shows empty state when no changes', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(WorkingCopyStatus(entries: [])),
          wc
              .repoWorkingCopyDiffsProvider(identity)
              .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
        ],
      );

      expect(find.text('No changes'), findsOneWidget);
    });

    testWidgets('untracked files are included in unstaged column', (
      tester,
    ) async {
      final untrackedEntry = const WorkingCopyEntry(
        path: 'new_file.dart',
        oldPath: '',
        untracked: true,
        staged: false,
        indexStatus: FileChangeKind.added,
        hasUnstagedChange: false,
        worktreeStatus: FileChangeKind.added,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      );

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(
                WorkingCopyStatus(entries: [unstagedEntry, untrackedEntry]),
              ),
          wc
              .repoWorkingCopyDiffsProvider(identity)
              .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
        ],
      );

      // Both should appear in unstaged
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('new_file.dart'), findsOneWidget);
    });

    testWidgets('commit draft survives a widget rebuild (e.g. switching to the '
        'History tab and back via ShellRoute)', (tester) async {
      final ProviderContainer container = await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith(
            (ref) =>
                FakeRepoSessionController(identity, const RepoSessionState()),
          ),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(WorkingCopyStatus(entries: [stagedEntry])),
          wc
              .repoWorkingCopyDiffsProvider(identity)
              .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
        ],
      );

      await tester.enterText(find.byType(TextField).at(0), 'my summary');
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'my description');
      await tester.pump();

      final draftBefore = container.read(workingCopyDraftProvider(identity));
      expect(draftBefore.summary, 'my summary');
      expect(draftBefore.description, 'my description');

      // Simulate the ShellRoute disposing WorkingCopyView (e.g. switching
      // to the History tab) by pumping an unrelated widget into the SAME
      // provider container: this tears down WorkingCopyView's local State
      // -- including its TextEditingControllers -- but the container, and
      // therefore workingCopyDraftProvider's state, survives, exactly like
      // the app's single top-level ProviderScope does across navigation.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );

      // Simulate switching back to Working Copy: a brand new
      // WorkingCopyView widget/State is created and must re-seed its
      // controllers from the surviving draft rather than starting blank.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorkingCopyView(identity: identity),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('my summary'), findsOneWidget);
      expect(find.text('my description'), findsOneWidget);
    });

    testWidgets('selecting a file asks for both sides, each under its own '
        'path', (tester) async {
      // A staged rename plus the old name back in the work tree: the two
      // sides of one logical file are not the same string, so a single
      // request under "the path that was clicked" would leave one pane
      // permanently empty.
      const WorkingCopyEntry stagedRename = WorkingCopyEntry(
        path: 'lib/new.dart',
        oldPath: 'lib/old.dart',
        untracked: false,
        staged: true,
        indexStatus: FileChangeKind.renamed,
        hasUnstagedChange: false,
        worktreeStatus: FileChangeKind.modified,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 100,
        isSubmodule: false,
        isConflicted: false,
      );
      const WorkingCopyEntry worktreeOld = WorkingCopyEntry(
        path: 'lib/old.dart',
        oldPath: '',
        untracked: true,
        staged: false,
        indexStatus: FileChangeKind.modified,
        hasUnstagedChange: true,
        worktreeStatus: FileChangeKind.added,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      );

      final FakeRepoSessionController fake = FakeRepoSessionController(
        identity,
        const RepoSessionState(),
      );

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyView(identity: identity),
        ),
        overrides: [
          repoSessionProvider(identity).overrideWith((ref) => fake),
          wc
              .repoWorkingCopyStatusProvider(identity)
              .overrideWithValue(
                const WorkingCopyStatus(
                  entries: <WorkingCopyEntry>[stagedRename, worktreeOld],
                ),
              ),
          wc
              .repoWorkingCopyDiffsProvider(identity)
              .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
        ],
      );

      await tester.tap(find.text('lib/new.dart'));
      await tester.pump();

      // Counted, not `.any`: a double dispatch is a regression this repo has
      // shipped before, and `.any` is blind to it.
      final List<FakeCommand> diffs = fake.commandLog
          .where((FakeCommand c) => c.name == 'requestDiff')
          .toList(growable: false);
      expect(diffs.length, 2);
      expect(
        diffs
            .map((FakeCommand c) => '${c.args['staged']}:${c.args['path']}')
            .toSet(),
        <String>{'false:lib/old.dart', 'true:lib/new.dart'},
        reason:
            'the unstaged side is asked for under the old name and the '
            'staged side under the new one',
      );
    });
  });
}
