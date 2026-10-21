// Regression test for the operation-outcome attribution bug a full-project
// code review found: RepoSessionController used to pair a checkout()/
// deleteBranch() call with whichever GBM_EVENT_OPERATION_FINISHED event
// arrived next, using two plain booleans. Since OperationRunner's queue can
// hold more than one operation (roughly thirty controller methods share the
// same event channel), an unrelated operation submitted in between stole
// the outcome, silently dropping the real one's recovery choices.
//
// This exercises the real reducer (RepoSessionController._handleOperationOutcome,
// via the @visibleForTesting debugHandleOperationOutcome/debugRecordCheckout/
// debugRecordDeleteBranch hooks) rather than the surface it renders.
//
// Attribution-only tests (no retry) use FakeRepoSessionController
// (test/support/fake_repo_session.dart) directly -- it does not override
// debugRecordCheckout/debugHandleOperationOutcome, so those reach the real
// implementation.
//
// The retry tests below use a bespoke _RecordingRepoSessionController
// instead: FakeRepoSessionController overrides retryCheckoutWithChoice /
// retryDeleteBranchWithChoice / dismissCheckoutChoices /
// dismissDeleteBranchChoices themselves (they just log to commandLog), which
// would make a retry test pass or fail without ever touching the real
// retry logic under test. _RecordingRepoSessionController overrides only
// checkout()/deleteBranch() (to avoid a real FFI call), leaving
// retryCheckoutWithChoice and friends as the genuine implementation.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/branch_deletion_probe.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/operation_choice.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

Map<String, dynamic> _failedOutcome({required String kind}) =>
    <String, dynamic>{
      'succeeded': false,
      'kind': kind,
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': OperationChoiceKind.stashAndRetry.index,
          'destructive': false,
        },
      ],
    };

/// A delete core refused with a "Delete anyway" choice: a `-d` that was
/// not fully merged, or (with [codeName]) a `-D` whose branch moved.
Map<String, dynamic> _forceableRefusal({String? codeName}) => <String, dynamic>{
  'succeeded': false,
  'kind': 'delete-branch',
  'summary': 'refused',
  'error': codeName == null
      ? null
      : <String, dynamic>{
          'code': 21,
          'codeName': codeName,
          'message': 'refused',
          'detail': '',
          'argv': <String>[],
          'exitCode': 0,
        },
  'choices': <Map<String, dynamic>>[
    <String, dynamic>{
      'kind': OperationChoiceKind.forceDiscard.index,
      'destructive': true,
    },
  ],
};

Map<String, dynamic> _succeededOutcome({required String kind}) =>
    <String, dynamic>{'succeeded': true, 'kind': kind};

/// A recorded checkout()/deleteBranch() call, for the retry tests below.
class _RecordedCall {
  const _RecordedCall(this.name, this.args);
  final String name;
  final Map<String, Object?> args;
}

/// See the file-level doc comment for why this exists instead of
/// [FakeRepoSessionController]: it leaves retryCheckoutWithChoice /
/// dismissCheckoutChoices / retryDeleteBranchWithChoice /
/// dismissDeleteBranchChoices as the real implementation, overriding only
/// checkout()/deleteBranch() themselves so a retry doesn't reach real FFI.
class _RecordingRepoSessionController extends RepoSessionController {
  _RecordingRepoSessionController(
    RepoIdentity identity,
    RepoSessionState initialState,
  ) : super(FakeGbmBindings(), identity, FakeRecentsRepository()) {
    state = initialState;
  }

  final List<_RecordedCall> calls = <_RecordedCall>[];

  @override
  void checkout({
    required String target,
    bool detach = false,
    bool createBranch = false,
    String newBranchName = '',
    bool force = false,
    bool stashFirst = false,
    bool recurseSubmodules = false,
  }) {
    calls.add(
      _RecordedCall('checkout', <String, Object?>{
        'target': target,
        'force': force,
        'stashFirst': stashFirst,
      }),
    );
  }

  @override
  void deleteBranch({
    required List<DeleteBranchEntry> entries,
    bool isRemote = false,
    String remoteName = '',
    List<RemoteBranchDeletion> thenDeleteRemote =
        const <RemoteBranchDeletion>[],
  }) {
    calls.add(
      _RecordedCall('deleteBranch', <String, Object?>{
        'entries': entries,
        'isRemote': isRemote,
        'remoteName': remoteName,
        'thenDeleteRemote': thenDeleteRemote,
        'names': <String>[for (final DeleteBranchEntry e in entries) e.name],
        'force': entries.any((DeleteBranchEntry e) => e.force),
      }),
    );
  }

