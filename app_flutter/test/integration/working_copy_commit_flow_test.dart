// Spec P03's commit box, at the seam a widget test cannot reach: does
// pressing the button (or the shortcut, which dispatches through the real
// WorkspaceScreen._buildActionHandlers()) actually reach the controller, and
// does the box clear on the right event rather than on the press.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/working_copy_draft_repository.dart';
import 'package:gbm_flutter/features/working_copy/widgets/commit_message_box.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';
import 'package:gbm_flutter/routing/route_paths.dart';

import 'package:gbm_flutter/widgets/gbm_button.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/repo',
  gitDir: '/repo/.git',
);

RefSnapshot _refsAt(String target) => RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: target,
  ),
  refs: const <RefInfo>[],
  refCountGuardTripped: false,
  totalRefCount: 0,
);

const WorkingCopyEntry _staged = WorkingCopyEntry(
  path: 'lib/a.dart',
  oldPath: '',
  untracked: false,
  staged: true,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: false,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 3,
  stagedRemoved: 1,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: 0,
  isSubmodule: false,
  isConflicted: false,
);

RepoSessionState _sessionAt(String head) => RepoSessionState(
  isOpen: true,
  refs: _refsAt(head),
  workingCopyStatus: const WorkingCopyStatus(
    entries: <WorkingCopyEntry>[_staged],
  ),
);

Future<PumpedWorkspace> _pumpAtWorkingCopy(
  WidgetTester tester, {
  String head = 'deadbeef',
}) async {
  final PumpedWorkspace pumped = await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: _sessionAt(head),
    workingCopyBuilder: (BuildContext context, _) =>
        const WorkingCopyView(identity: _identity),
  );
  pumped.router.go(
    RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
  );
  await tester.pumpAndSettle();
  return pumped;
}

/// The commit summary field specifically. `find.byType(TextField).first` is
/// the sidebar's branch filter -- it comes earlier in the tree, and typing
/// into it silently leaves the commit box empty.
final Finder _summaryField = find
    .descendant(
      of: find.byType(CommitMessageBox),
      matching: find.byType(TextField),
    )
    .first;

int _commits(PumpedWorkspace pumped) => pumped.controller.commandLog
    .where((FakeCommand c) => c.name == 'commit')
    .length;

