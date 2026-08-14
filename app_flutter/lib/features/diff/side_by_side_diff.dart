import '../../data/models/parsed_diff.dart';

/// One rendered row of a side-by-side diff. Either side may be null,
/// meaning that side is blank padding -- a pure addition has no left line,
/// a pure deletion has no right line.
class SideBySideRow {
  const SideBySideRow({this.left, this.right});

  final DiffLine? left;
  final DiffLine? right;
}

/// Dart port of `gbm::pairHunkForSideBySide` (src/core/git/SideBySideDiff.h)
/// -- a pure, already-fully-tested transformation over data the Dart side
/// already has in hand (a decoded [DiffHunk]), not a reimplementation of any
/// git operation or diff parsing. Round-tripping through capi for a
/// synchronous relayout of data already fetched would be pure overhead, so
/// this stays client-side, mirroring the core function line for line
/// (including its test cases -- see side_by_side_diff_test.dart) to keep the
/// two in lockstep if either ever changes.
///
/// Git's unified diff already groups each changed region as a contiguous
/// run of removed lines immediately followed by a contiguous run of added
/// lines, bracketed by context. That is exactly the shape a side-by-side
/// view wants: pairing removed[i] with added[i] up to the shorter run's
/// length, padding the rest with blanks. Context lines pass straight across
/// unchanged, appearing identically on both sides.
List<SideBySideRow> pairHunkForSideBySide(DiffHunk hunk) {
  final List<SideBySideRow> rows = <SideBySideRow>[];
  final List<DiffLine> removedRun = <DiffLine>[];
  final List<DiffLine> addedRun = <DiffLine>[];

  void flushRun() {
    final int n = removedRun.length > addedRun.length
        ? removedRun.length
        : addedRun.length;
    for (int i = 0; i < n; i++) {
      rows.add(
        SideBySideRow(
          left: i < removedRun.length ? removedRun[i] : null,
          right: i < addedRun.length ? addedRun[i] : null,
        ),
      );
    }
    removedRun.clear();
    addedRun.clear();
  }

  DiffLineKind lastRealKind = DiffLineKind.context;
  for (final DiffLine line in hunk.lines) {
    switch (line.kind) {
      case DiffLineKind.removed:
        removedRun.add(line);
        lastRealKind = DiffLineKind.removed;
      case DiffLineKind.added:
        addedRun.add(line);
        lastRealKind = DiffLineKind.added;
      case DiffLineKind.context:
        flushRun();
        rows.add(SideBySideRow(left: line, right: line));
        lastRealKind = DiffLineKind.context;
      case DiffLineKind.noNewlineMarker:
        // Belongs to whichever side it immediately follows, not to both: it
        // means that one file (old or new) has no trailing newline, not
        // that the pair of them agree on it.
        if (lastRealKind == DiffLineKind.removed) {
          removedRun.add(line);
        } else if (lastRealKind == DiffLineKind.added) {
          addedRun.add(line);
        } else {
          flushRun();
          rows.add(SideBySideRow(left: line, right: line));
        }
    }
  }
  flushRun();
  return rows;
}
