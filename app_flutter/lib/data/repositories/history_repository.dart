import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/changed_file.dart';
import '../models/commit_meta.dart';
import '../models/graph_snapshot.dart';
import '../models/list_selection.dart';
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

/// The History commit list's multi-selection, per repository -- family-scoped
/// like every other per-repo provider here, rather than a single global
/// `StateProvider`, so selection in one open repository never leaks into
/// another. Spec page 13 also keeps selections from bleeding *between lists*
/// (「選取狀態跨 scope 不混用」), which is why the sidebar's branch tree holds
/// its own [ListSelection] rather than sharing this one.
///
/// Holds oid hex strings. Selection is expressed against the *unfiltered*
/// graph snapshot, so a range taken while a filter is active is still
/// judged for contiguity against real history -- see
/// [ListSelection.isContiguousIn].
final StateProviderFamily<ListSelection<String>, RepoIdentity>
commitSelectionProvider =
    StateProvider.family<ListSelection<String>, RepoIdentity>(
      (ref, identity) => const ListSelection<String>(),
    );

/// The currently-selected commit's oid in [CommitGraphView] -- the single
/// target every one-commit surface reads (the commit detail panel, the
/// changed-files panel).
///
/// **Derived, not independently writable**: it is exactly
/// [commitSelectionProvider]'s anchor. Before multi-select this was its own
/// `StateProvider` that call sites wrote to directly; keeping that alongside
/// a selection set would have meant two selection states that could disagree,
/// so the anchor is now the one source of truth and this is a read-only view
/// of it. Write through [commitSelectionProvider] instead.
final ProviderFamily<String?, RepoIdentity> selectedCommitProvider =
    Provider.family<String?, RepoIdentity>(
      (ref, identity) => ref.watch(commitSelectionProvider(identity)).anchor,
    );

/// The currently-selected file path within the selected commit's changed files.
/// Null means show commit metadata; non-null means show the diff for that file.
final StateProviderFamily<String?, RepoIdentity>
selectedCommitFilePathProvider = StateProvider.family<String?, RepoIdentity>(
  (ref, identity) => null,
);
