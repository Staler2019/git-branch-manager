import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/file_tree.dart';
import '../../../data/models/working_copy_status.dart';
import '../../../data/repositories/file_list_view_mode_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/file_list_mode_switcher.dart';
import '../../../widgets/file_tree_folder_row.dart';
import '../../../widgets/file_list_mode_toggle_button.dart';
import '../../../widgets/gbm_badge.dart';
import '../../../widgets/gbm_row.dart';
import '../../../widgets/split_pane.dart';
import '../working_copy_file_identity.dart';
import '../working_copy_selection_state.dart';

/// A two-column drag-and-drop board for staging/unstaging files in working copy.
///
/// Left column: unstaged files. Right column: staged files.
///
/// - **An empty column is still a drop target.** Its placeholder text is
///   drawn inside the `DragTarget`, not in place of it -- the shape that
///   shipped first drew the placeholder *instead of* the target, so a
///   repository with nothing staged had no way to stage anything by
///   dragging, and with no checkbox anywhere that meant no way at all.
/// - **Dragging is the only way a file changes columns.** There is no
///   checkbox anywhere in this widget -- not on a file row, not on the
///   column header, not on a tree-mode folder row. That is a deliberate
///   deviation from spec P03-1 / P03-3 / P03-10 and `SCOPES` rows 1, 4 and
///   5, all of which describe checkboxes; see docs/ledger.md for the
///   decision and its reasoning. The two scopes whose only spec affordance
///   was a checkbox keep an entry point: a whole column goes through
///   `Repository → Stage all` (Ctrl/Cmd+Alt+A) or the row context menu, and
///   a whole folder is dragged as one row in tree mode.
/// - Click to select a single file; Ctrl/Cmd+click accumulates, Shift+click
///   ranges, Shift+Ctrl/Cmd+click extends a range (spec P13 `MULTIKEYS`).
/// - **Selection is shared by both columns.** A partly-staged file is one
///   row on each side and both light up together, because there is exactly
///   one selection set and it is keyed by [logicalFileKey] rather than by
///   raw path -- which is also what makes a rename's two differently-named
///   rows highlight as the one file they are.
/// - Optional file activation callback (for diff view selection).
/// - Optional row widget wrapper for context menus.
/// - List/Tree display mode, rendered by the shared [FileListModeSwitcher]
///   every other file list in the app uses.
///
/// Presentational apart from the one shared [FileListModeToggleButton] in
/// its header, which reads the app-wide list/tree preference for itself (the
/// same arrangement `changed_files_panel.dart` uses). Everything else arrives
/// as a plain value or callback, and every stage/unstage is delegated.
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
  });

  /// Files with unstaged changes, in display order.
  final List<WorkingCopyEntry> unstagedEntries;

  /// Files that are staged, in display order.
  final List<WorkingCopyEntry> stagedEntries;

  /// Called when files are dragged from unstaged to staged.
  /// Receives list of file paths to stage.
  final ValueChanged<List<String>> onStageRequested;

  /// Called when files are dragged from staged to unstaged.
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

  @override
  State<WorkingCopyBoard> createState() => _WorkingCopyBoardState();
}

class _WorkingCopyBoardState extends State<WorkingCopyBoard> {
  /// The board's one selection, holding [logicalFileKey]s. Both columns read
  /// it; neither owns it. A second per-column set is how the two sides would
  /// come to disagree about whether a partly-staged file is selected.
  late WorkingCopySelectionState _selection;

  @override
  void initState() {
    super.initState();
    _selection = WorkingCopySelectionState(allPaths: _allKeys());
  }

  @override
  void didUpdateWidget(WorkingCopyBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync selection if entries changed (e.g., after stage/unstage)
    if (oldWidget.unstagedEntries != widget.unstagedEntries ||
        oldWidget.stagedEntries != widget.stagedEntries) {
      _selection = _selection.syncWithPaths(_allKeys());
    }
  }

  /// Every key on the board, used only to prune a selection after a
  /// stage/unstage made some rows disappear.
  List<String> _allKeys() => <String>{
    ..._keysInRenderOrder(widget.unstagedEntries),
    ..._keysInRenderOrder(widget.stagedEntries),
  }.toList(growable: false);

