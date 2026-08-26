// Render-site tests for spec P03 變體 B's scope cards. The split itself is
// pure and tested in `diff_scopes_test.dart`; what this file checks is that
// each card's button exists from the start, says how many lines it moves,
// and hands `gbm_stage_lines` exactly those lines -- never the unchanged
// context the gap rule swallowed into the same card.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';

import '../../support/pump_app.dart';

DiffHunk _hunk(String sketch, {int hunkIndex = 0}) => DiffHunk(
  oldStart: 1,
  oldCount: sketch.length,
  newStart: 1,
  newCount: sketch.length,
  heading: '',
  lines: <DiffLine>[
    for (int i = 0; i < sketch.length; i++)
      DiffLine(
        kind: switch (sketch[i]) {
          '+' => DiffLineKind.added,
          '-' => DiffLineKind.removed,
          _ => DiffLineKind.context,
        },
        oldLine: i + 1,
        newLine: i + 1,
        // Unique per hunk, so a finder in a multi-hunk file addresses one
        // row rather than the same index in every hunk.
        text: 'h$hunkIndex l$i',
      ),
  ],
);

DiffFile _file(List<String> sketches, {bool binary = false}) => DiffFile(
  oldPath: 'lib/a.dart',
  newPath: 'lib/a.dart',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: binary,
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
  displayPath: 'lib/a.dart',
  hunks: <DiffHunk>[
    for (int i = 0; i < sketches.length; i++) _hunk(sketches[i], hunkIndex: i),
  ],
);

/// The one-shot card's own button text.
///
/// Scoped to the card on purpose: the scope card it supersedes keeps its
/// button drawn (struck through and inert), and for a range that happens to
/// cover exactly one scope the two labels are the same string -- so an
/// unscoped `findsOneWidget` fails for a reason that has nothing to do with
/// the behaviour under test.
Finder temporaryLabel(String text) => find.descendant(
  of: find.byKey(const ValueKey<String>('temporary-scope-card')),
  matching: find.text(text),
);

/// Focuses the well without selecting anything, the way a user who intends to
/// work by keyboard would: one click, then the arrows.
Future<void> clickThen(WidgetTester tester, String row) async {
  await tester.tap(find.text(row));
  await tester.pump();
}

