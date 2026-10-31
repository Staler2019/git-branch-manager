import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [SliverList] that a far jump does not walk.
///
/// [RenderSliverList] has no extents, so it lays out from the child it
/// already has to wherever the scroll offset is, building every item in
/// between: one jump a quarter of the way down a 5,000-line diff built
/// 4,413 rows, for about 50 on screen. When the offset is further than the
/// cache extent from every child laid out, this one drops them and starts
/// at the item [indexAt] names, placed at [offsetOf]; the rest of the layout
/// is [RenderSliverList]'s own, which also corrects the estimate's error
/// when a scroll back up reaches item 0 (plan: Slice J).
///
/// Both callbacks are estimates in the list's own scroll coordinates. Where
/// they are off, the items still run on without a gap; only where a seeded
/// item lands is off, by the estimate's error above it. The extent past the
/// last item laid out is counted in the same estimate, `offsetOf(count)`
/// being the total: the framework's own guess (the laid-out items' average,
/// times the rest) put a thumb dragged to 90% past the estimated end, so
/// the seed landed on the last item and the list sprang back from beyond
/// it.
class SeededSliverList extends SliverMultiBoxAdaptorWidget {
  const SeededSliverList({
    super.key,
    required super.delegate,
    required this.indexAt,
    required this.offsetOf,
  });

  /// The item at scroll offset `offset`, estimated.
  final int Function(double offset) indexAt;

  /// Item `index`'s estimated top; `offsetOf(count)` is the total.
  final double Function(int index) offsetOf;

  @override
  double? estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    final int? count = delegate.estimatedChildCount;
    if (count == null || lastIndex >= count - 1) {
      return super.estimateMaxScrollOffset(
        constraints,
        firstIndex,
        lastIndex,
        leadingScrollOffset,
        trailingScrollOffset,
      );
    }
    return trailingScrollOffset + offsetOf(count) - offsetOf(lastIndex + 1);
  }

  @override
  RenderSeededSliverList createRenderObject(BuildContext context) =>
      RenderSeededSliverList(
        childManager: context as SliverMultiBoxAdaptorElement,
        indexAt: indexAt,
        offsetOf: offsetOf,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSeededSliverList renderObject,
  ) {
    renderObject
      ..indexAt = indexAt
      ..offsetOf = offsetOf;
  }
}

class RenderSeededSliverList extends RenderSliverList {
  RenderSeededSliverList({
    required super.childManager,
    required this.indexAt,
    required this.offsetOf,
  });

  int Function(double offset) indexAt;
  double Function(int index) offsetOf;

  /// How many layouts started at a seeded item; for the counting tests.
  int seedCount = 0;

  @override
  void performLayout() {
    final double start = constraints.scrollOffset + constraints.cacheOrigin;
    final double end = start + constraints.remainingCacheExtent;
    final int count = childManager.childCount;
    // The end the last layout reported, which is what a scrollbar dragged
    // to the bottom was aiming at.
    final double? reportedEnd = geometry?.scrollExtent;
    bool seeded = false;
    if (count > 0 && _isFar(start, end)) {
      if (firstChild != null) collectGarbage(childCount, 0);
      final int index = indexAt(constraints.scrollOffset).clamp(0, count - 1);
      if (addInitialChild(index: index, layoutOffset: offsetOf(index))) {
        seedCount++;
        seeded = true;
      }
    }
    super.performLayout();
    if (seeded && reportedEnd != null) _keepAtEnd(count, reportedEnd);
  }

  /// A seeded window that reached the end the list last reported stays at
  /// the end. Where the layout puts the end is off from that report by the
  /// estimate's error, and left alone a thumb dragged to the bottom would
  /// stop short of it or past it; a walk would have measured the items on
  /// the way and sprung back.
  void _keepAtEnd(int count, double reportedEnd) {
    final RenderBox? last = lastChild;
    if (geometry?.scrollOffsetCorrection != null || last == null) return;
    final double window =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    if (indexOf(last) != count - 1 || window < reportedEnd) return;
    final double? top = childScrollOffset(last);
    if (top == null) return;
    final double error = top + paintExtentOf(last) - reportedEnd;
    if (error.abs() > precisionErrorTolerance) {
      geometry = SliverGeometry(scrollOffsetCorrection: error);
    }
  }

  /// Whether the layout would walk more than a cache extent to reach
  /// [start]..[end]; walking that little is cheaper than reseeding.
  bool _isFar(double start, double end) {
    final RenderBox? first = firstChild;
    final RenderBox? last = lastChild;
    // No children: RenderSliverList would start at item 0, at 0.
    if (first == null || last == null) {
      return start > constraints.remainingCacheExtent;
    }
    final double? top = childScrollOffset(first);
    final double? lastTop = childScrollOffset(last);
    // Children without a layout offset (reordered) or a size: leave them to
    // RenderSliverList, which knows how to recover from that.
    if (top == null || lastTop == null || !last.hasSize) return false;
    final double bottom = lastTop + paintExtentOf(last);
    final double gap = start > bottom
        ? start - bottom
        : (top > end ? top - end : 0);
    return gap > constraints.remainingCacheExtent;
  }
}
