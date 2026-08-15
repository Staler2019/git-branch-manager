import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/file_tree.dart';
import '../../../data/models/working_copy_status.dart';
import '../../../data/repositories/file_list_view_mode_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/file_tree_list.dart';
import '../../../widgets/split_pane.dart';
import '../working_copy_selection_state.dart';

/// A two-column drag-and-drop board for staging/unstaging files in working copy.
///
/// Left column: unstaged files
/// Right column: staged files
///
/// Features:
/// - Drag files between columns to stage/unstage
/// - Click to select single file
/// - Ctrl/Cmd+click for accumulative selection
/// - Shift+click for range selection
/// - Shift+Ctrl/Cmd+click to extend range
/// - Column header checkbox for select-all/deselect-all
/// - Tri-state checkbox reflecting partial selection
/// - Optional file activation callback (for diff view selection)
/// - Optional row widget wrapper for context menus
/// - List/Tree display mode toggle
///
/// This is a presentational widget with no Riverpod dependencies.
/// All stage/unstage operations are delegated to callbacks.
class WorkingCopyBoard extends StatefulWidget {
  const WorkingCopyBoard({
    super.key,
    required this.unstagedEntries,
    required this.stagedEntries,
    required this.onStageRequested,
    required this.onUnstageRequested,
    this.onFileActivated,
    this.rowWrapper,
    this.mode = FileListViewMode.list,
    this.expandedFolders = const {},
  });

  /// Files with unstaged changes, in display order.
  final List<WorkingCopyEntry> unstagedEntries;

  /// Files that are staged, in display order.
  final List<WorkingCopyEntry> stagedEntries;

  /// Called when files are dragged from unstaged to staged, or header checkbox selects all.
  /// Receives list of file paths to stage.
  final ValueChanged<List<String>> onStageRequested;

  /// Called when files are dragged from staged to unstaged, or header checkbox deselects all.
  /// Receives list of file paths to unstage.
  final ValueChanged<List<String>> onUnstageRequested;

  /// Optional callback when a file row is tapped.
  /// Receives the file path and whether it came from the staged column.
  final Function(String path, bool fromStaged)? onFileActivated;

  /// Optional widget builder to wrap file rows (e.g., for context menus).
  /// Receives context, entry, fromStaged flag, the current selection in that
  /// column, and the built row child.
  ///
  /// The selection is handed out because it lives in this widget's private
  /// State, and context menu 05-F needs it: right-clicking inside a
  /// multi-selection has to act on the whole batch ("Stage 3 files"), which
  /// the wrapper cannot know otherwise.
  final Widget Function(
    BuildContext,
    WorkingCopyEntry,
    bool fromStaged,
    Set<String> selectedPaths,
    Widget,
  )?
  rowWrapper;

  /// Display mode: flat list or hierarchical tree.
  final FileListViewMode mode;

  /// Set of folder paths that are currently expanded in tree mode.
  final Set<String> expandedFolders;

  @override
  State<WorkingCopyBoard> createState() => _WorkingCopyBoardState();
}

class _WorkingCopyBoardState extends State<WorkingCopyBoard> {
  late WorkingCopySelectionState _unstagedSelection;
  late WorkingCopySelectionState _stagedSelection;
  late Set<String> _expandedFolders;

  @override
  void initState() {
    super.initState();
    final unstagedPaths = widget.unstagedEntries.map((e) => e.path).toList();
    final stagedPaths = widget.stagedEntries.map((e) => e.path).toList();
    _unstagedSelection = WorkingCopySelectionState(allPaths: unstagedPaths);
    _stagedSelection = WorkingCopySelectionState(allPaths: stagedPaths);
    _expandedFolders = Set<String>.from(widget.expandedFolders);
  }

  @override
  void didUpdateWidget(WorkingCopyBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync selections if entries changed (e.g., after stage/unstage)
    if (oldWidget.unstagedEntries != widget.unstagedEntries ||
        oldWidget.stagedEntries != widget.stagedEntries) {
      _initializeSelections();
    }
    // Sync expanded folders if they changed
    if (oldWidget.expandedFolders != widget.expandedFolders) {
      _expandedFolders = Set<String>.from(widget.expandedFolders);
    }
  }

