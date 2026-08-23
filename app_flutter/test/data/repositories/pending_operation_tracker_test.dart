// PendingOperationTracker attributes a GBM_EVENT_OPERATION_FINISHED outcome
// to the checkout()/deleteBranch() call that produced it, by "kind" rather
// than by assuming the next such event to arrive must be the answer. See
// its doc comment (pending_operation_tracker.dart) for why: OperationRunner's
// queue can hold more than one operation at a time, and roughly thirty other
// controller methods share the same event channel.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/pending_operation_tracker.dart';

const PendingCheckoutRequest _checkoutA = PendingCheckoutRequest(
  target: 'branch-a',
  detach: false,
  createBranch: false,
  newBranchName: '',
);

const PendingCheckoutRequest _checkoutB = PendingCheckoutRequest(
  target: 'branch-b',
  detach: false,
  createBranch: false,
  newBranchName: '',
);

const PendingDeleteBranchRequest _deleteA = PendingDeleteBranchRequest(
  names: <String>['gone-a'],
  isRemote: false,
  remoteName: '',
);

const PendingDeleteBranchRequest _deleteB = PendingDeleteBranchRequest(
  names: <String>['gone-b'],
  isRemote: false,
  remoteName: '',
);

void main() {
  group('PendingOperationKind.fromWireName', () {
    test('maps the exact wire strings JsonCodec emits', () {
      expect(
        PendingOperationKind.fromWireName('checkout'),
        PendingOperationKind.checkout,
      );
      expect(
        PendingOperationKind.fromWireName('delete-branch'),
        PendingOperationKind.deleteBranch,
      );
    });

    test('returns null for an empty string (unstamped operation)', () {
      expect(PendingOperationKind.fromWireName(''), isNull);
    });

    test('returns null for an unrecognized kind', () {
      expect(PendingOperationKind.fromWireName('merge'), isNull);
    });
  });

  group('PendingOperationTracker', () {
    test('takeCheckout returns null when nothing is pending', () {
      final tracker = PendingOperationTracker();
      expect(tracker.takeCheckout(), isNull);
    });

    test('takeDeleteBranch returns null when nothing is pending', () {
      final tracker = PendingOperationTracker();
      expect(tracker.takeDeleteBranch(), isNull);
    });

    test('takeCheckout pops in FIFO order for repeated same-kind calls', () {
      final tracker = PendingOperationTracker();
      tracker.recordCheckout(_checkoutA);
      tracker.recordCheckout(_checkoutB);

      expect(tracker.takeCheckout()?.target, 'branch-a');
      expect(tracker.takeCheckout()?.target, 'branch-b');
      expect(tracker.takeCheckout(), isNull);
    });

    test(
      'takeDeleteBranch pops in FIFO order for repeated same-kind calls',
      () {
        final tracker = PendingOperationTracker();
        tracker.recordDeleteBranch(_deleteA);
        tracker.recordDeleteBranch(_deleteB);

        expect(tracker.takeDeleteBranch()?.names, <String>['gone-a']);
        expect(tracker.takeDeleteBranch()?.names, <String>['gone-b']);
        expect(tracker.takeDeleteBranch(), isNull);
      },
    );

    test(
      'checkout and deleteBranch queues are independent when interleaved',
      () {
        final tracker = PendingOperationTracker();
        tracker.recordCheckout(_checkoutA);
        tracker.recordDeleteBranch(_deleteA);
        tracker.recordCheckout(_checkoutB);

        // A deleteBranch outcome landing between the two checkout calls must
        // not disturb the checkout queue's order or contents.
        expect(tracker.takeDeleteBranch()?.names, <String>['gone-a']);
        expect(tracker.takeCheckout()?.target, 'branch-a');
        expect(tracker.takeCheckout()?.target, 'branch-b');
      },
    );

    test('clear() drops every pending request in both queues', () {
      final tracker = PendingOperationTracker();
      tracker.recordCheckout(_checkoutA);
      tracker.recordDeleteBranch(_deleteA);

      tracker.clear();

      expect(tracker.takeCheckout(), isNull);
      expect(tracker.takeDeleteBranch(), isNull);
    });
  });

  group('fetch queue', () {
    test('a fetch outcome carries back the remote that was fetched', () {
      // The post-fetch gone-marking has to preview exactly the remotes this
      // fetch touched -- previewing all of them after a single-remote fetch
      // would fire network calls the user did not ask for.
      final tracker = PendingOperationTracker();
      tracker.recordFetch(const PendingFetchRequest(remoteName: 'origin'));

      expect(tracker.takeFetch()?.remoteName, 'origin');
    });

    test('an empty remote name means fetch --all', () {
      // FetchOperation appends --all when remoteName is empty
      // (RemoteOps.cpp), so the empty string is meaningful, not missing.
      final tracker = PendingOperationTracker();
      tracker.recordFetch(const PendingFetchRequest(remoteName: ''));

      final PendingFetchRequest? taken = tracker.takeFetch();
      expect(taken, isNotNull);
      expect(taken!.remoteName, '');
    });

    test('outcomes are attributed in submission order', () {
      final tracker = PendingOperationTracker();
      tracker.recordFetch(const PendingFetchRequest(remoteName: 'origin'));
      tracker.recordFetch(const PendingFetchRequest(remoteName: 'upstream'));

      expect(tracker.takeFetch()?.remoteName, 'origin');
      expect(tracker.takeFetch()?.remoteName, 'upstream');
    });

    test('another kind completing in between does not disturb it', () {
      // The whole reason this tracker exists: fetch shares
      // GBM_EVENT_WORKING_COPY_OPERATION_FINISHED with roughly thirty other
      // methods, so "the next completion event" is not a valid pairing.
      final tracker = PendingOperationTracker();
      tracker.recordFetch(const PendingFetchRequest(remoteName: 'origin'));
      tracker.recordCheckout(_checkoutA);
      tracker.recordFetch(const PendingFetchRequest(remoteName: 'upstream'));

      expect(tracker.takeCheckout()?.target, 'branch-a');
      expect(tracker.takeFetch()?.remoteName, 'origin');
      expect(tracker.takeFetch()?.remoteName, 'upstream');
    });

    test('takeFetch on an empty queue is null, not a throw', () {
      expect(PendingOperationTracker().takeFetch(), isNull);
    });

    test('clear() drops pending fetches too', () {
      // A session that closes mid-fetch will never deliver the outcome, so
      // leaving the request queued would misattribute the first fetch of
      // the next session.
      final tracker = PendingOperationTracker();
      tracker.recordFetch(const PendingFetchRequest(remoteName: 'origin'));

      tracker.clear();

      expect(tracker.takeFetch(), isNull);
    });
  });

  group('prune-remote queue', () {
    test('a prune outcome carries back the remote and the exact refs', () {
      // Clearing the gone-pending marks needs both: which remote's slice to
      // touch, and which refs inside it the user actually pruned (the Prune
      // dialog lets them deselect entries, so "everything previewed" is not
      // the same set).
      final tracker = PendingOperationTracker();
      tracker.recordPruneRemote(
        const PendingPruneRemoteRequest(
          remoteName: 'origin',
          refs: <String>['origin/gone-a'],
        ),
      );

      final PendingPruneRemoteRequest? taken = tracker.takePruneRemote();
      expect(taken?.remoteName, 'origin');
      expect(taken?.refs, <String>['origin/gone-a']);
    });

    test('outcomes are attributed in submission order', () {
      final tracker = PendingOperationTracker();
      tracker.recordPruneRemote(
        const PendingPruneRemoteRequest(
          remoteName: 'origin',
          refs: <String>['origin/a'],
        ),
      );
      tracker.recordPruneRemote(
        const PendingPruneRemoteRequest(
          remoteName: 'upstream',
          refs: <String>['upstream/b'],
        ),
      );

      expect(tracker.takePruneRemote()?.remoteName, 'origin');
      expect(tracker.takePruneRemote()?.remoteName, 'upstream');
    });

    test('another kind completing in between does not disturb it', () {
      // pruneRemote shares GBM_EVENT_OPERATION_FINISHED with deleteBranch
      // and ~thirty others, which is the whole reason for this tracker.
      final tracker = PendingOperationTracker();
      tracker.recordPruneRemote(
        const PendingPruneRemoteRequest(
          remoteName: 'origin',
          refs: <String>['origin/a'],
        ),
      );
      tracker.recordCheckout(_checkoutA);

      expect(tracker.takeCheckout()?.target, 'branch-a');
      expect(tracker.takePruneRemote()?.remoteName, 'origin');
    });

    test('takePruneRemote on an empty queue is null, not a throw', () {
      expect(PendingOperationTracker().takePruneRemote(), isNull);
    });

    test('clear() drops pending prunes too', () {
      final tracker = PendingOperationTracker();
      tracker.recordPruneRemote(
        const PendingPruneRemoteRequest(
          remoteName: 'origin',
          refs: <String>['origin/a'],
        ),
      );

      tracker.clear();

      expect(tracker.takePruneRemote(), isNull);
    });
  });

  group('PendingOperationKind wire names', () {
    test('fetch round-trips through the wire name', () {
      // Must match FetchOperation::kind() in RemoteOps.cpp exactly -- the
      // two sides are joined by this string and nothing checks them
      // together at compile time.
      expect(PendingOperationKind.fetch.wireName, 'fetch');
      expect(
        PendingOperationKind.fromWireName('fetch'),
        PendingOperationKind.fetch,
      );
    });

    test('prune-remote round-trips through the wire name', () {
      // Must match PruneRemoteOperation::kind() in RemoteOps.cpp exactly.
      expect(PendingOperationKind.pruneRemote.wireName, 'prune-remote');
      expect(
        PendingOperationKind.fromWireName('prune-remote'),
        PendingOperationKind.pruneRemote,
      );
    });

    test('an unknown kind is null, not a guess', () {
      expect(PendingOperationKind.fromWireName('pull'), isNull);
      expect(PendingOperationKind.fromWireName(''), isNull);
    });
  });
}
