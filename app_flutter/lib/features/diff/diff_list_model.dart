import 'dart:typed_data';

import '../../data/models/parsed_diff.dart';
import 'diff_block_order.dart';
import 'diff_full_file_fill.dart';
import 'diff_row_keys.dart';
import 'diff_scopes.dart';

/// The heights a [DiffListModel] estimates its items from.
///
/// [rowExtent] is one unwrapped code line. [cardChromeExtent] and
/// [gapChromeExtent] are what a card and a gap draw besides their rows (a
/// card's head, borders and margins). [charsPerLine] is how many characters
/// one wrapped line holds, or 0 when soft wrap is off and every row is one
/// line.
typedef DiffListMetrics = ({
  double rowExtent,
  double headingExtent,
  double cardChromeExtent,
  double gapChromeExtent,
  int charsPerLine,
});

/// What a synced `2 file` column needs to pad its segments (plan: Slice S).
///
/// [segmentOfUnit] is the segment of every sync unit of the column's blocks,
/// in order: a card or gap block is one unit, a fill run one per row
/// (`syncUnitSpans`). [spacerExtentOf] is what the column pads at the end of
/// a segment; only the estimates read it.
typedef DiffListSync = ({
  List<int> segmentOfUnit,
  int segmentCount,
  double Function(int segment) spacerExtentOf,
});

/// Estimated item heights, read off the eager layout at the test font
/// (row 22, heading 22, a card's head and margins 49, a gap's margins 4,
/// a column head 29). A jump reads them and corrects itself once the target is
/// built, and a synced column starts its slot heights from them until each
/// item is measured; nothing is laid out from them.
const DiffListMetrics kDiffListEstimate = (
  rowExtent: 22,
  headingExtent: 22,
  cardChromeExtent: 49,
  gapChromeExtent: 4,
  charsPerLine: 0,
);
const double kDiffLeadingEstimate = 29;

/// One item of the lazily built diff list.
sealed class DiffListItem {
  const DiffListItem();
}

/// Something the view draws above the diff (a column head, a notice); the
/// model only knows its extent.
final class DiffLeadingItem extends DiffListItem {
  const DiffLeadingItem(this.index);

  final int index;
}

/// The `@@` heading of [block]'s hunk, drawn above it in excerpt mode.
final class DiffHeadingItem extends DiffListItem {
  const DiffHeadingItem(this.block);

  final DiffBlock block;
}

/// A whole card or a whole gap. A card is never split across items: its
/// head, rows and nested one-shot block are laid out together.
final class DiffBlockItem extends DiffListItem {
  const DiffBlockItem(this.block);

  final DiffBlock block;
}

/// One full-file fill row. One per item, so a 5k-line file builds only the
/// rows on screen.
final class DiffFillItem extends DiffListItem {
  const DiffFillItem(this.row);

  final DiffFillRow row;
}

/// The end of a synced column's run in [segment]: as tall as the tallest
/// column's run there less this column's own, so every column's next
/// segment starts at the same height (「短側尾部插高度」). Draws no row.
final class DiffSpacerItem extends DiffListItem {
  const DiffSpacerItem(this.segment);

  final int segment;
}

