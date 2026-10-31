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

import 'package:flutter/gestures.dart';
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

    ScrollPosition positionOf(Finder view) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: view,
                matching: find.byWidgetPredicate(
                  (Widget w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                ),
              )
              .first,
        )
        .position;

    // In `2 file`, [follower] is the other column: one wheel tick makes
    // [view] the synced leader first, so every jump below is mirrored and
    // the numbers include the sync (plan: Slice S, S7).
    //
    // With no [step], each frame jumps 1/120 of the extent (about 930 px):
    // every frame builds a whole new viewport, a stress test. With [step],
    // each frame moves that many pixels from a third of the way down, about
    // a fast fling; the sync budget is read off this one (使用者裁定
    // 2026-10-31: p90 at most 2 ms above the same run without the sync).
    Future<void> measure(
      String label,
      Finder view, {
      Finder? follower,
      double? step,
    }) async {
      final ScrollPosition position = positionOf(view);
      if (follower != null) {
        // A tick that can move it, or [view] does not become the leader:
        // the previous run left both columns at the end, and a jump on a
        // column that is not the leader is pulled back to the leader's
        // offset the next frame.
        final TestPointer pointer = TestPointer(9, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(tester.getCenter(view)));
        await tester.sendEventToBinding(
          pointer.scroll(Offset(0, position.pixels > 0 ? -1 : 1)),
        );
        await tester.pumpAndSettle();
      }
      position.jumpTo(step == null ? 0 : position.maxScrollExtent / 3);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      timings.clear();
      final double extent = position.maxScrollExtent;
      const int frames = 120;
      int followed = 0;
      for (int i = 1; i <= frames; i++) {
        final double before = follower == null
            ? 0
            : positionOf(follower).pixels;
        position.jumpTo(
          step == null ? extent * i / frames : extent / 3 + step * i,
        );
        await tester.pump();
        if (follower != null && positionOf(follower).pixels != before) {
          followed++;
        }
      }
      // Every jump mirrored, or the numbers are not the sync's.
      if (follower != null) expect(followed, greaterThan(frames * 0.9));
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
        'extent=${extent.toStringAsFixed(0)}'
        '${follower == null ? '' : ' followerAt=${positionOf(follower).pixels.toStringAsFixed(0)} leaderAt=${position.pixels.toStringAsFixed(0)}'}',
      );
    }

    final Finder views = find.byType(ScopedDiffView);
    expect(views, findsOneWidget, reason: 'unified is the default');
    await measure('unified', views);
    await measure('unified-80px', views, step: 80);

    await tester.tap(find.text('2 file'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(views, findsNWidgets(2));
    await measure('2file-unstaged', views.first, follower: views.last);
    await measure('2file-staged', views.last, follower: views.first);
    await measure(
      '2file-unstaged-80px',
      views.first,
      follower: views.last,
      step: 80,
    );
    await measure(
      '2file-staged-80px',
      views.last,
      follower: views.first,
      step: 80,
    );
  });
}
