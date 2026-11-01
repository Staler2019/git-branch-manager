// Measures the full-file view against its budgets (open <= 100 ms, scroll
// <= 16 ms a frame) for 1k / 5k / 20k-line files. A measurement, not a
// gate: it prints numbers and asserts nothing, because a timing assertion on
// a developer machine is a flake. Outside `integration_test/*_test.dart` so
// the device batch loop does not pick it up.
//
//   flutter test integration_test/perf/full_file_view_perf_test.dart \
//     -d macos              (debug)
//   flutter drive --profile -d macos --driver=integration_test/perf/driver.dart \
//     --target=integration_test/perf/full_file_view_perf_test.dart   (profile)
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:integration_test/integration_test.dart';

/// A file of [total] lines with one-line replacements at [edited], as one
/// hunk per edit with [context] lines either side (the -U3 shape), or one
/// hunk of the whole file when [context] covers it (the full shape).
DiffFile _replacements(int total, List<int> edited, {required int context}) {
  final List<DiffHunk> hunks = <DiffHunk>[];
  final List<(int, int)> ranges = <(int, int)>[
    for (final int e in edited)
      (
        (e - context).clamp(1, total).toInt(),
        (e + context).clamp(1, total).toInt(),
      ),
  ];
  final List<(int, int)> merged = <(int, int)>[];
  for (final (int, int) r in ranges) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2 + 1) {
      merged[merged.length - 1] = (merged.last.$1, r.$2);
    } else {
      merged.add(r);
    }
  }
  for (final (int from, int to) in merged) {
    final List<DiffLine> lines = <DiffLine>[];
    for (int l = from; l <= to; l++) {
      final String text = '    final value$l = compute(input, $l); // body';
      if (edited.contains(l)) {
        lines
          ..add(
            DiffLine(
              kind: DiffLineKind.removed,
              oldLine: l,
              newLine: 0,
              text: text,
            ),
          )
          ..add(
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: l,
              text: '$text edited',
            ),
          );
      } else {
        lines.add(
          DiffLine(
            kind: DiffLineKind.context,
            oldLine: l,
            newLine: l,
            text: text,
          ),
        );
      }
    }
    hunks.add(
      DiffHunk(
        oldStart: from,
        oldCount: to - from + 1,
        newStart: from,
        newCount: to - from + 1,
        heading: '',
        lines: lines,
      ),
    );
  }
  return DiffFile(
    oldPath: 'a.dart',
    newPath: 'a.dart',
    kind: FileChangeKind.modified,
    oldMode: '',
    newMode: '',
    oldBlob: '',
    newBlob: '',
    binary: false,
    similarity: 0,
    addedLines: edited.length,
    removedLines: edited.length,
    displayPath: 'a.dart',
    hunks: hunks,
  );
}

double _ms(Duration d) => d.inMicroseconds / 1000;

double _percentile(List<double> sorted, double p) =>
    sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final bool softWrap in <bool>[false, true]) {
    for (final int total in <int>[1000, 5000, 20000]) {
      testWidgets('full file, $total lines, softWrap $softWrap', (
        WidgetTester tester,
      ) async {
        final List<int> edited = <int>[total ~/ 4, (3 * total) ~/ 4];
        final DiffFile excerpt = _replacements(total, edited, context: 3);
        final DiffFile full = _replacements(total, edited, context: total);
        final ScrollController vertical = ScrollController();
        addTearDown(vertical.dispose);

        final List<FrameTiming> timings = <FrameTiming>[];
        void collect(List<FrameTiming> t) => timings.addAll(t);
        SchedulerBinding.instance.addTimingsCallback(collect);
        addTearDown(
          () => SchedulerBinding.instance.removeTimingsCallback(collect),
        );

        // Settle an empty frame first, so the open measures this view and
        // not the first frame of the app.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        final Stopwatch open = Stopwatch()..start();
        final List<DiffFillRow>? fill = fullFileFillRows(<DiffFillSource>[
          (excerpt: excerpt, full: full, staged: false),
        ]);
        final double fillMs = open.elapsedMicroseconds / 1000;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: ScopedDiffView(
                contentWidth: 1400,
                verticalController: vertical,
                backdrop: const Color(0xFF101010),
                softWrap: softWrap,
                fill: fill,
                sources: <ScopedDiffSource>[
                  ScopedDiffSource(
                    title: 'Unstaged',
                    file: excerpt,
                    staged: false,
                    onStageScope: (int h, List<int> l) {},
                  ),
                ],
              ),
            ),
          ),
        );
        open.stop();

        // Timings are reported in batches; give the open frame time to land
        // before reading it, then scroll from a clean slate.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)),
        );
        final List<FrameTiming> openFrames = List<FrameTiming>.of(timings);
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
            timings.map((FrameTiming t) => _ms(t.buildDuration)).toList()
              ..sort();
        final List<double> raster =
            timings.map((FrameTiming t) => _ms(t.rasterDuration)).toList()
              ..sort();
        final double openBuild = openFrames.isEmpty
            ? double.nan
            : openFrames
                  .map((FrameTiming t) => _ms(t.buildDuration))
                  .reduce((double a, double b) => a > b ? a : b);
        final double openRaster = openFrames.isEmpty
            ? double.nan
            : openFrames
                  .map((FrameTiming t) => _ms(t.rasterDuration))
                  .reduce((double a, double b) => a > b ? a : b);

        // ignore: avoid_print
        print(
          'PERF lines=$total softWrap=$softWrap fillRows=${fill?.length} '
          'fillMs=${fillMs.toStringAsFixed(2)} '
          'openWallMs=${(open.elapsedMicroseconds / 1000).toStringAsFixed(1)} '
          'openBuildMs=${openBuild.toStringAsFixed(1)} '
          'openRasterMs=${openRaster.toStringAsFixed(1)} '
          'scrollFrames=${timings.length} '
          'scrollBuildP90=${_percentile(build, .9).toStringAsFixed(1)} '
          'scrollBuildMax=${_percentile(build, 1).toStringAsFixed(1)} '
          'scrollRasterP90=${_percentile(raster, .9).toStringAsFixed(1)} '
          'scrollRasterMax=${_percentile(raster, 1).toStringAsFixed(1)} '
          'extent=${extent.toStringAsFixed(0)}',
        );
        expect(fill, isNotNull);
      });
    }
  }
}
