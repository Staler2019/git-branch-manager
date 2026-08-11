import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/graph_snapshot.dart';
import 'repo_identity.dart';
import 'repo_session_repository.dart';

/// The commit graph, selected out of [repoSessionProvider] -- see
/// branch_repository.dart's doc comment for why this is a thin `select()`
/// rather than its own controller.
final ProviderFamily<GraphSnapshotView, RepoIdentity> repoGraphProvider =
    Provider.family<GraphSnapshotView, RepoIdentity>((ref, identity) {
      return ref.watch(repoSessionProvider(identity).select((state) => state.graph));
    });

final ProviderFamily<bool, RepoIdentity> repoIsRefreshingProvider = Provider.family<bool, RepoIdentity>((
  ref,
  identity,
) {
  return ref.watch(repoSessionProvider(identity).select((state) => state.isRefreshing));
});

void refreshRepoHistory(WidgetRef ref, RepoIdentity identity) {
  ref.read(repoSessionProvider(identity).notifier).refreshHistory();
}
