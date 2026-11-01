/// The span of positions one column item covers, inclusive at both ends.
///
/// `2 file` uses `IndexPosition` (a card covers its first through last row, a
/// fill row only itself); conflict resolve uses the index of its shared
/// `ParsedConflictFile.segments` entry.
typedef SyncSpan<P> = ({P lo, P hi});

/// Which segment each item of each column falls in, and how many there are.
///
/// Segment 0 is the leading one: the items that carry no position (column
/// heads, notices) before any that do. It always exists, possibly empty in
/// every column, so a column whose head is taller than another's has
/// somewhere to even that out.
class SyncSegments {
  const SyncSegments({required this.segmentOf, required this.count});

  /// `segmentOf[column][item]`, non-decreasing down each column.
  final List<List<int>> segmentOf;

  /// Segments 0 through `count - 1`; every one after 0 holds at least one
  /// item of some column.
  final int count;
}

/// Cuts the columns into segments as finely as possible without cutting any
/// column's item in two (plan: Slice S, 「定義」).
///
/// A k-way sweep in position order: an item starts a new segment only when
/// it begins strictly after everything already in the current one ends, so
/// two spans that touch at an end stay together and two that do not are
/// apart. O(N·C) for N items over C columns.
///
/// Each column must list its positioned items in non-decreasing `lo` order,
/// which is paint order for both callers. An item with no position takes the
/// segment of the item before it in its column, or 0.
SyncSegments partitionSyncSegments<P>(
  List<List<SyncSpan<P>?>> columns,
  int Function(P a, P b) compare,
) {
  final List<List<int>> segmentOf = <List<int>>[
    for (final List<SyncSpan<P>?> column in columns)
      List<int>.filled(column.length, 0),
  ];
  final List<int> next = List<int>.filled(columns.length, 0);
  int segment = 0;
  P? reach;
  while (true) {
    int best = -1;
    for (int c = 0; c < columns.length; c++) {
      // An item with no position goes where its column already is.
      while (next[c] < columns[c].length && columns[c][next[c]] == null) {
        segmentOf[c][next[c]] = next[c] == 0 ? 0 : segmentOf[c][next[c] - 1];
        next[c]++;
      }
      if (next[c] == columns[c].length) continue;
      if (best < 0 ||
          compare(columns[c][next[c]]!.lo, columns[best][next[best]]!.lo) < 0) {
        best = c;
      }
    }
    if (best < 0) break;
    final SyncSpan<P> span = columns[best][next[best]]!;
    if (reach == null || compare(span.lo, reach) > 0) {
      segment++;
      reach = span.hi;
    } else if (compare(span.hi, reach) > 0) {
      reach = span.hi;
    }
    segmentOf[best][next[best]] = segment;
    next[best]++;
  }
  return SyncSegments(segmentOf: segmentOf, count: segment + 1);
}
