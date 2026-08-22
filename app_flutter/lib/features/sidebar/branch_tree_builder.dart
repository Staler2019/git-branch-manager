import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'branch_filter.dart';

/// Base class for a node in the branch tree (folder or leaf).
sealed class BranchTreeNode {
  const BranchTreeNode();
}

/// A folder node containing zero or more child nodes.
final class BranchTreeFolder extends BranchTreeNode {
  const BranchTreeFolder({
    required this.folderName,
    required this.children,
    required this.isExpanded,
  });

  /// Display name of the folder (e.g., 'feature' from 'feature/auth').
  final String folderName;

  /// Child nodes (folders or leaves).
  final List<BranchTreeNode> children;

  /// Whether this folder is currently expanded in the UI.
  final bool isExpanded;
}

/// A leaf node representing an actual branch ref.
final class BranchTreeLeaf extends BranchTreeNode {
  const BranchTreeLeaf({required this.ref});

  /// The underlying branch reference.
  final RefInfo ref;
}

/// Builds a hierarchical tree from a flat list of branch refs, grouping by
/// common path prefixes (e.g., 'feature/auth' and 'feature/dark-mode' both
/// group under a 'feature' folder).
///
/// Each path segment separated by '/' becomes a folder level. Single-segment
/// names (no '/') appear as leaf nodes at the root.
///
/// [expandedFolders] is a set of folder path strings (e.g., 'feature',
/// 'feature/sub') that should be expanded; folders not in this set are
/// collapsed by default.
///
/// Returns an immutable list of root-level nodes, ordered by branch name.
List<BranchTreeNode> buildBranchTree(
  List<RefInfo> branches,
  Set<String> expandedFolders,
) {
  if (branches.isEmpty) {
    return const <BranchTreeNode>[];
  }

  // Map from folder path (e.g. 'feature', 'feature/sub') to its children
  final Map<String, _FolderNode> folderIndex = {};

  // Root-level nodes (both folders and direct leaves)
  final Map<String, BranchTreeNode> rootNodes = {};

  for (final ref in branches) {
    final parts = ref.shortName.split('/');

    if (parts.length == 1) {
      // No nesting -- direct leaf at root
      rootNodes[ref.shortName] = BranchTreeLeaf(ref: ref);
    } else {
      // Build or navigate the tree for all but the last segment
      String currentPath = '';
      for (int i = 0; i < parts.length - 1; i++) {
        final segment = parts[i];
        final previousPath = currentPath;
        currentPath = currentPath.isEmpty ? segment : '$currentPath/$segment';

        if (!folderIndex.containsKey(currentPath)) {
          final folder = _FolderNode(
            folderName: segment,
            folderPath: currentPath,
            isExpanded: expandedFolders.contains(currentPath),
          );
          folderIndex[currentPath] = folder;

          // Add to parent (or root)
          if (previousPath.isEmpty) {
            rootNodes[currentPath] = folder;
          } else {
            folderIndex[previousPath]!.children.add(folder);
          }
        }
      }

      // Add the leaf to its immediate parent folder
      final leaf = BranchTreeLeaf(ref: ref);
      folderIndex[currentPath]!.children.add(leaf);
    }
  }

  // Convert _FolderNode to BranchTreeFolder and sort
  final List<BranchTreeNode> result = rootNodes.values.map((node) {
    if (node is _FolderNode) {
      return _folderNodeToTree(node);
    }
    return node;
  }).toList();

  // Sort by folder/branch name (folders before leaves, each group sorted)
  result.sort(_compareTreeNodes);

  return result.toList(growable: false);
}

/// Splits a remote branch's [RefInfo.fullName]
/// (`refs/remotes/<remote>/<branch>`) into its remote name and the branch
/// name as it exists on the remote (no remote prefix) -- the inverse of what
/// [mergeLocalAndRemoteBranches] does to a remote-only leaf's `shortName`
/// for tree grouping. Used wherever an action needs the remote name back
/// (checkout-as-new-local, prune this ref, delete on remote).
(String remote, String branch) remoteBranchParts(String fullName) {
  const String prefix = 'refs/remotes/';
  final String rest = fullName.startsWith(prefix)
      ? fullName.substring(prefix.length)
      : fullName;
  final int slash = rest.indexOf('/');
  if (slash < 0) return (rest, '');
  return (rest.substring(0, slash), rest.substring(slash + 1));
}

