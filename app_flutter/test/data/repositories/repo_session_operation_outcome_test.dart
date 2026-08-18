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
import 'package:gbm_flutter/data/models/operation_choice.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

Map<String, dynamic> _failedOutcome({
  required String kind,
  String label = 'Stash changes and switch',
}) => <String, dynamic>{
  'succeeded': false,
  'kind': kind,
  'choices': <Map<String, dynamic>>[
    <String, dynamic>{
      'kind': OperationChoiceKind.stashAndRetry.index,
      'label': label,
      'explanation': 'explanation',
      'destructive': false,
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
    required List<String> names,
    bool force = false,
    bool isRemote = false,
    String remoteName = '',
  }) {
    calls.add(
      _RecordedCall('deleteBranch', <String, Object?>{
        'names': names,
        'force': force,
      }),
    );
  }
}

void main() {
  group('RepoSessionController._handleOperationOutcome (attribution)', () {
    test(
      'an outcome with no matching pending kind leaves checkoutChoices untouched',
      () {
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
      },
    );

    test('a "checkout"-kind outcome populates checkoutChoices', () {
      final fake = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      fake.debugRecordCheckout(target: 'feature');

      fake.debugHandleOperationOutcome(_failedOutcome(kind: 'checkout'));

      expect(fake.state.checkoutChoices, hasLength(1));
      expect(
        fake.state.checkoutChoices.single.label,
        'Stash changes and switch',
      );
    });

    test('a "delete-branch"-kind outcome populates deleteBranchChoices', () {
      final fake = FakeRepoSessionController(
        _identity,
        const RepoSessionState(),
      );
      fake.debugRecordDeleteBranch(names: const <String>['gone']);

      fake.debugHandleOperationOutcome(
        _failedOutcome(kind: 'delete-branch', label: 'Force delete'),
      );

      expect(fake.state.deleteBranchChoices, hasLength(1));
      expect(fake.state.deleteBranchChoices.single.label, 'Force delete');
    });

    test(
      'checkout and deleteBranch outcomes interleave without cross-contamination',
      () {
        final fake = FakeRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        fake.debugRecordCheckout(target: 'feature');
        fake.debugRecordDeleteBranch(names: const <String>['gone']);

        // deleteBranch's outcome arrives first even though checkout was
        // requested first -- exactly the interleaving that broke the old
        // two-boolean design.
        fake.debugHandleOperationOutcome(
          _failedOutcome(kind: 'delete-branch', label: 'Force delete'),
        );
        expect(fake.state.deleteBranchChoices, hasLength(1));
        expect(fake.state.checkoutChoices, isEmpty);

        fake.debugHandleOperationOutcome(
          _failedOutcome(kind: 'checkout', label: 'Stash changes and switch'),
        );
        expect(fake.state.checkoutChoices, hasLength(1));
        // deleteBranchChoices must still hold its own outcome, untouched by
        // the later checkout outcome.
        expect(fake.state.deleteBranchChoices, hasLength(1));
      },
    );
  });

  group(
    'RepoSessionController retry (real retryCheckoutWithChoice/retryDeleteBranchWithChoice)',
    () {
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

      test(
        'retryDeleteBranchWithChoice resubmits the request that actually failed',
        () {
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

          expect(controller.state.deleteBranchChoices, isEmpty);
          expect(controller.calls, hasLength(1));
          expect(controller.calls.single.name, 'deleteBranch');
          expect(controller.calls.single.args['names'], <String>['gone']);
          expect(controller.calls.single.args['force'], true);
        },
      );

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

      test('a successful outcome clears the retained failed request', () {
        final controller = _RecordingRepoSessionController(
          _identity,
          const RepoSessionState(),
        );
        controller.debugRecordCheckout(target: 'first-attempt');
        controller.debugHandleOperationOutcome(
          _failedOutcome(kind: 'checkout'),
        );
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
    },
  );
}
