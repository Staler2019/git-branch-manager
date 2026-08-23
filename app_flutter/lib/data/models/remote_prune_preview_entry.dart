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
  String get fullRefName =>
      ref.startsWith(_kRemotePrefix) ? ref : '$_kRemotePrefix$ref';
}

const String _kRemotePrefix = 'refs/remotes/';
