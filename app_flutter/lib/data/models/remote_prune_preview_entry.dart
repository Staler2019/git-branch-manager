/// Mirrors `gbm::RemotePrunePreviewEntry` (src/core/git/ops/RemoteOps.h) as
/// serialized by `capi::toJson(const RemotePrunePreviewEntry&)`.
class RemotePrunePreviewEntry {
  const RemotePrunePreviewEntry({required this.ref});

  factory RemotePrunePreviewEntry.fromJson(Map<String, dynamic> json) {
    return RemotePrunePreviewEntry(ref: json['ref'] as String);
  }

  static List<RemotePrunePreviewEntry> listFromJson(List<dynamic> json) {
    return json
        .map(
          (e) => RemotePrunePreviewEntry.fromJson(e as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  /// The remote-tracking ref's short name, e.g. "origin/feature/old-branch"
  /// -- what `git branch -d -r` accepts, and what
  /// [RepoSessionController.pruneRemote]'s `refs` parameter expects back.
  final String ref;
}
