// Slice S3: in `2 file` the two columns are cut into the same segments, and
// each pads its shorter runs at their ends (「短側尾部插高度」) until every
// segment starts at the same height in both. Not yet scrolled together
// (S4): these tests draw everything at offset 0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

// Unstaged replaces 10..12 (six card rows), staged replaces 11 (two): the
// card segment is twice as tall on the unstaged side. Both replace 30, a
// hunk of its own, so excerpt mode has two segments past the leading one.
const Set<int> _unstagedEdits = <int>{10, 11, 12, 30};
const Set<int> _stagedEdits = <int>{11, 30};

Future<void> _pump(
  WidgetTester tester, {
  required bool fullFile,
  required bool softWrap,
  double width = 900,
}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpGbmWidget(
    tester,
    child: WorkingCopyDiffPane(
      softWrap: softWrap,
      displayPath: 'lib/a.dart',
      unstagedFile: replacementsDiff(40, _unstagedEdits, context: 3),
      stagedFile: replacementsDiff(40, _stagedEdits, context: 3),
      unstagedFullFile: replacementsDiff(
        40,
        _unstagedEdits,
        context: kAllContext,
      ),
      stagedFullFile: replacementsDiff(40, _stagedEdits, context: kAllContext),
      fullFile: fullFile,
      unstagedLoading: false,
      stagedLoading: false,
      onStageScope: (_, _, _) {},
      onDiscardScope: (_, _) {},
      onTemporaryScopeChanged: (_) {},
      onToggleFullFile: () {},
    ),
  );
  await tester.tap(find.text('2 file'));
  // The first frame lays out on estimates; the measured heights land after
  // it ([FLU-postframe-no-frame]), and the spacers they resize after that.
  for (int i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Finder _spacer(int column, int segment) => find.byWidgetPredicate(
  (Widget w) =>
      w is SyncSlotSpacer && w.column == column && w.segment == segment,
);

int _segmentCount(WidgetTester tester, int column) => tester
    .widgetList<SyncSlotSpacer>(find.byType(SyncSlotSpacer))
    .where((SyncSlotSpacer s) => s.column == column)
    .length;

/// Every segment ends at the same height in both columns: the bottom of its
/// spacer is the top of the next segment.
void _expectAligned(WidgetTester tester) {
  final int count = _segmentCount(tester, 0);
  expect(count, greaterThan(2), reason: 'the fixture must cut segments');
  expect(_segmentCount(tester, 1), count);
  for (int k = 0; k < count; k++) {
    expect(
      tester.getRect(_spacer(1, k)).bottom,
      closeTo(tester.getRect(_spacer(0, k)).bottom, 0.5),
      reason: 'segment $k',
    );
  }
}

Finder _rowText(String text) => find.text(text, findRichText: true);

void main() {
  for (final bool fullFile in const <bool>[false, true]) {
    for (final bool softWrap in const <bool>[false, true]) {
      testWidgets('fullFile=$fullFile softWrap=$softWrap: every segment '
          'starts at the same height in both columns', (
        WidgetTester tester,
      ) async {
        await _pump(tester, fullFile: fullFile, softWrap: softWrap);
        expect(find.byType(ScopedDiffView), findsNWidgets(2));
        _expectAligned(tester);
      });
    }
  }

  testWidgets('soft wrap with one column narrower wraps it taller, and the '
      'other pads to it', (WidgetTester tester) async {
    await _pump(tester, fullFile: true, softWrap: true, width: 500);
    _expectAligned(tester);
  });

  testWidgets('the shorter column pads at the end of the segment, not its '
      'start', (WidgetTester tester) async {
    await _pump(tester, fullFile: false, softWrap: false);
    // The staged card's last row is `edited L11`; the unstaged card ends at
    // `edited L12`, two rows later, so the staged spacer of that segment
    // comes after its card.
    final Rect stagedCardEnd = tester.getRect(
      find
          .descendant(
            of: find.byType(ScopedDiffView).last,
            matching: _rowText('edited L11'),
          )
          .first,
    );
    final Iterable<SyncSlotSpacer> padding = tester
        .widgetList<SyncSlotSpacer>(find.byType(SyncSlotSpacer))
        .where(
          (SyncSlotSpacer s) =>
              s.column == 1 && tester.getRect(find.byWidget(s)).height > 10,
        );
    expect(padding, isNotEmpty);
    for (final SyncSlotSpacer s in padding) {
      expect(
        tester.getRect(find.byWidget(s)).top,
        greaterThanOrEqualTo(stagedCardEnd.bottom),
      );
    }
  });

  // F2: a mark sits where its card sits in the column, as a share of the
  // height both columns share -- so the two rulers read on one scale even
  // where a card starts lower in its segment on one side.
  testWidgets('full-file: each ruler mark sits at its card\'s share of the '
      'shared height', (WidgetTester tester) async {
    await _pump(tester, fullFile: true, softWrap: true);
    final List<Element> views = find.byType(ScopedDiffView).evaluate().toList();
    expect(views.length, 2);
    final List<double> totals = <double>[];
    for (int c = 0; c < 2; c++) {
      final Finder inView = find.byWidget(views[c].widget);
      final Rect list = tester.getRect(
        find
            .descendant(
              of: inView,
              matching: find.byWidgetPredicate(
                (Widget w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
      final int last = _segmentCount(tester, c) - 1;
      // The last spacer's item also draws the well's bottom edge.
      final double total =
          tester
              .getRect(
                find
                    .ancestor(
                      of: _spacer(c, last),
                      matching: find.byWidgetPredicate(
                        (Widget w) =>
                            w.runtimeType.toString() == '_FrameSegment',
                      ),
                    )
                    .first,
              )
              .bottom -
          list.top;
      totals.add(total);
      final Rect ruler = tester.getRect(
        find.descendant(
          of: inView,
          matching: find.byKey(const ValueKey<String>('diff-overview-ruler')),
        ),
      );
      final List<Rect> cards = tester
          .widgetList(
            find.descendant(
              of: inView,
              matching: find.byWidgetPredicate(
                (Widget w) => w.runtimeType.toString() == '_ScopeCard',
              ),
            ),
          )
          .map((Widget w) => tester.getRect(find.byWidget(w)))
          .toList();
      expect(cards, hasLength(2), reason: 'column $c');
      for (int n = 1; n <= cards.length; n++) {
        final Rect mark = tester.getRect(
          find.descendant(
            of: inView,
            matching: find.byKey(ValueKey<String>('ruler-mark-$n')),
          ),
        );
        // A card's item starts where its ring's margin does.
        final double share = (cards[n - 1].top - list.top) / total;
        expect(
          mark.top - ruler.top,
          closeTo(ruler.height * share, 3),
          reason: 'column $c card $n',
        );
      }
    }
    expect(totals[1], closeTo(totals[0], 0.5));
  });

  // A fill run cut by segments has a spacer between every two rows; at
  // height 0 the rows must still stack as one run does in `unified`.
  testWidgets('full-file: a fill run stacks as it does unsynced', (
    WidgetTester tester,
  ) async {
    double pitch() =>
        tester.getRect(_rowText('L21').first).top -
        tester.getRect(_rowText('L20').first).top;
    await _pump(tester, fullFile: true, softWrap: false);
    final double synced = pitch();
    await tester.tap(find.text('unified'));
    await tester.pump();
    expect(synced, pitch());
  });

  // A new SyncSlotHeights forgets every measured height, so the pane keeps
  // one for as long as its inputs stay the same.
  testWidgets('a pane rebuild with the same diffs keeps the slot heights', (
    WidgetTester tester,
  ) async {
    await _pump(tester, fullFile: true, softWrap: false);
    ScopedDiffSync? syncOf() =>
        tester.widget<ScopedDiffView>(find.byType(ScopedDiffView).first).sync;
    final ScopedDiffSync? before = syncOf();
    expect(before, isNotNull);
    // Back and forth through `unified` rebuilds the pane twice.
    await tester.tap(find.text('unified'));
    await tester.pump();
    await tester.tap(find.text('2 file'));
    await tester.pump();
    expect(identical(syncOf()!.heights, before!.heights), isTrue);
  });

  testWidgets('unified draws no spacer', (WidgetTester tester) async {
    await _pump(tester, fullFile: true, softWrap: false);
    await tester.tap(find.text('unified'));
    await tester.pump();
    expect(find.byType(SyncSlotSpacer), findsNothing);
  });

  testWidgets('a pane with one side empty still pads that side', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpGbmWidget(
      tester,
      child: WorkingCopyDiffPane(
        softWrap: false,
        displayPath: 'lib/a.dart',
        unstagedFile: replacementsDiff(40, _unstagedEdits, context: 3),
        stagedFile: null,
        unstagedLoading: false,
        stagedLoading: false,
        onStageScope: (_, _, _) {},
        onDiscardScope: (_, _) {},
        onTemporaryScopeChanged: (_) {},
      ),
    );
    await tester.tap(find.text('2 file'));
    for (int i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    _expectAligned(tester);
  });
}
