/// Mirrors the two-sided conflict composition model specified in the design.
/// A conflict line can originate from either the 'ours' side or the 'theirs'
/// side of a merge conflict.
enum ConflictLineSource { ours, theirs }

/// A single line selected from either the 'ours' or 'theirs' side of a conflict
/// region, with its source side and full line content (including line ending,
/// e.g. 'foo\n' or 'foo\r\n').
class ConflictLineEntry {
  const ConflictLineEntry({required this.source, required this.lineContent});

  final ConflictLineSource source;
  final String lineContent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConflictLineEntry &&
          source == other.source &&
          lineContent == other.lineContent;

  @override
  int get hashCode => Object.hash(source, lineContent);
}

/// State of a single conflict region's line-order composition, tracking an
/// ordered list of selected lines, an undo stack for removals, and a flag
/// indicating whether the region has been manually edited as free text.
///
/// Once [manuallyEdited] is true, all line-order operations
/// ([appendLine], [removeAt], [undoLastRemoval]) throw [StateError] — the UI
/// layer is responsible for disabling these operations and showing the
/// region's free-text editor instead. [resetRegion] is the only way to
/// transition back to an unresolved state.
///
/// The undo stack is per-region and LIFO (last-removed-first restored). Each
/// stack entry records the removed [ConflictLineEntry] and its original
/// position in the ordered list. Undo unconditionally restores to that
/// position, even if lines were appended afterward — the position index
/// from the removal time is always in bounds.
class ConflictRegionState {
  const ConflictRegionState({
    required this.orderedLines,
    required this.undoStack,
    required this.manuallyEdited,
  });

  final List<ConflictLineEntry> orderedLines;
  final List<({ConflictLineEntry entry, int position})> undoStack;
  final bool manuallyEdited;

  /// Creates an unresolved region state (empty sequence, no edits, no undo
  /// history).
  factory ConflictRegionState.unresolved() {
    return ConflictRegionState(
      orderedLines: const <ConflictLineEntry>[],
      undoStack: const <({ConflictLineEntry entry, int position})>[],
      manuallyEdited: false,
    );
  }

  ConflictRegionState copyWith({
    List<ConflictLineEntry>? orderedLines,
    List<({ConflictLineEntry entry, int position})>? undoStack,
    bool? manuallyEdited,
  }) {
    return ConflictRegionState(
      orderedLines: orderedLines ?? this.orderedLines,
      undoStack: undoStack ?? this.undoStack,
      manuallyEdited: manuallyEdited ?? this.manuallyEdited,
    );
  }

  /// Appends a new line to the ordered sequence.
  ///
  /// Throws [StateError] if [manuallyEdited] is true.
  ConflictRegionState appendLine(
    ConflictLineSource source,
    String lineContent,
  ) {
    if (manuallyEdited) {
      throw StateError(
        'Cannot append line to manually edited region; '
        'call resetRegion() first',
      );
    }
    final newEntry = ConflictLineEntry(
      source: source,
      lineContent: lineContent,
    );
    return copyWith(
      orderedLines: <ConflictLineEntry>[...orderedLines, newEntry],
    );
  }

  /// Removes the entry at [position] in the ordered sequence and pushes it
  /// onto the undo stack.
  ///
  /// Throws [StateError] if [manuallyEdited] is true, or [RangeError] if
  /// [position] is out of bounds.
  ConflictRegionState removeAt(int position) {
    if (manuallyEdited) {
      throw StateError(
        'Cannot remove line from manually edited region; '
        'call resetRegion() first',
      );
    }
    if (position < 0 || position >= orderedLines.length) {
      throw RangeError.range(position, 0, orderedLines.length - 1);
    }

    final removed = orderedLines[position];
    final newOrdered = <ConflictLineEntry>[
      ...orderedLines.sublist(0, position),
      ...orderedLines.sublist(position + 1),
    ];
    final newUndoStack = <({ConflictLineEntry entry, int position})>[
      ...undoStack,
      (entry: removed, position: position),
    ];

    return copyWith(orderedLines: newOrdered, undoStack: newUndoStack);
  }

  /// Restores the most recently removed line to its original position in the
  /// ordered sequence.
  ///
  /// Throws [StateError] if [manuallyEdited] is true or if the undo stack is
  /// empty.
  ConflictRegionState undoLastRemoval() {
    if (manuallyEdited) {
      throw StateError(
        'Cannot undo removal in manually edited region; '
        'call resetRegion() first',
      );
    }
    if (undoStack.isEmpty) {
      throw StateError('No removals to undo');
    }

    final lastRemoval = undoStack.last;
    final restored = lastRemoval.entry;
    final position = lastRemoval.position;

    // Insert at the original position
    final newOrdered = <ConflictLineEntry>[
      ...orderedLines.sublist(0, position),
      restored,
      ...orderedLines.sublist(position),
    ];

    final newUndoStack = undoStack.sublist(0, undoStack.length - 1);

    return copyWith(orderedLines: newOrdered, undoStack: newUndoStack);
  }

  /// Marks this region as manually edited. Line-order operations become
  /// inapplicable until [reset] is called.
  ConflictRegionState markManuallyEdited() {
    return copyWith(manuallyEdited: true);
  }

