import 'dart:collection';

/// A stable, machine-readable slug identifying which controller method
/// produced a GBM_EVENT_OPERATION_FINISHED outcome -- mirrors the `kind`
/// field `OperationRunner::workerLoop()` stamps on `OperationOutcome`
/// (src/core/git/OperationRunner.h/.cpp), which is only present for
/// operations that override `Operation::kind()` (currently checkout and
/// delete-branch; see CheckoutOp.cpp / BranchOps.cpp).
enum PendingOperationKind {
  checkout('checkout'),
  deleteBranch('delete-branch');

  const PendingOperationKind(this.wireName);

  /// The exact string `capi::toJson(const OperationOutcome&)` writes under
  /// the "kind" key.
  final String wireName;

  /// Null for an outcome with no "kind" (every operation other than
  /// checkout/deleteBranch) or an unrecognized one -- callers must treat
  /// that as "cannot attribute this outcome" rather than guessing.
  static PendingOperationKind? fromWireName(String wireName) {
    for (final PendingOperationKind kind in values) {
      if (kind.wireName == wireName) return kind;
    }
    return null;
  }
}

/// The fields of a [RepoSessionController.checkout] call, remembered so a
/// later outcome or recovery-choice retry can resubmit the exact same
/// request.
class PendingCheckoutRequest {
  const PendingCheckoutRequest({
    required this.target,
    required this.detach,
    required this.createBranch,
    required this.newBranchName,
  });

  final String target;
  final bool detach;
  final bool createBranch;
  final String newBranchName;
}

/// The fields of a [RepoSessionController.deleteBranch] call, remembered for
/// the same reason as [PendingCheckoutRequest].
class PendingDeleteBranchRequest {
  const PendingDeleteBranchRequest({
    required this.names,
    required this.isRemote,
    required this.remoteName,
  });

  final List<String> names;
  final bool isRemote;
  final String remoteName;
}

/// Attributes a GBM_EVENT_OPERATION_FINISHED outcome to the specific
/// checkout()/deleteBranch() call that produced it.
///
/// [RepoSessionController.checkout] and [RepoSessionController.deleteBranch]
/// share the same `submitOperation` event channel with roughly thirty other
/// controller methods (mergeBranch, resetTo, cherryPick*, *Rebase,
/// pruneRemote, *Bisect, *Import, ...). `OperationRunner`'s queue
/// (src/core/git/OperationRunner.h) can hold more than one operation at a
/// time -- it guarantees completion events arrive in the order operations
/// were submitted, but nothing else identifies which request a given
/// completion event answers. Pairing "the next operationFinished event" with
/// "the checkout I just called" is therefore wrong whenever anything else on
/// the shared channel is submitted in between.
///
/// This tracker keeps one FIFO queue per kind: since the C++ side completes
/// operations strictly in submission order, the outcome for the Nth
/// checkout() call is always the Nth entry popped off the checkout queue,
/// regardless of how many non-checkout operations completed in between.
class PendingOperationTracker {
  final Queue<PendingCheckoutRequest> _checkoutQueue =
      Queue<PendingCheckoutRequest>();
  final Queue<PendingDeleteBranchRequest> _deleteBranchQueue =
      Queue<PendingDeleteBranchRequest>();

  void recordCheckout(PendingCheckoutRequest request) =>
      _checkoutQueue.add(request);

  void recordDeleteBranch(PendingDeleteBranchRequest request) =>
      _deleteBranchQueue.add(request);

  /// Pops and returns the checkout request this outcome answers, or null if
  /// none is pending. A null here means a "checkout"-kind outcome arrived
  /// with no matching call recorded -- should not happen, but the caller
  /// must not crash the reducer over it.
  PendingCheckoutRequest? takeCheckout() =>
      _checkoutQueue.isEmpty ? null : _checkoutQueue.removeFirst();

  /// Same contract as [takeCheckout], for delete-branch.
  PendingDeleteBranchRequest? takeDeleteBranch() =>
      _deleteBranchQueue.isEmpty ? null : _deleteBranchQueue.removeFirst();

  /// Drops every pending request without producing outcomes for them --
  /// called when the session closes, since no further
  /// GBM_EVENT_OPERATION_FINISHED events will arrive to consume them.
  void clear() {
    _checkoutQueue.clear();
    _deleteBranchQueue.clear();
  }
}
