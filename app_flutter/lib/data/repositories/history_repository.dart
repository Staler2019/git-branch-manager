import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/changed_file.dart';
import '../models/commit_meta.dart';
import '../models/graph_snapshot.dart';
import '../models/parsed_diff.dart';
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

/// Changed files in a commit, selected out of [repoSessionProvider].
final ProviderFamily<List<ChangedFile>, RepoIdentity> commitFilesProvider =
    Provider.family<List<ChangedFile>, RepoIdentity>((ref, identity) {
      return ref.watch(
        repoSessionProvider(identity).select((state) => state.commitFiles),
      );
    });

/// The selected commit's file diff, selected out of [repoSessionProvider].
final ProviderFamily<ParsedDiff?, RepoIdentity> commitFileDiffProvider =
    Provider.family<ParsedDiff?, RepoIdentity>((ref, identity) {
      return ref.watch(
        repoSessionProvider(
          identity,
        ).select((state) => state.selectedCommitFileDiff),
      );
    });

void requestCommitFiles(WidgetRef ref, RepoIdentity identity, String oid) {
  ref.read(repoSessionProvider(identity).notifier).requestCommitFiles(oid);
}

void requestCommitFileDiff(
  WidgetRef ref,
  RepoIdentity identity,
  String oid,
  String path,
) {
  ref
      .read(repoSessionProvider(identity).notifier)
      .requestCommitFileDiff(oid, path);
}

/// The currently-selected commit's oid in [CommitGraphView], per repository
/// -- family-scoped like every other per-repo provider here, rather than a
/// single global `StateProvider`, so selection in one open repository never
/// leaks into another.
final StateProviderFamily<String?, RepoIdentity> selectedCommitProvider =
    StateProvider.family<String?, RepoIdentity>((ref, identity) => null);
