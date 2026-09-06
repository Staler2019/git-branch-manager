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
import 'package:gbm_flutter/widgets/gbm_dashed.dart';
import 'package:gbm_flutter/widgets/gbm_outlined_pill.dart';

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
      bool truncated = false,
      bool discardable = true,
      double width = 420,
    }) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: width,
          child: ScopedDiffView(
            softWrap: false,
            sources: <ScopedDiffSource>[
              ScopedDiffSource(
                title: isStaged ? 'Staged' : 'Unstaged',
                file: file,
                staged: isStaged,
                loading: loading,
                truncated: truncated,
                onStageScope: (int h, List<int> l) =>
                    staged.add((hunkIndex: h, lines: l)),
                onDiscardScope: discardable
                    ? (int h, List<int> l) =>
                          discarded.add((hunkIndex: h, lines: l))
                    : null,
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('a refused diff says so instead of claiming nothing changed', (
      WidgetTester tester,
    ) async {
      // The core refuses a diff over its byte cap and sends no files at all,
      // so `file` is null for a reason that is not "this side is clean".
      // Reading the two as one is what put "Nothing unstaged" in front of a
      // file whose own row badge said it had changes.
      await pump(tester, file: null, truncated: true);

      expect(find.text('Diff too large to display'), findsOneWidget);
      // `emptyLabel`'s default here; the Working Copy passes its own wording,
      // which working_copy_diff_pane_test.dart pins.
      expect(find.text('No changes'), findsNothing);
    });

    testWidgets('an ordinary empty side still says nothing changed', (
      WidgetTester tester,
    ) async {
      // The negative half: without it, the arm above could be drawn for every
      // empty side and the test would still pass.
      await pump(tester, file: null);

      expect(find.text('No changes'), findsOneWidget);
      expect(find.text('Diff too large to display'), findsNothing);
    });

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
      // 420px pane while hanging off the card it belongs to.
      //
      // The width is the *diff* pane's own floor. It used to be
      // `splitterWcColumns.minExtent` -- a file-list column's floor, which
      // was never this widget's neighbour and only ever stood in as "a
      // narrow number from the same view". `splitterWcDiffSides` is the
      // divider this view actually sits inside in `2 file` mode, and its
      // 140 is narrower than the old 200, so the check got stricter.
      await pump(
        tester,
        file: _file(<String>['.+-.']),
        width: GbmLayout.splitterWcDiffSides.minExtent,
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

    // **Nothing derived from the touched set is drawn while the pointer is
    // down.** Once the one-shot block moved inside the card (where the demo
    // puts it), drawing it mid-drag reparents the rows below it -- and those
    // rows carry the SelectionListeners whose reports decide the block
    // should exist, so the drag collapsed to a single row. The live feedback
    // during a drag is SelectionArea's own text highlight; the block is what
    // the drag *settles* into.
    testWidgets('no one-shot block appears until the pointer comes up', (
      WidgetTester tester,
    ) async {
      // The *same* DiffFile instance both times: `didUpdateWidget` drops the
      // selection when the file changes by identity, so a fresh fixture
      // would clear it for an unrelated reason and the assertion would pass
      // for the wrong one.
      final DiffFile file = _file(<String>['.++++.']);
      await pump(tester, file);

      final Rect first = tester.getRect(find.text('h0 l1'));
      final Rect last = tester.getRect(find.text('h0 l4'));
      final TestGesture gesture = await tester.startGesture(
        Offset(first.left + 1, first.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(Offset(last.right - 1, last.center.dy));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
        reason: 'drawn mid-drag it moves the rows the delegates report on',
      );

      // Now force a rebuild that this widget did not originate -- a parent
      // repainting mid-drag, which really happens (a status refresh, a
      // hover on an ancestor). Suppressing `setState` in the tracker's
      // listener cannot stop that one; only the gate inside `build` can, and
      // without this line the mutation that removes it stays green.
      await pump(tester, file);

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
        reason: 'a rebuild from outside must not draw the block either',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsOneWidget,
      );
    });

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

    // The demo's 變體 B nests `.variant-B-temp` **inside**
    // `.variant-B-card`, wrapping the selected rows in place; the card goes
    // `.variant-B-card-muted` and its own button `.variant-B-btn-off`. This
    // shipped instead as an extra row pinned to the top of the column --
    // an implementation convenience (a fixed slot cannot reparent the keyed
    // rows below it), not a design decision, and the user called it out.
    //
    // Asserting the ancestor, not the presence: a finder proves existence,
    // never position, and the top-slot version passed every existing
    // assertion in this file.
    testWidgets('the one-shot block is nested inside the scope card it '
        'covers, not pinned above the column', (WidgetTester tester) async {
      // Three added rows in one scope, with only the middle one selected --
      // so the card has a row before the block and a row after it, and
      // "in place" is a claim the fixture can actually falsify.
      await pump(tester, _file(<String>['.+++.']));
      await dragSelect(tester, 'h0 l2', 'h0 l2');

      final Finder temp = find.byKey(
        const ValueKey<String>('temporary-scope-card'),
      );
      expect(temp, findsOneWidget);
      expect(
        find.ancestor(
          of: temp,
          matching: find.byKey(const ValueKey<String>('scope-card-1')),
        ),
        findsOneWidget,
        reason: 'the block must live inside the card whose rows it covers',
      );

      // In place within that card: after the row above it, before the row
      // below it. Pinned to the top of anything -- the column or the card --
      // fails both.
      final Rect block = tester.getRect(temp);
      expect(tester.getRect(find.text('h0 l1')).bottom, lessThan(block.top));
      expect(tester.getRect(find.text('h0 l3')).top, greaterThan(block.bottom));
    });

    testWidgets('the covered card is muted and its own button is dead', (
      WidgetTester tester,
    ) async {
      await pump(tester, _file(<String>['.+..-.']));
      await dragSelect(tester, 'h0 l1', 'h0 l2');

      final GbmButton off = tester.widget<GbmButton>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('scope-card-1')),
              matching: find.byType(GbmButton),
            )
            .first,
      );
      expect(off.onPressed, isNull);
      expect(off.lineThrough, isTrue);

      // `.variant-B-card-muted`: the accent edge goes neutral while the
      // one-shot block holds the action. Asserted by identity, because a
      // card that kept its accent stripe throws no exception -- it just
      // shows two things claiming to be the live scope.
      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);
      // By predicate, not by index: the card is two nested Containers (the
      // radius/fill/shadow outside, the four border sides inside, because
      // Flutter forbids a borderRadius on a non-uniform border), and an
      // index into the descendants would silently follow that structure.
      final Container inner = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('scope-card-1')),
              matching: find.byWidgetPredicate(
                (Widget w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration! as BoxDecoration).border is Border,
              ),
            )
            .first,
      );
      expect(
        ((inner.decoration! as BoxDecoration).border! as Border).left.color,
        colors.borderStrong,
      );
    });

    // One scope, one press -- however many cards it reaches. The second and
    // later cards get the dashed body so the extent stays visible, but a
    // second head would be a second button claiming to be a second action.
    testWidgets('a selection spanning two cards still shows exactly one '
        'one-shot button', (WidgetTester tester) async {
      await pump(tester, _file(<String>['.+...+.']));
      await dragSelect(tester, 'h0 l1', 'h0 l5');

      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsOneWidget,
      );
      expect(find.text('一次性'), findsOneWidget);

      // Both cards are covered, so both go muted and both own buttons die --
      // it is the extent that is shared, not the action.
      for (final String card in const <String>[
        'scope-card-1',
        'scope-card-2',
      ]) {
        final GbmButton off = tester.widget<GbmButton>(
          find
              .descendant(
                of: find.byKey(ValueKey<String>(card)),
                matching: find.byType(GbmButton),
              )
              .first,
        );
        expect(off.onPressed, isNull, reason: '$card should be superseded');
      }
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

    // 變體 B's own CSS, quoted, for the four properties this group pins:
    //
    //   .variant-B-temp     { border: 1px dashed var(--accent); }
    //   .variant-B-temphead { border-bottom: 1px dashed var(--accent); }
    //   .variant-B-gap      { padding-left: 2px;
    //                         border-left: 1px dashed var(--border-default); }
    //   .variant-B-cardhead { border-bottom: 1px solid var(--border-default); }
    //   .variant-B-card     { margin: var(--space-2) 0; }
    //
    // 使用者裁定「照建議」on section 06 of
    // docs/claude-design-demo/working-copy-layout-spec.html, items S3, S4
    // (its border and muted ground only, not its 30px height), S9 and S10.
    group('-- 變體 B card chrome', () {
      testWidgets('the one-shot block is outlined in dashed accent, and its '
          'head is underlined in the same dash', (WidgetTester tester) async {
        await pump(tester, _file(<String>['.+-.']));
        await clickThen(tester, 'h0 l1');
        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);

        final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

        // The dash is the whole point: it is what separates the one-shot
        // block from the solid-edged cards that persist. Both were solid
        // before, differing only in colour.
        final GbmDashedBorder outline = tester.widget<GbmDashedBorder>(
          find.byKey(const ValueKey<String>('temporary-scope-card')),
        );
        expect(outline.color.toARGB32(), colors.accent.toARGB32());

        final GbmDashedLine rule = tester.widget<GbmDashedLine>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('temporary-scope-card')),
            matching: find.byType(GbmDashedLine),
          ),
        );
        expect(rule.axis, Axis.horizontal);
        expect(rule.color.toARGB32(), colors.accent.toARGB32());
      });

      testWidgets('a context gap is marked by a dashed rule, not a solid one '
          'plus dimming', (WidgetTester tester) async {
        // Two changes far enough apart to leave a gap between them.
        await pump(tester, _file(<String>['+.....+']));

        final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);
        final GbmDashedLine rule = tester
            .widgetList<GbmDashedLine>(find.byType(GbmDashedLine))
            .first;
        expect(rule.axis, Axis.vertical);
        expect(rule.color.toARGB32(), colors.borderDefault.toARGB32());

        // 變體 B dims nothing anywhere -- grepped, the word `opacity` appears
        // only under `.variant-A-*` and `.variant-C-*`. The dashed rule is
        // what marks context; the built version marked it twice, once with a
        // 2px solid rule and again by fading the code itself.
        expect(find.byType(Opacity), findsNothing);
      });

      testWidgets('the card head is separated from the code by a rule, and a '
          'superseded head sits on sunken ground', (WidgetTester tester) async {
        await pump(tester, _file(<String>['.+-.']));
        final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

        Container headOf(String cardKey) => tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(ValueKey<String>(cardKey)),
                matching: find.byWidgetPredicate(
                  (Widget w) =>
                      w is Container &&
                      w.decoration is BoxDecoration &&
                      (w.decoration! as BoxDecoration).border is Border &&
                      ((w.decoration! as BoxDecoration).border! as Border)
                              .bottom
                              .width >
                          0 &&
                      ((w.decoration! as BoxDecoration).border! as Border)
                              .left
                              .width ==
                          0,
                ),
              )
              .first,
        );

        final BoxDecoration live =
            headOf('scope-card-1').decoration! as BoxDecoration;
        expect(
          (live.border! as Border).bottom.color.toARGB32(),
          colors.borderDefault.toARGB32(),
        );
        expect(live.color!.toARGB32(), colors.surfacePanelRaised.toARGB32());

        // Now supersede it and read the same head again.
        await clickThen(tester, 'h0 l1');
        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);

        final BoxDecoration muted =
            headOf('scope-card-1').decoration! as BoxDecoration;
        expect(muted.color!.toARGB32(), colors.surfaceSunken.toARGB32());
      });

      testWidgets('a hunk heading is followed by a rule, and a card is spaced '
          'by space2', (WidgetTester tester) async {
        await pump(tester, _file(<String>['.+.']));

        // S9: the heading is mono text plus a 1px rule filling the rest of
        // the row. Without it the `@@ …` line reads as another code line.
        expect(
          find.byKey(const ValueKey<String>('hunk-heading-rule-0')),
          findsOneWidget,
        );

        // S10: space2 (8), not space1 (4). Read off the widget rather than
        // measured, because the margin collapses against nothing here and a
        // rect comparison would only see the sum of two neighbours' margins.
        final Container card = tester.widget<Container>(
          find.byKey(const ValueKey<String>('scope-card-1')),
        );
        expect(
          card.margin,
          const EdgeInsets.symmetric(vertical: GbmSpacing.space2),
        );
      });

      // `.variant-B-once { border: 1px solid var(--warning);
      //                    border-radius: var(--radius-full);
      //                    font-weight: var(--weight-semibold);
      //                    color: var(--warning) }` -- transparent ground.
      //
      // S8. It shipped as a [GbmBadge] at its default neutral kind, which is
      // the same shape as the +N/-N count pills sitting a few pixels away in
      // the card head above. This is the one thing on screen that says
      // 「這個按下去就沒了」, and it should not look like a tally.
      testWidgets('the 一次性 pill is outlined in warning, not a neutral '
          'badge', (WidgetTester tester) async {
        await pump(tester, _file(<String>['.+-.']));
        await clickThen(tester, 'h0 l1');
        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);

        final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);
        final Finder pill = find.ancestor(
          of: find.text('一次性'),
          matching: find.byType(GbmOutlinedPill),
        );
        expect(pill, findsOneWidget);

        final GbmOutlinedPill widget = tester.widget<GbmOutlinedPill>(pill);
        expect(widget.color.toARGB32(), colors.warning.toARGB32());
        expect(widget.background, isNull, reason: 'transparent ground');
        expect(widget.fontWeight, GbmTypography.weightSemibold);

        // And it is no longer the neutral badge it used to be. Asserted
        // because "an outlined pill exists" would still pass with a stray
        // GbmBadge left beside it.
        expect(
          find.ancestor(of: find.text('一次性'), matching: find.byType(GbmBadge)),
          findsNothing,
        );
      });

      // `.variant-B-dot { width: 8px; height: 8px }` and
      // `.variant-B-chip { padding: 1px var(--space-2);
      //                    background: var(--surface-panel-raised);
      //                    border: 1px solid var(--border-subtle);
      //                    border-radius: var(--radius-full);
      //                    color: var(--text-tertiary) }`.
      //
      // S5, partially: the chip and the 8px dot are adopted, the title's
      // text-sm/semibold/primary is **not** -- every other pane header in
      // this app is textXs/bold/secondary, and matching the design here
      // would make this one header unlike its neighbours.
      testWidgets('the column head draws an 8px dot and a ringed count chip', (
        WidgetTester tester,
      ) async {
        await pump(tester, _file(<String>['.+-.']));
        final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

        final Container dot = tester.widget<Container>(
          find.byKey(const ValueKey<String>('column-head-dot')),
        );
        expect(dot.constraints?.maxWidth, 8);
        expect(dot.constraints?.maxHeight, 8);

        final GbmOutlinedPill chip = tester.widget<GbmOutlinedPill>(
          find.ancestor(
            of: find.textContaining('個 scope'),
            matching: find.byType(GbmOutlinedPill),
          ),
        );
        expect(chip.color.toARGB32(), colors.textTertiary.toARGB32());
        expect(chip.borderColor?.toARGB32(), colors.borderSubtle.toARGB32());
        expect(
          chip.background?.toARGB32(),
          colors.surfacePanelRaised.toARGB32(),
        );

        // The title deliberately keeps this app's own header treatment.
        final Text title = tester.widget<Text>(find.text('Unstaged'));
        expect(title.style?.fontSize, GbmTypography.textXs);
        expect(title.style?.fontWeight, FontWeight.bold);
        expect(title.style?.color?.toARGB32(), colors.textSecondary.toARGB32());
      });

      // `.variant-B-card:hover { border-color: var(--border-strong);
      //                          border-left-color: var(--accent-hover);
      //                          box-shadow: var(--shadow-md) }`
      //
      // S11. The card had no hover state at all -- the one dimension-D
      // signal it was missing, on a surface whose whole affordance is
      // "press the button on the card you are pointing at".
      testWidgets('a scope card lifts and brightens under the pointer', (
        WidgetTester tester,
      ) async {
        await pump(tester, _file(<String>['.+-.']));
        final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

        Border borderOf() =>
            (tester
                            .widget<Container>(
                              find
                                  .descendant(
                                    of: find.byKey(
                                      const ValueKey<String>('scope-card-1'),
                                    ),
                                    matching: find.byWidgetPredicate(
                                      (Widget w) =>
                                          w is Container &&
                                          w.decoration is BoxDecoration &&
                                          (w.decoration! as BoxDecoration)
                                                  .border
                                              is Border &&
                                          ((w.decoration! as BoxDecoration)
                                                          .border!
                                                      as Border)
                                                  .left
                                                  .width ==
                                              3,
                                    ),
                                  )
                                  .first,
                            )
                            .decoration!
                        as BoxDecoration)
                    .border!
                as Border;

        BoxDecoration outerOf() =>
            tester
                    .widget<Container>(
                      find.byKey(const ValueKey<String>('scope-card-1')),
                    )
                    .decoration!
                as BoxDecoration;

        expect(
          borderOf().top.color.toARGB32(),
          colors.borderDefault.toARGB32(),
        );
        expect(borderOf().left.color.toARGB32(), colors.accent.toARGB32());
        final List<BoxShadow> resting = outerOf().boxShadow!;

        final TestGesture pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(pointer.removePointer);
        await pointer.addPointer(location: Offset.zero);
        await pointer.moveTo(
          tester.getCenter(find.byKey(const ValueKey<String>('scope-card-1'))),
        );
        await tester.pump();

        expect(borderOf().top.color.toARGB32(), colors.borderStrong.toARGB32());
        expect(borderOf().left.color.toARGB32(), colors.accentHover.toARGB32());
        // Asserted as "a different shadow from the resting one", not against
        // a literal: shadowMd is a token whose values are the design's, and
        // copying them here would be a second source for them.
        expect(outerOf().boxShadow, isNot(equals(resting)));
        expect(
          outerOf().boxShadow,
          GbmEffects.shadowMd(GbmThemeVariant.darkTechnical),
        );
      });
    });
  });

  group('ScopedDiffView -- U5: the direction is the first card painted', () {
    late List<({bool staged, int hunkIndex, List<int> lines})> staged;

    setUp(() => staged = <({bool staged, int hunkIndex, List<int> lines})>[]);

    /// One hunk, three added lines, sitting at [start] on the index side.
    ///
    /// Both line numbers are set to the same run because a source reads only
    /// its own side ([indexPositionOf] takes `oldLine` for unstaged and
    /// `newLine` for staged), and giving them different runs would only make
    /// the fixture harder to read without changing what either side sees.
    DiffFile sideFile({required String tag, required int start}) => DiffFile(
      oldPath: 'lib/a.dart',
      newPath: 'lib/a.dart',
      kind: FileChangeKind.modified,
      oldMode: '',
      newMode: '',
      oldBlob: '',
      newBlob: '',
      binary: false,
      similarity: 0,
      addedLines: 3,
      removedLines: 0,
      displayPath: 'lib/a.dart',
      hunks: <DiffHunk>[
        DiffHunk(
          oldStart: start,
          oldCount: 3,
          newStart: start,
          newCount: 3,
          heading: '',
          lines: <DiffLine>[
            for (int i = 0; i < 3; i++)
              DiffLine(
                kind: DiffLineKind.added,
                oldLine: start + i,
                newLine: start + i,
                text: '$tag l$i',
              ),
          ],
        ),
      ],
    );

    /// Staged at line 10, unstaged at line 100 -- so the region sort paints
    /// the **staged** card first, and source order and painted order
    /// disagree. A fixture with the unstaged side first cannot tell the two
    /// apart ([TEST-fixture-cannot-disagree]).
    Future<void> pump(WidgetTester tester) => pumpGbmWidget(
      tester,
      child: SizedBox(
        width: 600,
        child: ScopedDiffView(
          softWrap: false,
          sources: <ScopedDiffSource>[
            ScopedDiffSource(
              title: 'Unstaged',
              file: sideFile(tag: 'un', start: 100),
              staged: false,
              onStageScope: (int h, List<int> l) =>
                  staged.add((staged: false, hunkIndex: h, lines: l)),
            ),
            ScopedDiffSource(
              title: 'Staged',
              file: sideFile(tag: 'st', start: 10),
              staged: true,
              onStageScope: (int h, List<int> l) =>
                  staged.add((staged: true, hunkIndex: h, lines: l)),
            ),
          ],
        ),
      ),
    );

    Future<void> dragSelect(WidgetTester tester, String from, String to) async {
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

    testWidgets('the staged card is painted above the unstaged one', (
      tester,
    ) async {
      await pump(tester);

      expect(
        tester.getRect(find.text('st l0')).top,
        lessThan(tester.getRect(find.text('un l0')).top),
        reason:
            'the fixture only discriminates while the region sort has put '
            'source 1 first',
      );

      // 變更 N is numbered over the painted list, so the staged card is 1
      // and the unstaged one is 2 -- the reverse of source order. This is
      // the claim `hunkSegments`' deleted `firstOrdinal` used to make one
      // level down; it could not survive there, because a number handed out
      // while the blocks are still grouped by hunk is shuffled by the sort
      // that follows ([CULT-nothing-silently-dropped]).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('scope-card-1')),
          matching: find.text('st l0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('scope-card-2')),
          matching: find.text('un l0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a drag crossing both directions takes the direction of the '
        'card it reached first', (tester) async {
      await pump(tester);

      await dragSelect(tester, 'st l0', 'un l2');

      // The whole of U5, stated where the user reads it: 「取它碰到的第一張
      // 卡片的方向」. The first card the drag reaches is the staged one, so
      // the one-shot button unstages -- and the unstaged rows it also
      // crossed are excluded rather than folded in, because git has no one
      // action that stages and unstages at once.
      expect(
        temporaryLabel('Unstage 3 lines'),
        findsOneWidget,
        reason:
            'source order would answer 「stage」 here; painted order is what '
            'U5 names',
      );
      expect(
        temporaryLabel('Stage 3 lines'),
        findsNothing,
        reason: 'one drag is one direction, and one press',
      );

      // The other direction's card is excluded, not consumed: it keeps its
      // own button and stays pressable. Paired with the assertion above --
      // no Stage label *inside* the one-shot card -- this one being outside
      // it is what the two together say.
      expect(find.text('Stage 3 lines'), findsOneWidget);
    });
  });

  // 使用者回報:「my current untracked file, i stage the middle line
  // (document...) and it should split into 3 scope, but its only 2 scope」.
  //
  // Both diffs below are what a real repository answered, measured rather
  // than invented: a 5-line untracked file with only its middle line staged
  // gives `git diff` an `@@ -1 +1,5 @@` hunk whose context line *is* the
  // staged one, and `git diff --cached` a `new file mode` hunk holding just
  // that line.
  group('ScopedDiffView -- an untracked file with its middle line staged', () {
    DiffFile unstagedSide() => DiffFile(
      oldPath: 'new.txt',
      newPath: 'new.txt',
      kind: FileChangeKind.modified,
      oldMode: '',
      newMode: '',
      oldBlob: '',
      newBlob: '',
      binary: false,
      similarity: 0,
      addedLines: 4,
      removedLines: 0,
      displayPath: 'new.txt',
      hunks: <DiffHunk>[
        DiffHunk(
          oldStart: 1,
          oldCount: 1,
          newStart: 1,
          newCount: 5,
          heading: '',
          lines: <DiffLine>[
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 1,
              text: 'alpha',
            ),
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 2,
              text: 'bravo',
            ),
            DiffLine(
              kind: DiffLineKind.context,
              oldLine: 1,
              newLine: 3,
              text: 'document',
            ),
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 4,
              text: 'delta',
            ),
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 5,
              text: 'echo',
            ),
          ],
        ),
      ],
    );

    DiffFile stagedSide() => DiffFile(
      oldPath: '',
      newPath: 'new.txt',
      kind: FileChangeKind.added,
      oldMode: '',
      newMode: '100644',
      oldBlob: '',
      newBlob: '',
      binary: false,
      similarity: 0,
      addedLines: 1,
      removedLines: 0,
      displayPath: 'new.txt',
      hunks: <DiffHunk>[
        DiffHunk(
          oldStart: 0,
          oldCount: 0,
          newStart: 1,
          newCount: 1,
          heading: '',
          lines: <DiffLine>[
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 1,
              text: 'document',
            ),
          ],
        ),
      ],
    );

    Future<void> pump(WidgetTester tester) => pumpGbmWidget(
      tester,
      child: SizedBox(
        width: 600,
        child: ScopedDiffView(
          softWrap: false,
          sources: <ScopedDiffSource>[
            ScopedDiffSource(
              title: 'Unstaged',
              file: unstagedSide(),
              staged: false,
              onStageScope: (int h, List<int> l) {},
            ),
            ScopedDiffSource(
              title: 'Staged',
              file: stagedSide(),
              staged: true,
              onStageScope: (int h, List<int> l) {},
            ),
          ],
        ),
      ),
    );

    testWidgets('git sees three regions, so there are three cards', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      // Two before this fix: the gap rule folded alpha/bravo and delta/echo
      // into one card across the single unchanged line between them -- and
      // that line is the staged change itself.
      expect(
        tester
            .widgetList<GbmButton>(find.byType(GbmButton))
            .map((GbmButton b) => b.label)
            .toList(),
        <String>['Stage 2 lines', 'Unstage 1 line', 'Stage 2 lines'],
      );
    });

    testWidgets('the staged card is painted between the two unstaged ones', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      // Order, not just count: three cards in the wrong order would satisfy
      // the assertion above. The staged card sits *on* index line 1, the
      // first unstaged card is inserted before it and the second after it,
      // which is what the two-part index position exists to express.
      //
      // Measured geometrically, off rows and a button that each resolve to
      // exactly one widget -- `find.text('document')` would not, because the
      // staged row and the unstaged side's context row both say it
      // ([FLU-finder-proves-existence-not-position]).
      final double staged = tester
          .getRect(find.widgetWithText(GbmButton, 'Unstage 1 line'))
          .top;
      expect(tester.getRect(find.text('bravo')).top, lessThan(staged));
      expect(tester.getRect(find.text('delta')).top, greaterThan(staged));
    });

    // 使用者裁定 B: 「合併模式下把另一側已經當成變更畫出來的 context 列隱藏
    // 掉」. The unstaged diff carries `document` as context because it is
    // what its two insertions sit around -- but in a merged list the staged
    // card *is* that line, one row below, so drawing it twice states the
    // same index line twice in one list.
    testWidgets('the line the other side stages is not drawn twice', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(find.text('document'), findsOneWidget);
      // And it is the staged card's row that survives, not the context one:
      // the surviving row sits inside the card whose button unstages.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.widgetWithText(GbmButton, 'Unstage 1 line'),
            matching: find.byKey(const ValueKey<String>('scope-card-2')),
          ),
          matching: find.text('document'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('nothing else is dropped', (WidgetTester tester) async {
      await pump(tester);

      // The suppression is narrow: only a context row whose index line the
      // other source changes. Every real change on both sides still draws.
      for (final String text in <String>['alpha', 'bravo', 'delta', 'echo']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
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
    softWrap: false,
    sources: <ScopedDiffSource>[
      ScopedDiffSource(
        title: 'Unstaged',
        file: _file,
        staged: false,
        onStageScope: widget.onStageScope,
      ),
    ],
    onTemporaryScopeChanged: widget.onTemporaryScopeChanged,
  );
}
