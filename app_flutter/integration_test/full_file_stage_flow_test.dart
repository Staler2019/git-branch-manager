// Device-tier E2E for the Working Copy full-file view: every way of moving
// lines still moves exactly the lines it moved in excerpt mode, now that the
// rows between the cards are drawn too.
//
// The claim this file exists for is the one the plan's key constraint rests
// on: the -U3 diff stays the only source of every stage/unstage/discard
// payload, and a fill row (`'f:$source:$line'`, not a hunk row) contributes
// nothing to one. Every widget test of that runs on `FakeGbmBindings`; only
// here does the payload reach `git apply --cached` through the real dylib,
// so the assertions read `git diff --cached` and the file on disk, never the
// UI.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:integration_test/integration_test.dart';

import 'support/key_shortcuts.dart';
import 'support/real_repo_harness.dart';

/// `L1`..`L[total]`, one per line, with `INSERTED_<name>` after each line of
/// [inserts].
String _lines(int total, [Map<int, String> inserts = const <int, String>{}]) {
  final StringBuffer out = StringBuffer();
  for (int n = 1; n <= total; n++) {
    out.writeln('L$n');
    if (inserts[n] case final String name) out.writeln('INSERTED_$name');
  }
  return out.toString();
}

/// Three insertions, each more than six lines from the next, so git keeps
/// three hunks and the view three cards; the rows between them (`L1`-`L2`,
/// `L9`-`L12`, `L19`, `L26`) exist only as fill rows.
const Map<int, String> _three = <int, String>{5: 'ONE', 15: 'TWO', 22: 'THREE'};

void _commit(String repo, String content) {
  File('$repo/fixture.txt').writeAsStringSync(content);
  runGit(repo, <String>['add', 'fixture.txt']);
  runGit(repo, <String>['commit', '-m', 'add fixture']);
}

