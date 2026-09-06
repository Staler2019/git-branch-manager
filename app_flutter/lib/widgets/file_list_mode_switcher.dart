import 'package:flutter/material.dart';

import '../data/models/file_tree.dart';
import '../data/repositories/file_list_view_mode_repository.dart';
import 'file_tree_folder_row.dart';
import 'file_tree_list.dart';

/// Switches a flat file list between List and Tree display modes, per
/// [mode] (read from the shared [fileListViewModeProvider] by each caller --
/// spec page 03 item 10: "同一個設定套用到 Working Copy 兩欄、History 的
/// Changed files、Compare 的 Files、以及 Conflict 視窗的檔案清單"). List
/// mode renders the flat list [leafBuilder] would have produced on its own,
/// labelled with each item's whole path; tree mode groups by folder via
/// [FileTree.fromPaths], renders folders with [FileTreeFolderRow], and
/// labels each leaf with only the segment its folder rows have not already
/// written. See [leafBuilder] for why the label is passed in.
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

  /// Builds one file row. `label` is **what the row should draw as its
  /// name**, and it differs by mode -- the whole path in list mode, and in
  /// tree mode only the part the folder rows above have not already said.
  ///
  /// It is a parameter rather than something each caller derives because a
  /// leaf has no way to know its own depth: the builder is handed the item
  /// `T`, and `T` is a `DiffFile` or a `WorkingCopyEntry` carrying one
  /// string. Every one of the six call sites therefore drew `item.path` in
  /// both modes, which made tree mode repeat under each folder row exactly
  /// the prefix that row had just written, and left the two modes drawing
  /// identical text. Spec P03 item 10 is explicit that 「平鋪完整路徑」 is
  /// the *list* mode's definition: 「每個檔案清單標題右側一組兩鍵切換：
  /// 平鋪完整路徑，或依資料夾摺成樹狀」.
  final Widget Function(BuildContext context, T item, String label) leafBuilder;

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
            // List mode is 「平鋪完整路徑」, so the label *is* the path.
            leafBuilder(context, items[index], pathOf(items[index])),
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
            // `node.name`, not `node.displayPath`: the folder rows above
            // this leaf already carry the prefix, and a file's `name` is
            // always its bare basename. ~~The second half of this comment
            // used to say `name` carries the whole collapsed chain for a
            // leaf its folders collapsed into~~ -- that case no longer
            // exists: 使用者裁定（2026-09-05）「檔案不會有 folder」, so
            // `_collapseIfSingleChild` (`file_tree.dart`) stops at the
            // folder and every file has a real folder row above it.
            return item == null
                ? const SizedBox.shrink()
                : leafBuilder(context, item, node.name);
          },
    );
  }
}
