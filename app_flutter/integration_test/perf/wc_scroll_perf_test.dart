// Measures scrolling the Working Copy diff inside the real app, per side of
// `2 file` and in `unified`, on a 5,000-line file in full-file view. A
// measurement, not a gate: it prints numbers and asserts nothing about time.
//
// full_file_view_perf_test.dart pumps a bare ScopedDiffView, so it cannot see
// what the screen around the view does on a scroll; this one goes through
// WorkingCopyView, which is where that happens.
//
//   flutter drive --profile -d macos --driver=integration_test/perf/driver.dart \
//     --target=integration_test/perf/wc_scroll_perf_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:integration_test/integration_test.dart';

import '../support/real_repo_harness.dart';

const int _total = 5000;

String _lines(Map<int, String> replaced) => <String>[
  for (int n = 1; n <= _total; n++)
    replaced[n] ?? '    final value$n = compute(input, $n); // body',
].join('\n');

double _ms(Duration d) => d.inMicroseconds / 1000;

double _percentile(List<double> sorted, double p) =>
    sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late String repo;
  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_perf_wc_scroll_');
    File('$repo/fixture.txt').writeAsStringSync(_lines(const <int, String>{}));
    runGit(repo, <String>['add', 'fixture.txt']);
    runGit(repo, <String>['commit', '-m', 'add fixture']);
    // One staged edit near the top, one unstaged near the bottom, so both
    // sides of `2 file` hold a card.
    File('$repo/fixture.txt')
        .writeAsStringSync(_lines(const <int, String>{1000: 'STAGED'}));
    runGit(repo, <String>['add', 'fixture.txt']);
    File('$repo/fixture.txt').writeAsStringSync(
      _lines(const <int, String>{1000: 'STAGED', 4000: 'UNSTAGED'}),
    );
  });
  tearDown(() => deleteTempGitRepo(repo));

  testWidgets('scrolling each side', (WidgetTester tester) async {
    await pumpRealAppOn(tester, repo);
    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(
      find
          .descendant(
            of: find.byType(WorkingCopyBoard),
            matching: find.text('fixture.txt'),
          )
          .first,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(
      find.byWidgetPredicate(
        (Widget w) =>
            w is GbmIconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.expand,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final List<FrameTiming> timings = <FrameTiming>[];
    void collect(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));

    Future<void> measure(String label, Finder view) async {
      final ScrollPosition position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: view,
                  matching: find.byWidgetPredicate(
                    (Widget w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.down,
                  ),
                )
                .first,
          )
          .position;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      timings.clear();
      final double extent = position.maxScrollExtent;
      const int frames = 120;
      for (int i = 1; i <= frames; i++) {
        position.jumpTo(extent * i / frames);
        await tester.pump();
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      final List<double> build =
          timings.map((FrameTiming t) => _ms(t.buildDuration)).toList()..sort();
      final List<double> raster =
          timings.map((FrameTiming t) => _ms(t.rasterDuration)).toList()
            ..sort();
      // ignore: avoid_print
      print(
        'PERF $label frames=${timings.length} '
        'buildP50=${_percentile(build, .5).toStringAsFixed(1)} '
        'buildP90=${_percentile(build, .9).toStringAsFixed(1)} '
        'buildMax=${_percentile(build, 1).toStringAsFixed(1)} '
        'rasterP90=${_percentile(raster, .9).toStringAsFixed(1)} '
        'extent=${extent.toStringAsFixed(0)}',
      );
    }

    final Finder views = find.byType(ScopedDiffView);
    expect(views, findsOneWidget, reason: 'unified is the default');
    await measure('unified', views);

    await tester.tap(find.text('2 file'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(views, findsNWidgets(2));
    await measure('2file-unstaged', views.first);
    await measure('2file-staged', views.last);
  });
}
