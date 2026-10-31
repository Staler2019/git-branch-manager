// A far jump in a lazy list without extents walks every item between where
// it is and where it is going (a 5k-line diff built 4,413 rows for one jump
// to a quarter of the way down). [SeededSliverList] starts the layout at the
// item its estimate names instead (plan: Slice J, J1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/widgets/seeded_sliver_list.dart';

const int _count = 1000;

/// Uneven on purpose: 20, 26, 32, 38, 44, then again.
double _height(int i) => 20.0 + (i % 5) * 6;

/// Prefix offsets of [heightOf]; `offsets[_count]` is the total.
List<double> _prefix(double Function(int) heightOf) {
  final List<double> offsets = <double>[0];
  for (int i = 0; i < _count; i++) {
    offsets.add(offsets.last + heightOf(i));
  }
  return offsets;
}

int _indexIn(List<double> offsets, double y) {
  int lo = 0;
  int hi = _count - 1;
  while (lo < hi) {
    final int mid = (lo + hi + 1) >> 1;
    if (offsets[mid] <= y) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

class _Harness {
  _Harness({double Function(int)? estimate, double initialOffset = 0})
    : estimates = _prefix(estimate ?? _height),
      controller = ScrollController(initialScrollOffset: initialOffset);

  final List<double> estimates;
  final ScrollController controller;
  final Set<int> built = <int>{};
  int builds = 0;

  Widget get widget => Directionality(
    textDirection: TextDirection.ltr,
    child: CustomScrollView(
      controller: controller,
      slivers: <Widget>[
        SeededSliverList(
          indexAt: (double y) => _indexIn(estimates, y),
          offsetOf: (int i) => estimates[i],
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int i) {
              builds++;
              built.add(i);
              return SizedBox(
                key: ValueKey<int>(i),
                height: _height(i),
                child: Text('item $i'),
              );
            },
            childCount: _count,
            addAutomaticKeepAlives: false,
          ),
        ),
      ],
    ),
  );

  RenderSeededSliverList render(WidgetTester tester) => tester
      .renderObject<RenderSeededSliverList>(find.byType(SeededSliverList));
}

Future<_Harness> _pump(
  WidgetTester tester, {
  double Function(int)? estimate,
  double initialOffset = 0,
}) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final _Harness h = _Harness(estimate: estimate, initialOffset: initialOffset);
  addTearDown(h.controller.dispose);
  await tester.pumpWidget(h.widget);
  return h;
}

/// The items on screen, top to bottom, with their rects.
List<(int, Rect)> _onScreen(WidgetTester tester) {
  final List<(int, Rect)> out = <(int, Rect)>[];
  for (final Element e in find.byType(SizedBox).evaluate()) {
    final Key? key = e.widget.key;
    if (key is! ValueKey<int>) continue;
    final Rect r = tester.getRect(find.byKey(key));
    if (r.bottom <= 0 || r.top >= 600) continue;
    out.add((key.value, r));
  }
  out.sort(((int, Rect) a, (int, Rect) b) => a.$2.top.compareTo(b.$2.top));
  return out;
}

void _expectContiguous(List<(int, Rect)> items) {
  expect(items, isNotEmpty);
  for (int k = 1; k < items.length; k++) {
    expect(items[k].$1, items[k - 1].$1 + 1, reason: 'indices in order');
    expect(
      items[k].$2.top,
      moreOrLessEquals(items[k - 1].$2.bottom),
      reason: 'item ${items[k].$1} starts where ${items[k - 1].$1} ends',
    );
  }
}

/// Steps of half a viewport, never a far jump, until [to].
Future<void> _walk(WidgetTester tester, _Harness h, double to) async {
  for (int guard = 0; guard < 2000; guard++) {
    final double at = h.controller.position.pixels;
    if ((at - to).abs() < 0.01) return;
    final double next = at > to
        ? (at - 300 < to ? to : at - 300)
        : (at + 300 > to ? to : at + 300);
    h.controller.jumpTo(next);
    await tester.pump();
  }
  fail('never reached $to');
}

void main() {
  testWidgets('a far jump builds only the items near where it lands, '
      'forward and back', (WidgetTester tester) async {
    final _Harness h = await _pump(tester);
    final double total = h.estimates[_count];
    for (final double f in <double>[.25, .75, .1]) {
      h.builds = 0;
      h.controller.jumpTo(total * f);
      await tester.pump();
      expect(h.builds, lessThan(60), reason: 'jump to $f');
    }
    expect(h.render(tester).seedCount, 3);
  });

  testWidgets('with an exact estimate, the item at the top after a far jump '
      'is the one the estimate names, and the items run on without a gap', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _pump(tester);
    final double to = h.estimates[600] + 10;
    h.controller.jumpTo(to);
    await tester.pump();
    final List<(int, Rect)> items = _onScreen(tester);
    expect(items.first.$1, 600);
    expect(items.first.$2.top, moreOrLessEquals(-10));
    _expectContiguous(items);
  });

  testWidgets('with an estimate 30% short, walking back up from a far jump '
      'ends with item 0 at the top and the offset at 0, never seeding on the '
      'way', (WidgetTester tester) async {
    final _Harness h = await _pump(
      tester,
      estimate: (int i) => _height(i) / 1.3,
    );
    h.controller.jumpTo(h.estimates[_count] / 2);
    await tester.pump();
    expect(h.render(tester).seedCount, 1);
    _expectContiguous(_onScreen(tester));

    await _walk(tester, h, 0);
    await tester.pump();
    expect(h.render(tester).seedCount, 1, reason: 'half-viewport steps');
    expect(h.controller.position.pixels, 0);
    final List<(int, Rect)> items = _onScreen(tester);
    expect(items.first.$1, 0);
    expect(items.first.$2.top, 0);
    _expectContiguous(items);
  });

  testWidgets('scrolling in steps of half a viewport never seeds', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _pump(tester);
    await _walk(tester, h, 8000);
    await _walk(tester, h, 2000);
    expect(h.render(tester).seedCount, 0);
    _expectContiguous(_onScreen(tester));
  });

  testWidgets('opening at a stored offset builds only the items near it', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _pump(tester, initialOffset: 20000);
    expect(h.builds, lessThan(60));
    expect(h.controller.position.pixels, 20000);
    expect(h.render(tester).seedCount, 1);
    _expectContiguous(_onScreen(tester));
  });

  testWidgets('an estimate naming an index past the end seeds at the last '
      'item', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    final List<double> offsets = _prefix(_height);
    int builds = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeededSliverList(
              indexAt: (double y) => _count + 50,
              offsetOf: (int i) => offsets[i],
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int i,
              ) {
                builds++;
                return SizedBox(height: _height(i));
              }, childCount: _count),
            ),
          ],
        ),
      ),
    );
    builds = 0;
    controller.jumpTo(offsets[_count] - 600);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(builds, lessThan(60));
    expect(
      tester
          .renderObject<RenderSeededSliverList>(find.byType(SeededSliverList))
          .seedCount,
      1,
    );
  });
}
