import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ref_snapshot.dart';
import 'repo_identity.dart';
import 'repo_session_repository.dart';

/// The branch/tag/HEAD domain, selected out of [repoSessionProvider] so
/// `features/sidebar` widgets rebuild only when refs actually change, not on
/// every graph or repo-state update. See the plan's Riverpod-layering note:
/// `data/repositories/*` owns FFI state, feature providers derive from it.
final ProviderFamily<RefSnapshot, RepoIdentity> repoRefsProvider = Provider.family<RefSnapshot, RepoIdentity>((
  ref,
  identity,
) {
  return ref.watch(repoSessionProvider(identity).select((state) => state.refs));
});

/// `git switch`/`git checkout`, delegating to the owning session's
/// controller. Not itself a provider -- called from widget event handlers
/// with a `WidgetRef` in hand, e.g. `checkoutBranch(ref, identity, name)`.
void checkoutBranch(
  WidgetRef ref,
  RepoIdentity identity,
  String target, {
  bool createBranch = false,
  String newBranchName = '',
}) {
  ref
      .read(repoSessionProvider(identity).notifier)
      .checkout(target: target, createBranch: createBranch, newBranchName: newBranchName);
}