  void _initializeSelections() {
    final unstagedPaths = widget.unstagedEntries.map((e) => e.path).toList();
    final stagedPaths = widget.stagedEntries.map((e) => e.path).toList();

    _unstagedSelection = _unstagedSelection.syncWithPaths(unstagedPaths);
    _stagedSelection = _stagedSelection.syncWithPaths(stagedPaths);
  }

  void _onUnstagedTap(String path) {
    final isCtrlCmd =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    setState(() {
      if (isCtrlCmd && isShift) {
        _unstagedSelection = _unstagedSelection.shiftControlSelectPath(path);
      } else if (isShift) {
        _unstagedSelection = _unstagedSelection.shiftSelectPath(path);
      } else if (isCtrlCmd) {
        _unstagedSelection = _unstagedSelection.togglePath(path);
      } else {
        _unstagedSelection = _unstagedSelection.selectSinglePath(path);
      }
    });
    widget.onFileActivated?.call(path, false);
  }

  void _onStagedTap(String path) {
    final isCtrlCmd =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    setState(() {
      if (isCtrlCmd && isShift) {
        _stagedSelection = _stagedSelection.shiftControlSelectPath(path);
      } else if (isShift) {
        _stagedSelection = _stagedSelection.shiftSelectPath(path);
      } else if (isCtrlCmd) {
        _stagedSelection = _stagedSelection.togglePath(path);
      } else {
        _stagedSelection = _stagedSelection.selectSinglePath(path);
      }
    });
    widget.onFileActivated?.call(path, true);
  }

  void _onUnstagedHeaderCheckbox() {
    setState(() {
      _unstagedSelection = _unstagedSelection.toggleSelectAll();
    });
    // Trigger stage callback if all are now selected
    if (_unstagedSelection.getCheckState() == CheckState.checked) {
      widget.onStageRequested(_unstagedSelection.selected.toList());
    }
  }

  void _onStagedHeaderCheckbox() {
    setState(() {
      _stagedSelection = _stagedSelection.toggleSelectAll();
    });
    // Trigger unstage callback if all are now selected
    if (_stagedSelection.getCheckState() == CheckState.checked) {
      widget.onUnstageRequested(_stagedSelection.selected.toList());
    }
  }

  void _onUnstagedDragAccept(List<String> draggedPaths, bool fromStaged) {
    if (!fromStaged) return; // Only accept from staged
    widget.onUnstageRequested(draggedPaths);
  }

  void _onStagedDragAccept(List<String> draggedPaths, bool fromStaged) {
    if (fromStaged) return; // Only accept from unstaged
    widget.onStageRequested(draggedPaths);
  }

  @override
  Widget build(BuildContext context) {
    return GbmSplitPane(
      axis: Axis.horizontal,
      spec: GbmLayout.splitterWcColumns,
      storageId: 'wc.columns',
      children: <Widget>[
        _buildColumn(
          context,
          header: 'UNSTAGED',
          entries: widget.unstagedEntries,
          selection: _unstagedSelection,
          onTap: _onUnstagedTap,
          onHeaderCheckbox: _onUnstagedHeaderCheckbox,
          onDragAccept: _onUnstagedDragAccept,
          fromStaged: false,
          headerCheckboxKey: const Key('wc-header-checkbox-unstaged'),
        ),
        _buildColumn(
          context,
          header: 'STAGED',
          entries: widget.stagedEntries,
          selection: _stagedSelection,
          onTap: _onStagedTap,
          onHeaderCheckbox: _onStagedHeaderCheckbox,
          onDragAccept: _onStagedDragAccept,
          fromStaged: true,
          headerCheckboxKey: const Key('wc-header-checkbox-staged'),
        ),
      ],
    );
  }

