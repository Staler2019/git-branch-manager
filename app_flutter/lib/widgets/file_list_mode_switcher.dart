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
/// For read-only file lists with no staging/selection checkboxes --
/// `working_copy_board.dart`'s own tree rendering needs a tri-state folder
/// checkbox for bulk stage/unstage, so it builds `FileTreeList` directly
/// instead of going through this widget. Expand/collapse state is not
/// threaded through here at all: [FileTreeList] already owns and persists
/// it internally across rebuilds (see that widget's own `_expandedFolders`
/// State), so there is nothing for this wrapper to manage.
class FileListModeSwitcher<T> extends StatelessWidget {
  const FileListModeSwitcher({
    super.key,
    required this.mode,
    required this.items,
    required this.pathOf,
    required this.leafBuilder,
    this.emptyBuilder,
  });

  final FileListViewMode mode;
  final List<T> items;
  final String Function(T item) pathOf;
  final Widget Function(BuildContext context, T item) leafBuilder;
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
      selectedPaths: const <String>{},
      onFolderCheckStateChanged: (_) {}, // Read-only: no staging here.
      onItemBuilder:
          (
            BuildContext context,
            FileTreeNode node,
            int level,
            VoidCallback? onFolderToggle,
          ) {
            if (node.isDirectory) {
              return FileTreeFolderRow(node: node, onToggle: onFolderToggle);
            }
            final T? item = byPath[node.displayPath];
            return item == null
                ? const SizedBox.shrink()
                : leafBuilder(context, item);
          },
    );
  }
}
