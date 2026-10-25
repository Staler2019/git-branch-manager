import 'package:flutter/foundation.dart';

/// How tall each synced segment's slot is, and where each slot starts.
///
/// Every column's own height in a segment is its estimate until a measured
/// one is [report]ed. A slot is as tall as its tallest column; a shorter
/// column pads the difference at the end of its run ([spacerHeight], 「短側
/// 尾部插高度」). Since every column pads to the same slots, they all share
/// one set of slot tops ([offsetOf]), which is what lets one column's offset
/// be mirrored into another's.
///
/// **The prefix of slot tops is a cache**
/// ([CULT-cache-documents-three-things]): its key is the whole table of
/// column heights, so any [report] that changes a value invalidates it (and
/// is the only thing that does); it is rebuilt in O(segments) on the next
/// read, not on the report, so a frame of many reports pays once. A missed
/// invalidation would hand stale tops to the mirror, and the columns would
/// settle out of line by the changed height. Rebuilding beat a Fenwick tree
/// by being simpler at ≤ 19.2 µs per frame for 20k segments (measured
/// 2026-10-25, ledger).
class SyncSlotHeights extends ChangeNotifier {
  SyncSlotHeights._(this._columns, this._segments)
    : _own = Float64List(_columns * _segments);

  /// [estimate] seeds every column's height in every segment.
  factory SyncSlotHeights.forSegments({
    required int columns,
    required int segments,
    required double Function(int column, int segment) estimate,
  }) {
    final SyncSlotHeights h = SyncSlotHeights._(columns, segments);
    for (int c = 0; c < columns; c++) {
      for (int k = 0; k < segments; k++) {
        h._own[c * segments + k] = estimate(c, k);
      }
    }
    return h;
  }

  final int _columns;
  final int _segments;
  final Float64List _own;
  Float64List? _tops;
  int _prefixBuilds = 0;

  /// How many times the prefix was rebuilt; for the counting test.
  int get prefixBuilds => _prefixBuilds;

  int get segmentCount => _segments;

  /// [column]'s measured height in [segment]. Notifies only when it changed:
  /// even when the slot does not, that column's own spacer does.
  void report(int column, int segment, double height) {
    final int i = column * _segments + segment;
    if (_own[i] == height) return;
    _own[i] = height;
    _tops = null;
    notifyListeners();
  }

  double slotHeight(int segment) {
    double h = 0;
    for (int c = 0; c < _columns; c++) {
      final double v = _own[c * _segments + segment];
      if (v > h) h = v;
    }
    return h;
  }

  /// What [column] pads at the end of its run in [segment].
  double spacerHeight(int column, int segment) =>
      slotHeight(segment) - _own[column * _segments + segment];

  Float64List get _prefix {
    final Float64List? cached = _tops;
    if (cached != null) return cached;
    final Float64List tops = Float64List(_segments + 1);
    for (int k = 0; k < _segments; k++) {
      tops[k + 1] = tops[k] + slotHeight(k);
    }
    _prefixBuilds++;
    return _tops = tops;
  }

  /// The top of [segment]'s slot, shared by every column.
  double offsetOf(int segment) => _prefix[segment];

  double get totalHeight => _prefix[_segments];

  double toOffset(int segment, double within) => _prefix[segment] + within;

  /// The slot [offset] falls in and how far into it. A slot top belongs to
  /// that slot (`within == 0`), skipping any empty slots stacked on it;
  /// outside the slots clamps to either end.
  ({int segment, double within}) locate(double offset) {
    final Float64List tops = _prefix;
    if (offset <= 0) return (segment: 0, within: 0.0);
    // The last segment whose top is at or above the offset.
    int lo = 0;
    int hi = _segments - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (tops[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final double within = offset - tops[lo];
    final double slot = tops[lo + 1] - tops[lo];
    return (segment: lo, within: within > slot ? slot : within);
  }
}