  /// Clears the ordered sequence, the undo stack, and the manually-edited flag,
  /// returning to an unresolved state.
  ConflictRegionState reset() {
    return ConflictRegionState.unresolved();
  }

  /// Assembles the result text from the ordered sequence by concatenating
  /// line content. Line endings are preserved as written in [lineContent].
  String assembledResult() {
    return orderedLines.map((e) => e.lineContent).join('');
  }
}

/// Top-level state for line-order conflict resolution across all regions
/// of a conflict file.
///
/// Each region can be independently resolved via line-order composition
/// ([appendLine], [removeAt], [undoLastRemoval]) or manually edited
/// ([markManuallyEdited]). Regions are indexed by their order in the parsed
/// conflict file (0 to regionCount-1).
class ConflictLineOrderState {
  const ConflictLineOrderState({required this.regions});

  final List<ConflictRegionState> regions;

  /// Gets the region count (number of conflict regions).
  int get regionCount => regions.length;

  /// Creates an initial unresolved state for [regionCount] conflict regions.
  factory ConflictLineOrderState.initial(int regionCount) {
    return ConflictLineOrderState(
      regions: List<ConflictRegionState>.generate(
        regionCount,
        (_) => ConflictRegionState.unresolved(),
        growable: false,
      ),
    );
  }

  ConflictLineOrderState _copyWithRegion(
    int regionIndex,
    ConflictRegionState newRegion,
  ) {
    final newRegions = <ConflictRegionState>[...regions];
    newRegions[regionIndex] = newRegion;
    return ConflictLineOrderState(
      regions: List<ConflictRegionState>.unmodifiable(newRegions),
    );
  }

  /// Appends a line to the ordered sequence of [regionIndex].
  ///
  /// Throws [StateError] if the region is manually edited, or [RangeError]
  /// if [regionIndex] is out of bounds.
  ConflictLineOrderState appendLine(
    int regionIndex,
    ConflictLineSource source,
    String lineContent,
  ) {
    RangeError.checkValidIndex(regionIndex, regions, 'regionIndex');
    final updated = regions[regionIndex].appendLine(source, lineContent);
    return _copyWithRegion(regionIndex, updated);
  }

  /// Removes the line at [orderedPosition] in the sequence of [regionIndex].
  ///
  /// Throws [StateError] if the region is manually edited, or [RangeError]
  /// if indices are out of bounds.
  ConflictLineOrderState removeAt(int regionIndex, int orderedPosition) {
    RangeError.checkValidIndex(regionIndex, regions, 'regionIndex');
    final updated = regions[regionIndex].removeAt(orderedPosition);
    return _copyWithRegion(regionIndex, updated);
  }

  /// Restores the most recently removed line to the sequence of [regionIndex].
  ///
  /// Throws [StateError] if the region is manually edited or undo stack is
  /// empty, or [RangeError] if [regionIndex] is out of bounds.
  ConflictLineOrderState undoLastRemoval(int regionIndex) {
    RangeError.checkValidIndex(regionIndex, regions, 'regionIndex');
    final updated = regions[regionIndex].undoLastRemoval();
    return _copyWithRegion(regionIndex, updated);
  }

  /// Marks [regionIndex] as manually edited.
  ///
  /// Throws [RangeError] if [regionIndex] is out of bounds.
  ConflictLineOrderState markManuallyEdited(int regionIndex) {
    RangeError.checkValidIndex(regionIndex, regions, 'regionIndex');
    final updated = regions[regionIndex].markManuallyEdited();
    return _copyWithRegion(regionIndex, updated);
  }

  /// Resets [regionIndex] to an unresolved state (clears sequence, undo stack,
  /// and manually-edited flag).
  ///
  /// Throws [RangeError] if [regionIndex] is out of bounds.
  ConflictLineOrderState resetRegion(int regionIndex) {
    RangeError.checkValidIndex(regionIndex, regions, 'regionIndex');
    final updated = regions[regionIndex].reset();
    return _copyWithRegion(regionIndex, updated);
  }

  /// Gets the ordered lines for [regionIndex].
  ///
  /// Throws [RangeError] if [regionIndex] is out of bounds.
  List<ConflictLineEntry> getOrderedLines(int regionIndex) {
    RangeError.checkValidIndex(regionIndex, regions, 'regionIndex');
    return List<ConflictLineEntry>.unmodifiable(
      regions[regionIndex].orderedLines,
    );
  }

  /// Whether [regionIndex] is marked as manually edited.
  ///
  /// Throws [RangeError] if [regionIndex] is out of bounds.
  bool isManuallyEdited(int regionIndex) {
    RangeError.checkValidIndex(regionIndex, regions, 'regionIndex');
    return regions[regionIndex].manuallyEdited;
  }

  /// Assembles the result text for [regionIndex] from its ordered sequence.
  ///
  /// Throws [RangeError] if [regionIndex] is out of bounds.
  String assembledResult(int regionIndex) {
    RangeError.checkValidIndex(regionIndex, regions, 'regionIndex');
    return regions[regionIndex].assembledResult();
  }
}
