import '../../data/models/parsed_diff.dart';
import 'diff_full_file_fill.dart';
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
///
/// [fill] is the full-file view's unchanged rows ([fullFileFillRows]), or
/// null in excerpt mode. Each is placed on the same index ruler at
/// `(indexLine, 0)` -- an index line no hunk draws, so it never ties with a
/// hunk row -- and adjacent ones are joined into one [DiffFillSegment].
List<DiffBlock> orderedDiffBlocks(
  List<DiffSide> sides,
  List<Map<int, List<DiffScope>>> scopesBySource, {
  List<DiffFillRow>? fill,
}) {
  // Every drawable block of every source, decorated with where it sits on
  // the index -- the ruler the two diffs share ([indexPositionOf]).
  final List<DiffBlock> blocks = <DiffBlock>[];
  final List<Map<int, Set<int>>> hidden = hiddenContextLines(
    sides,
    scopesBySource,
  );

  // In a merged list a context run is placed row by row: placed as one block
  // at its first row, a run straddling the other side's region would paint
  // its later rows above that region (使用者裁定 ②'s ordering half). Cards
  // stay whole -- [splitHunkIntoScopes]' barriers keep the other side's rows
  // out of every card's span, so a card never needs to be cut for the sort.
  final bool merged = sides.length > 1;

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
        if (merged && segment is DiffGapSegment) {
          for (final int line in segment.lineIndices) {
            blocks.add((
              sourceIndex: sourceIndex,
              hunkIndex: hunkIndex,
              segment: DiffGapSegment(List<int>.unmodifiable(<int>[line])),
              position: indexPositionOf(hunk, line, staged: source.staged),
            ));
          }
          continue;
        }
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

  for (final DiffFillRow row in fill ?? const <DiffFillRow>[]) {
    blocks.add((
      sourceIndex: row.sourceIndex,
      hunkIndex: -1,
      segment: DiffFillSegment(
        List<DiffFillRow>.unmodifiable(<DiffFillRow>[row]),
      ),
      position: (line: row.indexLine, offset: 0),
    ));
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
  // unstaged side comes first ([indexRankOf] -- the same rank the scope
  // barriers order by), which is the reading order the two-column layout
  // taught. Skipped for a single source in excerpt mode, so `2 file` mode
  // provably cannot be reordered by this (U6); with a fill it runs, and a
  // lone side's hunk blocks are already in this order, so only the fill
  // moves.
  if (merged || fill != null) {
    final List<int> order = <int>[for (int i = 0; i < blocks.length; i++) i];
    order.sort((int a, int b) {
      final int byPosition = compareIndexPositions(
        blocks[a].position,
        blocks[b].position,
      );
      if (byPosition != 0) return byPosition;
      final int byRank = indexRankOf(
        staged: sides[blocks[a].sourceIndex].staged,
      ).compareTo(indexRankOf(staged: sides[blocks[b].sourceIndex].staged));
      if (byRank != 0) return byRank;
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
      ..addAll(_joinAdjacentGaps(sorted));
  }

  return blocks;
}

/// Joins gap rows of one hunk that the sort left next to each other back
/// into one block (and adjacent fill rows into one run), so a merged list draws the same [DiffGapSegment] runs a
/// lone side would.
///
/// No line-index contiguity check: two rows of one hunk can only be
/// separated by a hidden row, and a hidden row's surviving copy has the same
/// index line, so it is always painted between them -- adjacency already
/// implies consecutive indices (a mutation removing such a check survived
/// every fixture, which is how this was found).
List<DiffBlock> _joinAdjacentGaps(List<DiffBlock> blocks) {
  final List<DiffBlock> out = <DiffBlock>[];
  for (final DiffBlock block in blocks) {
    if (out.isNotEmpty) {
      final DiffBlock last = out.last;
      // Fill rows join whoever supplied them: each row keeps its own source.
      if (block.segment case DiffFillSegment(:final List<DiffFillRow> rows)
          when last.segment is DiffFillSegment) {
        out[out.length - 1] = (
          sourceIndex: last.sourceIndex,
          hunkIndex: last.hunkIndex,
          segment: DiffFillSegment(
            List<DiffFillRow>.unmodifiable(<DiffFillRow>[
              ...(last.segment as DiffFillSegment).rows,
              ...rows,
            ]),
          ),
          position: last.position,
        );
        continue;
      }
      if (block.segment is DiffGapSegment &&
          last.segment is DiffGapSegment &&
          block.sourceIndex == last.sourceIndex &&
          block.hunkIndex == last.hunkIndex) {
        out[out.length - 1] = (
          sourceIndex: last.sourceIndex,
          hunkIndex: last.hunkIndex,
          segment: DiffGapSegment(
            List<int>.unmodifiable(<int>[
              ...last.segment.lineIndices,
              ...block.segment.lineIndices,
            ]),
          ),
          position: last.position,
        );
        continue;
      }
    }
    out.add(block);
  }
  return out;
}