/// Merges [localBranches] with the subset of [remoteBranches] that has no
/// local branch tracking it ("remote-only", Flutter Desktop Spec's
/// `BRANCH_STATES` "Remote only（未 checkout）") into one flat list ready for
/// [buildBranchTree] -- spec page 02 items 4/12: "Local 與 remote 不再分兩
/// 段，同一條分支只出現一次". A local branch's [RefInfo.upstream] is git's
/// `%(upstream)` output, the tracked ref's *full* name
/// (`refs/remotes/origin/main`, confirmed against real `git for-each-ref`
/// output, not `%(upstream:short)`), so it's matched directly against a
/// remote branch's [RefInfo.fullName]. A matched remote branch is dropped --
/// the local leaf already represents it. An unmatched one is kept with its
/// `shortName` rewritten to drop the leading `<remote>/` segment (recover it
/// with [remoteBranchParts] on `fullName`) so it groups into the same folder
/// a same-named local branch would, since [buildBranchTree] groups by
/// `shortName.split('/')`. Symbolic remote refs (`origin/HEAD`) are excluded
/// -- not a real branch to show or check out.
List<RefInfo> mergeLocalAndRemoteBranches(
  List<RefInfo> localBranches,
  List<RefInfo> remoteBranches,
) {
  final Set<String> trackedUpstreams = localBranches
      .map((b) => b.upstream)
      .where((u) => u.isNotEmpty)
      .toSet();

  final List<RefInfo> remoteOnly = remoteBranches
      .where((r) => !r.isSymbolic && !trackedUpstreams.contains(r.fullName))
      .map(
        (r) => RefInfo(
          fullName: r.fullName,
          shortName: remoteBranchParts(r.fullName).$2,
          kind: r.kind,
          target: r.target,
          upstream: r.upstream,
          ahead: r.ahead,
          behind: r.behind,
          hasTrackingInfo: r.hasTrackingInfo,
          isGone: r.isGone,
          isHead: r.isHead,
          isSymbolic: r.isSymbolic,
          worktreePath: r.worktreePath,
        ),
      )
      .toList(growable: false);

  return <RefInfo>[...localBranches, ...remoteOnly];
}

/// Filters [branches] to those whose [RefInfo.shortName] matches [query]
/// under [matchesBranchFilter] (Cmd/Ctrl+Shift+E "Filter branches", see
/// gbm_action_id.dart's `editFilterBranches`). Matching is flat against the
/// full slash-delimited name (e.g. 'docs' matches 'chore/docs'), independent
/// of [buildBranchTree]'s folder grouping -- callers building a filtered
/// tree should pass the filtered list into [buildBranchTree] afterward.
///
/// This used to inline a bare `contains`, which failed spec P02-14's own
/// worked example; the rule now lives in `branch_filter.dart` because tags
/// and stashes are filtered by the same box and must share it.
///
/// A blank (empty or whitespace-only) [query] returns [branches] unchanged.
List<RefInfo> filterBranches(List<RefInfo> branches, String query) {
  if (query.trim().isEmpty) {
    return branches;
  }
  return branches
      .where((ref) => matchesBranchFilter(ref.shortName, query))
      .toList(growable: false);
}

/// Internal representation of a folder node being built.
class _FolderNode extends BranchTreeNode {
  _FolderNode({
    required this.folderName,
    required this.folderPath,
    required this.isExpanded,
  });

  final String folderName;
  final String folderPath;
  final bool isExpanded;
  final List<BranchTreeNode> children = <BranchTreeNode>[];
}

/// Recursively converts a _FolderNode to a BranchTreeFolder.
BranchTreeFolder _folderNodeToTree(_FolderNode node) {
  final convertedChildren = node.children.map((child) {
    if (child is _FolderNode) {
      return _folderNodeToTree(child);
    }
    return child;
  }).toList();

  convertedChildren.sort(_compareTreeNodes);

  return BranchTreeFolder(
    folderName: node.folderName,
    children: convertedChildren.toList(growable: false),
    isExpanded: node.isExpanded,
  );
}

/// Comparison function for sorting tree nodes: folders first (alphabetically),
/// then leaves (alphabetically).
int _compareTreeNodes(BranchTreeNode a, BranchTreeNode b) {
  final aIsFolder = a is BranchTreeFolder;
  final bIsFolder = b is BranchTreeFolder;

  if (aIsFolder && !bIsFolder) return -1;
  if (!aIsFolder && bIsFolder) return 1;

  final aName = switch (a) {
    BranchTreeFolder(:final folderName) => folderName,
    BranchTreeLeaf(:final ref) => ref.shortName,
    _FolderNode(:final folderName) => folderName,
  };

  final bName = switch (b) {
    BranchTreeFolder(:final folderName) => folderName,
    BranchTreeLeaf(:final ref) => ref.shortName,
    _FolderNode(:final folderName) => folderName,
  };

  return aName.compareTo(bName);
}

/// What 05-J's "Fetch branches in folder" needs to call
/// `RepoSessionController.fetchRemote(remoteName:, refs:)`: the single
/// remote every fetchable branch in [refs] tracks, and the branch names
/// (as they exist on that remote, no prefix) to fetch. A local branch
/// with no configured upstream contributes nothing (there is no remote
/// ref for it to fetch). Returns null when there is nothing fetchable, or
/// when the branches present track more than one distinct remote --
/// `gbm_remote_fetch()` targets exactly one remote per call, and picking
/// one over another silently would fetch less than the user asked for.
(String remote, List<String> branches)? fetchableRefsInFolder(
  List<RefInfo> refs,
) {
  final Map<String, List<String>> byRemote = <String, List<String>>{};
  for (final RefInfo ref in refs) {
    final String upstream = ref.kind == RefKind.remoteBranch
        ? ref.fullName
        : ref.upstream;
    if (upstream.isEmpty) continue;
    final (String remote, String branch) = remoteBranchParts(upstream);
    if (remote.isEmpty || branch.isEmpty) continue;
    (byRemote[remote] ??= <String>[]).add(branch);
  }
  if (byRemote.length != 1) return null;
  final MapEntry<String, List<String>> only = byRemote.entries.single;
  return (only.key, only.value);
}