/// The painted diff list as something a lazy list can index: its items, the
/// row keys in painted order, and an estimated vertical position for each
/// item.
///
/// Built per build of the view from the blocks
/// [orderedDiffBlocks] orders, so the order the rows are keyed in is the
/// order they are painted in ([SPEC-range-follows-paint-order]). Positions
/// are estimates -- a card's real height depends on its width and on the
/// selection -- good enough to jump near something and let the view correct
/// itself once it is built.
class DiffListModel {
  /// [headings] is whether a hunk heading goes above each change of source
  /// or hunk, which is excerpt mode; full-file mode draws none. Fill blocks
  /// neither draw a heading nor reset which hunk was last headed, the same
  /// rule the view's own loop follows.
  ///
  /// With [sync], every segment of the column ends in a [DiffSpacerItem],
  /// a segment this column has nothing in included, and segment 0 is the
  /// leading items'. A heading goes with the block it heads. Rows, cards
  /// and keys are exactly what they are without it.
  factory DiffListModel.fromBlocks(
    List<DiffBlock> blocks, {
    required List<DiffSide> sides,
    required bool headings,
    required DiffListMetrics metrics,
    List<double> leadingExtents = const <double>[],
    DiffListSync? sync,
  }) {
    final List<DiffListItem> items = <DiffListItem>[];
    final List<double> extents = <double>[];
    final List<String> rowKeys = <String>[];
    final List<int> itemRowStart = <int>[];
    final List<int> cardItems = <int>[];
    final List<int> changedRows = <int>[];
    final List<int> fillRunOffsets = <int>[];
    final List<int> segmentOfItem = <int>[];
    int segment = 0;
    int unit = 0;

    double rowExtentOf(DiffLine line) {
      final int chars = metrics.charsPerLine;
      if (chars <= 0) return metrics.rowExtent;
      final int lines = (line.text.length + chars - 1) ~/ chars;
      return metrics.rowExtent * (lines < 1 ? 1 : lines);
    }

    void add(DiffListItem item, double extent) {
      itemRowStart.add(rowKeys.length);
      items.add(item);
      extents.add(extent);
      fillRunOffsets.add(0);
      segmentOfItem.add(segment);
    }

    // Closes every segment before [next] with its spacer.
    void padTo(int next) {
      if (sync == null) return;
      while (segment < next) {
        add(DiffSpacerItem(segment), sync.spacerExtentOf(segment));
        segment++;
      }
    }

    int segmentOfNextUnit() => sync == null ? 0 : sync.segmentOfUnit[unit++];

    for (int i = 0; i < leadingExtents.length; i++) {
      add(DiffLeadingItem(i), leadingExtents[i]);
    }

    int? lastSourceIndex;
    int? lastHunkIndex;
    for (final DiffBlock block in blocks) {
      if (block.segment case DiffFillSegment(:final List<DiffFillRow> rows)) {
        // One segment is one run: [orderedDiffBlocks] joins adjacent fill
        // rows whatever their source.
        for (int k = 0; k < rows.length; k++) {
          final DiffFillRow row = rows[k];
          padTo(segmentOfNextUnit());
          add(DiffFillItem(row), rowExtentOf(row.line));
          fillRunOffsets[items.length - 1] = k;
          rowKeys.add(selectionFillRowKey(row.sourceIndex, row.indexLine));
        }
        continue;
      }
      padTo(segmentOfNextUnit());
      if (headings &&
          (block.sourceIndex != lastSourceIndex ||
              block.hunkIndex != lastHunkIndex)) {
        lastSourceIndex = block.sourceIndex;
        lastHunkIndex = block.hunkIndex;
        add(DiffHeadingItem(block), metrics.headingExtent);
      }

      final List<DiffLine> lines =
          sides[block.sourceIndex].file!.hunks[block.hunkIndex].lines;
      final bool card = block.segment is DiffScopeSegment;
      if (card) cardItems.add(items.length);
      final int item = items.length;
      add(DiffBlockItem(block), 0);
      double extent = card ? metrics.cardChromeExtent : metrics.gapChromeExtent;
      for (final int lineIndex in block.segment.lineIndices) {
        final DiffLine line = lines[lineIndex];
        if (card && line.kind != DiffLineKind.context) {
          changedRows.add(rowKeys.length);
        }
        rowKeys.add(
          selectionRowKey(block.sourceIndex, block.hunkIndex, lineIndex),
        );
        extent += rowExtentOf(line);
      }
      extents[item] = extent;
    }
    padTo(sync?.segmentCount ?? 0);
    itemRowStart.add(rowKeys.length);

    final Float64List offsets = Float64List(items.length + 1);
    for (int i = 0; i < items.length; i++) {
      offsets[i + 1] = offsets[i] + extents[i];
    }
    final Int32List itemOfRow = Int32List(rowKeys.length);
    for (int i = 0; i < items.length; i++) {
      for (int r = itemRowStart[i]; r < itemRowStart[i + 1]; r++) {
        itemOfRow[r] = i;
      }
    }

    return DiffListModel._(
      List<DiffListItem>.unmodifiable(items),
      List<String>.unmodifiable(rowKeys),
      Map<String, int>.unmodifiable(<String, int>{
        for (int r = 0; r < rowKeys.length; r++) rowKeys[r]: r,
      }),
      Int32List.fromList(itemRowStart),
      itemOfRow,
      List<int>.unmodifiable(cardItems),
      List<int>.unmodifiable(changedRows),
      offsets,
      Int32List.fromList(fillRunOffsets),
      Int32List.fromList(segmentOfItem),
    );
  }

  DiffListModel._(
    this.items,
    this.rowKeys,
    this._rowIndex,
    this._itemRowStart,
    this._itemOfRow,
    this.cardItems,
    this.changedRows,
    this._offsets,
    this._fillRunOffsets,
    this._segmentOfItem,
  );

  /// Every item, in painted order: the leading items, then the diff.
  final List<DiffListItem> items;

  /// Every row's key ([selectionRowKey], [selectionFillRowKey]), in painted
  /// order -- the order a drag's range and `Shift + ↑ ↓` walk.
  final List<String> rowKeys;

  /// The item index of each card, in painted order: card `n` (1-based, as
  /// its head numbers it) is `items[cardItems[n - 1]]`.
  final List<int> cardItems;

  /// The indices into [rowKeys] of every changed card row, ascending.
  final List<int> changedRows;

  final Map<String, int> _rowIndex;
  final Int32List _itemRowStart;
  final Int32List _itemOfRow;

  /// `_offsets[i]` is the estimated top of item `i`; the last entry is the
  /// total.
  final Float64List _offsets;

  final Int32List _fillRunOffsets;
  final Int32List _segmentOfItem;

  /// The sync segment item [item] is in; 0 for every item when unsynced.
  int segmentOfItem(int item) => _segmentOfItem[item];

  /// How many fill rows of the same run come before fill item [item]: the
  /// segment of the run's dashed rule it draws. 0 for any other item.
  int fillRunOffsetOf(int item) => _fillRunOffsets[item];

  /// Where [key] sits in [rowKeys], or null when no row has it.
  int? rowIndexOf(String key) => _rowIndex[key];

  /// The item that draws row [row].
  int itemOfRow(int row) => _itemOfRow[row];

  /// The first row item [item] draws; with [rowCountOf], its run of rows.
  int firstRowOf(int item) => _itemRowStart[item];

  /// How many rows item [item] draws: none for a heading or a leading item.
  int rowCountOf(int item) => _itemRowStart[item + 1] - _itemRowStart[item];

  /// Item [item]'s estimated height.
  double extentOf(int item) => _offsets[item + 1] - _offsets[item];

  /// Item [item]'s estimated top; `offsetOf(items.length)` is the total.
  double offsetOf(int item) => _offsets[item];

  double get totalExtent => _offsets[items.length];

  /// The item whose estimated extent holds [y], clamped to the first and
  /// last item; null for an empty list.
  int? itemAt(double y) {
    if (items.isEmpty) return null;
    // The last i with _offsets[i] <= y, by binary search.
    int lo = 0;
    int hi = items.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (_offsets[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
