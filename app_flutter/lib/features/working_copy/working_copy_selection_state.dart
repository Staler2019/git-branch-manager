import '../../data/models/file_tree.dart';

/// Manages selection state for files in a single column (unstaged/staged).
///
/// This is a pure immutable Dart class that does not depend on Flutter or Riverpod,
/// making it easy to test in isolation. Every operation returns a new instance;
/// never mutates in place.
///
/// Supports seven selection scopes:
/// - Single file: [selectSinglePath], plain click
/// - Multiple non-contiguous: [togglePath], Ctrl/Cmd+click
/// - Contiguous range: [shiftSelectPath], Shift+click
/// - Entire column: [selectAll]/[deselectAll]/[toggleSelectAll], header checkbox
/// - Folder (tree mode only): [selectPaths]/[deselectPaths], folder checkbox
/// - Hunk: delegated to diff pane
/// - Arbitrary contiguous lines: delegated to diff pane
class WorkingCopySelectionState {
  /// Creates a new selection state.
  const WorkingCopySelectionState({
    required this.allPaths,
    this.selected = const {},
    this.lastClickedPath,
  });

  /// All file paths in order (used for range calculation).
  final List<String> allPaths;

  /// Currently selected file paths.
  final Set<String> selected;

  /// The last clicked path, used as anchor for Shift+click ranges.
  /// Set by plain click and Ctrl/Cmd+click; unchanged by Shift+click.
  final String? lastClickedPath;

  /// Single click: replace selection with this one file, update anchor.
  WorkingCopySelectionState selectSinglePath(String path) {
    if (!allPaths.contains(path)) return this;
    return WorkingCopySelectionState(
      allPaths: allPaths,
      selected: {path},
      lastClickedPath: path,
    );
  }

  /// Ctrl/Cmd+click: toggle this path in selection, update anchor.
  WorkingCopySelectionState togglePath(String path) {
    if (!allPaths.contains(path)) return this;
    final newSelected = {...selected};
    if (newSelected.contains(path)) {
      newSelected.remove(path);
    } else {
      newSelected.add(path);
    }
    return WorkingCopySelectionState(
      allPaths: allPaths,
      selected: newSelected,
      lastClickedPath: path,
    );
  }

  /// Shift+click: select all paths from anchor to clicked path (inclusive).
  /// If no anchor is set, acts like [selectSinglePath].
  /// Anchor is not updated by shift selection.
  WorkingCopySelectionState shiftSelectPath(String path) {
    if (!allPaths.contains(path)) return this;

    final anchor = lastClickedPath;
    if (anchor == null) {
      // No anchor: treat as single click
      return selectSinglePath(path);
    }

    // Find indices
    final anchorIndex = allPaths.indexOf(anchor);
    final pathIndex = allPaths.indexOf(path);

    if (anchorIndex < 0 || pathIndex < 0) return this;

    final start = anchorIndex < pathIndex ? anchorIndex : pathIndex;
    final end = anchorIndex > pathIndex ? anchorIndex : pathIndex;

    final newSelected = <String>{};
    for (int i = start; i <= end; i++) {
      newSelected.add(allPaths[i]);
    }

    return WorkingCopySelectionState(
      allPaths: allPaths,
      selected: newSelected,
      lastClickedPath: anchor, // anchor unchanged
    );
  }

  /// Shift+Ctrl/Cmd+click: add range from anchor to clicked path to existing selection.
  /// If no anchor, acts like [togglePath].
  WorkingCopySelectionState shiftControlSelectPath(String path) {
    if (!allPaths.contains(path)) return this;

    final anchor = lastClickedPath;
    if (anchor == null) {
      // No anchor: treat as toggle
      return togglePath(path);
    }

    final anchorIndex = allPaths.indexOf(anchor);
    final pathIndex = allPaths.indexOf(path);

    if (anchorIndex < 0 || pathIndex < 0) return this;

    final start = anchorIndex < pathIndex ? anchorIndex : pathIndex;
    final end = anchorIndex > pathIndex ? anchorIndex : pathIndex;

    final newSelected = {...selected};
    for (int i = start; i <= end; i++) {
      newSelected.add(allPaths[i]);
    }

    return WorkingCopySelectionState(
      allPaths: allPaths,
      selected: newSelected,
      lastClickedPath: anchor, // anchor unchanged
    );
  }

  /// Select all files in the column.
  WorkingCopySelectionState selectAll() {
    return WorkingCopySelectionState(
      allPaths: allPaths,
      selected: allPaths.toSet(),
      lastClickedPath: lastClickedPath,
    );
  }

  /// Deselect all files in the column.
  WorkingCopySelectionState deselectAll() {
    return WorkingCopySelectionState(
      allPaths: allPaths,
      selected: const {},
      lastClickedPath: lastClickedPath,
    );
  }

  /// Toggle select-all: if nothing or partial is selected, select all.
  /// If all are selected, deselect all.
  WorkingCopySelectionState toggleSelectAll() {
    final checkState = getCheckState();
    if (checkState == CheckState.checked) {
      return deselectAll();
    } else {
      return selectAll();
    }
  }

  /// Add multiple paths to selection (for folder checkbox in tree mode).
  WorkingCopySelectionState selectPaths(Iterable<String> paths) {
    final valid = paths.where((p) => allPaths.contains(p));
    if (valid.isEmpty) return this;
    return WorkingCopySelectionState(
      allPaths: allPaths,
      selected: {...selected, ...valid},
      lastClickedPath: lastClickedPath,
    );
  }

  /// Remove multiple paths from selection.
  WorkingCopySelectionState deselectPaths(Iterable<String> paths) {
    final newSelected = {...selected};
    for (final path in paths) {
      newSelected.remove(path);
    }
    return WorkingCopySelectionState(
      allPaths: allPaths,
      selected: newSelected,
      lastClickedPath: lastClickedPath,
    );
  }

  /// Sync selection with a new list of paths (e.g., after a stage/unstage operation).
  /// Prunes selected paths that are no longer in allPaths, and prunes anchor if removed.
  WorkingCopySelectionState syncWithPaths(List<String> newPaths) {
    final newPathSet = newPaths.toSet();
    final prunedSelected = selected
        .where((p) => newPathSet.contains(p))
        .toSet();
    final newAnchor =
        lastClickedPath != null && newPathSet.contains(lastClickedPath)
        ? lastClickedPath
        : null;

    return WorkingCopySelectionState(
      allPaths: newPaths,
      selected: prunedSelected,
      lastClickedPath: newAnchor,
    );
  }

  /// Get the three-state checkbox state for this column.
  /// Uses [CheckState] from file_tree.dart for consistency with tree implementation.
  CheckState getCheckState() {
    if (allPaths.isEmpty) {
      return CheckState.unchecked;
    }

    final selectedCount = selected.length;
    if (selectedCount == 0) {
      return CheckState.unchecked;
    } else if (selectedCount == allPaths.length) {
      return CheckState.checked;
    } else {
      return CheckState.indeterminate;
    }
  }
}
