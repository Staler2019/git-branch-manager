import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/ref_snapshot.dart';
import '../../data/models/remote_info.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';

/// What spec page 13's `MULTIBRANCHMENU` does to a multi-branch selection:
/// Fetch, Push, Compare, and the reasons the first two are unavailable.
///
/// Built fresh from the current selection at each call site rather than held
/// as state -- the selection is `SidebarPanel`'s, and a second stored copy of
/// it is the shape this repo keeps finding bugs in. Everything here is a pure
/// function of [selectedNames] plus what the providers say right now.
///
/// Delete is *not* here: spec page 13 requires a batch delete to be confirmed
/// item by item, so it opens a dialog and belongs with the panel's other
/// routing.
class BranchBulkActions {
  const BranchBulkActions({
    required this.ref,
    required this.identity,
    required this.selectedNames,
  });

  final WidgetRef ref;
  final RepoIdentity identity;
  final List<String> selectedNames;

  /// The selected branches that still exist in the ref snapshot, as
  /// [RefInfo] rather than bare names -- Fetch and Push both need each
  /// branch's `upstream` to work out which remote it belongs to.
  List<RefInfo> selectedRefs() {
    final RefSnapshot refs = ref.read(repoRefsProvider(identity));
    final Set<String> names = selectedNames.toSet();
    return <RefInfo>[
      for (final RefInfo b in refs.localBranches)
        if (names.contains(b.shortName)) b,
    ];
  }

  /// Groups [branches] by the remote their upstream lives on.
  ///
  /// `RefInfo.upstream` is the **full** ref name (`%(upstream)`, e.g.
  /// `refs/remotes/origin/main`), so the remote comes from
  /// [remoteBranchParts] -- never from splitting on the first slash, which
  /// yields `"refs"` and is the live bug #74 records in
  /// `delete_branch_dialog.dart`. `upstream.isEmpty` is the "no upstream"
  /// test, **not** `hasTrackingInfo`: the latter mirrors
  /// `%(upstream:track)`, which is an empty string for a branch exactly in
  /// sync with its upstream (the Tier 0c trap).
  Map<String, List<RefInfo>> groupByUpstreamRemote(List<RefInfo> branches) {
    final Map<String, List<RefInfo>> byRemote = <String, List<RefInfo>>{};
    for (final RefInfo b in branches) {
      if (b.upstream.isEmpty) continue;
      final (String remote, String _) = remoteBranchParts(b.upstream);
      if (remote.isEmpty) continue;
      byRemote.putIfAbsent(remote, () => <RefInfo>[]).add(b);
    }
    return byRemote;
  }

  /// MULTIBRANCHMENU's `Fetch N branches`.
  ///
  /// Spec page 13 says nothing about which remote a multi-branch fetch
  /// targets, so the rule here is the only one that needs no guessing: a
  /// branch is fetched through the remote its own upstream names. One
  /// `gbm_remote_fetch` call per distinct remote, each carrying that
  /// remote's refspecs -- `gbm_capi.h` rejects a non-empty `refs` with an
  /// empty `remoteName`, so a single batched call is not available, and a
  /// selection spanning two remotes is genuinely two fetches.
  ///
  /// A branch with no upstream has no remote-tracking ref to update and is
  /// skipped; when *none* of the selection has one, the menu row is
  /// disabled with [fetchBlockedReason] rather than silently doing nothing.
  void fetch() {
    final Map<String, List<RefInfo>> byRemote = groupByUpstreamRemote(
      selectedRefs(),
    );
    final RepoSessionController session = ref.read(
      repoSessionProvider(identity).notifier,
    );
    byRemote.forEach((String remote, List<RefInfo> branches) {
      session.fetchRemote(
        remoteName: remote,
        refs: <String>[
          for (final RefInfo b in branches) remoteBranchParts(b.upstream).$2,
        ],
      );
    });
  }

  /// MULTIBRANCHMENU's `Push N branches`.
  ///
  /// Published branches go to the remote their upstream names, one
  /// `gbm_push` per remote -- and because `gbm_push` now takes a branch
  /// list, that is one `git push <remote> a b c` per remote rather than one
  /// per branch, which is what keeps a same-remote batch a single
  /// background task (spec page 10).
  ///
  /// Unpublished branches (spec's `local` badge state, "還沒 push 過…Push
  /// 後 badge 自動消失") are the case Push exists for, but they name no
  /// remote. They are pushed to the repository's sole remote with
  /// `--set-upstream` when there is exactly one; with several remotes there
  /// is nothing to infer from, so they are excluded and the row explains
  /// that via [pushBlockedReason]. They are also kept in their own call
  /// rather than folded into a same-remote published group: `push -u` would
  /// otherwise repoint a branch that tracks a differently-named upstream.
  void push() {
    final List<RefInfo> selected = selectedRefs();
    final Map<String, List<RefInfo>> byRemote = groupByUpstreamRemote(selected);
    final List<RefInfo> unpublished = <RefInfo>[
      for (final RefInfo b in selected)
        if (b.upstream.isEmpty) b,
    ];
    final RepoSessionController session = ref.read(
      repoSessionProvider(identity).notifier,
    );
    byRemote.forEach((String remote, List<RefInfo> branches) {
      session.pushChanges(
        remoteName: remote,
        branches: <String>[for (final RefInfo b in branches) b.shortName],
      );
    });
    final String? sole = soleRemoteName();
    if (unpublished.isNotEmpty && sole != null) {
      session.pushChanges(
        remoteName: sole,
        branches: <String>[for (final RefInfo b in unpublished) b.shortName],
        setUpstream: true,
      );
    }
  }

  /// The repository's only remote, or null when it has none or several.
  String? soleRemoteName() {
    final List<RemoteInfo> remotes = ref
        .read(repoSessionProvider(identity))
        .remotes;
    return remotes.length == 1 ? remotes.single.name : null;
  }

  /// Why `Fetch N branches` is off, or null when it is available.
  String? fetchBlockedReason() => groupByUpstreamRemote(selectedRefs()).isEmpty
      ? 'None of the selected branches has an upstream to fetch from'
      : null;

  /// Why `Push N branches` is off, or null when it is available. See [push]
  /// for why an unpublished branch needs a sole remote.
  String? pushBlockedReason() {
    final List<RefInfo> selected = selectedRefs();
    final bool anyPublished = groupByUpstreamRemote(selected).isNotEmpty;
    final bool anyUnpublished = selected.any((RefInfo b) => b.upstream.isEmpty);
    if (anyUnpublished && soleRemoteName() == null) {
      return anyPublished
          ? 'Some selected branches have no upstream, and this repository '
                'has no single remote to push them to'
          : 'The selected branches have no upstream, and this repository '
                'has no single remote to push them to';
    }
    return anyPublished || anyUnpublished ? null : 'Nothing to push';
  }

  /// COMPARES 1: 「同時選兩個分支 → 右鍵 Compare」. Both sides are known, so
  /// unlike 05-B's single-branch "Compare with…" this fills the tab
  /// outright instead of leaving the right to the ref picker.
  void compare(BuildContext context) {
    if (selectedNames.length != 2) return;
    final String repoId = Uri.encodeComponent(identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(identity).notifier)
        .open(left: selectedNames.first, right: selectedNames.last);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }
}
