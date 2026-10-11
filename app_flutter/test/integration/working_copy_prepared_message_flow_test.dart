// prepared-commit-message-spec.html section 04, rulings ①②③⑨⑪: the box
// takes git's prepared merge/squash message when the operation happens, puts
// back what it held when the operation is abandoned with the autofill
// untouched, and does all of that once per operation -- a tab switch is not a
// second merge.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/working_copy/widgets/commit_message_box.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/repo',
  gitDir: '/repo/.git',
);

const RefSnapshot _refs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'deadbeef',
  ),
  refs: <RefInfo>[],
  refCountGuardTripped: false,
  totalRefCount: 0,
);

RepoState _repoState({required bool pending}) => RepoState(
  flags: pending ? RepoStateFlags.merge : 0,
  isClean: !pending,
  isSequencerOperation: false,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
  preparedMessagePending: pending,
);

RepoSessionState _session({bool pending = false}) => RepoSessionState(
  isOpen: true,
  refs: _refs,
  repoState: _repoState(pending: pending),
  workingCopyStatus: const WorkingCopyStatus(entries: <WorkingCopyEntry>[]),
);

final Finder _fields = find.descendant(
  of: find.byType(CommitMessageBox),
  matching: find.byType(TextField),
);

String _summary(WidgetTester tester) =>
    tester.widget<TextField>(_fields.at(0)).controller!.text;
String _description(WidgetTester tester) =>
    tester.widget<TextField>(_fields.at(1)).controller!.text;

int _requests(PumpedWorkspace pumped) => pumped.controller.commandLog
    .where((FakeCommand c) => c.name == 'requestPreparedMessage')
    .length;

const String _mergeMessage = "Merge branch 'topic'\n\nConflicts resolved.\n";

Future<PumpedWorkspace> _pump(
  WidgetTester tester, {
  bool pending = false,
  Map<String, Object> initialPrefs = const <String, Object>{},
}) async {
  final PumpedWorkspace pumped = await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: _session(pending: pending),
    initialPrefs: initialPrefs,
    workingCopyBuilder: (BuildContext context, _) =>
        const WorkingCopyView(identity: _identity),
  );
  pumped.router.go(
    RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
  );
  await tester.pumpAndSettle();
  return pumped;
}

Future<void> _type(WidgetTester tester, String summary, String body) async {
  await tester.enterText(_fields.at(0), summary);
  await tester.enterText(_fields.at(1), body);
  await tester.pump();
}

Future<void> _setPending(
  WidgetTester tester,
  PumpedWorkspace pumped,
  bool pending,
) async {
  pumped.controller.emit(
    pumped.controller.state.copyWith(repoState: _repoState(pending: pending)),
  );
  await tester.pumpAndSettle();
}

Future<void> _reply(
  WidgetTester tester,
  PumpedWorkspace pumped, {
  String message = _mergeMessage,
  bool failed = false,
}) async {
  pumped.controller.emit(
    pumped.controller.state.copyWith(
      preparedMessage: PreparedMessageReply(message: message, failed: failed),
    ),
  );
  await tester.pumpAndSettle();
}

