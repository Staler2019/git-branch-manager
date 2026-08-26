// Device-tier E2E for spec P03 變體 B's two ways of moving *lines* (not whole
// files) between the two columns: a scope card's own button, and the one-shot
// scope a text selection makes.
//
// Why this file has to exist. Every existing test of this stops short of the
// seam that matters. `scoped_diff_view_test.dart` pumps the view bare and
// asserts the callback fired; `working_copy_diff_pane_test.dart` pumps the
// real container and asserts the same; both run on `FakeGbmBindings`, so
// nothing between `stageLines()` and the index is exercised at all.
// `WorkingCopyApiTest.StageLinesStagesOnlyTheSelectedAddedLines` covers the
// C++ half but is called from C++, never through `dart:ffi` -- whose
// `lookupFunction` matches by symbol name and never by signature.
//
// So the whole path -- text selection -> touched rows -> scope -> hunk index
// + line indices -> `gbm_stage_lines` -> `git apply --cached` -> the index --
// has never been run end to end by anything. This file runs it, and asserts
// against `git diff --cached` rather than against the UI, so a button that
// dispatches into a void cannot pass.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

const String _committed = 'alpha\nbravo\ncharlie\ndelta\necho\n';

/// Two insertions **three** unchanged lines apart, so 變體 B's default scope
/// (which merges changes separated by <= 2 unchanged lines) leaves two
/// separate cards. One card is what makes "this card's button moved only its
/// own lines" a claim the other card can falsify.
const String _modified =
    'alpha\nINSERTED_ONE\nbravo\ncharlie\ndelta\nINSERTED_TWO\necho\n';

void _buildFixture(String repo) {
  File('$repo/fixture.txt').writeAsStringSync(_committed);
  runGit(repo, <String>['add', 'fixture.txt']);
  runGit(repo, <String>['commit', '-m', 'add fixture']);
  File('$repo/fixture.txt').writeAsStringSync(_modified);
}

String _stagedDiff(String repo) =>
    runGit(repo, <String>['diff', '--cached', '--', 'fixture.txt']).stdout
        as String;

