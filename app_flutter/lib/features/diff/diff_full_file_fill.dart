import 'dart:math' as math;

import '../../data/models/parsed_diff.dart';

/// One unchanged row the full-file view draws between the -U3 cards: which
/// source it is drawn from, the index line it is (the ruler both working-copy
/// diffs share, see `indexPositionOf`), and the row itself, taken from that
/// source's full-context diff.
typedef DiffFillRow = ({int sourceIndex, int indexLine, DiffLine line});

/// One source of the pane: its -U3 diff (the one every stage/unstage/discard
/// resolves against), its full-context diff, and which direction it is.
typedef DiffFillSource = ({DiffFile? excerpt, DiffFile? full, bool staged});

/// The rows the full-file view adds, in index-line order, or null when they
/// cannot be trusted and the pane must stay in excerpt mode.
///
/// A row is every index line that no source's -U3 hunk already draws --
/// as context or as a change -- so with two sources (unified) a line is
/// filled at most once and never next to a copy a card already shows. It is
/// taken from the unstaged source when there is one (the rank the merged
/// order puts first), else the staged one; any line no hunk draws is context
/// in both full diffs, so the choice changes no text.
///
/// Null when any source with a -U3 diff has no full diff yet, is binary, or
/// has a full diff whose changed rows (kind, line numbers, text) differ from
/// its -U3 diff's: the file moved between the two git invocations, and a row
/// filled from the newer file would sit beside cards from the older one.
/// A source with no -U3 diff (that direction has no change) is skipped.
List<DiffFillRow>? fullFileFillRows(List<DiffFillSource> sources) {
  final Set<int> drawn = <int>{};
  // index line -> (sourceIndex, row, staged) of the best candidate so far.
  final Map<int, (int, DiffLine, bool)> candidates =
      <int, (int, DiffLine, bool)>{};

  for (int sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
    final DiffFillSource source = sources[sourceIndex];
    final DiffFile? excerpt = source.excerpt;
    if (excerpt == null) continue;
    final DiffFile? full = source.full;
    if (full == null || excerpt.binary || full.binary) return null;
    if (!_sameChanges(excerpt, full)) return null;

    for (final DiffHunk hunk in excerpt.hunks) {
      for (final DiffLine line in hunk.lines) {
        final int? index = _indexLineOf(line, staged: source.staged);
        if (index != null) drawn.add(index);
      }
    }
    for (final DiffHunk hunk in full.hunks) {
      for (final DiffLine line in hunk.lines) {
        if (line.kind != DiffLineKind.context) continue;
        final int index = source.staged ? line.newLine : line.oldLine;
        final (int, DiffLine, bool)? held = candidates[index];
        // Unstaged wins a tie with staged; the first source wins otherwise.
        if (held == null || (held.$3 && !source.staged)) {
          candidates[index] = (sourceIndex, line, source.staged);
        }
      }
    }
  }

  final List<int> lines =
      candidates.keys.where((int l) => !drawn.contains(l)).toList()..sort();
  return <DiffFillRow>[
    for (final int l in lines)
      (sourceIndex: candidates[l]!.$1, indexLine: l, line: candidates[l]!.$2),
  ];
}

/// The index line [line] occupies, or null for a row that is not one: an
/// unstaged diff runs index -> work tree, so its index is the old side and a
/// work-tree-only (added) row has none; a staged diff runs HEAD -> index, so
/// its index is the new side and a HEAD-only (removed) row has none.
int? _indexLineOf(DiffLine line, {required bool staged}) {
  final int n = staged ? line.newLine : line.oldLine;
  if (line.kind == DiffLineKind.noNewlineMarker || n == 0) return null;
  return n;
}

/// How many lines [file]'s longer side has, as far as its hunks reach --
/// for a full-context diff, the file's whole length.
int diffFileLineCount(DiffFile file) {
  int lines = 0;
  for (final DiffHunk hunk in file.hunks) {
    lines = math.max(lines, hunk.oldStart + hunk.oldCount - 1);
    lines = math.max(lines, hunk.newStart + hunk.newCount - 1);
  }
  return lines;
}

/// Whether [full] changes exactly the rows [excerpt] does (kind, line
/// numbers, text) -- false when the file moved between the two git
/// invocations, the case [fullFileFillRows] refuses to fill.
bool fullDiffAgreesWith(DiffFile excerpt, DiffFile full) =>
    _sameChanges(excerpt, full);

bool _sameChanges(DiffFile a, DiffFile b) {
  final List<String> ca = _changes(a);
  final List<String> cb = _changes(b);
  if (ca.length != cb.length) return false;
  for (int i = 0; i < ca.length; i++) {
    if (ca[i] != cb[i]) return false;
  }
  return true;
}

List<String> _changes(DiffFile file) => <String>[
  for (final DiffHunk hunk in file.hunks)
    for (final DiffLine line in hunk.lines)
      if (line.kind == DiffLineKind.added || line.kind == DiffLineKind.removed)
        '${line.kind.value}|${line.oldLine}|${line.newLine}|${line.text}',
];
