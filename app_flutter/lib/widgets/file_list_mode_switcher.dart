import 'package:flutter/material.dart';

import '../data/models/file_tree.dart';
import '../data/repositories/file_list_view_mode_repository.dart';
import 'file_tree_folder_row.dart';
import 'file_tree_list.dart';

/// Switches a flat file list between List and Tree display modes, per
/// [mode] (read from the shared [fileListViewModeProvider] by each caller --
/// spec page 03 item 10: "同一個設定套用到 Working Copy 兩欄、History 的
/// Changed files、Compare 的 Files、以及 Conflict 視窗的檔案清單"). List
/// mode renders exactly the flat list [leafBuilder] would have produced on
/// its own; tree mode groups by folder via [FileTree.fromPaths] and renders
/// folders with [FileTreeFolderRow].
///
/// Folder rows default to the read-only [FileTreeFolderRow]; a list whose
/// folders are themselves actionable passes [folderBuilder] to wrap or
/// replace that row (`working_copy_board.dart` makes each folder a
/// `Draggable` carrying every leaf underneath it). Before the Working Copy
/// board dropped its checkboxes it could not use this widget at all -- it
/// needed a tri-state folder checkbox and so built [FileTreeList] by hand,
/// duplicating both list and tree rendering.
///
/// Expand/collapse state is not threaded through here at all: [FileTreeList]
/// already owns and persists it internally across rebuilds (see that
/// widget's own `_expandedFolders` State), so there is nothing for this
/// wrapper to manage.
class FileListModeSwitcher<T> extends StatelessWidget {
  const FileListModeSwitcher({
    super.key,
    required this.mode,
    required this.items,
    required this.pathOf,
    required this.leafBuilder,
    this.folderBuilder,
    this.emptyBuilder,
  });

  final FileListViewMode mode;
  final List<T> items;
  final String Function(T item) pathOf;
  final Widget Function(BuildContext context, T item) leafBuilder;

  /// Builds a folder row in tree mode. Null renders [FileTreeFolderRow],
  /// which is what every read-only list wants; a staging list overrides it
  /// to attach folder-level affordances.
  final Widget Function(
    BuildContext context,
    FileTreeNode node,
    VoidCallback? onToggle,
  )?
  folderBuilder;

  final WidgetBuilder? emptyBuilder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return emptyBuilder?.call(context) ?? const SizedBox.shrink();
    }

    if (mode == FileListViewMode.list) {
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (BuildContext context, int index) =>
            leafBuilder(context, items[index]),
      );
    }

    final Map<String, T> byPath = <String, T>{
      for (final T item in items) pathOf(item): item,
    };
    final FileTree tree = FileTree.fromPaths(
      items.map(pathOf).toList(growable: false),
    );

    return FileTreeList(
      fileTree: tree,
      mode: mode,
      onItemBuilder:
          (
            BuildContext context,
            FileTreeNode node,
            int level,
            VoidCallback? onFolderToggle,
          ) {
            if (node.isDirectory) {
              return folderBuilder?.call(context, node, onFolderToggle) ??
                  FileTreeFolderRow(node: node, onToggle: onFolderToggle);
            }
            final T? item = byPath[node.displayPath];
            return item == null
                ? const SizedBox.shrink()
                : leafBuilder(context, item);
          },
    );
  }
}