void main() {
  group('the box clears on success, not on the press', () {
    testWidgets('a submitted message stays put until HEAD moves', (
      WidgetTester tester,
    ) async {
      // The box used to clear on the press. A commit that failed -- nothing
      // staged, a rejecting hook, a bad identity -- took the message with
      // it, and now that the message is also on disk that loss would be
      // permanent.
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'fix: something');
      await tester.pump();

      await tester.tap(find.widgetWithText(GbmButton, 'Commit'));
      await tester.pump();

      expect(_commits(pumped), 1);
      expect(
        pumped.container.read(workingCopyDraftProvider(_identity)).summary,
        'fix: something',
      );
    });

    testWidgets('an unrelated refresh at the same HEAD does not clear it', (
      WidgetTester tester,
    ) async {
      // Status refreshes republish the session constantly while a commit is
      // in flight. Only HEAD actually *moving* means the commit landed.
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'fix: something');
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Commit'));
      await tester.pump();

      pumped.controller.emit(
        _sessionAt('deadbeef').copyWith(isRefreshing: false),
      );
      await tester.pump();
      await tester.pump();

      expect(
        pumped.container.read(workingCopyDraftProvider(_identity)).summary,
        'fix: something',
      );
    });

    testWidgets('HEAD moving clears it', (WidgetTester tester) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'fix: something');
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Commit'));
      await tester.pump();

      pumped.controller.emit(_sessionAt('cafebabe'));
      await tester.pumpAndSettle();

      expect(
        pumped.container.read(workingCopyDraftProvider(_identity)).summary,
        isEmpty,
      );
    });

    testWidgets('an error while the commit is outstanding stops the wait', (
      WidgetTester tester,
    ) async {
      // Otherwise the *next* HEAD move -- another commit, a checkout --
      // would clear a message written since.
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'fix: something');
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Commit'));
      await tester.pump();

      pumped.controller.emit(
        _sessionAt('deadbeef').copyWith(
          lastError: const GitError(
            code: 1,
            codeName: 'GBM_ERR_GIT',
            message: 'hook refused',
            detail: '',
            argv: <String>['git', 'commit'],
            exitCode: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      pumped.controller.emit(_sessionAt('cafebabe'));
      await tester.pumpAndSettle();

      expect(
        pumped.container.read(workingCopyDraftProvider(_identity)).summary,
        'fix: something',
      );
    });
  });

  group('amend is a mode', () {
    testWidgets('entering asks for HEAD\'s message rather than hoping it is '
        'cached', (WidgetTester tester) async {
      // commitMetaCache is filled by History's viewport scrolling past a
      // commit; on a session that never opened History it is empty, and the
      // box would come up blank -- which reads as "the commit had no
      // message".
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);

      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pumpAndSettle();

      final Iterable<FakeCommand> asked = pumped.controller.commandLog.where(
        (FakeCommand c) => c.name == 'requestCommitMeta',
      );
      expect(asked.length, 1);
      expect(asked.single.args['oids'], <String>['deadbeef']);
    });

    testWidgets('the message arriving fills the box in', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pumpAndSettle();

      pumped.controller.emit(
        _sessionAt(
          'deadbeef',
        ).copyWith(commitMetaCache: <String, CommitMeta>{'deadbeef': _meta()}),
      );
      await tester.pumpAndSettle();

      expect(find.text('feat: the last commit'), findsOneWidget);
      expect(find.text('its body'), findsOneWidget);
    });

    testWidgets('cancelling puts back what the box held', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'mine');
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pumpAndSettle();
      pumped.controller.emit(
        _sessionAt(
          'deadbeef',
        ).copyWith(commitMetaCache: <String, CommitMeta>{'deadbeef': _meta()}),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(GbmButton, 'Cancel amend'));
      await tester.pumpAndSettle();

      expect(find.text('mine'), findsOneWidget);
      expect(find.text('feat: the last commit'), findsNothing);
      expect(find.widgetWithText(GbmButton, 'Commit'), findsOneWidget);
    });

    testWidgets('submitting in the mode passes --amend', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'reworded');
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pump();

      final Iterable<FakeCommand> commits = pumped.controller.commandLog.where(
        (FakeCommand c) => c.name == 'commit',
      );
      expect(commits.length, 1);
      expect(commits.single.args['amend'], isTrue);
    });

    testWidgets('a successful amend leaves the mode', (
      WidgetTester tester,
    ) async {
      // reset() is what clears the draft on success, and `amending` lives in
      // the same object -- so a cleared box that stayed in the mode would
      // leave the next commit silently rewriting HEAD.
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'reworded');
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pump();

      pumped.controller.emit(_sessionAt('cafe1234'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(GbmButton, 'Amend'), findsOneWidget);
      expect(find.widgetWithText(GbmButton, 'Cancel amend'), findsNothing);
    });

    testWidgets('the shortcut enters the mode rather than rewriting HEAD '
        'sight-unseen', (WidgetTester tester) async {
      // The menu item and Ctrl/Cmd+Shift+A used to go straight to
      // `submitCommit(amend: true)`, overwriting the published message with
      // whatever the box happened to hold -- without the user ever seeing
      // what they replaced. Entering the mode is what makes it visible.
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'mine');
      await tester.pump();

      await _pressAmendShortcut(tester);
      await tester.pumpAndSettle();

      expect(_commits(pumped), 0);
      expect(
        pumped.controller.commandLog
            .where((FakeCommand c) => c.name == 'requestCommitMeta')
            .length,
        1,
      );
      expect(find.widgetWithText(GbmButton, 'Cancel amend'), findsOneWidget);
    });

    testWidgets('the shortcut submits once already in the mode', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'reworded');
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pumpAndSettle();

      await _pressAmendShortcut(tester);
      await tester.pump();

      final Iterable<FakeCommand> commits = pumped.controller.commandLog.where(
        (FakeCommand c) => c.name == 'commit',
      );
      expect(commits.length, 1);
      expect(commits.single.args['amend'], isTrue);
    });
  });

  // Ruling ④: amending during a merge fails in git itself ("You are in the
  // middle of a merge -- cannot amend"), so the button is not drawn and the
  // menu item and shortcut are disabled. A pending squash has no MERGE_HEAD
  // and amends fine, so it keeps the button.
  group('no amend during a merge', () {
    RepoSessionState merging({bool squash = false}) =>
        _sessionAt('deadbeef').copyWith(
          repoState: RepoState(
            flags: squash ? 0 : RepoStateFlags.merge,
            isClean: false,
            isSequencerOperation: false,
            rebaseStep: 0,
            rebaseTotal: 0,
            rebaseOntoLabel: '',
            indexLocked: false,
            indexLockAgeSeconds: null,
            describe: '',
            preparedMessagePending: true,
          ),
        );

    testWidgets('the button is not drawn while merging', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);

      pumped.controller.emit(merging());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(GbmButton, 'Amend'), findsNothing);
      expect(find.widgetWithText(GbmButton, 'Commit'), findsOneWidget);
    });

    testWidgets('the shortcut does not enter the mode while merging', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      pumped.controller.emit(merging());
      await tester.pumpAndSettle();

      await _pressAmendShortcut(tester);
      await tester.pumpAndSettle();

      expect(
        pumped.controller.commandLog
            .where((FakeCommand c) => c.name == 'requestCommitMeta')
            .length,
        0,
      );
      expect(find.widgetWithText(GbmButton, 'Cancel amend'), findsNothing);
    });

    testWidgets('a pending squash keeps the button', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);

      pumped.controller.emit(merging(squash: true));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(GbmButton, 'Amend'), findsOneWidget);
    });
  });

  // Ruling ⑤⑭ (overrides P3 item 8 for this one case): resolving every
  // conflict by taking ours leaves nothing staged, and `git commit` still
  // concludes the merge. Outside a merge the old rule stands.
  group('Commit with nothing staged', () {
    RepoSessionState nothingStaged({required bool merging}) => RepoSessionState(
      isOpen: true,
      refs: _refsAt('deadbeef'),
      repoState: RepoState(
        flags: merging ? RepoStateFlags.merge : 0,
        isClean: !merging,
        isSequencerOperation: false,
        rebaseStep: 0,
        rebaseTotal: 0,
        rebaseOntoLabel: '',
        indexLocked: false,
        indexLockAgeSeconds: null,
        describe: '',
        preparedMessagePending: merging,
      ),
      workingCopyStatus: const WorkingCopyStatus(entries: <WorkingCopyEntry>[]),
    );

    for (final bool merging in <bool>[true, false]) {
      testWidgets(
        merging
            ? 'is allowed while a merge is in progress'
            : 'is not allowed outside a merge',
        (WidgetTester tester) async {
          final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
          pumped.controller.emit(nothingStaged(merging: merging));
          await tester.pumpAndSettle();
          await tester.enterText(_summaryField, 'conclude');
          await tester.pump();

          final GbmButton commit = tester.widget<GbmButton>(
            find.widgetWithText(GbmButton, 'Commit'),
          );
          expect(commit.onPressed != null, merging);
        },
      );
    }
  });

  // 使用者 2026-10-10 ruled the keyboard and menu clear the box on success
  // like the button. The wait used to live in the view's private field, set
  // only by the button, so Cmd+Enter left a committed message in the box.
  group('every commit path clears the box once HEAD moves', () {
    String draftSummary(PumpedWorkspace p) =>
        p.container.read(workingCopyDraftProvider(_identity)).summary;
    String? pending(PumpedWorkspace p) =>
        p.container.read(workingCopyDraftProvider(_identity)).pendingCommitFrom;

    testWidgets('Cmd/Ctrl+Enter', (WidgetTester tester) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'fix: via keyboard');
      await tester.pump();
      await _pressCommitShortcut(tester);

      pumped.controller.emit(_sessionAt('cafebabe'));
      await tester.pumpAndSettle();

      expect(draftSummary(pumped), isEmpty);
      expect(
        tester.widget<TextField>(_summaryField).controller!.text,
        isEmpty,
        reason: 'the field on screen follows the draft',
      );
    });

    testWidgets('HEAD moving while Working Copy is off screen still counts', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'fix: something');
      await tester.pump();
      await _pressCommitShortcut(tester);
      pumped.router.go(
        RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
      );
      await tester.pumpAndSettle();

      pumped.controller.emit(_sessionAt('cafebabe'));
      await tester.pumpAndSettle();
      pumped.router.go(
        RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
      );
      await tester.pumpAndSettle();

      expect(draftSummary(pumped), isEmpty);
      expect(pending(pumped), isNull);

      // A later, unrelated HEAD move must not clear what is typed next.
      await tester.enterText(_summaryField, 'next thought');
      await tester.pump();
      pumped.controller.emit(_sessionAt('0ddba11'));
      await tester.pumpAndSettle();
      expect(draftSummary(pumped), 'next thought');
    });

    // The draft outlives the workspace shell; a shell that was not there
    // when HEAD moved has to look at HEAD when it comes back.
    testWidgets('HEAD moving while the repository is closed still counts', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _sessionAt('deadbeef'),
        workingCopyBuilder: (BuildContext context, _) =>
            const WorkingCopyView(identity: _identity),
        topLevelRoutes: <RouteBase>[
          GoRoute(
            path: '/elsewhere',
            builder: (BuildContext context, _) => const Scaffold(),
          ),
        ],
      );
      final String wcPath = RoutePaths.workingCopyFor(
        Uri.encodeComponent(_identity.workDir),
      );
      pumped.router.go(wcPath);
      await tester.pumpAndSettle();
      await tester.enterText(_summaryField, 'fix: something');
      await tester.pump();
      await _pressCommitShortcut(tester);
      pumped.router.go('/elsewhere');
      await tester.pumpAndSettle();

      pumped.controller.emit(_sessionAt('cafebabe'));
      await tester.pumpAndSettle();
      pumped.router.go(wcPath);
      await tester.pumpAndSettle();

      expect(draftSummary(pumped), isEmpty);
      expect(pending(pumped), isNull);
      await tester.enterText(_summaryField, 'next thought');
      await tester.pump();
      pumped.controller.emit(_sessionAt('0ddba11'));
      await tester.pumpAndSettle();
      expect(draftSummary(pumped), 'next thought');
    });

    testWidgets('a reopen at the same HEAD stops waiting', (
      WidgetTester tester,
    ) async {
      // The commit failed or its outcome is unknown: keep the user's text and
      // stop waiting, so a later checkout does not wipe it.
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _sessionAt('deadbeef'),
        workingCopyBuilder: (BuildContext context, _) =>
            const WorkingCopyView(identity: _identity),
        topLevelRoutes: <RouteBase>[
          GoRoute(
            path: '/elsewhere',
            builder: (BuildContext context, _) => const Scaffold(),
          ),
        ],
      );
      final String wcPath = RoutePaths.workingCopyFor(
        Uri.encodeComponent(_identity.workDir),
      );
      pumped.router.go(wcPath);
      await tester.pumpAndSettle();
      await tester.enterText(_summaryField, 'fix: something');
      await tester.pump();
      await _pressCommitShortcut(tester);
      pumped.router.go('/elsewhere');
      await tester.pumpAndSettle();
      pumped.router.go(wcPath);
      await tester.pumpAndSettle();

      expect(pending(pumped), isNull);
      pumped.controller.emit(_sessionAt('0ddba11'));
      await tester.pumpAndSettle();
      expect(draftSummary(pumped), 'fix: something');
    });
  });

  group('Ctrl/Cmd+Enter', () {
    testWidgets('commits when the box is already on screen', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'fix: via keyboard');
      await tester.pump();

      await _pressCommitShortcut(tester);

      expect(_commits(pumped), 1);
    });

    testWidgets('amends, not double-commits, while the box is in amend mode', (
      WidgetTester tester,
    ) async {
      // The primary button says `Amend` here. A hardcoded `amend: false` on
      // this path would make the keyboard write a *second* commit carrying
      // HEAD's backfilled message while the button in front of the user said
      // otherwise -- the three-dispatch-path divergence CLAUDE.md's
      // Intent/Action section exists to prevent.
      final PumpedWorkspace pumped = await _pumpAtWorkingCopy(tester);
      await tester.enterText(_summaryField, 'reworded');
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pumpAndSettle();

      await _pressCommitShortcut(tester);

      final Iterable<FakeCommand> commits = pumped.controller.commandLog.where(
        (FakeCommand c) => c.name == 'commit',
      );
      expect(commits.length, 1);
      expect(commits.single.args['amend'], isTrue);
    });

    testWidgets('navigates instead of committing from History', (
      WidgetTester tester,
    ) async {
      // Committing a draft the user cannot see is what the navigate-first
      // behaviour existed to prevent; that reason expires once the box is
      // on screen, and only then.
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _sessionAt('deadbeef'),
        workingCopyBuilder: (BuildContext context, _) =>
            const WorkingCopyView(identity: _identity),
      );
      pumped.container
          .read(workingCopyDraftProvider(_identity).notifier)
          .updateSummary('unseen draft');
      await tester.pumpAndSettle();

      await _pressCommitShortcut(tester);
      await tester.pumpAndSettle();

      expect(_commits(pumped), 0);
      expect(
        pumped.router.state.uri.path,
        RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
      );
    });
  });
}

Future<void> _pressAmendShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await tester.pump();
}

Future<void> _pressCommitShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await tester.pump();
}

CommitMeta _meta() => const CommitMeta(
  oid: 'deadbeef',
  tree: '',
  parents: <String>[],
  author: Signature(name: 'a', email: 'a@b', when: 0, tzOffsetMinutes: 0),
  committer: Signature(name: 'a', email: 'a@b', when: 0, tzOffsetMinutes: 0),
  subject: 'feat: the last commit',
  body: 'its body',
  signedCommit: false,
);
