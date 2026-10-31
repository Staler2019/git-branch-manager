// Device-tier E2E for synchronized scrolling (plan: Slice S, S7): `2 file`'s
// two columns and the conflict window's three scroll as one against the
// real dylib, and a drag across a segment's spacer still stages exactly the
// lines it framed -- read from `git diff --cached`, never the UI.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_window.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:integration_test/integration_test.dart';

import 'support/key_shortcuts.dart';
import 'support/real_repo_harness.dart';

/// `L1`..`L[total]`, one per line, with [replace]'s lines swapped in.
String _lines(int total, [Map<int, String> replace = const <int, String>{}]) {
  final StringBuffer out = StringBuffer();
  for (int n = 1; n <= total; n++) {
    out.writeln(replace[n] ?? 'L$n');
  }
  return out.toString();
}

/// Staged: `L20`..`L23` become `S20`..`S23`. Unstaged, on top of that:
/// `S21` becomes `W21`, and `L32`, `L33` become `W32`, `W33` -- near enough
/// that both cards fit one screen, so a drag between them never
/// autoscrolls. Segment 21's staged card is four replacements to the
/// unstaged card's one, so the unstaged column carries a spacer below its
/// card, between `W21` and the card at 32.
const Map<int, String> _staged = <int, String>{
  20: 'S20',
  21: 'S21',
  22: 'S22',
  23: 'S23',
};
const Map<int, String> _working = <int, String>{
  20: 'S20',
  21: 'W21',
  22: 'S22',
  23: 'S23',
  32: 'W32',
  33: 'W33',
};

Finder _view({required bool staged}) => find.byWidgetPredicate(
  (Widget w) =>
      w is ScopedDiffView &&
      w.sources.any((ScopedDiffSource s) => s.staged == staged),
);

Finder _text(Finder view, String text) =>
    find.descendant(of: view, matching: find.text(text));

ScrollPosition _vertical(WidgetTester tester, Finder within) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: within,
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    )
    .position;

