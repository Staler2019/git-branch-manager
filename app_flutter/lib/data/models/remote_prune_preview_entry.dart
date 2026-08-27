/// Mirrors `gbm::RemotePrunePreviewEntry` (src/core/git/ops/RemoteOps.h) as
/// serialized by `capi::toJson(const RemotePrunePreviewEntry&)`.
class RemotePrunePreviewEntry {
  const RemotePrunePreviewEntry({required this.ref});

  factory RemotePrunePreviewEntry.fromJson(Map<String, dynamic> json) {
    return RemotePrunePreviewEntry(ref: json['ref'] as String);
  }

  static List<RemotePrunePreviewEntry> listFromJson(List<dynamic> json) {
    return json
        .map((e) => RemotePrunePreviewEntry.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// The remote-tracking ref's short name, e.g. "origin/feature/old-branch"
  /// -- what `git branch -d -r` accepts, and what
  /// [RepoSessionController.pruneRemote]'s `refs` parameter expects back.
  final String ref;

  /// [ref] as a full ref name, e.g. "refs/remotes/origin/feature/old-branch".
  ///
  /// Everything that decides whether a branch row is gone compares against a
  /// full name: `RefInfo.upstream` is git's `%(upstream)` (not
  /// `%(upstream:short)`) and a remote branch's `RefInfo.fullName` is
  /// likewise `refs/remotes/...`. Comparing [ref] to either of those
  /// directly never matches, so the marking would silently never appear --
  /// the same class of bug as `delete_branch_dialog.dart`'s first-slash
  /// split (#74), just in the other direction.
  ///
  /// Idempotent by design: an input that already carries the prefix is
  /// returned unchanged rather than doubled, so this stays correct if the
  /// C++ side's chosen form ever moves.
  String get fullRefName => fullRemoteRefName(ref);
}

/// Idempotently expands a remote-tracking ref to its full name.
///
/// Shared rather than private to [RemotePrunePreviewEntry] because the two
/// forms meet outside a preview entry as well: `pruneRemote`'s `refs`
/// argument carries short names from the Prune dialog and full names from
/// `sidebar_panel.dart`, and anything comparing either against stored state
/// has to agree on one form first.
String fullRemoteRefName(String ref) =>
    ref.startsWith(_kRemotePrefix) ? ref : '$_kRemotePrefix$ref';

/// The exact argument list `git branch --delete --remotes` will accept, from
/// a prune ref list in either form.
///
/// This is the **wire boundary** for pruning, and it exists because git is
/// stricter here than anywhere else this codebase touches refs: `branch -r -d`
/// resolves its argument *relative to* `refs/remotes/`, so a full name asks
/// for `refs/remotes/refs/remotes/origin/x` and git answers
/// `error: remote-tracking branch '...' not found` with exit 1. Measured on
/// git 2.55.0; `src/core/git/ops/RemoteOps.h`'s `PruneRemoteRequest::refs`
/// documents the same short-name contract on the C++ side.
///
/// Needed because the two producers genuinely disagree and always did:
/// `prune_remote_branches_dialog.dart` sends git's short names while
/// `gonePendingByRemote` stores full ones, and for months the sidebar's own
/// "Prune this ref" fed the latter straight through -- every such prune failed
/// silently from the user's point of view. Normalising here rather than at
/// each call site means a new caller cannot reintroduce it.
///
/// Safe with respect to the gone-marking: `withGonePendingRemoved()` puts
/// whatever it is given back through [fullRemoteRefName] before comparing, so
/// the pending set keeps comparing full names either way.
///
/// Note for tests: `FakeRepoSessionController` overrides `pruneRemote()`
/// wholesale, so a fake-backed test sees the *caller's* form, not this
/// function's output. That is deliberate -- it keeps a caller passing the
/// wrong form visible instead of being laundered by the double.
List<String> pruneRefArguments(List<String> refs) =>
    refs.map(shortRemoteRefName).toList(growable: false);

/// The inverse of [fullRemoteRefName], equally idempotent. For display only:
/// `origin/feature/x` is what the user recognises, while every comparison in
/// this codebase is done on the full form.
String shortRemoteRefName(String ref) =>
    ref.startsWith(_kRemotePrefix) ? ref.substring(_kRemotePrefix.length) : ref;

const String _kRemotePrefix = 'refs/remotes/';
