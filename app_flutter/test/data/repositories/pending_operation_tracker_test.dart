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
}