Future<void> _wheel(WidgetTester tester, Finder over, Offset delta) async {
  final TestPointer pointer = TestPointer(7, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(tester.getCenter(over)));
  await tester.sendEventToBinding(pointer.scroll(delta));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

/// Opens Working Copy on `fixture.txt` in `2 file`, full file on when
/// [fullFile] is.
Future<void> _openTwoFile(
  WidgetTester tester,
  String repo, {
  bool fullFile = false,
}) async {
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
  await tester.tap(find.text('2 file'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  if (fullFile) {
    await tester.tap(
      find.byWidgetPredicate(
        (Widget w) =>
            w is GbmIconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.expand,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
  expect(_view(staged: false), findsOneWidget);
  expect(_view(staged: true), findsOneWidget);
}

/// The staged diff, read once the app has finished with the index: the
/// board lists a partly staged file in both columns ([_stagedAfterApp] in
/// `full_file_stage_flow_test.dart`, [TEST-no-dart-process-while-core-runs-git]).
Future<String> _stagedAfterApp(WidgetTester tester, String repo) async {
  final Finder rows = find.descendant(
    of: find.byType(WorkingCopyBoard),
    matching: find.text('fixture.txt'),
  );
  for (int i = 0; i < 100 && rows.evaluate().length < 2; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return runGit(repo, <String>['diff', '--cached', '--', 'fixture.txt']).stdout
      as String;
}

/// Every fill row both columns have built on screen sits at one height in
/// both: the claim is the same rows side by side, not the same pixels,
/// since each column's offset counts its own estimates for what it has not
/// built.
void _expectRowsAligned(WidgetTester tester, Finder a, Finder b) {
  final Rect view = tester.getRect(a);
  int compared = 0;
  for (int n = 1; n <= 400; n++) {
    final Finder inA = _text(a, 'L$n');
    final Finder inB = _text(b, 'L$n');
    if (inA.evaluate().length != 1 || inB.evaluate().length != 1) continue;
    final Rect ra = tester.getRect(inA);
    if (ra.bottom < view.top || ra.top > view.bottom) continue;
    compared++;
    expect(tester.getRect(inB).top, closeTo(ra.top, 0.5), reason: 'L$n');
  }
  expect(compared, greaterThan(5));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;

  setUp(() => repo = createTempGitRepo(prefix: 'gbm_e2e_sync_scroll_'));
  tearDown(() => deleteTempGitRepo(repo));

  group('2 file', () {
    setUp(() {
      File('$repo/fixture.txt').writeAsStringSync(_lines(400));
      runGit(repo, <String>['add', 'fixture.txt']);
      runGit(repo, <String>['commit', '-m', 'add fixture']);
      File('$repo/fixture.txt').writeAsStringSync(_lines(400, _staged));
      runGit(repo, <String>['add', 'fixture.txt']);
      File('$repo/fixture.txt').writeAsStringSync(_lines(400, _working));
    });

    testWidgets('a wheel on the unstaged column carries the staged one to '
        'the same rows', (tester) async {
      await _openTwoFile(tester, repo, fullFile: true);
      final Finder unstaged = _view(staged: false);
      final Finder staged = _view(staged: true);

      await _wheel(tester, unstaged, const Offset(0, 3000));
      final ScrollPosition lead = _vertical(tester, unstaged);
      expect(lead.pixels, greaterThan(2000));
      _expectRowsAligned(tester, unstaged, staged);

      // `lead` follows once staged leads, so its value before the wheel is
      // what staged has to move up from.
      final double before = lead.pixels;
      await _wheel(tester, staged, const Offset(0, -1500));
      expect(_vertical(tester, staged).pixels, lessThan(before));
      _expectRowsAligned(tester, unstaged, staged);
    });

    testWidgets('a drag across the unstaged column\'s spacer stages only '
        'the lines it framed', (tester) async {
      await _openTwoFile(tester, repo);
      final Finder unstaged = _view(staged: false);
      // W21 to near the top first, a wheel before the drag rather than an
      // autoscroll during it.
      await _wheel(
        tester,
        unstaged,
        Offset(
          0,
          tester.getRect(_text(unstaged, 'W21')).top -
              tester.getRect(unstaged).top -
              40,
        ),
      );
      final Rect from = tester.getRect(_text(unstaged, 'W21'));
      final Rect to = tester.getRect(_text(unstaged, 'W32'));
      // Premise: both rows are on screen, so the drag is unscrolled.
      final Rect view = tester.getRect(unstaged);
      expect(from.top, greaterThan(view.top), reason: '$from in $view');
      expect(to.bottom, lessThan(view.bottom - 40), reason: '$to in $view');
      // Premise: a spacer lies between the two rows.
      expect(
        find
            .descendant(of: unstaged, matching: find.byType(SyncSlotSpacer))
            .evaluate()
            .map((Element e) => tester.getRect(find.byWidget(e.widget)))
            .where(
              (Rect r) =>
                  r.height > 20 && r.top >= from.bottom && r.bottom <= to.top,
            ),
        isNotEmpty,
      );

      final TestGesture gesture = await tester.startGesture(
        Offset(from.left + 1, from.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (final double t in const <double>[0.25, 0.5, 0.75, 1.0]) {
        await gesture.moveTo(
          Offset.lerp(
            Offset(from.left + 1, from.center.dy),
            Offset(to.right - 1, to.center.dy),
            t,
          )!,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
      await tester.pump();
      await gesture.removePointer();
      expect(find.text('一次性'), findsOneWidget, reason: 'no one-shot scope');
      await tester.pumpAndSettle();
      await pressActionShortcut(
        tester,
        GbmActionId.repositoryStageSelectedLines,
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final String diff = await _stagedAfterApp(tester, repo);
      // `--cached` is against HEAD, so the staged S20..S23 show as added.
      // The drag started on +W21, so -S21 above it stays (S21 kept, W21
      // added), and it ended on +W32: -L32 and -L33 go, +W33 does not.
      expect(diff, contains('+S20\n+S21\n+W21\n+S22\n+S23\n'), reason: diff);
      expect(diff, contains('-L32\n-L33\n+W32\n L34\n'), reason: diff);
      expect(diff, isNot(contains('+W33')), reason: diff);
    });
  });

  testWidgets('the conflict window\'s three columns follow a wheel on any '
      'one of them', (tester) async {
    // Two regions far apart in a long file; theirs is longer in each, so
    // ours and the result pad every region.
    File('$repo/fixture.txt').writeAsStringSync(_lines(300));
    runGit(repo, <String>['add', 'fixture.txt']);
    runGit(repo, <String>['commit', '-m', 'add fixture']);
    runGit(repo, <String>['checkout', '-b', 'feature']);
    File('$repo/fixture.txt').writeAsStringSync(
      _lines(300, <int, String>{
        50: 'T50a\nT50b\nT50c\nT50d\nT50e\nT50f',
        250: 'T250a\nT250b\nT250c\nT250d\nT250e\nT250f',
      }),
    );
    runGit(repo, <String>['commit', '-am', 'theirs']);
    runGit(repo, <String>['checkout', 'main']);
    File('$repo/fixture.txt')
        .writeAsStringSync(_lines(300, <int, String>{50: 'O50', 250: 'O250'}));
    runGit(repo, <String>['commit', '-am', 'ours']);
    Process.runSync('git', <String>[
      'merge',
      'feature',
    ], workingDirectory: repo);

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
    await tester.pumpAndSettle(const Duration(seconds: 1));

    Finder column(int c) => find
        .descendant(
          of: find.byType(ConflictResolveWindow),
          matching: find.byType(GbmCodeHScroll),
        )
        .at(c);
    expect(
      find.descendant(
        of: find.byType(ConflictResolveWindow),
        matching: find.byType(GbmCodeHScroll),
      ),
      findsNWidgets(3),
    );
    for (final int lead in <int>[0, 2, 1]) {
      await _wheel(tester, column(lead), const Offset(0, 1500));
      final double at = _vertical(tester, column(lead)).pixels;
      expect(at, greaterThan(0), reason: 'column $lead moved');
      for (int c = 0; c < 3; c++) {
        final ScrollPosition p = _vertical(tester, column(c));
        expect(
          p.pixels,
          closeTo(at.clamp(p.minScrollExtent, p.maxScrollExtent), 0.5),
          reason: 'column $c after a wheel on column $lead',
        );
      }
      await _wheel(tester, column(lead), const Offset(0, -800));
    }
  });
}
