import '../../data/models/parsed_diff.dart';
import 'diff_scopes.dart';

/// One drawable block of a merged (or single-source) diff list: which
/// source and hunk it comes from, what it draws, and where it sits on the
/// index ruler both working-copy diffs share.
typedef DiffBlock = ({
  int sourceIndex,
  int hunkIndex,
  DiffSegment segment,
  IndexPosition position,
});

/// The painted order of every block of [sides] -- the one derivation both
/// the widgets and the selection range read ([SPEC-range-follows-paint-order]).
///
/// A side with no file, a binary file or no hunks draws nothing.
List<DiffBlock> orderedDiffBlocks(
  List<DiffSide> sides,
  List<Map<int, List<DiffScope>>> scopesBySource,
) {
  // Every drawable block of every source, decorated with where it sits on
  // the index -- the ruler the two diffs share ([indexPositionOf]).
  final List<DiffBlock> blocks = <DiffBlock>[];
  final List<Map<int, Set<int>>> hidden = hiddenContextLines(
    sides,
    scopesBySource,
  );

  for (int sourceIndex = 0; sourceIndex < sides.length; sourceIndex++) {
    final DiffSide source = sides[sourceIndex];
    final DiffFile? diffFile = source.file;
    if (diffFile == null || diffFile.binary || diffFile.hunks.isEmpty) {
      continue;
    }
    final Map<int, List<DiffScope>> byHunk = scopesBySource[sourceIndex];
    for (int hunkIndex = 0; hunkIndex < diffFile.hunks.length; hunkIndex++) {
      final DiffHunk hunk = diffFile.hunks[hunkIndex];
      for (final DiffSegment segment in hunkSegments(
        hunk,
        byHunk[hunkIndex] ?? const <DiffScope>[],
        // 使用者裁定 B (docs/records/2026-10-04-merged-diff-region-order.md),
        // extended to context the other source draws as context: a row
        // another source already draws is dropped here rather than drawn
        // twice ([hiddenContextLines]). Empty for a single source, so
        // `2 file` mode is untouched.
        hiddenLines: hidden[sourceIndex][hunkIndex] ?? const <int>{},
      )) {
        blocks.add((
          sourceIndex: sourceIndex,
          hunkIndex: hunkIndex,
          segment: segment,
          // The empty case is unreachable by construction -- a gap
          // segment is only emitted for a non-empty run and a scope
          // always has at least one changed line -- so it only has to be
          // a total order, not a meaningful position.
          position: segment.lineIndices.isEmpty
              ? (line: source.staged ? hunk.newStart : hunk.oldStart, offset: 0)
              : indexPositionOf(
                  hunk,
                  segment.lineIndices.first,
                  staged: source.staged,
                ),
        ));
      }
    }
  }

  // Ruling U1 (docs/records/2026-10-04-merged-diff-region-order.md):
  // 「我要對齊的不是行號，是 git 判斷出的區域變更」. Ordering
  // *regions* asserts only that one region precedes another in the file,
  // which is true in the index coordinates both diffs already carry. It is
  // not the hard line alignment 變體 B's own note forbids -- that would
  // claim two rows from two different diffs are the same line.
  //
  // Sorted, never merged: 「unstage, stage 必定是不同 scope」, so two
  // regions at the same position stay two cards with two buttons.
  //
  // Decorated with the original index because [List.sort] is not stable
  // and the tie-break has to be deterministic: at equal positions the
  // unstaged side comes first, which is the reading order the two-column
  // layout taught. Skipped entirely for a single source, so `2 file` mode
  // provably cannot be reordered by this (U6).
  if (sides.length > 1) {
    final List<int> order = <int>[for (int i = 0; i < blocks.length; i++) i];
    order.sort((int a, int b) {
      final int byPosition = compareIndexPositions(
        blocks[a].position,
        blocks[b].position,
      );
      if (byPosition != 0) return byPosition;
      final int bySource = blocks[a].sourceIndex.compareTo(
        blocks[b].sourceIndex,
      );
      if (bySource != 0) return bySource;
      return a.compareTo(b);
    });
    final List<DiffBlock> sorted = <DiffBlock>[
      for (final int i in order) blocks[i],
    ];
    blocks
      ..clear()
      ..addAll(sorted);
  }

  return blocks;
}