  /// The probe "Delete anyway" reads tips from. Recorded in [calls] too, so
  /// a test can count how many reads a retry made.
  BranchDeletionProbeReply Function(List<String> names) probe =
      (List<String> names) => BranchDeletionProbeReply(
        probes: <BranchDeletionProbe>[
          for (final String name in names)
            ProbeCounted(
              name,
              tipOid: 'probed-$name',
              upstream: 'refs/remotes/origin/$name',
              unsyncedCount: 2,
            ),
        ],
      );

  @override
  Future<BranchDeletionProbeReply> probeBranchDeletion(List<String> names) {
    calls.add(
      _RecordedCall('probeBranchDeletion', <String, Object?>{'names': names}),
    );
    return Future<BranchDeletionProbeReply>.value(probe(names));
  }
}

void main() {
  group('RepoSessionController._handleOperationOutcome (attribution)', () {
    test('an outcome with no matching pending kind leaves checkoutChoices untouched', () {
      final fake = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      fake.debugRecordCheckout(target: 'feature');

      // Neither an unstamped outcome (kind: '') nor one for a different
      // kind may be treated as this checkout's answer.
      fake.debugHandleOperationOutcome(_failedOutcome(kind: ''));
      expect(fake.state.checkoutChoices, isEmpty);

      fake.debugHandleOperationOutcome(_failedOutcome(kind: 'delete-branch'));
      expect(fake.state.checkoutChoices, isEmpty);
    });

    test('a "checkout"-kind outcome populates checkoutChoices', () {
      final fake = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      fake.debugRecordCheckout(target: 'feature');

      fake.debugHandleOperationOutcome(_failedOutcome(kind: 'checkout'));

      expect(fake.state.checkoutChoices, hasLength(1));
      expect(
        fake.state.checkoutChoices.single.kind,
        OperationChoiceKind.stashAndRetry,
      );
    });

    test('a "delete-branch"-kind outcome populates deleteBranchChoices', () {
      final fake = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      fake.debugRecordDeleteBranch(names: const <String>['gone']);

      fake.debugHandleOperationOutcome(_failedOutcome(kind: 'delete-branch'));

      expect(fake.state.deleteBranchChoices, hasLength(1));
      expect(
        fake.state.deleteBranchChoices.single.kind,
        OperationChoiceKind.stashAndRetry,
      );
    });

    test('checkout and deleteBranch outcomes interleave without cross-contamination', () {
      final fake = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      fake.debugRecordCheckout(target: 'feature');
      fake.debugRecordDeleteBranch(names: const <String>['gone']);

      // deleteBranch's outcome arrives first even though checkout was
      // requested first -- exactly the interleaving that broke the old
      // two-boolean design.
      fake.debugHandleOperationOutcome(_failedOutcome(kind: 'delete-branch'));
      expect(fake.state.deleteBranchChoices, hasLength(1));
      expect(fake.state.checkoutChoices, isEmpty);

      fake.debugHandleOperationOutcome(_failedOutcome(kind: 'checkout'));
      expect(fake.state.checkoutChoices, hasLength(1));
      // deleteBranchChoices must still hold its own outcome, untouched by
      // the later checkout outcome.
      expect(fake.state.deleteBranchChoices, hasLength(1));
    });

    // Pins the coupling `dialog_copy_test.dart`'s "lock/sequencer refusal"
    // widget test assumes without being able to see it: that test seeds
    // checkoutChoices and lastError by hand, so it cannot tell whether the
    // real reducer ever actually publishes both for one preflight-shaped
    // failure. This drives the real _handleOperationOutcome (via
    // debugRecordCheckout/debugHandleOperationOutcome) with a payload shaped
    // exactly like OperationRunner::preflight()'s index.lock refusal --
    // retry + removeLock choices, no stashAndRetry/forceDiscard, plus a
    // full `error` map (OperationRunner.cpp:69-72 sets outcome.error to a
    // real GitError on this path -- this was wrongly written here as "no
    // formal GitError, falls back to summary" and corrected in place per
    // CLAUDE.md's standing rule 4: a `summary`-only payload would have
    // exercised _errorFromOutcomePayload's *fallback* branch instead of the
    // one preflight's index.lock refusal actually takes) -- and checks both
    // fields land. If a future change ever set one without the other, every
    // dialog-level widget test would stay green regardless, because none of
    // them drives this reducer.
    test('a preflight-shaped ("retry"/"removeLock" choices, GitError.LockHeld) '
        'outcome populates checkoutChoices and lastError together', () {
      final fake = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      fake.debugRecordCheckout(target: 'feature');

      fake.debugHandleOperationOutcome(<String, dynamic>{
        'succeeded': false,
        'kind': 'checkout',
        'summary':
            'Another Git process appears to be running in this '
            'repository',
        'error': <String, dynamic>{
          'code': 4, // GitError::Code::LockHeld's ordinal
          'codeName': 'LockHeld',
          'message':
              'Another Git process appears to be running in this '
              'repository',
          'detail': 'Lock file: .git/index.lock',
          'argv': <String>[],
          'exitCode': -1,
        },
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': OperationChoiceKind.retry.index,
            'destructive': false,
          },
          <String, dynamic>{
            'kind': OperationChoiceKind.removeLock.index,
            'destructive': true,
          },
        ],
      });

      expect(fake.state.checkoutChoices, hasLength(2));
      expect(
        fake.state.checkoutChoices.map((c) => c.kind),
        containsAll(<OperationChoiceKind>[
          OperationChoiceKind.retry,
          OperationChoiceKind.removeLock,
        ]),
      );
      expect(
        fake.state.lastError?.message,
        'Another Git process appears to be running in this repository',
      );
    });
  });

  group('RepoSessionController retry (real retryCheckoutWithChoice/retryDeleteBranchWithChoice)', () {
    test(
      'retryCheckoutWithChoice resubmits the request that actually failed',
      () {
        final controller = _RecordingRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        controller.debugRecordCheckout(target: 'retry-target');
        controller.debugHandleOperationOutcome(
          _failedOutcome(kind: 'checkout'),
        );
        expect(controller.state.checkoutChoices, isNotEmpty);

        controller.retryCheckoutWithChoice(OperationChoiceKind.stashAndRetry);

        expect(controller.state.checkoutChoices, isEmpty);
        expect(controller.calls, hasLength(1));
        expect(controller.calls.single.name, 'checkout');
        expect(controller.calls.single.args['target'], 'retry-target');
        expect(controller.calls.single.args['stashFirst'], true);
      },
    );

    // A6 C3: "Delete anyway" sends `-D`, and a `-D` needs the tip the
    // user's commits were counted at -- the refused `-d` never carried one.
    test(
      'retryDeleteBranchWithChoice forces the failed request at probed tips',
      () async {
        final controller = _RecordingRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        controller.debugRecordDeleteBranch(names: const <String>['gone']);
        controller.debugHandleOperationOutcome(
          _failedOutcome(kind: 'delete-branch'),
        );
        expect(controller.state.deleteBranchChoices, isNotEmpty);

        controller.retryDeleteBranchWithChoice(
          OperationChoiceKind.forceDiscard,
        );
        await pumpEventQueue();

        expect(controller.state.deleteBranchChoices, isEmpty);
        final List<_RecordedCall> deletes = controller.calls
            .where((_RecordedCall c) => c.name == 'deleteBranch')
            .toList();
        expect(deletes, hasLength(1));
        expect(deletes.single.args['entries'], const <DeleteBranchEntry>[
          DeleteBranchEntry.forced('gone', expectedTipOid: 'probed-gone'),
        ]);
      },
    );

    // The partial-delete case: `-d merged unmerged` removed `merged` and
    // refused `unmerged`. The retry must not ask core to force a branch that
    // no longer exists, nor send it without a tip.
    test(
      'a forced retry drops the names the first pass already deleted',
      () async {
        final controller = _RecordingRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        controller.probe = (List<String> names) =>
            const BranchDeletionProbeReply(
              probes: <BranchDeletionProbe>[
                ProbeNotFound('merged'),
                ProbeNoReference('unmerged', tipOid: 'tip-of-unmerged'),
              ],
            );
        controller.debugRecordDeleteBranch(
          names: const <String>['merged', 'unmerged'],
        );
        controller.debugHandleOperationOutcome(
          _failedOutcome(kind: 'delete-branch'),
        );

        controller.retryDeleteBranchWithChoice(
          OperationChoiceKind.forceDiscard,
        );
        await pumpEventQueue();

        final List<_RecordedCall> deletes = controller.calls
            .where((_RecordedCall c) => c.name == 'deleteBranch')
            .toList();
        expect(deletes, hasLength(1));
        expect(deletes.single.args['entries'], const <DeleteBranchEntry>[
          DeleteBranchEntry.forced(
            'unmerged',
            expectedTipOid: 'tip-of-unmerged',
          ),
        ]);
      },
    );

    test('a forced retry whose probe failed deletes nothing', () async {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.probe = (List<String> names) => const BranchDeletionProbeReply(
        probes: <BranchDeletionProbe>[],
        error: GitError(
          code: 13,
          codeName: 'ProcessFailed',
          message: 'could not read refs',
          detail: '',
          argv: <String>[],
          exitCode: 128,
        ),
      );
      controller.debugRecordDeleteBranch(names: const <String>['gone']);
      controller.debugHandleOperationOutcome(
        _failedOutcome(kind: 'delete-branch'),
      );

      controller.retryDeleteBranchWithChoice(OperationChoiceKind.forceDiscard);
      await pumpEventQueue();

      expect(
        controller.calls.where((_RecordedCall c) => c.name == 'deleteBranch'),
        isEmpty,
      );
      expect(controller.state.lastError?.message, 'could not read refs');
    });

    test(
      'dismissCheckoutChoices drops the retained request without resubmitting',
      () {
        final controller = _RecordingRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        controller.debugRecordCheckout(target: 'retry-target');
        controller.debugHandleOperationOutcome(
          _failedOutcome(kind: 'checkout'),
        );

        controller.dismissCheckoutChoices();
        expect(controller.state.checkoutChoices, isEmpty);

        // A stray retry after dismiss must not resubmit a stale request.
        controller.retryCheckoutWithChoice(OperationChoiceKind.stashAndRetry);
        expect(controller.calls, isEmpty);
      },
    );

    test("retryCheckoutWithChoice's retry case resubmits the request "
        'unmodified -- no stashFirst/force flag', () {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.debugRecordCheckout(target: 'retry-target');
      controller.debugHandleOperationOutcome(_failedOutcome(kind: 'checkout'));

      controller.retryCheckoutWithChoice(OperationChoiceKind.retry);

      expect(controller.state.checkoutChoices, isEmpty);
      expect(controller.calls, hasLength(1));
      expect(controller.calls.single.name, 'checkout');
      expect(controller.calls.single.args['target'], 'retry-target');
      expect(controller.calls.single.args['force'], false);
      expect(controller.calls.single.args['stashFirst'], false);
    });

    test("retryCheckoutWithChoice's removeLock case attempts lock removal "
        '(a no-op here -- FakeGbmBindings never opens a real session, so '
        "_removeStaleIndexLock()'s own null-session guard short-circuits "
        "before reaching the binding) then resubmits unmodified, exactly "
        'like the retry case above', () {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.debugRecordCheckout(target: 'retry-target');
      controller.debugHandleOperationOutcome(_failedOutcome(kind: 'checkout'));

      controller.retryCheckoutWithChoice(OperationChoiceKind.removeLock);

      expect(controller.state.checkoutChoices, isEmpty);
      expect(controller.calls, hasLength(1));
      expect(controller.calls.single.name, 'checkout');
      expect(controller.calls.single.args['target'], 'retry-target');
      expect(controller.calls.single.args['force'], false);
      expect(controller.calls.single.args['stashFirst'], false);
    });

    test("retryDeleteBranchWithChoice's retry case resubmits the request "
        'unmodified -- no force flag', () {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.debugRecordDeleteBranch(names: const <String>['gone']);
      controller.debugHandleOperationOutcome(
        _failedOutcome(kind: 'delete-branch'),
      );

      controller.retryDeleteBranchWithChoice(OperationChoiceKind.retry);

      expect(controller.state.deleteBranchChoices, isEmpty);
      // The refusal's own tip read is a call too; only deletes count here.
      final List<_RecordedCall> deletes = controller.calls
          .where((_RecordedCall c) => c.name == 'deleteBranch')
          .toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.args['names'], <String>['gone']);
      expect(deletes.single.args['force'], false);
    });

    test("retryDeleteBranchWithChoice's removeLock case attempts lock "
        'removal then resubmits unmodified, exactly like the retry case '
        'above', () {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.debugRecordDeleteBranch(names: const <String>['gone']);
      controller.debugHandleOperationOutcome(
        _failedOutcome(kind: 'delete-branch'),
      );

      controller.retryDeleteBranchWithChoice(OperationChoiceKind.removeLock);

      expect(controller.state.deleteBranchChoices, isEmpty);
      // The refusal's own tip read is a call too; only deletes count here.
      final List<_RecordedCall> deletes = controller.calls
          .where((_RecordedCall c) => c.name == 'deleteBranch')
          .toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.args['names'], <String>['gone']);
      expect(deletes.single.args['force'], false);
    });

    // A6 C4: the remote half is sent by the controller, after the local
    // delete succeeds -- never alongside it, where a refused local delete
    // would still lose the remote branch.
    test('a local delete that succeeds then sends its remote half', () {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.debugRecordDeleteBranch(
        names: const <String>['x'],
        thenDeleteRemote: const <RemoteBranchDeletion>[
          RemoteBranchDeletion(remoteName: 'origin', names: <String>['x']),
        ],
      );
      controller.debugHandleOperationOutcome(
        _succeededOutcome(kind: 'delete-branch'),
      );

      final List<_RecordedCall> deletes = controller.calls
          .where((_RecordedCall c) => c.name == 'deleteBranch')
          .toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.args['isRemote'], isTrue);
      expect(deletes.single.args['remoteName'], 'origin');
      expect(deletes.single.args['names'], <String>['x']);
    });

    test(
      'a refused local delete holds its remote half until a retry',
      () async {
        final controller = _RecordingRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        const List<RemoteBranchDeletion> remote = <RemoteBranchDeletion>[
          RemoteBranchDeletion(remoteName: 'origin', names: <String>['x']),
        ];
        controller.debugRecordDeleteBranch(
          names: const <String>['x'],
          thenDeleteRemote: remote,
        );
        controller.debugHandleOperationOutcome(_forceableRefusal());

        expect(controller.state.deleteBranchChoices, isNotEmpty);
        expect(
          controller.calls.where((_RecordedCall c) => c.name == 'deleteBranch'),
          isEmpty,
          reason: 'nothing is sent while the local delete is refused',
        );

        controller.retryDeleteBranchWithChoice(
          OperationChoiceKind.forceDiscard,
        );
        await pumpEventQueue();

        final List<_RecordedCall> deletes = controller.calls
            .where((_RecordedCall c) => c.name == 'deleteBranch')
            .toList();
        expect(deletes, hasLength(1));
        expect(deletes.single.args['isRemote'], isFalse);
        expect(deletes.single.args['thenDeleteRemote'], remote);
      },
    );

    // The local side is done when every name is already gone -- a first pass
    // that deleted some and was refused on the rest, then the rest removed
    // elsewhere. What the user confirmed for the remote still goes out.
    test(
      '"Delete anyway" with every branch already gone still sends the remote',
      () async {
        final controller = _RecordingRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        controller.probe = (List<String> names) =>
            const BranchDeletionProbeReply(
              probes: <BranchDeletionProbe>[ProbeNotFound('x')],
            );
        const List<RemoteBranchDeletion> remote = <RemoteBranchDeletion>[
          RemoteBranchDeletion(remoteName: 'origin', names: <String>['x']),
        ];
        controller.debugRecordDeleteBranch(
          names: const <String>['x'],
          thenDeleteRemote: remote,
        );
        controller.debugHandleOperationOutcome(_forceableRefusal());
        await pumpEventQueue();

        controller.retryDeleteBranchWithChoice(
          OperationChoiceKind.forceDiscard,
        );
        await pumpEventQueue();

        final List<_RecordedCall> deletes = controller.calls
            .where((_RecordedCall c) => c.name == 'deleteBranch')
            .toList();
        expect(deletes, hasLength(1));
        expect(deletes.single.args['isRemote'], isTrue);
        expect(deletes.single.args['remoteName'], 'origin');
        expect(deletes.single.args['names'], <String>['x']);
      },
    );

    test('a StaleBranchTip refusal opens the choices and deletes nothing', () {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.debugRecordDeleteBranch(names: const <String>['x']);
      controller.debugHandleOperationOutcome(
        _forceableRefusal(codeName: 'StaleBranchTip'),
      );

      expect(controller.state.deleteBranchChoices, isNotEmpty);
      expect(
        controller.calls.where((_RecordedCall c) => c.name == 'deleteBranch'),
        isEmpty,
      );
    });

    // The count the recovery dialog shows and the tip "Delete anyway" sends
    // come from one read, taken when the refusal arrived. A branch moved
    // after it is refused by core, not deleted past a stale number.
    test(
      '"Delete anyway" sends the tip read when the refusal arrived',
      () async {
        final controller = _RecordingRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        controller.probe = (List<String> names) =>
            const BranchDeletionProbeReply(
              probes: <BranchDeletionProbe>[
                ProbeCounted(
                  'x',
                  tipOid: 'tip-A',
                  upstream: 'refs/remotes/origin/x',
                  unsyncedCount: 1,
                ),
              ],
            );
        controller.debugRecordDeleteBranch(names: const <String>['x']);
        controller.debugHandleOperationOutcome(_forceableRefusal());
        await pumpEventQueue();

        // The branch moves on; a second read would now say tip-B.
        controller.probe = (List<String> names) =>
            const BranchDeletionProbeReply(
              probes: <BranchDeletionProbe>[
                ProbeCounted(
                  'x',
                  tipOid: 'tip-B',
                  upstream: 'refs/remotes/origin/x',
                  unsyncedCount: 2,
                ),
              ],
            );
        controller.retryDeleteBranchWithChoice(
          OperationChoiceKind.forceDiscard,
        );
        await pumpEventQueue();

        final List<_RecordedCall> deletes = controller.calls
            .where((_RecordedCall c) => c.name == 'deleteBranch')
            .toList();
        expect(deletes, hasLength(1));
        expect(deletes.single.args['entries'], const <DeleteBranchEntry>[
          DeleteBranchEntry.forced('x', expectedTipOid: 'tip-A'),
        ]);
        expect(
          controller.calls.where(
            (_RecordedCall c) => c.name == 'probeBranchDeletion',
          ),
          hasLength(1),
        );
      },
    );

    // The recovery dialog draws the count of the same read "Delete anyway"
    // sends; until it lands there is nothing to draw and nothing to send.
    test('the read taken on a refusal is published once it lands', () async {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      const BranchDeletionProbeReply reply = BranchDeletionProbeReply(
        probes: <BranchDeletionProbe>[
          ProbeCounted(
            'x',
            tipOid: 'tip-A',
            upstream: 'refs/remotes/origin/x',
            unsyncedCount: 1,
          ),
        ],
      );
      controller.probe = (List<String> names) => reply;
      controller.debugRecordDeleteBranch(names: const <String>['x']);
      controller.debugHandleOperationOutcome(_forceableRefusal());

      expect(controller.state.deleteBranchRecoveryProbe, isNull);
      await pumpEventQueue();
      expect(controller.state.deleteBranchRecoveryProbe, same(reply));
    });

    test('a read that lands after Cancel is not published', () async {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.probe = (List<String> names) =>
          const BranchDeletionProbeReply(probes: <BranchDeletionProbe>[]);
      controller.debugRecordDeleteBranch(names: const <String>['x']);
      controller.debugHandleOperationOutcome(_forceableRefusal());
      controller.dismissDeleteBranchChoices();
      await pumpEventQueue();

      expect(controller.state.deleteBranchRecoveryProbe, isNull);
    });

    test('"Delete anyway" clears the published read', () async {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.probe = (List<String> names) =>
          const BranchDeletionProbeReply(probes: <BranchDeletionProbe>[]);
      controller.debugRecordDeleteBranch(names: const <String>['x']);
      controller.debugHandleOperationOutcome(_forceableRefusal());
      await pumpEventQueue();
      expect(controller.state.deleteBranchRecoveryProbe, isNotNull);

      controller.retryDeleteBranchWithChoice(OperationChoiceKind.forceDiscard);
      expect(controller.state.deleteBranchRecoveryProbe, isNull);
    });

    test('a successful outcome clears the retained failed request', () {
      final controller = _RecordingRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      controller.debugRecordCheckout(target: 'first-attempt');
      controller.debugHandleOperationOutcome(_failedOutcome(kind: 'checkout'));
      expect(controller.state.checkoutChoices, isNotEmpty);

      controller.debugRecordCheckout(target: 'first-attempt');
      controller.debugHandleOperationOutcome(
        _succeededOutcome(kind: 'checkout'),
      );
      expect(controller.state.checkoutChoices, isEmpty);

      // No failed request left to retry.
      controller.retryCheckoutWithChoice(OperationChoiceKind.stashAndRetry);
      expect(controller.calls, isEmpty);
    });
  });
}
