import '../../data/models/parsed_diff.dart';

/// How many unchanged lines may sit between two changed lines before they
/// stop being "one change".
///
/// Two is a judgement, not a spec number: a blank line plus a closing brace
/// is the commonest thing to find wedged between two edits to the same
/// thought, and splitting there would make the user press two buttons for
/// one intention. Three is where the second change starts reading as its own
/// paragraph.
const int kDefaultScopeGap = 2;

/// One directly actionable block of a hunk: the lines a single
/// Stage/Unstage press moves, plus whatever unchanged lines the gap rule
/// swallowed so the block still reads as continuous code.
///
/// [lineIndices] is a contiguous run from the first changed line to the last,
/// which is what gets drawn as one card. [changedLineIndices] is the subset
/// that actually moves -- the only thing `gbm_stage_lines` may be handed, and
/// the number the button writes out.
class DiffScope {
  const DiffScope({
    required this.lineIndices,
    required this.changedLineIndices,
    required this.addedCount,
    required this.removedCount,
  });

  /// Every line index in the block, in order, including the unchanged lines
  /// the gap rule merged in. Indices are into the hunk's own `lines` array.
  final List<int> lineIndices;

  /// The added/removed line indices only, in order.
  final List<int> changedLineIndices;

  final int addedCount;
  final int removedCount;
}

/// Splits one hunk into the blocks the diff pane draws as cards.
///
/// Two changed lines join one scope when at most [maxGap] unchanged lines
/// separate them. Leading and trailing context stays outside every scope: it
/// is what the change sits *in*, not part of it.
///
/// A hunk with no changed line at all yields no scopes rather than one empty
/// one, so a caller can render "nothing to stage here" without a special
/// case.
List<DiffScope> splitHunkIntoScopes(
  DiffHunk hunk, {
  int maxGap = kDefaultScopeGap,
}) {
  final List<int> changed = <int>[
    for (int i = 0; i < hunk.lines.length; i++)
      if (_isChanged(hunk.lines[i].kind)) i,
  ];
  if (changed.isEmpty) return const <DiffScope>[];

  final List<DiffScope> scopes = <DiffScope>[];
  List<int> group = <int>[changed.first];

  void close() {
    scopes.add(_scopeFrom(hunk, group));
  }

  for (final int index in changed.skip(1)) {
    // The unchanged lines strictly between this change and the previous one.
    final int gap = index - group.last - 1;
    if (gap <= maxGap) {
      group.add(index);
    } else {
      close();
      group = <int>[index];
    }
  }
  close();

  return List<DiffScope>.unmodifiable(scopes);
}

/// Every scope of every hunk in [file], keyed by hunk index.
///
/// Keyed rather than flattened because **a scope may never cross a hunk**:
/// `gbm_stage_lines` takes one hunk index and line indices within it, so two
/// changes that look adjacent on screen across a hunk boundary are still two
/// separate patches. A flat list would lose the one piece of information the
/// call needs.
///
/// A binary file has no hunks and so returns an empty map.
Map<int, List<DiffScope>> splitDiffFileIntoScopes(
  DiffFile file, {
  int maxGap = kDefaultScopeGap,
}) {
  if (file.binary) return const <int, List<DiffScope>>{};
  return <int, List<DiffScope>>{
    for (int hunkIndex = 0; hunkIndex < file.hunks.length; hunkIndex++)
      hunkIndex: splitHunkIntoScopes(file.hunks[hunkIndex], maxGap: maxGap),
  };
}

/// Only added and removed lines move. Context passes through a rebuilt patch
/// either way, and so does the no-newline marker (see
/// `UnifiedDiffParser::buildLineSelectionPatch`) -- which is also why the
/// marker must not be allowed to split a scope: it is not a change, but it
/// is not a wall between changes either.
bool _isChanged(DiffLineKind kind) =>
    kind == DiffLineKind.added || kind == DiffLineKind.removed;

DiffScope _scopeFrom(DiffHunk hunk, List<int> changedIndices) {
  final int first = changedIndices.first;
  final int last = changedIndices.last;
  int added = 0;
  int removed = 0;
  for (final int index in changedIndices) {
    if (hunk.lines[index].kind == DiffLineKind.added) {
      added++;
    } else {
      removed++;
    }
  }
  return DiffScope(
    lineIndices: List<int>.unmodifiable(<int>[
      for (int i = first; i <= last; i++) i,
    ]),
    changedLineIndices: List<int>.unmodifiable(changedIndices),
    addedCount: added,
    removedCount: removed,
  );
}

/// One drawable block of a hunk: either a run of context lines that no scope
/// claimed, or a scope.
///
/// Rendering reads this list straight through, so the "which lines are in a
/// card and which are the code around it" decision stays in one pure place
/// instead of being re-derived by a widget's build method.
sealed class DiffSegment {
  const DiffSegment();

  /// The hunk-line indices this segment draws, in order.
  List<int> get lineIndices;
}

/// Context lines outside every scope -- the code a change sits in.
final class DiffGapSegment extends DiffSegment {
  const DiffGapSegment(this.lineIndices);

  @override
  final List<int> lineIndices;
}

/// A scope, plus its 1-based position among the scopes of the same side, so
/// the card can be labelled 「變更 2」 without the widget counting for itself.
final class DiffScopeSegment extends DiffSegment {
  const DiffScopeSegment({required this.scope, required this.ordinal});

  final DiffScope scope;
  final int ordinal;

  @override
  List<int> get lineIndices => scope.lineIndices;
}

/// Interleaves [scopes] with the context runs between them, covering every
/// line of [hunk] exactly once and in order.
///
/// [firstOrdinal] is where this hunk's scope numbering continues from, so a
/// file's cards read 變更 1, 2, 3… across hunk boundaries rather than
/// restarting at every `@@`.
List<DiffSegment> hunkSegments(
  DiffHunk hunk,
  List<DiffScope> scopes, {
  int firstOrdinal = 1,
}) {
  final List<DiffSegment> segments = <DiffSegment>[];
  int cursor = 0;
  int ordinal = firstOrdinal;

  void gapUpTo(int end) {
    if (end <= cursor) return;
    segments.add(
      DiffGapSegment(
        List<int>.unmodifiable(<int>[for (int i = cursor; i < end; i++) i]),
      ),
    );
  }

  for (final DiffScope scope in scopes) {
    gapUpTo(scope.lineIndices.first);
    segments.add(DiffScopeSegment(scope: scope, ordinal: ordinal++));
    cursor = scope.lineIndices.last + 1;
  }
  gapUpTo(hunk.lines.length);

  return List<DiffSegment>.unmodifiable(segments);
}
