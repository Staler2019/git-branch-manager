import '../diff_block_order.dart';
import '../diff_full_file_fill.dart';
import '../diff_scopes.dart';
import 'sync_segments.dart';

/// One column's sync units and where each sits on the index ruler both
/// `2 file` columns share ([indexPositionOf]), for [partitionSyncSegments].
///
/// A card or gap block is one unit, from its first row to its last. A fill
/// run is one unit per row at `(indexLine, 0)`: as one unit, a run would
/// overlap the other column's run across every card between them and the
/// whole full-file view would be one segment. The units are the order
/// `DiffListModel.fromBlocks` meets them in, which is what its
/// `DiffListSync.segmentOfUnit` is read against.
List<SyncSpan<IndexPosition>> syncUnitSpans(
  List<DiffBlock> blocks,
  List<DiffSide> sides,
) {
  final Map<(int, int), List<IndexPosition>> positions =
      <(int, int), List<IndexPosition>>{};
  return <SyncSpan<IndexPosition>>[
    for (final DiffBlock block in blocks)
      if (block.segment case DiffFillSegment(:final List<DiffFillRow> rows))
        for (final DiffFillRow row in rows)
          (
            lo: (line: row.indexLine, offset: 0),
            hi: (line: row.indexLine, offset: 0),
          )
      else
        () {
          final DiffSide side = sides[block.sourceIndex];
          final List<IndexPosition> of = positions.putIfAbsent(
            (block.sourceIndex, block.hunkIndex),
            () => indexPositionsOf(
              side.file!.hunks[block.hunkIndex],
              staged: side.staged,
            ),
          );
          final List<int> lines = block.segment.lineIndices;
          return (lo: of[lines.first], hi: of[lines.last]);
        }(),
  ];
}
