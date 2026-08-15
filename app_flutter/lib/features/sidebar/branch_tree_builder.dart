import 'package:gbm_flutter/data/models/ref_snapshot.dart';

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

/// Filters [branches] to those whose [RefInfo.shortName] contains [query]
/// as a case-insensitive substring (Cmd/Ctrl+Shift+E "Filter branches", see
/// gbm_action_id.dart's `editFilterBranches`). Matching is flat against the
/// full slash-delimited name (e.g. 'docs' matches 'chore/docs'), independent
/// of [buildBranchTree]'s folder grouping -- callers building a filtered
/// tree should pass the filtered list into [buildBranchTree] afterward.
///
/// A blank (empty or whitespace-only) [query] returns [branches] unchanged.
List<RefInfo> filterBranches(List<RefInfo> branches, String query) {
  final String trimmed = query.trim();
  if (trimmed.isEmpty) {
    return branches;
  }
  final String needle = trimmed.toLowerCase();
  return branches
      .where((ref) => ref.shortName.toLowerCase().contains(needle))
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
