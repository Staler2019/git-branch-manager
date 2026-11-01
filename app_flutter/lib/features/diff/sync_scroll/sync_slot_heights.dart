import 'package:flutter/foundation.dart';

/// How tall each synced segment's slot is, and where each slot starts.
///
/// Every column's own height in a segment, and its lead -- how far down
/// its first code row starts, or none -- is its estimate until a measured
/// one is [report]ed. A column whose first code row sits higher than
/// another's pads the difference at the start of its run ([topPad]), so the
/// first code rows line up (plan: Slice H, 「所有非程式碼列」). A slot is as
/// tall as its tallest padded column; a shorter column pads the rest at the
/// end of its run ([spacerHeight], 「短側尾部插高度」). Since every column
/// pads to the same slots, they all share one set of slot tops
/// ([offsetOf]), which is what lets one column's offset be mirrored into
/// another's.
///
/// **The prefix of slot tops is a cache**
/// ([CULT-cache-documents-three-things]): its key is the whole table of
/// column heights and leads, so any [report] that changes either
/// invalidates it (and is the only thing that does); it is rebuilt in O(segments) on the next
/// read, not on the report, so a frame of many reports pays once. A missed
/// invalidation would hand stale tops to the mirror, and the columns would
/// settle out of line by the changed height. Rebuilding beat a Fenwick tree
/// by being simpler at ≤ 19.2 µs per frame for 20k segments (measured
/// 2026-10-25, ledger).
class SyncSlotHeights extends ChangeNotifier {
  SyncSlotHeights._(this._columns, this._segments)
    : _own = Float64List(_columns * _segments),
      _lead = Float64List(_columns * _segments)
        ..fillRange(0, _columns * _segments, double.nan);

  /// [estimate] seeds every column's height in every segment, and
  /// [estimateLead] its lead (null: no code row; the default for all).
  factory SyncSlotHeights.forSegments({
    required int columns,
    required int segments,
    required double Function(int column, int segment) estimate,
    double? Function(int column, int segment)? estimateLead,
  }) {
    final SyncSlotHeights h = SyncSlotHeights._(columns, segments);
    for (int c = 0; c < columns; c++) {
      for (int k = 0; k < segments; k++) {
        h._own[c * segments + k] = estimate(c, k);
        h._lead[c * segments + k] = estimateLead?.call(c, k) ?? double.nan;
      }
    }
    return h;
  }

  final int _columns;
  final int _segments;
  final Float64List _own;

  /// Each column's lead in each segment; NaN where it has no code row.
  final Float64List _lead;
  Float64List? _tops;
  int _prefixBuilds = 0;

  /// How many times the prefix was rebuilt; for the counting test.
  int get prefixBuilds => _prefixBuilds;

  int get segmentCount => _segments;

  /// [column]'s measured height in [segment], and its [lead] (null: no code
  /// row there). Notifies only when either changed: even when the slot does
  /// not, that column's own spacers do.
  void report(int column, int segment, double height, {double? lead}) {
    final int i = column * _segments + segment;
    final double l = lead ?? double.nan;
    if (_own[i] == height && _sameLead(_lead[i], l)) return;
    _own[i] = height;
    _lead[i] = l;
    _tops = null;
    notifyListeners();
  }

  static bool _sameLead(double a, double b) => a == b || (a.isNaN && b.isNaN);

  /// The lowest first code row in [segment], from its run's top; NaN when no
  /// column has one.
  double _leadMax(int segment) {
    double m = double.nan;
    for (int c = 0; c < _columns; c++) {
      final double v = _lead[c * _segments + segment];
      if (!v.isNaN && (m.isNaN || v > m)) m = v;
    }
    return m;
  }

  /// What [column] pads at the start of its run in [segment]: what its first
  /// code row needs to come down to the lowest one; nothing without one.
  double topPad(int column, int segment) {
    final double own = _lead[column * _segments + segment];
    if (own.isNaN) return 0;
    return _leadMax(segment) - own;
  }

  double slotHeight(int segment) {
    final double lead = _leadMax(segment);
    double h = 0;
    for (int c = 0; c < _columns; c++) {
      final int i = c * _segments + segment;
      final double v =
          _own[i] + (_lead[i].isNaN || lead.isNaN ? 0 : lead - _lead[i]);
      if (v > h) h = v;
    }
    return h;
  }

  /// What [column] pads at the end of its run in [segment].
  double spacerHeight(int column, int segment) =>
      slotHeight(segment) -
      topPad(column, segment) -
      _own[column * _segments + segment];

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
