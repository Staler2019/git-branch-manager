import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repo_identity.dart';

/// Whether any UI surface is currently listing a remote's prune candidates.
///
/// Narrower than [PruneAudienceRegistry] on purpose, and declared on the
/// *reading* side: the background auto-prune needs to know 「is someone
/// looking at this remote's candidates right now」 and nothing else. A
/// consumer can be satisfied without a Riverpod container, and — the reason
/// this interface exists at all — the session repository does not have to
/// grow a method whose name mentions a dialog.
///
/// The direction matters. Before this, `PruneRemoteBranchesDialogContent`
/// called `beginPruneDialogPreview` / `endPruneDialogPreview` **on the
/// session controller**, so a git session held a field about which dialog
/// was on screen and had to keep it in step. That is a UI concept pushed
/// down into the data layer; this is the data layer asking a question and
/// the UI answering it.
abstract interface class PruneAudience {
  /// True while at least one live surface has declared it is showing
  /// [remote]'s prune candidates.
  bool holdsRemote(String remote);

  /// Registers [listener], called whenever a remote stops being held, and
  /// returns the function that removes it again.
  ///
  /// Part of the port rather than of the registry alone, and that is
  /// deliberate: a consumer that gates on [holdsRemote] needs to know when
  /// the gate opened, or the work it held back waits for an unrelated trigger
  /// that may never come. Leaving this to whoever assembles the two meant a
  /// test that supplies its own consumer got the gate without the release —
  /// half the behaviour, silently.
  VoidCallback addReleaseListener(VoidCallback listener);
}

/// Which remotes have their prune candidates on screen, and for whom.
///
/// **A plain class behind a plain `Provider`, exactly like
/// [OpenRepoSessions], and not a `StateNotifier`.** That is a constraint,
/// not a preference: a surface must be able to register itself from
/// `initState`, and Riverpod throws 「Tried to modify a provider while the
/// widget tree was building」 for a state change in any widget life-cycle
/// method. A first version was a `StateNotifier<Set<String>>` and every
/// dialog test failed on exactly that. Nothing renders from this, so the
/// change-notification a notifier buys was never wanted — only the
/// restriction it came with.
///
/// **Keyed by instance token, never by remote name.** Two dialogs listing
/// the same remote can coexist (measured: pushing one dialog route twice
/// really does mount two instances, each issuing its own preview), and with
/// the remote as the key the first one's `dispose` released the hold in
/// front of the second — whose list is the one the user is actually looking
/// at. The token is whatever object the caller passes; a `State` is the
/// natural choice.
class PruneAudienceRegistry implements PruneAudience {
  /// Live surfaces, each mapped to the remote it is showing, or null when it
  /// has not resolved one yet.
  ///
  /// [Map.identity] rather than a plain map: the contract is 「this exact
  /// object」, so a token that overrode `==` must not be able to collide
  /// with another surface's.
  final Map<Object, String?> _byInstance = Map<Object, String?>.identity();

  final List<VoidCallback> _releaseListeners = <VoidCallback>[];

  @override
  bool holdsRemote(String remote) => _byInstance.containsValue(remote);

  /// Announces that [token] is a live surface, holding nothing yet.
  ///
  /// Called **synchronously**, before the surface knows which remote it will
  /// show. That is what makes a late [declare] refusable: a surface torn
  /// down before it resolved a remote is already out of [_byInstance], so
  /// its in-flight callback cannot leave behind a hold that nothing will
  /// ever release. The previous shape guarded this with a `mounted` check —
  /// a timing defence where this is a structural one.
  void register(Object token) {
    _byInstance.putIfAbsent(token, () => null);
  }

  /// Records that [token] is showing [remote]'s candidates.
  ///
  /// A no-op for a token that is not registered — either never registered,
  /// or already released. Re-declaring replaces the previous remote, so a
  /// surface switching its picker does not leave the old one held forever;
  /// that replacement can itself release a hold, hence the notify.
  void declare(Object token, String remote) {
    if (!_byInstance.containsKey(token)) return;
    if (_byInstance[token] == remote) return;
    final Set<String> before = _held();
    _byInstance[token] = remote;
    _notifyIfReleased(before);
  }

  /// Drops [token]'s hold. Safe to call for a token that never registered or
  /// never declared, which is the ordinary path for a dialog dismissed
  /// before it resolved a remote.
  void release(Object token) {
    if (!_byInstance.containsKey(token)) return;
    final Set<String> before = _held();
    _byInstance.remove(token);
    _notifyIfReleased(before);
  }

  /// Only on *release*. A new hold is not interesting to the one consumer
  /// this exists for — the deferred prune sweep, which wants to re-run when
  /// work may have come due — and firing on a hold being taken would make
  /// the signal read as 「anything changed」, which is a different and less
  /// useful fact.
  @override
  VoidCallback addReleaseListener(VoidCallback listener) {
    _releaseListeners.add(listener);
    return () => _releaseListeners.remove(listener);
  }

  Set<String> _held() => _byInstance.values.whereType<String>().toSet();

  void _notifyIfReleased(Set<String> before) {
    if (before.difference(_held()).isEmpty) return;
    // Over a copy: a listener may remove itself, and one throwing must not
    // strand the others -- this is a background-prune retry, so there is no
    // surface to report a failure on anyway.
    for (final VoidCallback listener in _releaseListeners.toList()) {
      listener();
    }
  }

  @visibleForTesting
  Set<String> get heldRemotes => _held();
}

/// One audience per repository, like every other per-repo UI-state family.
final ProviderFamily<PruneAudienceRegistry, RepoIdentity>
pruneAudienceProvider = Provider.family<PruneAudienceRegistry, RepoIdentity>(
  (Ref ref, RepoIdentity identity) => PruneAudienceRegistry(),
);
