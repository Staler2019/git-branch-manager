/// Represents a single node in the file tree.
///
/// A node can be a file or directory. Directory nodes can have children.
/// Single-child folders are automatically collapsed during tree construction.
///
/// A tri-state `CheckState` and a `getCheckState()` on both this and [FileTree]
/// were deleted along with the Working Copy board's checkboxes: no surface
/// under `lib/` ever called either one. [getAllLeafPaths] stayed, because the
/// board's folder drag really does need every leaf under a folder.
class FileTreeNode {
  /// Creates a file tree node.
  const FileTreeNode({
    required this.name,
    required this.displayPath,
    required this.isDirectory,
    this.children = const [],
  });

  /// The display name of this node (just the last segment or collapsed path).
  final String name;

  /// The root-anchored path of this node, including collapsed segments.
  ///
  /// For a file it is the path it was built from. For a folder it is
  /// `<parent's displayPath>/<name>` -- so a folder deep in the tree names
  /// itself from the root even though [name] draws only its own (possibly
  /// concatenated) label. `FileTreeList` uses it as the expand/collapse key,
  /// which is why it must be unique across the whole tree.
  final String displayPath;

  /// Whether this node represents a directory.
  final bool isDirectory;

  /// The child nodes of this node (empty if this is a file).
  final List<FileTreeNode> children;

  /// Returns all leaf (file) paths under this node.
  ///
  /// If this is a file node, returns a list containing only its displayPath.
  /// If this is a directory node, returns all leaf paths from all descendants.
  List<String> getAllLeafPaths() {
    if (!isDirectory) {
      return [displayPath];
    }

    final result = <String>[];
    for (final child in children) {
      result.addAll(child.getAllLeafPaths());
    }
    return result;
  }
}

/// The root of a file tree, typically constructed from a flat list of paths.
class FileTree {
  /// Creates a file tree with the given children.
  const FileTree({this.children = const []});

  /// The top-level children of this tree (files and/or directories).
  final List<FileTreeNode> children;

  /// Creates a file tree from a flat list of file paths.
  ///
  /// Single-child folders are automatically collapsed:
  /// For example, if files exist at:
  /// - lib/app/views/a.dart
  /// - lib/app/views/b.dart
  ///
  /// And lib -> app -> views are all single-child folders,
  /// they will be collapsed into a single display path "lib/app/views".
  factory FileTree.fromPaths(List<String> paths) {
    if (paths.isEmpty) {
      return const FileTree();
    }

    // Build raw tree structure first
    final rootChildren = <String, _TreeNodeData>{};

    for (final path in paths) {
      final segments = path.split('/');
      _insertPath(rootChildren, segments, 0, path);
    }

    // Convert to FileTreeNode with collapsing
    final displayedChildren = _buildDisplayNodes(rootChildren, '');

    return FileTree(children: displayedChildren);
  }

  /// Returns all leaf (file) paths in this tree.
  List<String> getAllLeafPaths() {
    final result = <String>[];
    for (final child in children) {
      result.addAll(child.getAllLeafPaths());
    }
    return result;
  }
}

/// Internal data structure for building the tree before collapsing.
class _TreeNodeData {
  final String? leafPath; // non-null if this is a leaf (file)
  final Map<String, _TreeNodeData> children;

  _TreeNodeData({this.leafPath, Map<String, _TreeNodeData>? children})
    : children = children ?? {};

  bool get isLeaf => leafPath != null;
}

/// Inserts a file path into the tree structure.
void _insertPath(
  Map<String, _TreeNodeData> nodes,
  List<String> segments,
  int index,
  String fullPath,
) {
  if (index >= segments.length) {
    return;
  }

  final segment = segments[index];
  final isLastSegment = index == segments.length - 1;

  if (!nodes.containsKey(segment)) {
    if (isLastSegment) {
      nodes[segment] = _TreeNodeData(leafPath: fullPath);
    } else {
      nodes[segment] = _TreeNodeData();
    }
  }

  if (!isLastSegment) {
    _insertPath(nodes[segment]!.children, segments, index + 1, fullPath);
  }
}

/// Converts internal tree structure to display nodes with collapsing.
///
/// [parentPath] is the root-anchored path of the folder these nodes sit in,
/// empty at the top level. It exists so a folder's [FileTreeNode.displayPath]
/// names it from the root -- see [_collapseIfSingleChild].
List<FileTreeNode> _buildDisplayNodes(
  Map<String, _TreeNodeData> nodeMap,
  String parentPath,
) {
  return nodeMap.entries.map((entry) {
    return _buildDisplayNode(entry.key, entry.value, parentPath);
  }).toList();
}

/// Builds a single display node, collapsing single-child paths as needed.
FileTreeNode _buildDisplayNode(
  String name,
  _TreeNodeData data,
  String parentPath,
) {
  if (data.isLeaf) {
    // Leaf node (file)
    return FileTreeNode(
      name: name,
      displayPath: data.leafPath!,
      isDirectory: false,
      children: const [],
    );
  }

  // Directory node - try to collapse single-child path
  final collapsed = _collapseIfSingleChild(name, data, parentPath);
  return collapsed;
}

/// Recursively collapses single-child directories into a single display path.
///
/// [label] is what the row draws -- the folder's own name, with any collapsed
/// chain concatenated onto it. [parentPath] is where that row sits, so the
/// node's `displayPath` is `parentPath/label` and therefore unique across the
/// whole tree: `FileTreeList` keys expand/collapse on it, and two `features`
/// folders under different parents opened and closed together while it was
/// only the prefix accumulated from this level down.
FileTreeNode _collapseIfSingleChild(
  String label,
  _TreeNodeData data,
  String parentPath,
) {
  // Collapse only while the single child is itself a **folder**.
  //
  // 使用者裁定（2026-09-05）:「樹狀模式下，我想要的是像 vscode 一樣，
  // folder 可以堆疊名稱，但是檔案不會有 folder」—— VS Code's own
  // `explorer.compactFolders` compacts a chain of folders and stops at the
  // file, so a file row always draws a bare basename under a real folder row.
  //
  // ~~This used to collapse through a *file* child too, keeping the whole
  // chain in `name`~~ — that shipped, and it is what the ruling overturns:
  // `docs/ledger/x.md` + `docs/rules/y.md` drew `docs` with two rows reading
  // `ledger/x.md` and `rules/y.md`, so folding the tree cost indentation and
  // bought nothing. Spec P03 item 10's own example
  // (「只有一個子項的資料夾會自動串接成 lib/app/views 一列」) is a chain of
  // *folders* and is untouched by this — what is retired is the previous
  // round's extension of it to a file child, not the spec's own case.
  if (data.children.length == 1 && data.leafPath == null) {
    final entry = data.children.entries.single;
    final childData = entry.value;

    // Never recurse into a leaf: `_collapseIfSingleChild` would take its
    // bottom branch and hand back an empty *directory* named after the file,
    // dropping the file out of the tree and out of [getAllLeafPaths].
    if (!childData.isLeaf) {
      return _collapseIfSingleChild(
        '$label/${entry.key}',
        childData,
        parentPath,
      );
    }
  }

  // Cannot collapse further - build children normally
  final String fullPath = parentPath.isEmpty ? label : '$parentPath/$label';
  final children = _buildDisplayNodes(data.children, fullPath);

  return FileTreeNode(
    name: label,
    displayPath: fullPath,
    isDirectory: true,
    children: children,
  );
}