/// The staged diff, read only once the app has finished with the index.
///
/// The board lists a partly staged file in both columns, so that is the
/// signal the stage and the refresh after it are done; only then may the
/// test spawn git, since a dart:io `Process` alive while the core runs git
/// makes the core's git fail ([TEST-no-dart-process-while-core-runs-git]).
Future<String> _stagedAfterApp(WidgetTester tester, String repo) async {
  final Finder rows = find.descendant(
    of: find.byType(WorkingCopyBoard),
    matching: find.text('fixture.txt'),
  );
  for (int i = 0; i < 100 && rows.evaluate().length < 2; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return _stagedDiff(repo);
}

String _stagedDiff(String repo) =>
    runGit(repo, <String>['diff', '--cached', '--', 'fixture.txt']).stdout
        as String;

Finder get _view => find.byType(ScopedDiffView);

Finder _text(String text) =>
    find.descendant(of: _view, matching: find.text(text));

/// Opens Working Copy on `fixture.txt` and turns the full-file view on with
/// the titlebar button, the way a user does.
Future<void> _openFullFile(WidgetTester tester, String repo) async {
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
  expect(
    _text('L10'),
    findsOneWidget,
    reason: 'L10 lies between two cards: only a fill row draws it',
  );
}

/// A mouse drag from the left edge of [from]'s text to the right edge of
/// [to]'s, both on screen.
Future<void> _drag(WidgetTester tester, String from, String to) async {
  final Rect start = tester.getRect(_text(from));
  final Rect end = tester.getRect(_text(to));
  final TestGesture gesture = await tester.startGesture(
    Offset(start.left + 1, start.center.dy),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  for (final double t in const <double>[0.25, 0.5, 0.75, 1.0]) {
    await gesture.moveTo(
      Offset.lerp(
        Offset(start.left + 1, start.center.dy),
        Offset(end.right - 1, end.center.dy),
        t,
      )!,
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
  await tester.pump();
  await gesture.removePointer();
}

/// Submits the one-shot scope by its keyboard path.
///
/// [headOnScreen] is false after a drag that scrolled: the block's head --
/// its label and its button -- sits at the top of the range, which by then
/// is scrolled out and unbuilt, so only the staged diff can say whether a
/// range was made.
Future<void> _stageSelection(
  WidgetTester tester, {
  bool headOnScreen = true,
}) async {
  if (headOnScreen) {
    expect(find.text('一次性'), findsOneWidget, reason: 'no one-shot scope');
  }
  await tester.pumpAndSettle();
  await pressActionShortcut(tester, GbmActionId.repositoryStageSelectedLines);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;

  setUp(() => repo = createTempGitRepo(prefix: 'gbm_e2e_full_file_'));
  tearDown(() => deleteTempGitRepo(repo));

  group('three insertions, full file on', () {
    setUp(() {
      _commit(repo, _lines(26));
      File('$repo/fixture.txt').writeAsStringSync(_lines(26, _three));
    });

    testWidgets('a card button stages only that card\'s line', (tester) async {
      await _openFullFile(tester, repo);
      await tester.tap(
        find.descendant(of: _view, matching: find.text('Stage 1 line')).at(1),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final String staged = await _stagedAfterApp(tester, repo);
      expect(staged, contains('+INSERTED_TWO'));
      expect(staged, isNot(contains('+INSERTED_ONE')));
      expect(staged, isNot(contains('+INSERTED_THREE')));
    });

    testWidgets('discarding a card line reverts only that line on disk', (
      tester,
    ) async {
      await _openFullFile(tester, repo);
      await tester.tap(_text('INSERTED_TWO'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard…'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('Discard line'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        File('$repo/fixture.txt').readAsStringSync(),
        _lines(26, <int, String>{5: 'ONE', 22: 'THREE'}),
      );
    });

    testWidgets('a drag from a fill row across two cards stages both, and '
        'not the third', (tester) async {
      await _openFullFile(tester, repo);
      await _drag(tester, 'L1', 'INSERTED_TWO');
      await _stageSelection(tester);

      final String staged = await _stagedAfterApp(tester, repo);
      expect(staged, contains('+INSERTED_ONE'), reason: staged);
      expect(staged, contains('+INSERTED_TWO'), reason: staged);
      expect(staged, isNot(contains('+INSERTED_THREE')), reason: staged);
    });

    testWidgets('Shift+Down walks across fill rows into the next card', (
      tester,
    ) async {
      await _openFullFile(tester, repo);
      // Focus in the diff, on a fill row, so the click selects nothing.
      await tester.tap(_text('L1'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // The seed is INSERTED_ONE; then L6-L8, the fill rows L9-L12, L13-L15
      // and INSERTED_TWO: 1 + 10 + 1 presses.
      for (int i = 0; i < 12; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      }
      await _stageSelection(tester);

      final String staged = await _stagedAfterApp(tester, repo);
      expect(staged, contains('+INSERTED_ONE'), reason: staged);
      expect(
        staged,
        contains('+INSERTED_TWO'),
        reason: 'a walk that skipped or stalled on the fill rows stops short',
      );
      expect(staged, isNot(contains('+INSERTED_THREE')), reason: staged);
    });
  });

  // Both directions in one unified list: each side's full diff carries every
  // line of the file, and each must be drawn once.
  testWidgets('unified with a staged and an unstaged side draws each line '
      'once', (tester) async {
    _commit(repo, _lines(26));
    File('$repo/fixture.txt').writeAsStringSync(_lines(26, {5: 'ONE'}));
    runGit(repo, <String>['add', 'fixture.txt']);
    File('$repo/fixture.txt').writeAsStringSync(_lines(26, _three));

    await _openFullFile(tester, repo);
    expect(_text('INSERTED_ONE'), findsOneWidget);
    expect(_text('INSERTED_TWO'), findsOneWidget);
    // The list is lazy: walk it a screen at a time. A line drawn by both
    // sides would be drawn twice at one position, so within one screen.
    final ScrollableState list = tester.state<ScrollableState>(
      find
          .descendant(
            of: _view,
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    );
    final Set<int> seen = <int>{};
    for (double at = 0; ; at += 150) {
      list.position.jumpTo(at.clamp(0, list.position.maxScrollExtent));
      await tester.pump();
      for (int n = 1; n <= 26; n++) {
        final int count = _text('L$n').evaluate().length;
        expect(count, lessThanOrEqualTo(1), reason: 'L$n is drawn twice');
        if (count == 1) seen.add(n);
      }
      if (at >= list.position.maxScrollExtent) break;
    }
    expect(seen, <int>{for (int n = 1; n <= 26; n++) n});
  });

  // The lazy list's own case: autoscroll carries the drag past rows that were
  // never built, and the range comes from the two endpoints alone.
  testWidgets('an autoscrolling drag past unbuilt rows stages from its start '
      'row to its end row', (tester) async {
    _commit(repo, _lines(1000));
    File('$repo/fixture.txt').writeAsStringSync(
      _lines(1000, <int, String>{5: 'ONE', 900: 'TWO', 950: 'THREE'}),
    );
    await _openFullFile(tester, repo);

    final Rect view = tester.getRect(_view);
    final Rect start = tester.getRect(_text('INSERTED_ONE'));
    final TestGesture gesture = await tester.startGesture(
      Offset(start.left + 1, start.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(Offset(start.left + 40, view.bottom + 30));
    bool reached = false;
    for (int frame = 0; frame < 3000 && !reached; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final Finder two = _text('INSERTED_TWO');
      reached =
          two.evaluate().isNotEmpty &&
          tester.getRect(two).bottom < view.bottom - 4 &&
          tester.getRect(two).top > view.top;
    }
    expect(reached, isTrue, reason: 'autoscroll never brought TWO on screen');
    final Rect end = tester.getRect(_text('INSERTED_TWO'));
    await gesture.moveTo(Offset(end.right - 1, end.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();
    await gesture.removePointer();
    await _stageSelection(tester, headOnScreen: false);

    final String staged = await _stagedAfterApp(tester, repo);
    expect(staged, contains('+INSERTED_ONE'), reason: staged);
    expect(staged, contains('+INSERTED_TWO'), reason: staged);
    expect(staged, isNot(contains('+INSERTED_THREE')), reason: staged);
  });
}