/// Three pumps because the handler defers to a post-frame callback, the
/// tracker coalesces its notification to one per frame, and only then does
/// `setState` rebuild.
Future<void> shiftArrow(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  group('ScopedDiffView', () {
    late List<({int hunkIndex, List<int> lines})> staged;
    late List<({int hunkIndex, List<int> lines})> discarded;

    setUp(() {
      staged = <({int hunkIndex, List<int> lines})>[];
      discarded = <({int hunkIndex, List<int> lines})>[];
    });

    Future<void> pump(
      WidgetTester tester, {
      DiffFile? file,
      bool isStaged = false,
      bool loading = false,
      bool discardable = true,
      double width = 420,
    }) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: width,
          child: ScopedDiffView(
            title: isStaged ? 'Staged' : 'Unstaged',
            file: file,
            staged: isStaged,
            loading: loading,
            onStageScope: (int h, List<int> l) =>
                staged.add((hunkIndex: h, lines: l)),
            onDiscardScope: discardable
                ? (int h, List<int> l) =>
                      discarded.add((hunkIndex: h, lines: l))
                : null,
          ),
        ),
      );
    }

    testWidgets('every scope gets its own button, present before anything is '
        'selected', (WidgetTester tester) async {
      // Two changes three context lines apart -> two scopes -> two buttons,
      // with nothing clicked first. The checkbox version showed zero
      // buttons until a line was ticked.
      await pump(tester, file: _file(<String>['.+...+.']));

      expect(find.byType(GbmButton), findsNWidgets(2));
      expect(find.text('變更 1'), findsOneWidget);
      expect(find.text('變更 2'), findsOneWidget);
    });

    testWidgets('the button sends exactly the lines that move, not the '
        'context the gap rule swallowed', (WidgetTester tester) async {
      // '.+..-.' is one card spanning indices 1..4, but only 1 and 4 change.
      await pump(tester, file: _file(<String>['.+..-.']));

      await tester.tap(find.text('Stage 4 lines (2 changed)'));

      expect(staged.length, 1);
      expect(staged.single.hunkIndex, 0);
      expect(
        staged.single.lines,
        <int>[1, 4],
        reason:
            'passing 1..4 would ask git to stage two unchanged lines, which '
            'buildLineSelectionPatch would reject or mis-apply',
      );
    });

    testWidgets('the label counts moving lines and singularises at one', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+.']));
      expect(find.text('Stage 1 line'), findsOneWidget);
    });

    testWidgets('the staged side unstages instead of staging', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+-.']), isStaged: true);

      expect(find.text('Unstage 2 lines'), findsOneWidget);
      expect(find.text('Stage 2 lines'), findsNothing);
    });

    testWidgets('scope numbering continues across hunks', (
      WidgetTester tester,
    ) async {
      // A per-hunk counter would draw 變更 1 twice, so "the second one" would
      // name two different cards in the same column.
      await pump(tester, file: _file(<String>['.+.', '.-.']));

      expect(find.text('變更 1'), findsOneWidget);
      expect(find.text('變更 2'), findsOneWidget);
    });

    // The two columns' file rows already draw this exact fact as a GbmBadge
    // pill (`working_copy_board.dart`'s `_lineCountBadges`). Bare mono text
    // in the card head meant one screen drew one fact two ways. Asserting
    // the *kind*, not only the label: a neutral pill in the added slot looks
    // wrong and throws nothing.
    testWidgets('the card head draws +N/-M as GbmBadges, as the file rows do', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+-.']));

      final List<GbmBadge> badges = tester
          .widgetList<GbmBadge>(find.byType(GbmBadge))
          .toList();

      expect(badges.length, 2);
      expect(badges[0].label, '+1');
      expect(badges[0].kind, GbmBadgeKind.added);
      expect(badges[1].label, '\u22121');
      expect(badges[1].kind, GbmBadgeKind.removed);
    });

    // Same rule the file rows follow: a zero is *not measured*, and a `+0`
    // pill would claim a measurement that never happened.
    testWidgets('a card with no removals draws no removed badge', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+.']));

      final List<GbmBadge> badges = tester
          .widgetList<GbmBadge>(find.byType(GbmBadge))
          .toList();

      expect(badges.length, 1);
      expect(badges.single.label, '+1');
    });

    /// Three pumps, and each one is a real hop. The click's own handler
    /// defers to a post-frame callback (it must not race the row delegates
    /// still settling from the tap collapsing the text selection); that
    /// callback calls `setTouched`, whose notification is itself coalesced
    /// to one per frame; only then does `setState` rebuild with the card.
    Future<void> tapHeading(WidgetTester tester, Finder heading) async {
      await tester.tap(heading);
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    // `SCOPES` row 6's own `how` column is 「點 hunk 標頭列（@@ …）」, and the
    // heading was a bare Text with no gesture on it at all -- the row's
    // *note* (right-click Stage hunk) was implemented and its `how` was not.
    // A conformance cell that reads 符合 off "the granularity is reachable"
    // cannot see that: reachable by some other input is not the input the
    // spec names.
    testWidgets('clicking the hunk heading selects every row in that hunk', (
      WidgetTester tester,
    ) async {
      // Two scopes in one hunk: what the click buys over the cards is a
      // single press that moves both.
      await pump(tester, file: _file(<String>['.+...+.']));
      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
      );

      await tapHeading(tester, find.textContaining('@@ '));

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('temporary-scope-card')),
          matching: find.textContaining('Stage '),
        ),
      );

      expect(staged.length, 1);
      expect(staged.single.hunkIndex, 0);
      expect(
        staged.single.lines,
        <int>[1, 5],
        reason:
            'the click frames the whole hunk, but only its changed lines may '
            'be sent to git',
      );
    });

    testWidgets('clicking one heading leaves the other hunk alone', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+.', '.-.']));

      await tapHeading(tester, find.textContaining('@@ ').last);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('temporary-scope-card')),
          matching: find.textContaining('Stage '),
        ),
      );

      expect(staged.length, 1);
      expect(
        staged.single.hunkIndex,
        1,
        reason: 'the second heading was clicked, so the second hunk moves',
      );
    });

    // The two inputs `SCOPES` names besides the drag select no *text*, so
    // SelectionArea paints nothing and the count on a button would be the
    // only word the user got about what they had selected. Asserting the
    // overlay by identity: a wrong colour throws no exception.
    testWidgets('the rows in the scope are tinted, so the selection is '
        'visible without a text highlight', (WidgetTester tester) async {
      await pump(tester, file: _file(<String>['.+.', '.-.']));

      Iterable<Container> rowBoxes() => tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(DiffLineView),
              matching: find.byType(Container),
            ),
          )
          .where((Container c) => c.foregroundDecoration != null);

      expect(rowBoxes(), isEmpty, reason: 'nothing is selected yet');

      await tapHeading(tester, find.textContaining('@@ ').first);

      final List<Container> tinted = rowBoxes().toList();
      expect(
        tinted.length,
        3,
        reason: 'the first hunk has three rows and all of them were framed',
      );
      expect(
        (tinted.first.foregroundDecoration! as BoxDecoration).color,
        tokensFor(GbmThemeVariant.darkTechnical).accent.withValues(alpha: 0.18),
      );
    });

    // `SCOPES` row 7's `how` names two inputs -- 「diff 區按住拖過多行，或
    // Shift + ↑ ↓」 -- and only the drag existed. Flutter's own
    // SelectableRegion does not fill the gap: with the tracker's latch
    // removed entirely, Shift+ArrowDown after a drag still left the card's
    // count unchanged, so the region was not extending the selection either.
    testWidgets('Shift+Down with nothing selected seeds at the first changed '
        'row', (WidgetTester tester) async {
      await pump(tester, file: _file(<String>['.+..-.']));
      await clickThen(tester, 'h0 l0');

      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsOneWidget,
      );
      expect(
        temporaryLabel('Stage 1 line'),
        findsOneWidget,
        reason:
            'seeding on the first *changed* row, not the first row: a scope '
            'holding one context line has nothing to stage and would show no '
            'card at all',
      );
    });

    testWidgets('each further Shift+Down grows the range by one row', (
      WidgetTester tester,
    ) async {
      // '.+..-.': rows 1 and 4 move, 2 and 3 are context between them. The
      // labels below are the proof the range steps over rows rather than
      // over changed lines -- the middle two presses add nothing stageable
      // and must still widen the frame.
      await pump(tester, file: _file(<String>['.+..-.']));
      await clickThen(tester, 'h0 l0');

      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
      expect(temporaryLabel('Stage 2 lines (1 changed)'), findsOneWidget);

      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
      expect(temporaryLabel('Stage 4 lines (2 changed)'), findsOneWidget);
    });

    testWidgets('Shift+Up shrinks the range back toward its anchor', (
      WidgetTester tester,
    ) async {
      // Anchored at row 1 and grown down to row 4, Shift+Up must move the
      // *focus* end back up rather than extend upward from row 1 -- which is
      // the whole difference between a range and a grow-only set.
      await pump(tester, file: _file(<String>['.+..-.']));
      await clickThen(tester, 'h0 l0');

      for (int i = 0; i < 4; i++) {
        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(temporaryLabel('Stage 4 lines (2 changed)'), findsOneWidget);

      await shiftArrow(tester, LogicalKeyboardKey.arrowUp);
      expect(temporaryLabel('Stage 3 lines (1 changed)'), findsOneWidget);
    });

    testWidgets('the range walks in render order, so it crosses into the next '
        'hunk', (WidgetTester tester) async {
      // Two hunks of three rows. Seeded at hunk 0's row 1, five more presses
      // reach hunk 1's row 1 -- and a range measured in anything but the
      // order the rows are painted would not get there at all.
      await pump(tester, file: _file(<String>['.+.', '.-.']));
      await clickThen(tester, 'h0 l0');

      for (int i = 0; i < 6; i++) {
        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
      }

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('temporary-scope-card')),
          matching: find.textContaining('Stage '),
        ),
      );

      expect(
        staged.length,
        2,
        reason: 'a range spanning two hunks is one stageLines call per hunk',
      );
      expect(staged[0].hunkIndex, 0);
      expect(staged[1].hunkIndex, 1);
    });

    testWidgets('the head counts the cards below it', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+...+.', '.-.']));
      expect(find.text('3 個 scope'), findsOneWidget);
    });

    testWidgets('a hunk index reaches the callback unshifted', (
      WidgetTester tester,
    ) async {
      // gbm_stage_lines takes a hunk index; getting it wrong stages a
      // different part of the file with no error anywhere.
      await pump(tester, file: _file(<String>['.+.', '.-.']));

      await tester.tap(find.text('Stage 1 line').first);
      await tester.tap(find.text('Stage 1 line').last);

      expect(staged.map((r) => r.hunkIndex).toList(), <int>[0, 1]);
    });

    testWidgets('a loading side keeps its head and shows a spinner', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: null, loading: true);

      expect(find.text('Unstaged'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Deliberately no pumpAndSettle: an indeterminate indicator schedules
      // frames forever (#101).
    });

    testWidgets('a side with nothing on it says so instead of spinning', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: null);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No changes'), findsOneWidget);
    });

    testWidgets('a binary file names itself and offers no button', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(const <String>[], binary: true));

      expect(find.textContaining('binary file'), findsOneWidget);
      expect(find.byType(GbmButton), findsNothing);
    });

    testWidgets('the card head keeps its button inside the card at a narrow '
        'width', (WidgetTester tester) async {
      // The bound is the card, not the pane: a button can sit inside a
      // 420px pane while hanging off the 200px card it belongs to.
      await pump(
        tester,
        file: _file(<String>['.+-.']),
        width: GbmLayout.splitterWcColumns.minExtent,
      );

      final Rect button = tester.getRect(find.byType(GbmButton));
      final Rect card = tester.getRect(
        find.byKey(const ValueKey<String>('scope-card-1')),
      );

      // Both edges: Expanded would satisfy "does not stick out to the
      // right" while collapsing the button to nothing.
      expect(button.left, greaterThanOrEqualTo(card.left - 0.01));
      expect(button.right, lessThanOrEqualTo(card.right + 0.01));
      expect(
        button.width,
        greaterThan(0),
        reason: 'a zero-width button is not a button that fits',
      );
      expect(tester.getRect(find.text('變更 1')).width, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('ScopedDiffView -- a text selection is a one-shot scope', () {
    late List<({int hunkIndex, List<int> lines})> staged;
    late List<void Function()?> submitters;

    setUp(() {
      staged = <({int hunkIndex, List<int> lines})>[];
      submitters = <void Function()?>[];
    });

    Future<void> pump(
      WidgetTester tester,
      DiffFile? file, {
      GlobalKey<_HostState>? hostKey,
    }) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 600,
          child: _Host(
            key: hostKey,
            initialFile: file,
            onStageScope: (int h, List<int> l) =>
                staged.add((hunkIndex: h, lines: l)),
            onTemporaryScopeChanged: submitters.add,
          ),
        ),
      );
      // One extra frame for the post-frame report of the initial (absent)
      // scope.
      await tester.pump();
    }

    /// Drags a mouse selection from the middle of [from]'s text to the
    /// middle of [to]'s. The shape is the SDK's own SelectableRegion test
    /// idiom; the trailing pumps matter because SelectionTouchTracker
    /// defers its notification to the next frame (selection geometry
    /// settles during layout, and writing state from there would be a
    /// mid-frame setState).
    Future<void> dragSelect(WidgetTester tester, String from, String to) async {
      // Anchored on the text's own edges, not its box centre. A diff line's
      // text sits in an Expanded far wider than its glyphs, so the centre of
      // the box is past the end of the string -- a drag between two centres
      // starts *after* the first row's last character and leaves that row
      // out of the selection entirely.
      final Rect fromRect = tester.getRect(find.text(from));
      final Rect toRect = tester.getRect(find.text(to));

      final TestGesture gesture = await tester.startGesture(
        Offset(fromRect.left + 1, fromRect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(Offset(toRect.right - 1, toRect.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a drag across changed lines raises a temporary card', (
      WidgetTester tester,
    ) async {
      await pump(tester, _file(<String>['.++.']));

      await dragSelect(tester, 'h0 l1', 'h0 l2');

      expect(find.text('一次性'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsOneWidget,
      );
    });

    testWidgets('Shift+Down after a drag continues from where the drag ended', (
      WidgetTester tester,
    ) async {
      // The two inputs are alternatives for one granularity, so they have to
      // share one range rather than each own a separate one.
      await pump(tester, _file(<String>['.+..-.']));
      await dragSelect(tester, 'h0 l1', 'h0 l2');
      expect(temporaryLabel('Stage 2 lines (1 changed)'), findsOneWidget);

      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);

      expect(
        temporaryLabel('Stage 3 lines (1 changed)'),
        findsOneWidget,
        reason:
            'restarting the range would drop back to one row instead of '
            'growing the drag by one',
      );
    });

    testWidgets('the scope stays put on idle frames after the drag ends', (
      WidgetTester tester,
    ) async {
      // The regression this pins really happened: every change to the
      // touched set rebuilds the rows, the rebuild perturbs the selection
      // geometry, the delegates re-report, and the card flapped in and out
      // frame after frame. One assertion right after the gesture cannot see
      // it -- the first frame was always correct.
      await pump(tester, _file(<String>['.++.']));
      await dragSelect(tester, 'h0 l1', 'h0 l2');

      for (int i = 0; i < 8; i++) {
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('temporary-scope-card')),
          findsOneWidget,
          reason: 'gone on idle frame $i',
        );
      }
    });

    testWidgets('the button names every row the drag framed, and the moving '
        'subset in parens', (WidgetTester tester) async {
      // '.++.' -> dragging line 0 (context) through line 2 (added) covers
      // three rows, two of which move.
      await pump(tester, _file(<String>['.++.']));

      await dragSelect(tester, 'h0 l0', 'h0 l2');

      expect(find.text('Stage 3 lines (2 changed)'), findsOneWidget);
    });

    testWidgets('the card it supersedes keeps its button, struck through and '
        'dead', (WidgetTester tester) async {
      await pump(tester, _file(<String>['.++.']));
      await dragSelect(tester, 'h0 l1', 'h0 l2');

      final Iterable<GbmButton> buttons = tester.widgetList<GbmButton>(
        find.byType(GbmButton),
      );
      final GbmButton superseded = buttons.firstWhere(
        (GbmButton b) => b.lineThrough,
      );

      expect(
        superseded.onPressed,
        isNull,
        reason:
            'struck through but still live is the same trap as a '
            'disabled-looking menu item with a real onTap',
      );
    });

    testWidgets('a drag over context alone raises nothing -- there is nothing '
        'to stage', (WidgetTester tester) async {
      await pump(tester, _file(<String>['..+']));

      await dragSelect(tester, 'h0 l0', 'h0 l1');

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
      );
      expect(find.text('Stage 1 line'), findsOneWidget);
    });

    testWidgets('a selection crossing two hunks makes one stageLines call per '
        'hunk, in file order', (WidgetTester tester) async {
      // gbm_stage_lines takes one hunk index. Counting, not `any`: a single
      // merged call and a double dispatch both look like "it fired".
      await pump(tester, _file(<String>['.+', '+.']));

      await dragSelect(tester, 'h0 l1', 'h1 l0');
      expect(
        tester
            .widgetList<GbmButton>(find.byType(GbmButton))
            .where((GbmButton b) => b.lineThrough)
            .length,
        2,
        reason: 'both hunks\' cards are superseded by the one selection',
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('temporary-scope-card')),
          matching: find.byType(GbmButton),
        ),
      );

      expect(staged.length, 2);
      expect(staged[0].hunkIndex, 0);
      expect(staged[0].lines, <int>[1]);
      expect(staged[1].hunkIndex, 1);
      expect(staged[1].lines, <int>[0]);
    });

    testWidgets('Ctrl+Shift+Enter stages the selection without touching the '
        'card', (WidgetTester tester) async {
      // #75 kept both readings of this key: `Ctrl/Cmd+Alt+S` globally (P16's
      // REVISIONS) and `Ctrl/Cmd+Shift+Enter` inside the diff's own focus
      // scope (P03-5 / SCOPES row 7). This is the scoped half.
      await pump(tester, _file(<String>['.++.']));
      await dragSelect(tester, 'h0 l1', 'h0 l2');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(staged.length, 1);
      expect(staged.single.hunkIndex, 0);
      expect(staged.single.lines, <int>[1, 2]);
    });

    testWidgets('one press spends it', (WidgetTester tester) async {
      await pump(tester, _file(<String>['.++.']));
      await dragSelect(tester, 'h0 l1', 'h0 l2');

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('temporary-scope-card')),
          matching: find.byType(GbmButton),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
      );
      expect(
        tester
            .widgetList<GbmButton>(find.byType(GbmButton))
            .where((GbmButton b) => b.lineThrough)
            .length,
        0,
        reason: 'the card it superseded gets its own button back',
      );
    });

    testWidgets('the submitter it publishes stages the same block the card '
        'button would', (WidgetTester tester) async {
      await pump(tester, _file(<String>['.++.']));
      await dragSelect(tester, 'h0 l1', 'h0 l2');

      final void Function()? submit = submitters.last;
      expect(
        submit,
        isNotNull,
        reason:
            'null here is what greys Ctrl/Cmd+Alt+S out, so a live '
            'selection has to publish something',
      );

      submit!();
      expect(staged.length, 1);
      expect(staged.single.lines, <int>[1, 2]);
    });

    testWidgets('the keyboard path spends the scope too, without a tap to do '
        'it for us', (WidgetTester tester) async {
      // Pressing the card's own button is a tap inside the SelectionArea,
      // which collapses the selection by itself. The shortcut is not, so
      // this is the only path that proves _submitTemporary clears.
      await pump(tester, _file(<String>['.++.']));
      await dragSelect(tester, 'h0 l1', 'h0 l2');

      submitters.last!();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
      );
      expect(
        submitters.last,
        isNull,
        reason:
            'a spent scope must un-publish, or the menu item stays live '
            'pointing at a selection that is gone',
      );
    });

    testWidgets('a shorter diff cannot inherit a selection made on the longer '
        'one', (WidgetTester tester) async {
      // The case the tracker's clear() is actually for. A SelectionListener
      // that is *unmounted* unregisters without notifying, so its key stays
      // in the touched set -- and the keys are positions, so on the shorter
      // diff that key now names a line the user never selected. (Swapping
      // two diffs of the same length does not show this: every row is still
      // mounted, and SelectableRegion drops the selection by itself.)
      final GlobalKey<_HostState> hostKey = GlobalKey<_HostState>();
      await pump(tester, _file(<String>['.++.']), hostKey: hostKey);
      await dragSelect(tester, 'h0 l1', 'h0 l2');

      hostKey.currentState!.setFile(_file(<String>['.+']));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
      );
    });

    testWidgets('swapping the diff in place drops the selection', (
      WidgetTester tester,
    ) async {
      // The element tree stays put and only the `file` prop changes -- which
      // is what a stage/unstage reply does. Re-pumping the whole tree would
      // clear the selection for an unrelated reason and prove nothing.
      final GlobalKey<_HostState> hostKey = GlobalKey<_HostState>();
      await pump(tester, _file(<String>['.++.']), hostKey: hostKey);
      await dragSelect(tester, 'h0 l1', 'h0 l2');
      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsOneWidget,
      );

      hostKey.currentState!.setFile(_file(<String>['.++.']));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
        reason:
            'the tracker keys are positions, so a carried-over selection '
            'would point at whatever now sits at those indices',
      );
    });
  });
}

/// Holds the diff in state so a test can replace it without rebuilding the
/// tree around it.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.initialFile,
    required this.onStageScope,
    required this.onTemporaryScopeChanged,
  });

  final DiffFile? initialFile;
  final void Function(int hunkIndex, List<int> lines) onStageScope;
  final void Function(void Function()? submit) onTemporaryScopeChanged;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late DiffFile? _file = widget.initialFile;

  void setFile(DiffFile? file) => setState(() => _file = file);

  @override
  Widget build(BuildContext context) => ScopedDiffView(
    title: 'Unstaged',
    file: _file,
    staged: false,
    onStageScope: widget.onStageScope,
    onTemporaryScopeChanged: widget.onTemporaryScopeChanged,
  );
}
