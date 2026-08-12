import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/commit_meta.dart';
import '../models/graph_snapshot.dart';
import 'repo_identity.dart';
import 'repo_session_repository.dart';

/// The commit graph, selected out of [repoSessionProvider] -- see
/// branch_repository.dart's doc comment for why this is a thin `select()`
/// rather than its own controller.
final ProviderFamily<GraphSnapshotView, RepoIdentity> repoGraphProvider =
    Provider.family<GraphSnapshotView, RepoIdentity>((ref, identity) {
      return ref.watch(
        repoSessionProvider(identity).select((state) => state.graph),
      );
    });

final ProviderFamily<bool, RepoIdentity> repoIsRefreshingProvider =
    Provider.family<bool, RepoIdentity>((ref, identity) {
      return ref.watch(
        repoSessionProvider(identity).select((state) => state.isRefreshing),
      );
    });

void refreshRepoHistory(WidgetRef ref, RepoIdentity identity) {
  ref.read(repoSessionProvider(identity).notifier).refreshHistory();
}

/// Batch-fetched commit metadata (author/subject/date), keyed by oid -- see
/// [RepoSessionState.commitMetaCache]. Populated by [requestCommitMeta].
final ProviderFamily<Map<String, CommitMeta>, RepoIdentity> commitMetaProvider =
    Provider.family<Map<String, CommitMeta>, RepoIdentity>((ref, identity) {
      return ref.watch(
        repoSessionProvider(identity).select((state) => state.commitMetaCache),
      );
    });

/// Requests metadata for whichever of `oids` are not already in
/// [commitMetaProvider] -- e.g. a commit list's newly-visible viewport rows.
/// Skipping already-cached oids here, not just relying on the cache to be
/// merged rather than replaced on the way back, is what keeps a fast scroll
/// from re-requesting the same handful of rows on every frame the viewport
/// shifts by one.
void requestCommitMeta(
  WidgetRef ref,
  RepoIdentity identity,
  List<String> oids,
) {
  final Map<String, CommitMeta> cached = ref.read(commitMetaProvider(identity));
  final List<String> missing = oids
      .where((oid) => !cached.containsKey(oid))
      .toList(growable: false);
  if (missing.isEmpty) return;
  ref.read(repoSessionProvider(identity).notifier).requestCommitMeta(missing);
}
