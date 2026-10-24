// The keys a painted diff row is known by. No Flutter import, so a model of
// the painted rows can name one without depending on the widgets that draw
// them; `selection_touch.dart` and `scoped_diff_view.dart` read the same two
// functions.

/// The key a diff row is tracked under.
///
/// Positional, so it is only valid for as long as the diff it was computed
/// from is on screen. [sourceIndex] is the first component because one
/// `ScopedDiffView` can now draw more than one diff at a time -- `unified`
/// mode merges the unstaged and staged diffs into a single list -- and the
/// two carry the same hunk and line numbers. Without it, row `0:0` of the
/// unstaged diff and row `0:0` of the staged one are one key, so a
/// `SelectionListener` registered for either would collide with the other's
/// and the framework would assert on two listeners sharing one notifier
/// ([FLU-selectionarea-gives-a-string]'s trap 1).
String selectionRowKey(int sourceIndex, int hunkIndex, int lineIndex) =>
    '$sourceIndex:$hunkIndex:$lineIndex';

/// The row key of a full-file fill row (`DiffFillSegment`): index line
/// [indexLine], drawn from source [sourceIndex].
///
/// Its own namespace, so it can never parse as a [selectionRowKey]: the
/// leading `f` is not an integer, and every reader that turns a key back
/// into a hunk line (`resolveTemporaryScope`, `touchedChangedLines`) skips a
/// key that does not parse. A fill row can widen what a drag framed, but it
/// cannot reach anything git is sent.
String selectionFillRowKey(int sourceIndex, int indexLine) =>
    'f:$sourceIndex:$indexLine';