/// Opens Working Copy and selects `fixture.txt` in the board, leaving the
/// diff pane showing its unstaged side on the left.
Future<void> _openDiff(WidgetTester tester, String repo) async {
  await pumpRealAppOn(tester, repo);
  await tester.tap(find.text('Working Copy'));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Scoped to the board: the diff pane's titlebar names the selected file
  // too, and `tap()` refuses an ambiguous finder.
  await tester.tap(
    find.descendant(
      of: find.byType(WorkingCopyBoard),
      matching: find.text('fixture.txt'),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// The unstaged (left) pane -- the one whose cards stage.
Finder get _unstagedPane =>
    find.byWidgetPredicate((Widget w) => w is ScopedDiffView && !w.staged);

/// The staged (right) pane -- the one whose cards *unstage*, i.e. the
/// 「往左」 direction. A separate capi entry point (`gbm_unstage_lines`,
/// `git apply --cached --reverse`) reading a separate diff (the staged one,
/// whose hunk indices are its own), so the stage direction passing says
/// nothing about this one.
Finder get _stagedPane =>
    find.byWidgetPredicate((Widget w) => w is ScopedDiffView && w.staged);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;

  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_e2e_stage_lines_');
    _buildFixture(repo);
  });

  tearDown(() => deleteTempGitRepo(repo));

  testWidgets('a scope card button stages only that card\'s lines', (
    tester,
  ) async {
    await _openDiff(tester, repo);

    expect(_unstagedPane, findsOneWidget);
    // Two insertions, three lines apart -> two cards, each one added line.
    expect(
      find.descendant(of: _unstagedPane, matching: find.text('Stage 1 line')),
      findsNWidgets(2),
      reason: 'the fixture is built to produce exactly two scopes',
    );

    await tester.tap(
      find
          .descendant(of: _unstagedPane, matching: find.text('Stage 1 line'))
          .first,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final String staged = _stagedDiff(repo);
    expect(
      staged.contains('+INSERTED_ONE'),
      isTrue,
      reason:
          'the first card\'s press must reach the index through the real '
          'dylib -- a button wired to a callback that goes nowhere looks '
          'identical in every other tier\n$staged',
    );
    expect(
      staged.contains('+INSERTED_TWO'),
      isFalse,
      reason: 'pressing one card must not stage the other card\'s line',
    );
  });

  testWidgets('a text selection stages exactly the lines it framed', (
    tester,
  ) async {
    await _openDiff(tester, repo);

    // Anchored on the text's own edges, not its box centre: a diff line's
    // text sits in an Expanded far wider than its glyphs, so a drag between
    // two centres starts past the end of the string.
    final Finder line = find.descendant(
      of: _unstagedPane,
      matching: find.text('INSERTED_TWO'),
    );
    expect(line, findsOneWidget);
    final Rect rect = tester.getRect(line);

    final TestGesture gesture = await tester.startGesture(
      Offset(rect.left + 1, rect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(Offset(rect.right - 1, rect.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(
      find.text('一次性'),
      findsOneWidget,
      reason:
          'the drag produced no one-shot scope, so there is nothing to press',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('temporary-scope-card')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('temporary-scope-card')),
        matching: find.textContaining('Stage'),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final String staged = _stagedDiff(repo);
    expect(staged.contains('+INSERTED_TWO'), isTrue, reason: staged);
    expect(
      staged.contains('+INSERTED_ONE'),
      isFalse,
      reason: 'the selection framed one line; the other must stay unstaged',
    );
  });

  testWidgets('a card on the staged side unstages -- the 「往左」 direction', (
    tester,
  ) async {
    // Stage both insertions up front, so the staged pane has two cards and
    // the unstaged pane has none: the only direction left to move is left.
    runGit(repo, <String>['add', 'fixture.txt']);

    await _openDiff(tester, repo);

    expect(_stagedPane, findsOneWidget);
    expect(
      find.descendant(of: _stagedPane, matching: find.text('Unstage 1 line')),
      findsNWidgets(2),
      reason:
          'the staged pane must render its own diff with its own cards; a '
          'pane that only ever shows the unstaged side would find nothing',
    );

    await tester.tap(
      find
          .descendant(of: _stagedPane, matching: find.text('Unstage 1 line'))
          .first,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final String staged = _stagedDiff(repo);
    expect(
      staged.contains('+INSERTED_ONE'),
      isFalse,
      reason:
          'gbm_unstage_lines must reach the index through the real dylib\n'
          '$staged',
    );
    expect(
      staged.contains('+INSERTED_TWO'),
      isTrue,
      reason: 'unstaging one card must leave the other card staged',
    );
  });

  testWidgets('a selection on the staged side unstages what it framed', (
    tester,
  ) async {
    runGit(repo, <String>['add', 'fixture.txt']);

    await _openDiff(tester, repo);

    final Finder line = find.descendant(
      of: _stagedPane,
      matching: find.text('INSERTED_TWO'),
    );
    expect(line, findsOneWidget);
    final Rect rect = tester.getRect(line);

    final TestGesture gesture = await tester.startGesture(
      Offset(rect.left + 1, rect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(Offset(rect.right - 1, rect.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(
      find.text('一次性'),
      findsOneWidget,
      reason:
          'the staged pane does not register a keyboard submitter '
          '(onTemporaryScopeChanged is null there), but it must still raise '
          'the card its own button lives on',
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('temporary-scope-card')),
        matching: find.textContaining('Unstage'),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final String staged = _stagedDiff(repo);
    expect(staged.contains('+INSERTED_TWO'), isFalse, reason: staged);
    expect(
      staged.contains('+INSERTED_ONE'),
      isTrue,
      reason: 'the selection framed one line; the other must stay staged',
    );
  });

  // `SCOPES` row 6's own `how` -- 「點 hunk 標頭列（@@ …）」 -- and row 7's
  // second one -- 「Shift + ↑ ↓」. Both were absent, which is what the report
  // 「左右 diff view 沒辦法選取 line 去左或右」 was actually about: every
  // *other* way of doing it worked (the four tests above), so what was
  // missing was the two inputs that are not a mouse drag.
  testWidgets('clicking the hunk heading stages the whole hunk in one press', (
    tester,
  ) async {
    await _openDiff(tester, repo);

    await tester.tap(
      find.descendant(of: _unstagedPane, matching: find.textContaining('@@ ')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('temporary-scope-card')),
        matching: find.textContaining('Stage '),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final String staged = _stagedDiff(repo);
    expect(staged.contains('+INSERTED_ONE'), isTrue, reason: staged);
    expect(
      staged.contains('+INSERTED_TWO'),
      isTrue,
      reason:
          'the fixture\'s two insertions are in one hunk but two scopes, so '
          'a heading click is the only single press that moves both',
    );
  });

  testWidgets('Shift+Down builds a range the button then stages', (
    tester,
  ) async {
    await _openDiff(tester, repo);

    // One click to put focus in the diff -- on a context row, so the click
    // itself selects nothing and only the arrows do.
    await tester.tap(
      find.descendant(of: _unstagedPane, matching: find.text('alpha')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Seeds on INSERTED_ONE (the first changed row), then walks down to
    // INSERTED_TWO -- across four context rows on the way.
    for (int i = 0; i < 5; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    }

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('temporary-scope-card')),
        matching: find.textContaining('Stage '),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final String staged = _stagedDiff(repo);
    expect(staged.contains('+INSERTED_ONE'), isTrue, reason: staged);
    expect(
      staged.contains('+INSERTED_TWO'),
      isTrue,
      reason:
          'five presses from the seed reach the second insertion; a range '
          'that stopped at the first changed row would not',
    );
  });

  // A drag that moves row by row, three sub-row steps each, against the real
  // SelectionArea delegates.
  //
  // **Read what this does and does not attest.** It is a regression net for
  // multi-row drags. It is *not* a reproduction of the reported
  // 「只能選一行」: with the mid-drag gate deliberately removed -- both the
  // `settledTouched` ternary and `_onTouchChanged`'s early return -- this
  // test still passed, at row granularity and at sub-row granularity. So no
  // synthetic gesture available here reproduces the symptom, and the fix
  // that followed the report is not verified against it by anything in this
  // repo. Do not cite this test as that verification.
  testWidgets('a row-by-row drag keeps every changed line it crossed', (
    tester,
  ) async {
    await _openDiff(tester, repo);

    // From the first insertion down to the second, one row at a time, so
    // every intermediate frame is a chance for the tree to move underneath
    // the gesture.
    const List<String> rows = <String>[
      'INSERTED_ONE',
      'bravo',
      'charlie',
      'delta',
      'INSERTED_TWO',
    ];

    Rect rectOf(String text) => tester.getRect(
      find.descendant(of: _unstagedPane, matching: find.text(text)),
    );

    final Rect first = rectOf(rows.first);
    final TestGesture gesture = await tester.startGesture(
      Offset(first.left + 1, first.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    // Sub-row increments, three per row: a real mouse emits far more move
    // events than rows, so a tree restructure can land between two moves
    // *within* a row rather than tidily between rows.
    for (final String row in rows) {
      final Rect rect = rectOf(row);
      for (final double t in const <double>[0.25, 0.6, 1.0]) {
        await gesture.moveTo(
          Offset(rect.left + (rect.width - 1) * t, rect.center.dy),
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
    }
    await gesture.up();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('temporary-scope-card')),
        matching: find.textContaining('Stage '),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final String staged = _stagedDiff(repo);
    expect(
      staged.contains('+INSERTED_ONE'),
      isTrue,
      reason: 'the drag started here\n$staged',
    );
    expect(
      staged.contains('+INSERTED_TWO'),
      isTrue,
      reason:
          'and ended here -- a scope that collapsed to the first row would '
          'stage only one of the two',
    );
  });
}
