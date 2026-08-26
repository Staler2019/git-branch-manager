import 'package:flutter/material.dart';

import '../data/models/file_tree.dart';
import '../data/repositories/file_list_view_mode_repository.dart';

/// Callback type for rendering a single file/folder row.
///
/// [node] is the tree node being rendered
/// [level] is the indentation level (0 for root)
/// [onFolderToggle] is non-null only for folder nodes and expands/collapses them
typedef FileTreeListItemBuilder =
    Widget Function(
      BuildContext context,
      FileTreeNode node,
      int level,
      VoidCallback? onFolderToggle,
    );

/// A widget that renders a file tree in either list mode (flat) or tree mode
/// (hierarchical with collapsible folders).
///
/// In list mode, all leaf nodes (files) are rendered in a flat list.
/// In tree mode, folders are displayed as collapsible nodes with indentation.
/// The caller provides a builder callback to customize how each node is rendered.
class FileTreeList extends StatefulWidget {
  const FileTreeList({
    required this.fileTree,
    required this.mode,
    required this.onItemBuilder,
    this.expandedFolders = const {},
    super.key,
  });

  /// The file tree to display.
  final FileTree fileTree;

  /// Current view mode: list (flat) or tree (hierarchical).
  final FileListViewMode mode;

  /// Builder callback for rendering each node.
  /// The callback receives the node, indentation level, and optionally
  /// a folder toggle callback for collapsible behavior.
  final FileTreeListItemBuilder onItemBuilder;

  /// Set of folder paths that are currently expanded (tree mode).
  final Set<String> expandedFolders;

  @override
  State<FileTreeList> createState() => _FileTreeListState();
}

class _FileTreeListState extends State<FileTreeList> {
  late Set<String> _expandedFolders;

  @override
  void initState() {
    super.initState();
    _expandedFolders = Set<String>.from(widget.expandedFolders);
  }

  @override
  void didUpdateWidget(FileTreeList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandedFolders != widget.expandedFolders) {
      _expandedFolders = Set<String>.from(widget.expandedFolders);
    }
  }

  void _toggleFolder(String folderPath) {
    setState(() {
      if (_expandedFolders.contains(folderPath)) {
        _expandedFolders.remove(folderPath);
      } else {
        _expandedFolders.add(folderPath);
      }
    });
  }

  List<Widget> _buildListItems(List<FileTreeNode> nodes, int level) {
    final items = <Widget>[];

    for (final node in nodes) {
      if (widget.mode == FileListViewMode.list) {
        // In list mode, only render leaf nodes (files)
        if (!node.isDirectory) {
          items.add(
            widget.onItemBuilder(
              context,
              node,
              level,
              null, // No folder toggle in list mode
            ),
          );
        } else {
          // Recursively render children of directories
          items.addAll(_buildListItems(node.children, level + 1));
        }
      } else {
        // In tree mode, render both folders and files with indentation
        items.add(
          Padding(
            padding: EdgeInsets.only(left: level * 16.0),
            child: widget.onItemBuilder(
              context,
              node,
              level,
              node.isDirectory ? () => _toggleFolder(node.displayPath) : null,
            ),
          ),
        );

        // If this is an expanded folder, render its children
        if (node.isDirectory && _expandedFolders.contains(node.displayPath)) {
          items.addAll(_buildListItems(node.children, level + 1));
        }
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildListItems(widget.fileTree.children, 0);

    return ListView(children: items);
  }
}