  Widget _buildColumn(
    BuildContext context, {
    required String header,
    required List<WorkingCopyEntry> entries,
    required WorkingCopySelectionState selection,
    required ValueChanged<String> onTap,
    required VoidCallback onHeaderCheckbox,
    required Function(List<String>, bool) onDragAccept,
    required bool fromStaged,
    required Key headerCheckboxKey,
  }) {
    final GbmColors colors = context.gbmColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Header with checkbox
        Container(
          height: GbmSpacing.rowHeightCompact,
          color: colors.surfacePanelRaised,
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 24,
                child: Checkbox(
                  key: headerCheckboxKey,
                  value: _checkboxValue(selection.getCheckState()),
                  tristate: true,
                  onChanged: (_) => onHeaderCheckbox(),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Expanded(
                child: Text(
                  header,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${entries.length}',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        // Files list
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    fromStaged ? 'No staged changes' : 'No unstaged changes',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                )
              : _buildFilesContent(
                  context,
                  entries: entries,
                  selection: selection,
                  onTap: onTap,
                  onDragAccept: onDragAccept,
                  fromStaged: fromStaged,
                ),
        ),
      ],
    );
  }

  /// Builds the files content area (list or tree, with drag-drop).
  Widget _buildFilesContent(
    BuildContext context, {
    required List<WorkingCopyEntry> entries,
    required WorkingCopySelectionState selection,
    required ValueChanged<String> onTap,
    required Function(List<String>, bool) onDragAccept,
    required bool fromStaged,
  }) {
    final GbmColors colors = context.gbmColors;
    final paths = entries.map((e) => e.path).toList();

    return DragTarget<_DraggedFiles>(
      onWillAcceptWithDetails: (details) {
        // Only accept drags from the other column
        return details.data.fromStaged != fromStaged;
      },
      onAcceptWithDetails: (details) {
        onDragAccept(details.data.paths, details.data.fromStaged);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          color: candidateData.isNotEmpty ? colors.surfaceHover : null,
          child: widget.mode == FileListViewMode.tree
              ? _buildTreeList(
                  context,
                  paths: paths,
                  entries: entries,
                  selection: selection,
                  onTap: onTap,
                  fromStaged: fromStaged,
                )
              : _buildFlatList(
                  context,
                  entries: entries,
                  selection: selection,
                  onTap: onTap,
                  fromStaged: fromStaged,
                ),
        );
      },
    );
  }

  /// Builds a flat list of files (FileListViewMode.list).
  Widget _buildFlatList(
    BuildContext context, {
    required List<WorkingCopyEntry> entries,
    required WorkingCopySelectionState selection,
    required ValueChanged<String> onTap,
    required bool fromStaged,
  }) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isSelected = selection.selected.contains(entry.path);
        final widget = _buildFileRow(
          context,
          entry: entry,
          isSelected: isSelected,
          onTap: onTap,
          selection: selection,
          fromStaged: fromStaged,
        );
        return widget;
      },
    );
  }

  /// Builds a tree view of files (FileListViewMode.tree).
  Widget _buildTreeList(
    BuildContext context, {
    required List<String> paths,
    required List<WorkingCopyEntry> entries,
    required WorkingCopySelectionState selection,
    required ValueChanged<String> onTap,
    required bool fromStaged,
  }) {
    final tree = FileTree.fromPaths(paths);
    final entriesMap = {for (final e in entries) e.path: e};

    return FileTreeList(
      fileTree: tree,
      mode: widget.mode,
      selectedPaths: selection.selected,
      expandedFolders: _expandedFolders,
      onItemBuilder: (context, node, level, onFolderToggle) {
        if (node.isDirectory) {
          return _buildFolderRow(
            context,
            node: node,
            selection: selection,
            onToggle: onFolderToggle,
            onFolderCheckStateChanged: (folderPath) {
              setState(() {
                final leaves = node.getAllLeafPaths();
                final checkState = node.getCheckState(selection.selected);
                if (checkState == CheckState.checked) {
                  // Toggle to unchecked
                  setState(() {
                    if (fromStaged) {
                      _stagedSelection = _stagedSelection.deselectPaths(leaves);
                    } else {
                      _unstagedSelection = _unstagedSelection.deselectPaths(
                        leaves,
                      );
                    }
                  });
                } else {
                  // Toggle to checked
                  setState(() {
                    if (fromStaged) {
                      _stagedSelection = _stagedSelection.selectPaths(leaves);
                    } else {
                      _unstagedSelection = _unstagedSelection.selectPaths(
                        leaves,
                      );
                    }
                  });
                }
              });
            },
          );
        } else {
          final entry = entriesMap[node.displayPath];
          if (entry != null) {
            final isSelected = selection.selected.contains(entry.path);
            return _buildFileRow(
              context,
              entry: entry,
              isSelected: isSelected,
              onTap: onTap,
              selection: selection,
              fromStaged: fromStaged,
            );
          }
          return const SizedBox();
        }
      },
      onFolderCheckStateChanged: (folderPath) {
        // Delegate to local folder checkbox handler
      },
    );
  }

  /// Builds a single file row with drag-drop support.
  Widget _buildFileRow(
    BuildContext context, {
    required WorkingCopyEntry entry,
    required bool isSelected,
    required ValueChanged<String> onTap,
    required WorkingCopySelectionState selection,
    required bool fromStaged,
  }) {
    final GbmColors colors = context.gbmColors;
    final draggedPaths = _getDraggedPaths(entry.path, selection);

    final rowChild = Container(
      key: Key(
        'wc-file-${fromStaged ? 'staged' : 'unstaged'}-${entry.path}${isSelected ? '-selected' : ''}',
      ),
      color: isSelected ? colors.surfaceSelected : null,
      child: InkWell(
        onTap: () => onTap(entry.path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 24,
                child: Icon(
                  Icons.drag_handle,
                  size: 16,
                  color: colors.textTertiary,
                ),
              ),
              Expanded(
                child: Text(
                  entry.path,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final draggableChild = Draggable<_DraggedFiles>(
      data: _DraggedFiles(paths: draggedPaths, fromStaged: fromStaged),
      feedback: Container(
        color: colors.surfaceSelected,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        child: Text(
          draggedPaths.length == 1
              ? entry.path
              : '${draggedPaths.length} files',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textPrimary,
          ),
        ),
      ),
      child: rowChild,
    );

    // If rowWrapper is provided, use it to wrap the row (e.g., for context menus)
    if (widget.rowWrapper != null) {
      return widget.rowWrapper!(
        context,
        entry,
        fromStaged,
        fromStaged ? _stagedSelection.selected : _unstagedSelection.selected,
        draggableChild,
      );
    }

    return draggableChild;
  }

  /// Builds a folder row for tree mode.
  Widget _buildFolderRow(
    BuildContext context, {
    required FileTreeNode node,
    required WorkingCopySelectionState selection,
    required VoidCallback? onToggle,
    required Function(String) onFolderCheckStateChanged,
  }) {
    final GbmColors colors = context.gbmColors;
    final checkState = node.getCheckState(selection.selected);

    return Container(
      height: GbmSpacing.rowHeightCompact,
      color: null,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Checkbox(
              value: _checkboxValue(checkState),
              tristate: true,
              onChanged: (_) => onFolderCheckStateChanged(node.displayPath),
              visualDensity: VisualDensity.compact,
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: Icon(
              Icons.arrow_right,
              size: 16,
              color: colors.textTertiary,
            ),
          ),
          Expanded(
            child: Text(
              node.name,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Get the paths to drag: if the dragged file is selected, drag all selected files.
  /// Otherwise, drag just this file.
  List<String> _getDraggedPaths(
    String draggedPath,
    WorkingCopySelectionState selection,
  ) {
    if (selection.selected.contains(draggedPath)) {
      return selection.selected.toList();
    }
    return <String>[draggedPath];
  }
}

/// Maps [CheckState] to the nullable bool a `tristate: true` [Checkbox]
/// needs to actually render its indeterminate dash -- collapsing
/// [CheckState.indeterminate] into `false` (as opposed to `null`) would make
/// a partially-selected column or folder look identical to an empty one.
bool? _checkboxValue(CheckState state) => switch (state) {
  CheckState.checked => true,
  CheckState.unchecked => false,
  CheckState.indeterminate => null,
};

/// Payload for drag-drop between columns.
class _DraggedFiles {
  _DraggedFiles({required this.paths, required this.fromStaged});

  final List<String> paths;
  final bool fromStaged;
}
