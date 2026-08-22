import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ref_snapshot.dart';
import '../../data/repositories/branch_filter_repository.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../sidebar/branch_tree_builder.dart';

/// How long the dispatcher waits after the last keystroke before starting a
/// walk. Long enough that typing a branch name is one `git rev-list` rather
/// than one per character, short enough to feel immediate.
const Duration kHistoryFilterDebounce = Duration(milliseconds: 250);

/// What the History graph asks `gbm_history_set_filter` for.
///
/// A value rather than three loose arguments so the dispatcher can compare it
/// against the last request it sent and skip an identical one — an unrelated
/// rebuild must not restart a history walk.
class HistoryFilterRequest {
  const HistoryFilterRequest({
    required this.includeRefs,
    required this.firstParentOnly,
    required this.noMerges,
  });

  /// The unfiltered walk: every ref, merges and parallel lanes included.
  static const HistoryFilterRequest none = HistoryFilterRequest(
    includeRefs: <String>[],
    firstParentOnly: false,
    noMerges: false,
  );

  /// Full ref names ('refs/heads/main'), never short ones — see
  /// gbm_history_set_filter()'s doc comment.
  final List<String> includeRefs;
  final bool firstParentOnly;
  final bool noMerges;

  @override
  bool operator ==(Object other) =>
      other is HistoryFilterRequest &&
      other.firstParentOnly == firstParentOnly &&
      other.noMerges == noMerges &&
      other.includeRefs.length == includeRefs.length &&
      _sameRefs(other.includeRefs);

  bool _sameRefs(List<String> other) {
    for (int i = 0; i < includeRefs.length; i++) {
      if (other[i] != includeRefs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(includeRefs), firstParentOnly, noMerges);

  @override
  String toString() =>
      'HistoryFilterRequest(${includeRefs.join(',')}, '
      'firstParentOnly: $firstParentOnly, noMerges: $noMerges)';
}

/// The graph's response to the sidebar's branch filter (spec P02-14).
///
/// The user's ruling, verbatim: 「只有一個分支：我要有 no merge 的效果，但是不會
/// 有平行線。兩分支以上，就照目前狀態顯示」. So **exactly one** match converges
/// the graph to a single line with no merge rows; anything else — no query, no
/// match, or two matches and up — is the ordinary walk.
///
/// Deliberately *not* driven by `branchSelectionProvider`: that selection
/// exists for Fetch/Push/Delete, and having it redraw the whole graph would be
/// a surprise. The filter is the thing the user typed to change what they are
/// looking at.
///
/// [branches] must be the merged local ∪ remote-only list the sidebar renders
/// (`mergeLocalAndRemoteBranches`), so a remote-only row counts as a branch
/// exactly as it looks on screen.
HistoryFilterRequest historyFilterFor(List<RefInfo> branches, String query) {
  if (query.trim().isEmpty) return HistoryFilterRequest.none;

  final List<RefInfo> matches = filterBranches(branches, query);
  if (matches.length != 1) return HistoryFilterRequest.none;

  // fullName, never shortName: mergeLocalAndRemoteBranches strips the
  // '<remote>/' prefix off a remote-only row's shortName so it groups with a
  // same-named local branch, so 'origin/main' arrives here as 'main' and
  // would resolve to the wrong ref — or to none at all. Same class of bug as
  // delete_branch_dialog.dart's first-slash split (#74).
  return HistoryFilterRequest(
    includeRefs: <String>[matches.first.fullName],
    firstParentOnly: true,
    noMerges: true,
  );
}

/// [historyFilterFor] applied to the live refs and the live filter box.
///
/// Derived rather than pushed from `SidebarPanel`, so it holds whether or not
/// the sidebar is on screen — which is the whole reason the query moved into
/// [branchFilterQueryProvider]. `WorkspaceScreen` is what listens and
/// dispatches; see its `_dispatchHistoryFilter`.
final ProviderFamily<HistoryFilterRequest, RepoIdentity>
historyFilterRequestProvider =
    Provider.family<HistoryFilterRequest, RepoIdentity>((ref, identity) {
      final RefSnapshot refs = ref.watch(repoRefsProvider(identity));
      return historyFilterFor(
        mergeLocalAndRemoteBranches(refs.localBranches, refs.remoteBranches),
        ref.watch(branchFilterQueryProvider(identity)),
      );
    });
