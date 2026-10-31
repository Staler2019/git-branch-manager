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
/// item lands is off, by the estimate's error above it.
class SeededSliverList extends SliverMultiBoxAdaptorWidget {
  const SeededSliverList({
    super.key,
    required super.delegate,
    required this.indexAt,
    required this.offsetOf,
  });

  /// The item at scroll offset `offset`, estimated.
  final int Function(double offset) indexAt;

  /// Item `index`'s estimated top.
  final double Function(int index) offsetOf;

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
    if (count > 0 && constraints.scrollOffset > 0 && _isFar(start, end)) {
      if (firstChild != null) collectGarbage(childCount, 0);
      final int index = indexAt(constraints.scrollOffset).clamp(0, count - 1);
      if (addInitialChild(index: index, layoutOffset: offsetOf(index))) {
        seedCount++;
      }
    }
    super.performLayout();
  }

  /// Whether the layout would walk more than a cache extent to reach
  /// [start]..[end]; walking that little is cheaper than reseeding.
  bool _isFar(double start, double end) {
    final RenderBox? first = firstChild;
    final RenderBox? last = lastChild;
    if (first == null || last == null) return true;
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