/// Refs re-read, as `publishRefs` publishes them: [head] (default: where
/// they were) and one more `refsEpoch`.
Future<void> _refsArrive(
  WidgetTester tester,
  PumpedWorkspace pumped, {
  String? head,
}) async {
  final RepoSessionState s = pumped.controller.state;
  pumped.controller.emit(
    s.copyWith(
      refsEpoch: s.refsEpoch + 1,
      refs: head == null
          ? null
          : RefSnapshot(
              head: HeadInfo(
                kind: HeadKind.branch,
                branchName: 'main',
                fullRef: 'refs/heads/main',
                target: head,
              ),
              refs: const <RefInfo>[],
              refCountGuardTripped: false,
              totalRefCount: 0,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A commit-meta reply: [oid] with [parents], or an empty reply when [oid]
/// is null. Either way one more `commitMetaReplySeq`.
Future<void> _metaReply(
  WidgetTester tester,
  PumpedWorkspace pumped, {
  String? oid,
  List<String> parents = const <String>[],
}) async {
  final RepoSessionState s = pumped.controller.state;
  pumped.controller.emit(
    s.copyWith(
      commitMetaReplySeq: s.commitMetaReplySeq + 1,
      commitMetaCache: oid == null
          ? null
          : <String, CommitMeta>{
              ...s.commitMetaCache,
              oid: CommitMeta(
                oid: oid,
                tree: '',
                parents: parents,
                author: const Signature(
                  name: 'a',
                  email: 'a@b',
                  when: 0,
                  tzOffsetMinutes: 0,
                ),
                committer: const Signature(
                  name: 'a',
                  email: 'a@b',
                  when: 0,
                  tzOffsetMinutes: 0,
                ),
                subject: 's',
                body: '',
                signedCommit: false,
              ),
            },
    ),
  );
  await tester.pumpAndSettle();
}

int _commands(PumpedWorkspace pumped, String name) => pumped
    .controller
    .commandLog
    .where((FakeCommand c) => c.name == name)
    .length;

void main() {
  testWidgets('a merge starting asks once and overwrites typed text (①②⑪)', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _type(tester, 'mine', 'my body');

    await _setPending(tester, pumped, true);
    expect(_requests(pumped), 1);
    await _reply(tester, pumped);

    expect(_summary(tester), "Merge branch 'topic'");
    expect(_description(tester), 'Conflicts resolved.');
    expect(_requests(pumped), 1);
  });

  // [FLU-listen-misses-the-current-value]: the app can start with a merge
  // already pending, and nothing changes after mount to fire a listener.
  testWidgets('a merge already pending at mount is picked up', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester, pending: true);
    expect(_requests(pumped), 1);

    await _reply(tester, pumped);

    expect(_summary(tester), "Merge branch 'topic'");
  });

  testWidgets('leaving the tab and coming back does not fill again', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _setPending(tester, pumped, true);
    await _reply(tester, pumped);
    await _type(tester, 'edited', 'during the merge');

    pumped.router.go(
      RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
    );
    await tester.pumpAndSettle();
    pumped.router.go(
      RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
    );
    await tester.pumpAndSettle();

    expect(_summary(tester), 'edited');
    expect(_requests(pumped), 1);
  });

  testWidgets('an abort with the autofill untouched puts back the text (③⑨)', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _type(tester, 'mine', 'my body');
    await _setPending(tester, pumped, true);
    await _reply(tester, pumped);

    await _setPending(tester, pumped, false);
    // Slice D R2: HEAD is re-read before an Abort is told from a commit.
    expect(_commands(pumped, 'refreshHistory'), 1);
    expect(_summary(tester), "Merge branch 'topic'");
    await _refsArrive(tester, pumped);

    expect(_summary(tester), 'mine');
    expect(_description(tester), 'my body');
    final SharedPreferences prefs = pumped.container.read(
      sharedPreferencesProvider,
    );
    await tester.pumpAndSettle();
    expect(
      prefs.getStringList('workingCopyPreparedEpisode:${_identity.workDir}'),
      isNull,
    );
  });

  // Slice D R2 (使用者 2026-10-11 「分辨 commit，其他照 Abort」).
  group('the merge ending without an in-app commit', () {
    Future<PumpedWorkspace> filledThenEnded(WidgetTester tester) async {
      final PumpedWorkspace pumped = await _pump(tester);
      await _type(tester, 'mine', 'my body');
      await _setPending(tester, pumped, true);
      await _reply(tester, pumped);
      await _setPending(tester, pumped, false);
      return pumped;
    }

    testWidgets('an error while re-reading refs is an Abort', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await filledThenEnded(tester);
      pumped.controller.emit(
        pumped.controller.state.copyWith(
          lastError: const GitError(
            code: 1,
            codeName: 'ProcessFailed',
            message: 'refs failed',
            detail: '',
            argv: <String>['git', 'for-each-ref'],
            exitCode: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_summary(tester), 'mine');
    });

    testWidgets('committed outside the app: the box clears', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await filledThenEnded(tester);
      await _refsArrive(tester, pumped, head: 'cafebabe');
      expect(_commands(pumped, 'requestCommitMeta'), 1);
      await _metaReply(
        tester,
        pumped,
        oid: 'cafebabe',
        parents: <String>['deadbeef', 'f00d'],
      );
      expect(_summary(tester), isEmpty);
      expect(_description(tester), isEmpty);
    });

    testWidgets('a reset elsewhere puts back the untouched autofill', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await filledThenEnded(tester);
      await _refsArrive(tester, pumped, head: '0ddba11');
      await _metaReply(
        tester,
        pumped,
        oid: '0ddba11',
        parents: <String>['beefcafe'],
      );
      expect(_summary(tester), 'mine');
    });

    testWidgets('a reset elsewhere keeps an edited message', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await _pump(tester);
      await _type(tester, 'mine', 'my body');
      await _setPending(tester, pumped, true);
      await _reply(tester, pumped);
      await _type(tester, "Merge branch 'topic'", 'my own words');
      await _setPending(tester, pumped, false);
      await _refsArrive(tester, pumped, head: '0ddba11');
      await _metaReply(
        tester,
        pumped,
        oid: '0ddba11',
        parents: <String>['beefcafe'],
      );
      expect(_description(tester), 'my own words');
    });

    testWidgets('no answer about the new HEAD is an Abort', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await filledThenEnded(tester);
      await _refsArrive(tester, pumped, head: 'cafebabe');
      await _metaReply(tester, pumped);
      expect(_summary(tester), 'mine');
    });

    testWidgets('a remount asks about the new HEAD again', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await filledThenEnded(tester);
      await _refsArrive(tester, pumped, head: 'cafebabe');
      expect(_commands(pumped, 'requestCommitMeta'), 1);

      pumped.router.go(
        RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
      );
      await tester.pumpAndSettle();
      pumped.router.go(
        RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
      );
      await tester.pumpAndSettle();

      expect(_commands(pumped, 'requestCommitMeta'), 2);
      await _metaReply(
        tester,
        pumped,
        oid: 'cafebabe',
        parents: <String>['deadbeef'],
      );
      expect(_summary(tester), isEmpty);
    });
  });

  testWidgets('an abort after the user edited keeps the edit', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _type(tester, 'mine', 'my body');
    await _setPending(tester, pumped, true);
    await _reply(tester, pumped);
    await _type(tester, "Merge branch 'topic'", 'my own words');

    await _setPending(tester, pumped, false);

    expect(_description(tester), 'my own words');
  });

  testWidgets('with the switch off, typed text is kept (⑪)', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(
      tester,
      initialPrefs: <String, Object>{
        'appPrefs.overwriteWithPreparedMessage': false,
      },
    );
    await _type(tester, 'mine', 'my body');
    await _setPending(tester, pumped, true);

    await _reply(tester, pumped);

    expect(_summary(tester), 'mine');
  });

  testWidgets('a failed read leaves the box alone and does not retry', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _type(tester, 'mine', 'my body');
    await _setPending(tester, pumped, true);

    await _reply(tester, pumped, message: '', failed: true);

    expect(_summary(tester), 'mine');
    expect(_requests(pumped), 1);
  });

  // git can have nothing prepared by the time the read runs (the merge was
  // concluded from a terminal). An empty reply is not a message: replacing
  // with it would wipe the box.
  testWidgets('an empty reply leaves the box alone', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _type(tester, 'mine', 'my body');
    await _setPending(tester, pumped, true);

    await _reply(tester, pumped, message: '\n');

    expect(_summary(tester), 'mine');
    expect(_description(tester), 'my body');
  });

  // 使用者 2026-10-10:「先進 amend 模式再開始 merge ... 以merge為優先，也就是以
  // git狀態為主」, and 「對cancel了話做message恢復」.
  group('a merge starting in amend mode', () {
    Future<PumpedWorkspace> inAmend(
      WidgetTester tester, {
      Map<String, Object> initialPrefs = const <String, Object>{},
    }) async {
      final PumpedWorkspace pumped = await _pump(
        tester,
        initialPrefs: initialPrefs,
      );
      await _type(tester, 'mine', 'my body');
      await tester.tap(find.widgetWithText(GbmButton, 'Amend'));
      await tester.pumpAndSettle();
      pumped.controller.emit(
        pumped.controller.state.copyWith(
          commitMetaCache: const <String, CommitMeta>{
            'deadbeef': CommitMeta(
              oid: 'deadbeef',
              tree: '',
              parents: <String>[],
              author: Signature(
                name: 'a',
                email: 'a@b',
                when: 0,
                tzOffsetMinutes: 0,
              ),
              committer: Signature(
                name: 'a',
                email: 'a@b',
                when: 0,
                tzOffsetMinutes: 0,
              ),
              subject: 'HEAD subject',
              body: 'HEAD body',
              signedCommit: false,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(_summary(tester), 'HEAD subject');
      return pumped;
    }

    testWidgets('leaves amend and takes git\'s message', (tester) async {
      final PumpedWorkspace pumped = await inAmend(tester);

      await _setPending(tester, pumped, true);
      expect(find.widgetWithText(GbmButton, 'Cancel amend'), findsNothing);
      expect(_requests(pumped), 1);
      await _reply(tester, pumped);

      expect(_summary(tester), "Merge branch 'topic'");
    });

    // The box on screen must be what the draft holds, or Commit sends text
    // the user cannot see.
    testWidgets('with the switch off, the box shows the pre-amend text', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await inAmend(
        tester,
        initialPrefs: <String, Object>{
          'appPrefs.overwriteWithPreparedMessage': false,
        },
      );

      await _setPending(tester, pumped, true);
      await _reply(tester, pumped);

      expect(_summary(tester), 'mine');
      expect(_description(tester), 'my body');
    });

    testWidgets('a failed read leaves the pre-amend text on screen', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await inAmend(tester);

      await _setPending(tester, pumped, true);
      await _reply(tester, pumped, message: '', failed: true);

      expect(_summary(tester), 'mine');
      expect(_description(tester), 'my body');
    });
  });

  /// The commit's own outcome, published before RepoState is re-read (the
  /// order `workingCopyOperationFinished` handles it in).
  Future<void> commitOutcome(
    WidgetTester tester,
    PumpedWorkspace pumped, {
    required bool succeeded,
  }) async {
    final RepoSessionState s = pumped.controller.state;
    pumped.controller.emit(
      s.copyWith(
        commitOutcomeSeq: s.commitOutcomeSeq + 1,
        lastCommitSucceeded: succeeded,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressCommitShortcut(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
  }

  // 使用者 2026-10-10: committing the unedited prepared message through the
  // keyboard used to put the pre-merge text back, because the merge ending
  // (pending -> false) looked exactly like an Abort.
  testWidgets('Cmd/Ctrl+Enter on the prepared message ends with an empty box', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _type(tester, 'mine', 'my body');
    await _setPending(tester, pumped, true);
    await _reply(tester, pumped);

    await pressCommitShortcut(tester);
    await commitOutcome(tester, pumped, succeeded: true);
    await _setPending(tester, pumped, false);

    expect(_summary(tester), isEmpty);
    expect(_description(tester), isEmpty);
  });

  // A1: an unrelated error mid-commit used to cancel the wait, and the merge
  // ending then put the pre-merge text back over a merge that had landed.
  testWidgets('an unrelated error mid-commit does not bring the pre-merge '
      'text back', (WidgetTester tester) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _type(tester, 'mine', 'my body');
    await _setPending(tester, pumped, true);
    await _reply(tester, pumped);

    await pressCommitShortcut(tester);
    pumped.controller.emit(
      pumped.controller.state.copyWith(
        lastError: const GitError(
          code: 1,
          codeName: 'ProcessFailed',
          message: 'fetch failed',
          detail: '',
          argv: <String>['git', 'fetch'],
          exitCode: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await commitOutcome(tester, pumped, succeeded: true);
    await _setPending(tester, pumped, false);

    expect(_summary(tester), isEmpty);
    expect(_description(tester), isEmpty);
  });
}
