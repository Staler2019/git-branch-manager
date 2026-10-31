// Measures scrolling the conflict-resolve window's three synced columns on a
// 5,000-line file with 20 conflicts (the full-file view's own cap): a
// stress pass that jumps 1/120 of the extent every frame, then single far
// jumps. A measurement, not a gate: the far-jump frame is held against the
// stress p90 x 1.5 by hand (plan: Slice J, J0/JB4).
//
//   flutter drive --profile -d macos --driver=integration_test/perf/driver.dart \
//     --target=integration_test/perf/conflict_scroll_perf_test.dart
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_window.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';
import 'package:integration_test/integration_test.dart';

import '../support/real_repo_harness.dart';

const int _total = 5000;

/// A conflict every 250 lines, from line 125: 21 text segments of about
/// 240 lines between 20 regions, six lines a side.
final List<int> _regions = <int>[for (int n = 125; n < _total; n += 250) n];

String _lines(String Function(int n)? replace) => <String>[
  for (int n = 1; n <= _total; n++)
    (_regions.contains(n) ? replace?.call(n) : null) ??
        '    final value$n = compute(input, $n); // body',
].join('\n');

String _six(String side, int n) =>
    <String>[for (int i = 0; i < 6; i++) '$side$n-$i'].join('\n');

double _ms(Duration d) => d.inMicroseconds / 1000;

double _percentile(List<double> sorted, double p) =>
    sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late String repo;
  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_perf_conflict_scroll_');
    File('$repo/fixture.txt').writeAsStringSync(_lines(null));
    runGit(repo, <String>['add', 'fixture.txt']);
    runGit(repo, <String>['commit', '-m', 'add fixture']);
    runGit(repo, <String>['checkout', '-b', 'feature']);
    File('$repo/fixture.txt').writeAsStringSync(_lines((n) => _six('T', n)));
    runGit(repo, <String>['commit', '-am', 'theirs']);
    runGit(repo, <String>['checkout', 'main']);
    File('$repo/fixture.txt').writeAsStringSync(_lines((n) => _six('O', n)));
    runGit(repo, <String>['commit', '-am', 'ours']);
    Process.runSync('git', <String>[
      'merge',
      'feature',
    ], workingDirectory: repo);
  });
  tearDown(() => deleteTempGitRepo(repo));

  testWidgets('scrolling the three columns', (WidgetTester tester) async {
    await pumpRealAppOn(tester, repo);
    await tester.tap(find.text('Resolve…'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(
      find
          .descendant(
            of: find.byType(ConflictResolveWindow),
            matching: find.text('fixture.txt'),
          )
          .first,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final List<FrameTiming> timings = <FrameTiming>[];
    void collect(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));

    final Finder result = find
        .descendant(
          of: find.byType(ConflictResolveWindow),
          matching: find.byType(GbmCodeHScroll),
        )
        .at(1);
    final ScrollPosition position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: result,
                matching: find.byWidgetPredicate(
                  (Widget w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                ),
              )
              .first,
        )
        .position;

    // The result column leads: one wheel tick that can move it.
    final TestPointer pointer = TestPointer(9, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(result)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 1)));
    await tester.pumpAndSettle();
    position.jumpTo(0);
    await tester.pumpAndSettle();

    Future<void> idle() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );

    await idle();
    timings.clear();
    final double extent = position.maxScrollExtent;
    const int frames = 120;
    for (int i = 1; i <= frames; i++) {
      position.jumpTo(extent * i / frames);
      await tester.pump();
    }
    await idle();
    final List<double> build =
        timings.map((FrameTiming t) => _ms(t.buildDuration)).toList()..sort();
    // ignore: avoid_print
    print(
      'PERF conflict-stress frames=${timings.length} '
      'buildP50=${_percentile(build, .5).toStringAsFixed(1)} '
      'buildP90=${_percentile(build, .9).toStringAsFixed(1)} '
      'buildMax=${_percentile(build, 1).toStringAsFixed(1)} '
      'extent=${extent.toStringAsFixed(0)}',
    );

    position.jumpTo(0);
    await tester.pumpAndSettle();
    final List<String> far = <String>[];
    for (final double f in <double>[.75, .1, .5, 0]) {
      await idle();
      timings.clear();
      position.jumpTo(position.maxScrollExtent * f);
      await tester.pump();
      await idle();
      final double worst = timings.isEmpty
          ? -1
          : timings
                .map((FrameTiming t) => _ms(t.buildDuration))
                .reduce((double a, double b) => a > b ? a : b);
      far.add('to$f=${worst.toStringAsFixed(1)}');
    }
    // ignore: avoid_print
    print('PERF conflict-far ${far.join(' ')}');
  });
}
