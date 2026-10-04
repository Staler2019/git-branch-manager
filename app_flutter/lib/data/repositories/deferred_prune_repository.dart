import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ref_snapshot.dart';
import '../models/remote_counterpart.dart';
import 'prune_audience.dart';
import 'repo_identity.dart';
import 'repo_session_repository.dart';

/// Prunes a remote-tracking ref that a fetch-triggered preview called gone and
/// that the automatic prune skipped only because a local branch claimed it.
///
/// Skipping a claimed ref is a **deferred** decision, not a closed one: the
/// claim disappears the moment the user deletes that local branch, and no
/// second preview runs to notice. Without this, the stale ref stays on disk
/// and the sidebar goes on drawing the just-deleted branch as a remote-only
/// row until the *next* fetch — the whole of the reported 「delete local
/// branch, and the branch shows as still a remote branch there」.
///
/// **Why this is its own object and not a method on `RepoSessionController`**:
/// the controller is the only thing that knows a preview reply's provenance,
/// and the Prune dialog is the only thing that knows whether its candidate
/// list is on screen. Neither knows *when a deferred decision comes due*, and
/// that is all this holds. `RepoSessionState.goneRefsDeferredByClaim` is the
/// seam on one side and [PruneAudience] the seam on the other; the paragraphs
/// above say why a fact crosses in that direction rather than a command
/// coming back.
///
/// **It only exists while something watches it.** A provider nothing reads is
/// never built, so `WorkspaceScreen` watches [deferredPruneProvider] for no
/// value at all — the watch *is* the mount, and deleting it deletes this
/// feature with no compile error.
class DeferredPruneNotifier extends StateNotifier<void> {
  DeferredPruneNotifier(this._ref, this._identity) : super(null) {
    // Two triggers, and neither subsumes the other. A refs update is what
    //「the claiming branch was deleted」 looks like; a fresh deferral is what a
    // new fetch preview looks like. `RefSnapshot` has no value equality, so
    // the first fires on every publish -- which is fine, because a sweep with
    // nothing due is a map lookup.
    _ref.listen<RefSnapshot>(
      repoSessionProvider(_identity).select((RepoSessionState s) => s.refs),
      (RefSnapshot? previous, RefSnapshot next) => _sweep(),
    );
    _ref.listen<Map<String, List<String>>>(
      repoSessionProvider(
        _identity,
      ).select((RepoSessionState s) => s.goneRefsDeferredByClaim),
      (Map<String, List<String>>? previous, Map<String, List<String>> next) {
        _forgetDispatchedOutside(next);
        _sweep();
      },
    );
    // Releasing a hold changes no state at all, so neither listener above can
    // see it -- and it is exactly when a prune held back for the Prune dialog
    // becomes safe. Without this the prune would wait for the next fetch.
    _removeReleaseListener = _ref
        .read(pruneAudienceProvider(_identity))
        .addReleaseListener(_sweep);
  }

  final Ref _ref;
  final RepoIdentity _identity;

  VoidCallback? _removeReleaseListener;

  /// Full ref names this notifier has already sent to `pruneRemote`.
  ///
  /// The gate is 「this ref has not been tried」, never 「this ref is prunable」
  /// (the same shape as `_autoPrunedWorktreePaths`). That is what makes the
  /// prune's own refs refresh a no-op instead of a loop: the refresh re-runs
  /// the sweep, and every ref in it has been tried. A failed prune therefore
  /// waits for the next fetch rather than retrying; the row keeps its gone
  /// marking meanwhile.
  ///
  /// It lives here, beside the policy, because the table lives in state this
  /// notifier cannot write. While both were the controller's, the same
  /// invariant was spelled 「remove from the table before dispatching」.
  final Set<String> _dispatched = <String>{};

  @override
  void dispose() {
    _removeReleaseListener?.call();
    _removeReleaseListener = null;
    super.dispose();
  }

  /// Drops `_dispatched` entries that [next] no longer defers.
  ///
  /// Required, not housekeeping: `goneRefsDeferredByClaim` is replaced per
  /// remote by each fetch preview, so a ref that came back onto the remote and
  /// later went away again arrives as a *fresh* deferral. Remembering the old
  /// attempt forever would make that second disappearance unprunable.
  void _forgetDispatchedOutside(Map<String, List<String>> next) {
    final Set<String> stillDeferred = <String>{
      for (final List<String> refs in next.values) ...refs,
    };
    _dispatched.removeWhere((String ref) => !stillDeferred.contains(ref));
  }

  /// Dispatches every deferred ref that has come due.
  ///
  /// Four conditions, and what separates them is not whether they pass but
  /// whether failing one is *final*:
  ///
  /// - **still claimed** — the deferred ref's normal state until the user
  ///   actually deletes the branch, so it is left alone and re-checked. This
  ///   is the one that must not be treated as final: `publishRefs` happens far
  ///   more often than a delete (`Session::onRefreshTimerFired` emits
  ///   `GBM_EVENT_REFS_UPDATED` unconditionally after every coalesced
  ///   refresh), so one F5 between the fetch and the delete would otherwise
  ///   discard the deferral and restore the bug in full.
  /// - **gone from `refs.remoteBranches`** — someone else already deleted it;
  ///   sending it would only earn 「remote-tracking branch not found」.
  /// - **no longer in `gonePendingByRemote`** — a newer preview stopped
  ///   calling it gone, i.e. it is back on the remote. The exit path.
  /// - **held by the audience** — the Prune dialog is listing this remote's
  ///   candidates right now. Held back, never discarded: pruning one empties
  ///   the list under the user and their own Prune button then fails against a
  ///   ref that is already gone ([REF-fetch-auto-prunes]).
  void _sweep() {
    final RepoSessionState session = _ref.read(repoSessionProvider(_identity));
    if (session.goneRefsDeferredByClaim.isEmpty) return;

    final PruneAudience audience = _ref.read(pruneAudienceProvider(_identity));
    final Set<String> claimed = claimedRemoteCounterparts(session.refs);
    final Set<String> present = <String>{
      for (final RefInfo remote in session.refs.remoteBranches) remote.fullName,
    };

    final RepoSessionController controller = _ref.read(
      repoSessionProvider(_identity).notifier,
    );

    session.goneRefsDeferredByClaim.forEach((
      String remote,
      List<String> deferred,
    ) {
      if (audience.holdsRemote(remote)) return;
      final Set<String> stillMarked =
          (session.gonePendingByRemote[remote] ?? const <String>[]).toSet();

      final List<String> due = <String>[
        for (final String ref in deferred)
          if (!_dispatched.contains(ref) &&
              !claimed.contains(ref) &&
              present.contains(ref) &&
              stillMarked.contains(ref))
            ref,
      ];
      if (due.isEmpty) return;

      // Recorded before dispatching, so a prune's own refs refresh -- which
      // re-enters this sweep -- finds nothing due.
      _dispatched.addAll(due);
      controller.pruneRemote(remote, due, automatic: true);
    });
  }
}

/// One per repository. Holds no value: it is watched to be built, not to be
/// read ([DeferredPruneNotifier]'s own doc comment).
final StateNotifierProviderFamily<DeferredPruneNotifier, void, RepoIdentity>
deferredPruneProvider =
    StateNotifierProvider.family<DeferredPruneNotifier, void, RepoIdentity>(
      (Ref ref, RepoIdentity identity) => DeferredPruneNotifier(ref, identity),
    );