  /// One column's keys **in the order its rows are painted**, which depends
  /// on the display mode -- the two modes paint different orders, and a range
  /// that spans the wrong one sweeps in rows the user never dragged across.
  ///
  /// List mode paints [entries] as they come: [FileListModeSwitcher] hands
  /// them straight to a `ListView.builder` and never builds a tree. Tree mode
  /// paints [FileTree.fromPaths]'s leaf order, which groups a folder's files
  /// together even when the status listed them apart.
  ///
  /// This used to build the tree unconditionally, on a comment asserting that
  /// both modes rendered through it. They do not, and in list mode the result
  /// was a range measured in tree order over rows painted in entry order:
  /// dragging from `lib/a.dart` to `lib/b.dart` skipped the `zz.txt` sitting
  /// visibly between them. Not building the tree in list mode is also the
  /// cheaper half -- it is the default mode, and this runs on every click.
  ///
  /// Known limit, tree mode only: a range can still include leaves inside a
  /// collapsed folder, which are not on screen. Ranging over rows nobody can
  /// see is a smaller wrong than ranging over the wrong rows, and fixing it
  /// needs the expand state that [FileTreeList] keeps to itself.
  List<String> _keysInRenderOrder(List<WorkingCopyEntry> entries) {
    if (widget.mode == FileListViewMode.list) {
      return entries.map(logicalFileKey).toList(growable: false);
    }
    final Map<String, String> keyByPath = <String, String>{
      for (final WorkingCopyEntry entry in entries)
        entry.path: logicalFileKey(entry),
    };
    return FileTree.fromPaths(
          entries.map((WorkingCopyEntry e) => e.path).toList(growable: false),
        )
        .getAllLeafPaths()
        .map((String path) => keyByPath[path]!)
        .toList(growable: false);
  }

  void _onTap(WorkingCopyEntry entry, bool fromStaged) {
    final List<String> order = _keysInRenderOrder(
      fromStaged ? widget.stagedEntries : widget.unstagedEntries,
    );
    setState(() {
      _selection = _applyClick(
        _selection.withOrder(order),
        logicalFileKey(entry),
      );
    });
    widget.onFileActivated?.call(entry.path, fromStaged);
  }

  /// The paths in [entries] whose logical file is currently selected -- what
  /// a drag or a context menu acts on. Converted back to paths here because
  /// git only ever takes a path, and each column has to hand over *its own*
  /// name for a renamed file.
  Set<String> _selectedPathsIn(List<WorkingCopyEntry> entries) => <String>{
    for (final WorkingCopyEntry entry in entries)
      if (_selection.selected.contains(logicalFileKey(entry))) entry.path,
  };

