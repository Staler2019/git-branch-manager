import 'dart:collection';

/// A stable, machine-readable slug identifying which controller method
/// produced an operation-completion outcome -- mirrors the `kind` field
/// `OperationRunner::workerLoop()` stamps on `OperationOutcome`
/// (src/core/git/OperationRunner.h/.cpp), which is only present for
/// operations that override `Operation::kind()` (currently checkout,
/// delete-branch, fetch and prune-remote; see CheckoutOp.cpp /
/// BranchOps.cpp / RemoteOps.cpp).
///
/// Spans both completion channels on purpose: checkout, delete-branch and
/// prune-remote arrive on GBM_EVENT_OPERATION_FINISHED, fetch on
/// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED. They are two capi events but
/// one `OperationRunner` queue, stamped on one code path, so one kind
/// vocabulary is correct.
enum PendingOperationKind {
  checkout('checkout'),
  deleteBranch('delete-branch'),
  fetch('fetch'),
  pruneRemote('prune-remote');

  const PendingOperationKind(this.wireName);

  /// The exact string `capi::toJson(const OperationOutcome&)` writes under
  /// the "kind" key.
  final String wireName;

  /// Null for an outcome with no "kind" (every operation other than
  /// checkout/deleteBranch/fetch/pruneRemote) or an unrecognized one --
  /// callers must treat that as "cannot attribute this outcome" rather
  /// than guessing.
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

/// The fields of a [RepoSessionController.fetchRemote] call that the
/// post-fetch work needs back once the outcome arrives.
///
/// Only the remote name, because that is the whole question the gone-marking
/// asks: which remotes did this fetch actually touch, so which ones should be
/// previewed for pruning. An empty string is meaningful, not missing -- it is
/// `git fetch --all` (`FetchOperation::run`, RemoteOps.cpp), which fans out
/// to every remote.
class PendingFetchRequest {
  const PendingFetchRequest({required this.remoteName});

  final String remoteName;
}

/// The fields of a [RepoSessionController.pruneRemote] call that the
/// gone-marking needs back once the outcome arrives.
///
/// Both, not just the remote: the Prune dialog lets the user deselect
/// entries before pruning, so the refs actually deleted are a subset of
/// what was previewed and only this list says which.
///
/// [refs] arrives in whichever form the call site used -- the dialog sends
/// git's short names (`origin/x`), `sidebar_panel.dart` sends full
/// `refs/remotes/...` names -- so anything comparing them against stored
/// state must normalise first. See
/// [RepoSessionState.withGonePendingRemoved].
class PendingPruneRemoteRequest {
  const PendingPruneRemoteRequest({
    required this.remoteName,
    required this.refs,
  });

  final String remoteName;
  final List<String> refs;
}

/// Attributes a GBM_EVENT_OPERATION_FINISHED outcome to the specific
/// checkout()/deleteBranch()/pruneRemote() call that produced it.
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

  /// Fetch completes on GBM_EVENT_WORKING_COPY_OPERATION_FINISHED rather
  /// than GBM_EVENT_OPERATION_FINISHED (it goes through
  /// `Session::submitWorkingCopyOperation`), but both channels are fed by
  /// the same `OperationRunner` queue and stamped on the same code path, so
  /// the FIFO reasoning above applies to it unchanged.
  final Queue<PendingFetchRequest> _fetchQueue = Queue<PendingFetchRequest>();

  /// Prune-remote rides GBM_EVENT_OPERATION_FINISHED (`Session::pruneRemote`
  /// goes through `submitOperation`, not `submitWorkingCopyOperation` --
  /// deleting remote-tracking refs never touches the working tree), the
  /// same channel as checkout and delete-branch.
  final Queue<PendingPruneRemoteRequest> _pruneRemoteQueue =
      Queue<PendingPruneRemoteRequest>();

  void recordCheckout(PendingCheckoutRequest request) =>
      _checkoutQueue.add(request);

  void recordDeleteBranch(PendingDeleteBranchRequest request) =>
      _deleteBranchQueue.add(request);

  void recordFetch(PendingFetchRequest request) => _fetchQueue.add(request);

  void recordPruneRemote(PendingPruneRemoteRequest request) =>
      _pruneRemoteQueue.add(request);

  /// Pops and returns the checkout request this outcome answers, or null if
  /// none is pending. A null here means a "checkout"-kind outcome arrived
  /// with no matching call recorded -- should not happen, but the caller
  /// must not crash the reducer over it.
  PendingCheckoutRequest? takeCheckout() =>
      _checkoutQueue.isEmpty ? null : _checkoutQueue.removeFirst();

  /// Same contract as [takeCheckout], for delete-branch.
  PendingDeleteBranchRequest? takeDeleteBranch() =>
      _deleteBranchQueue.isEmpty ? null : _deleteBranchQueue.removeFirst();

  /// Same contract as [takeCheckout], for fetch. Must be called for a
  /// *failed* fetch too: the queue tracks submissions, not successes, so
  /// skipping the pop on failure would attribute the next fetch's outcome to
  /// this request.
  PendingFetchRequest? takeFetch() =>
      _fetchQueue.isEmpty ? null : _fetchQueue.removeFirst();

  /// Same contract as [takeFetch], for prune-remote: must be called for a
  /// *failed* prune too, or this request would answer for the next prune's
  /// outcome and clear gone marks that prune never touched.
  PendingPruneRemoteRequest? takePruneRemote() =>
      _pruneRemoteQueue.isEmpty ? null : _pruneRemoteQueue.removeFirst();

  /// Drops every pending request without producing outcomes for them --
  /// called when the session closes, since no further
  /// GBM_EVENT_OPERATION_FINISHED events will arrive to consume them.
  void clear() {
    _checkoutQueue.clear();
    _deleteBranchQueue.clear();
    _fetchQueue.clear();
    _pruneRemoteQueue.clear();
  }
}
