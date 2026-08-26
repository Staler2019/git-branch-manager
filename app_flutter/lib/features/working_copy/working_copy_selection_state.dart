/// Manages the Working Copy board's file selection.
///
/// This is a pure immutable Dart class that does not depend on Flutter or Riverpod,
/// making it easy to test in isolation. Every operation returns a new instance;
/// never mutates in place.
///
/// **One instance covers both columns.** The identifiers it holds are logical
/// file keys (`working_copy_file_identity.dart`), not raw paths, so a file
/// that exists on both sides is one entry in [selected] and lights up in both
/// places. [allPaths] is the *one column* a click is being applied to, in the
/// order that column paints its rows -- range selection only means anything
/// within a single list, so the caller re-points it with [withOrder] before
/// each click.
///
/// Selection scopes it implements (spec P13 `MULTIKEYS`):
/// - Single file: [selectSinglePath], plain click
/// - Multiple non-contiguous: [togglePath], Ctrl/Cmd+click
/// - Contiguous range: [shiftSelectPath], Shift+click
/// - Extend a range: [shiftControlSelectPath], Shift+Ctrl/Cmd+click
///
/// Whole-column and whole-folder selection are absent on purpose: both were
/// checkbox-only in the spec, and the board has no checkboxes (see
/// `working_copy_board.dart`). Hunk and line scopes belong to the diff pane.
///
/// `selectAll`/`deselectAll`/`toggleSelectAll`/`selectPaths`/`deselectPaths`
/// and a tri-state `getCheckState` used to live here and were deleted rather
/// than left for a future caller: every one of them was written for the
/// checkbox column that the board no longer has, and none had a caller under
/// `lib/` -- only tests, which is orphan wiring with a green tick on it. The
/// `Ctrl/Cmd+A` that P13 `MULTIKEYS` does ask for is a *different* thing and
/// belongs to whichever list holds focus, not to a column-wide method here.
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

  /// Re-points [allPaths] at the column a click is about to land in, keeping
  /// [selected] and the anchor untouched.
  ///
  /// Unlike [syncWithPaths] this prunes nothing: the keys selected in the
  /// *other* column are still selected, they simply are not part of this
  /// column's range arithmetic.
  WorkingCopySelectionState withOrder(List<String> orderedPaths) {
    return WorkingCopySelectionState(
      allPaths: orderedPaths,
      selected: selected,
      lastClickedPath: lastClickedPath,
    );
  }

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

    // An anchor set in the *other* column is not in this column's order, so
    // there is no range to span. Falling back to a plain click is what the
    // no-anchor branch above already does; returning `this` instead would
    // make Shift+click after a click on the other side do nothing at all,
    // with nothing on screen to explain why.
    if (anchorIndex < 0) return selectSinglePath(path);
    if (pathIndex < 0) return this;

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

    // Same reasoning as [shiftSelectPath]: an anchor from the other column
    // gives no range, so this degrades to the plain Ctrl/Cmd+click it is
    // already holding down.
    if (anchorIndex < 0) return togglePath(path);
    if (pathIndex < 0) return this;

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
}