  /// P13 `MULTIKEYS`, read off the modifiers held at click time: plain click
  /// replaces the selection, Ctrl/Cmd toggles one row, Shift spans a range
  /// from the anchor, Shift+Ctrl/Cmd adds that range to what is already
  /// selected.
  WorkingCopySelectionState _applyClick(
    WorkingCopySelectionState selection,
    String key,
  ) {
    final bool isCtrlCmd =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final bool isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrlCmd && isShift) return selection.shiftControlSelectPath(key);
    if (isShift) return selection.shiftSelectPath(key);
    if (isCtrlCmd) return selection.togglePath(key);
    return selection.selectSinglePath(key);
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
          header: 'Unstaged',
          entries: widget.unstagedEntries,
          onDragAccept: _onUnstagedDragAccept,
          fromStaged: false,
        ),
        _buildColumn(
          context,
          header: 'Staged',
          entries: widget.stagedEntries,
          onDragAccept: _onStagedDragAccept,
          fromStaged: true,
        ),
      ],
    );
  }

  Widget _buildColumn(
    BuildContext context, {
    required String header,
    required List<WorkingCopyEntry> entries,
    required Function(List<String>, bool) onDragAccept,
    required bool fromStaged,
  }) {
    final GbmColors colors = context.gbmColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: GbmSpacing.rowHeightCompact,
          color: colors.surfacePanelRaised,
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
          child: Row(
            children: <Widget>[
              // `Unstaged · 2`, one string, exactly as spec page 03's mockup
              // writes it -- the count is part of the title, not a separate
              // number floated to the far end of the row.
              Expanded(
                child: Text(
                  '$header \u00b7 ${entries.length}',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // P03-10 puts the list/tree switch at the right of a file
              // list's header. One switch serves the whole board: the note
              // enumerates its subjects as "Working Copy 兩欄、History 的
              // Changed files、Compare 的 Files、Conflict 視窗的檔案清單" --
              // the two columns as one item -- and the mockup draws it on
              // the Unstaged header only. A second copy would be two
              // controls for one global preference.
              if (!fromStaged) const FileListModeToggleButton(),
            ],
          ),
        ),
        // Files list. The empty case lives *inside* [_buildFilesContent], not
        // instead of it: an empty column that is not a drop target cannot be
        // dropped on, and dragging is the only way a file changes side now.
        Expanded(
          child: _buildFilesContent(
            context,
            entries: entries,
            onDragAccept: onDragAccept,
            fromStaged: fromStaged,
          ),
        ),
        // The mockup's dashed hint, pinned to the bottom of the Unstaged
        // column. With no checkbox on any row, dragging is the only way a
        // file changes side, so the column has to say so somewhere.
        if (!fromStaged) _dropHint(context),
      ],
    );
  }

  /// 「拖曳檔案到右欄 = stage」 -- spec page 03's dashed panel.
  Widget _dropHint(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GbmSpacing.space2,
        0,
        GbmSpacing.space2,
        GbmSpacing.space2,
      ),
      child: Container(
        padding: const EdgeInsets.all(GbmSpacing.space2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderDefault),
          borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
        ),
        child: Text(
          '\u62d6\u66f3\u6a94\u6848\u5230\u53f3\u6b04 = stage',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.textTertiary,
          ),
        ),
      ),
    );
  }

  /// Builds the files content area (list or tree, with drag-drop).
  Widget _buildFilesContent(
    BuildContext context, {
    required List<WorkingCopyEntry> entries,
    required Function(List<String>, bool) onDragAccept,
    required bool fromStaged,
  }) {
    final GbmColors colors = context.gbmColors;

    return DragTarget<_DraggedFiles>(
      onWillAcceptWithDetails: (details) {
        // Only accept drags from the other column
        return details.data.fromStaged != fromStaged;
      },
      onAcceptWithDetails: (details) {
        onDragAccept(details.data.paths, details.data.fromStaged);
      },
      builder: (context, candidateData, rejectedData) {
        if (entries.isEmpty) {
          return Container(
            color: candidateData.isNotEmpty ? colors.surfaceHover : null,
            alignment: Alignment.center,
            child: Text(
              fromStaged ? 'No staged changes' : 'No unstaged changes',
              style: TextStyle(color: colors.textTertiary),
            ),
          );
        }
        return Container(
          color: candidateData.isNotEmpty ? colors.surfaceHover : null,
          child: FileListModeSwitcher<WorkingCopyEntry>(
            mode: widget.mode,
            items: entries,
            pathOf: (WorkingCopyEntry entry) => entry.path,
            leafBuilder: (BuildContext context, WorkingCopyEntry entry) =>
                _buildFileRow(
                  context,
                  entry: entry,
                  entries: entries,
                  fromStaged: fromStaged,
                ),
            folderBuilder:
                (
                  BuildContext context,
                  FileTreeNode node,
                  VoidCallback? onToggle,
                ) => _buildFolderRow(
                  context,
                  node: node,
                  onToggle: onToggle,
                  fromStaged: fromStaged,
                ),
          ),
        );
      },
    );
  }

  /// Builds a single file row with drag-drop support.
  Widget _buildFileRow(
    BuildContext context, {
    required WorkingCopyEntry entry,
    required List<WorkingCopyEntry> entries,
    required bool fromStaged,
  }) {
    final GbmColors colors = context.gbmColors;
    final Set<String> selectedPaths = _selectedPathsIn(entries);
    final bool isSelected = selectedPaths.contains(entry.path);
    final List<String> draggedPaths = isSelected
        ? selectedPaths.toList(growable: false)
        : <String>[entry.path];

    // `GbmRow`, not a hand-rolled `Container` + `InkWell`: an InkWell with no
    // explicit hoverColor silently inherits `ThemeData.hoverColor` (~4%
    // black/white, invisible on a real display), which is how this list
    // shipped with no visible hover at all. The design system owns
    // hover/selected here so these rows cannot disagree with the sidebar or
    // the Changed files panel.
    final rowChild = GbmRow(
      key: Key(
        'wc-file-${fromStaged ? 'staged' : 'unstaged'}-${entry.path}${isSelected ? '-selected' : ''}',
      ),
      height: GbmSpacing.rowHeightCompact,
      selected: isSelected,
      onTap: () => _onTap(entry, fromStaged),
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
      child: Row(
        children: <Widget>[
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
          ..._lineCountBadges(entry, fromStaged: fromStaged),
        ],
      ),
    );

    final draggableChild = Draggable<_DraggedFiles>(
      data: _DraggedFiles(paths: draggedPaths, fromStaged: fromStaged),
      feedback: _dragFeedback(
        context,
        label: draggedPaths.length == 1
            ? entry.path
            : '${draggedPaths.length} files',
      ),
      child: rowChild,
    );

    // If rowWrapper is provided, use it to wrap the row (e.g., for context menus)
    if (widget.rowWrapper != null) {
      return widget.rowWrapper!(
        context,
        entry,
        fromStaged,
        selectedPaths,
        draggableChild,
      );
    }

    return draggableChild;
  }

  /// The `+N` / `-N` pair at the end of a row, each column reading **its own
  /// side's** counts -- a partly-staged file has four independent numbers and
  /// showing the wrong pair would say the opposite of the truth. This is what
  /// replaced the tri-state checkbox's "half-selected" look: a number says
  /// how much is on this side, where an indeterminate dash only said "some".
  ///
  /// A zero draws nothing rather than `+0`. Zero means *not measured* (binary
  /// blob, mode-only change, untracked file over the byte cap -- see
  /// `WorkingCopyEntry`'s own doc comment), and a badge there would claim a
  /// measurement that never happened. Same rule and same reason as
  /// `changed_files_panel.dart`, which is also where the ASCII `-` comes
  /// from: two different minus glyphs across the app's file lists would read
  /// as two different things.
  List<Widget> _lineCountBadges(
    WorkingCopyEntry entry, {
    required bool fromStaged,
  }) {
    final int added = fromStaged ? entry.stagedAdded : entry.unstagedAdded;
    final int removed = fromStaged
        ? entry.stagedRemoved
        : entry.unstagedRemoved;

    return <Widget>[
      if (added > 0) ...<Widget>[
        const SizedBox(width: GbmSpacing.space1),
        GbmBadge(label: '+$added', kind: GbmBadgeKind.added),
      ],
      if (removed > 0) ...<Widget>[
        const SizedBox(width: GbmSpacing.space1),
        GbmBadge(label: '-$removed', kind: GbmBadgeKind.removed),
      ],
    ];
  }

  /// Builds a folder row for tree mode: the shared read-only
  /// [FileTreeFolderRow] (chevron + name, no checkbox), made draggable so a
  /// whole folder still moves between columns in one gesture -- that drag is
  /// what replaced `SCOPES`' tri-state folder checkbox.
  Widget _buildFolderRow(
    BuildContext context, {
    required FileTreeNode node,
    required VoidCallback? onToggle,
    required bool fromStaged,
  }) {
    final List<String> leaves = node.getAllLeafPaths();

    return Draggable<_DraggedFiles>(
      data: _DraggedFiles(paths: leaves, fromStaged: fromStaged),
      feedback: _dragFeedback(
        context,
        label: '${node.name} (${leaves.length} files)',
      ),
      child: FileTreeFolderRow(node: node, onToggle: onToggle),
    );
  }

  /// The floating label under the cursor while dragging. Wrapped in a
  /// [Material]: `Draggable.feedback` is inserted into the overlay, which is
  /// outside this widget's own Material ancestor.
  Widget _dragFeedback(BuildContext context, {required String label}) {
    final GbmColors colors = context.gbmColors;
    return Material(
      color: colors.surfaceSelected,
      borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GbmSpacing.space2,
          vertical: GbmSpacing.space1,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Payload for drag-drop between columns.
class _DraggedFiles {
  _DraggedFiles({required this.paths, required this.fromStaged});

  final List<String> paths;
  final bool fromStaged;
}
