// Splits the full-file view's open and scroll cost into its layers, so a
// fix is chosen from a number rather than a guess (CLAUDE.md standing rule
// 5). Each variant adds one layer to the one before it; E swaps the eager
// Column for a lazy ListView. A measurement: prints, asserts nothing.
//
//   flutter drive --profile -d macos --driver=integration_test/perf/driver.dart \
//     --target=integration_test/perf/diff_row_cost_perf_test.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/features/diff/selection_touch.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';
import 'package:integration_test/integration_test.dart';

double _ms(Duration d) => d.inMicroseconds / 1000;

double _percentile(List<double> sorted, double p) =>
    sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];

List<DiffLine> _lines(int n) => <DiffLine>[
  for (int l = 1; l <= n; l++)
    DiffLine(
      kind: DiffLineKind.context,
      oldLine: l,
      newLine: l,
      text: '    final value$l = compute(input, $l); // body',
    ),
];

enum _Variant { a, b, c, d, e }

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const Color backdrop = Color(0xFF101010);

  Widget body(_Variant v, List<DiffLine> lines, ScrollController vertical) {
    final SelectionTouchTracker tracker = SelectionTouchTracker();
    Widget row(int i) => switch (v) {
      _Variant.a => Text(lines[i].text, style: kDiffCodeTextStyle),
      _Variant.b || _Variant.c => DiffLineView(softWrap: false, line: lines[i]),
      _Variant.d || _Variant.e => SelectionTouchRow(
        tracker: tracker,
        rowKey: 'p:$i',
        child: DiffLineView(softWrap: false, line: lines[i]),
      ),
    };
    if (v == _Variant.e) {
      return GbmCodeHScroll(
        contentWidth: 1400,
        verticalController: vertical,
        backdrop: backdrop,
        child: SelectionArea(
          child: ListView.builder(
            controller: vertical,
            itemCount: lines.length,
            itemBuilder: (BuildContext context, int i) => row(i),
          ),
        ),
      );
    }
    final Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[for (int i = 0; i < lines.length; i++) row(i)],
    );
    return GbmCodeScrollWell(
      contentWidth: 1400,
      verticalController: vertical,
      backdrop: backdrop,
      child: v == _Variant.a || v == _Variant.b
          ? column
          : SelectionArea(child: column),
    );
  }

  for (final (int total, _Variant v) in <(int, _Variant)>[
    for (final _Variant v in _Variant.values) (5000, v),
    (20000, _Variant.e),
  ]) {
    testWidgets('variant ${v.name}, $total lines', (WidgetTester tester) async {
      final List<DiffLine> lines = _lines(total);
      final ScrollController vertical = ScrollController();
      addTearDown(vertical.dispose);
      final List<FrameTiming> timings = <FrameTiming>[];
      void collect(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(collect);
      addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(collect),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      timings.clear();

      final Stopwatch open = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: body(v, lines, vertical)),
        ),
      );
      open.stop();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      final double openBuild = timings.isEmpty
          ? double.nan
          : timings
                .map((FrameTiming t) => _ms(t.buildDuration))
                .reduce((double a, double b) => a > b ? a : b);
      timings.clear();

      final double extent = vertical.position.maxScrollExtent;
      const int frames = 120;
      for (int i = 1; i <= frames; i++) {
        vertical.jumpTo(extent * i / frames);
        await tester.pump();
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      final List<double> build =
          timings.map((FrameTiming t) => _ms(t.buildDuration)).toList()..sort();
      // ignore: avoid_print
      print(
        'ROWCOST variant=${v.name} lines=$total '
        'openWallMs=${(open.elapsedMicroseconds / 1000).toStringAsFixed(1)} '
        'openBuildMs=${openBuild.toStringAsFixed(1)} '
        'scrollFrames=${timings.length} '
        'scrollBuildP90=${_percentile(build, .9).toStringAsFixed(1)} '
        'scrollBuildMax=${_percentile(build, 1).toStringAsFixed(1)}',
      );
    });
  }
}
