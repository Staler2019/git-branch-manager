// The pane that carries spec P03 變體 B's titlebar and its `2 file` /
// `unified` switch. What this file is really for is the payoff of holding
// both replies at once: before `workingCopyDiffs` replaced the single
// `lastDiff` slot, one of these two panes could not have had content.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';
import 'package:gbm_flutter/widgets/split_pane.dart';

import '../../../support/pump_app.dart';

DiffFile _file(String text, {required bool added}) => DiffFile(
  oldPath: 'lib/a.dart',
  newPath: 'lib/a.dart',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: 1,
  removedLines: 0,
  displayPath: 'lib/a.dart',
  hunks: <DiffHunk>[
    DiffHunk(
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 1,
      heading: '',
      lines: <DiffLine>[
        DiffLine(
          kind: added ? DiffLineKind.added : DiffLineKind.removed,
          oldLine: 1,
          newLine: 1,
          text: text,
        ),
      ],
    ),
  ],
);

/// A file whose hunks each hold one added line, placed at a chosen position
/// on the **index** side -- the coordinate the two working-copy diffs share.
///
/// [indexStarts] is where each hunk begins on that side, so a caller can put
/// a staged region *between* two unstaged ones and see whether the merged
/// list really ordered by region or merely concatenated the two sides.
DiffFile _fileAt(
  List<({int indexStart, String text})> hunks, {
  required bool staged,
}) => DiffFile(
  oldPath: 'lib/a.dart',
  newPath: 'lib/a.dart',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: hunks.length,
  removedLines: 0,
  displayPath: 'lib/a.dart',
  hunks: <DiffHunk>[
    for (final ({int indexStart, String text}) hunk in hunks)
      DiffHunk(
        // The index side is `old` for the unstaged diff (index -> worktree)
        // and `new` for the staged one (HEAD -> index). The *other* side is
        // deliberately given a number that would produce the opposite order
        // if it were ever read by mistake.
        oldStart: staged ? 1000 - hunk.indexStart : hunk.indexStart,
        oldCount: 1,
        newStart: staged ? hunk.indexStart : 1000 - hunk.indexStart,
        newCount: 1,
        heading: '',
        lines: <DiffLine>[
          // A leading context line, and it is load-bearing rather than
          // scenery. A context line carries *both* numbers, so it is the
          // only kind that can tell "read the index side" apart from "read
          // whichever side happens to be non-zero": with added lines alone
          // the staged side's oldLine is 0 everywhere, indexPositionOf falls
          // back to the hunk's own start, and that fallback already reads
          // the right side -- so the whole loop could be mutated to read the
          // wrong one and this test stayed green
          // ([TEST-fixture-cannot-disagree]).
          DiffLine(
            kind: DiffLineKind.context,
            oldLine: staged ? 1000 - hunk.indexStart : hunk.indexStart,
            newLine: staged ? hunk.indexStart : 1000 - hunk.indexStart,
            text: '${hunk.text}-context',
          ),
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: staged ? 0 : hunk.indexStart + 1,
            newLine: staged ? hunk.indexStart + 1 : 0,
            text: hunk.text,
          ),
        ],
      ),
  ],
);

void main() {
  group('WorkingCopyDiffPane', () {
    late List<({bool staged, int hunkIndex, List<int> lines})> stageCalls;

    late List<void Function()?> submitters;

    setUp(() {
      stageCalls = <({bool staged, int hunkIndex, List<int> lines})>[];
      submitters = <void Function()?>[];
    });

    Future<void> pump(
      WidgetTester tester, {
      DiffFile? unstaged,
      DiffFile? staged,
      bool unstagedLoading = false,
      bool stagedLoading = false,
      bool unstagedTruncated = false,
      bool stagedTruncated = false,
      String displayPath = 'lib/a.dart',
    }) async {
      await pumpGbmWidget(
        tester,
        child: WorkingCopyDiffPane(
          softWrap: false,
          displayPath: displayPath,
          unstagedFile: unstaged,
          stagedFile: staged,
          unstagedLoading: unstagedLoading,
          stagedLoading: stagedLoading,
          unstagedTruncated: unstagedTruncated,
          stagedTruncated: stagedTruncated,
          onStageScope: (bool s, int h, List<int> l) =>
              stageCalls.add((staged: s, hunkIndex: h, lines: l)),
          onDiscardScope: (_, _) {},
          onTemporaryScopeChanged: (void Function()? submit) =>
              submitters.add(submit),
        ),
      );
    }

    testWidgets(
      'a side refused for its size says so, and only that side does',
      (WidgetTester tester) async {
        // Both sides drawn at once is the whole point of this pane, so the
        // refusal has to be per side. Pinned here rather than only in
        // ScopedDiffView's own tests because this is where the Working Copy's
        // wording lives -- and "Nothing unstaged" over a file that has changes
        // is the exact sentence this round exists to remove.
        await pump(
          tester,
          unstaged: null,
          unstagedTruncated: true,
          staged: _file('already staged', added: true),
        );

        expect(find.text('Diff too large to display'), findsOneWidget);
        expect(find.text('Nothing unstaged'), findsNothing);
        // The other side is untouched: it still draws its own diff.
        expect(find.text('already staged'), findsOneWidget);
      },
    );

    // 「右側 pane 再切成左右兩欄，等於把使用者抱怨的『左右擠』原封不動搬
    // 過去」-- the round that moved this pane to the right-hand half of the
    // window also made `unified` its default. `2 file` is untouched and one
    // click away; only the initial value moved.
    // **Corrected in place.** This used to be titled 「one column」 and its
    // comment said the `left` equality is 「what tells this apart from
    // `2 file`」. Still true, and no longer the interesting half: `unified`
    // is one merged list now, so *both* sides were always going to share a
    // left edge. What it really pins is the **tie-break** -- this fixture's
    // two hunks both start at index line 1, so region ordering cannot
    // separate them and the unstaged side comes first by rule. A fixture
    // whose numbers coincide cannot see ordering at all
    // ([TEST-fixture-cannot-disagree]); the test below it supplies one that
    // can.
    testWidgets('unified opens by default, unstaged first at equal index', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      final Rect unstaged = tester.getRect(find.text('still editing'));
      final Rect staged = tester.getRect(find.text('already staged'));

      // One column, unstaged above staged. The `left` equality is what
      // tells this apart from `2 file`, where the two sit at different x
      // and the same y -- "above" alone would be satisfied by rounding.
      expect(unstaged.left, equals(staged.left));
      expect(unstaged.bottom, lessThanOrEqualTo(staged.top));
    });

    testWidgets('2 file mode shows both sides of the same file at once', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );
      // `unified` is the default now, so this test has to ask for the mode
      // it is about instead of inheriting it. Both of these used to pump and
      // assert without touching the switch, which pinned `twoFile` as the
      // default without ever saying so -- and that implicit pin going red is
      // exactly what proves the default moved.
      await tester.tap(find.text('2 file'));
      await tester.pump();

      // Distinct text on each side: identical content would let the two
      // panes be swapped, or one of them be drawn twice, and still pass.
      expect(find.text('still editing'), findsOneWidget);
      expect(find.text('already staged'), findsOneWidget);
      expect(find.text('Unstaged'), findsOneWidget);
      expect(find.text('Staged'), findsOneWidget);
    });

    testWidgets('the left side is the unstaged one', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );
      // See the note above: `2 file` is no longer the default, and the dx
      // comparison below is only a meaningful pin once the mode is on.
      await tester.tap(find.text('2 file'));
      await tester.pump();

      expect(
        tester.getCenter(find.text('still editing')).dx,
        lessThan(tester.getCenter(find.text('already staged')).dx),
      );
    });

    testWidgets('a press on the staged side unstages, on the unstaged side '
        'stages', (WidgetTester tester) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      await tester.tap(find.text('Stage 1 line'));
      await tester.tap(find.text('Unstage 1 line'));

      expect(stageCalls.length, 2);
      expect(stageCalls[0].staged, isFalse);
      expect(stageCalls[1].staged, isTrue);
    });

    // Also corrected: 「stacks the sides」 described two views one above the
    // other, which is the design this round overruled. The assertion below
    // survives it unchanged because the two regions tie at index 1 -- same
    // reason as the test above, and the same reason it is not evidence that
    // the merge works.
    testWidgets('switching back to unified keeps the equal-index order', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      await tester.tap(find.text('unified'));
      await tester.pump();

      expect(find.text('still editing'), findsOneWidget);
      expect(find.text('already staged'), findsOneWidget);
      expect(
        tester.getCenter(find.text('still editing')).dy,
        lessThan(tester.getCenter(find.text('already staged')).dy),
        reason:
            'both regions sit at index 1, so the tie-break puts the '
            'unstaged one first',
      );
    });

    // C18's reuse audit: the two sides were a fixed 50/50 `Row` with a
    // hairline `Container` divider -- a hand-rolled GbmSplitPane. Every
    // other two-pane surface in the app is a real splitter, including
    // `wc.columns` in the board directly above this pane, so this was the
    // one place where a divider the user could see refused to move.
    testWidgets('2 file mode: the divider between the two sides drags', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      // The divider only exists in `2 file` mode, which is no longer the
      // default -- same implicit pin as the two tests above.
      await tester.tap(find.text('2 file'));
      await tester.pump();

      final double before = tester.getCenter(find.text('already staged')).dx;

      await tester.drag(
        find.byKey(const Key('gbm-split-divider-0')),
        const Offset(80, 0),
      );
      // Past kDoubleTapTimeout: the divider carries a double-tap recogniser
      // (double-click resets the split), whose timer is still pending after
      // a drag. pumpAndSettle is avoided on principle here (#101).
      await tester.pump(const Duration(milliseconds: 400));

      // Assert the content moved, not the persisted flex: a stored number
      // no layout reads would satisfy the latter and change nothing on
      // screen.
      expect(
        tester.getCenter(find.text('already staged')).dx,
        greaterThan(before),
        reason:
            'dragging right widens the unstaged side, pushing the '
            'staged side right',
      );
    });

    testWidgets('unified mode has no splitter between the sides', (
      WidgetTester tester,
    ) async {
      // Deliberate, not an oversight: unified is one scrollable holding
      // both sides, so there is no second pane to size.
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      await tester.tap(find.text('unified'));
      await tester.pump();

      expect(find.byType(GbmSplitPane), findsNothing);
    });

    // U1: 「我要對齊的不是行號，是 git 判斷出的區域變更，每個區塊會是一個
    // scope，然後 unstage, stage 必定是不同 scope」. One list, ordered by
    // where each region sits on the index -- the ruler the two diffs share.
    testWidgets('unified draws one merged list, not two stacked views', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      // One view, holding both directions. Two views stacked is exactly what
      // this round overruled, and counting them is the only assertion that
      // can tell the two designs apart -- both draw the same text.
      expect(find.byType(ScopedDiffView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ScopedDiffView),
          matching: find.text('Stage 1 line'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ScopedDiffView),
          matching: find.text('Unstage 1 line'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('unified orders cards by index region, not by side', (
      WidgetTester tester,
    ) async {
      // The discriminating fixture: the staged region sits *between* the two
      // unstaged ones. A fixture whose numbers coincide cannot see the
      // difference -- concatenating the sides and ordering by region give the
      // same answer there ([TEST-fixture-cannot-disagree]).
      await pump(
        tester,
        unstaged: _fileAt(<({int indexStart, String text})>[
          (indexStart: 1, text: 'first-unstaged'),
          (indexStart: 100, text: 'last-unstaged'),
        ], staged: false),
        staged: _fileAt(<({int indexStart, String text})>[
          (indexStart: 50, text: 'middle-staged'),
        ], staged: true),
      );

      final double first = tester.getTopLeft(find.text('first-unstaged')).dy;
      final double middle = tester.getTopLeft(find.text('middle-staged')).dy;
      final double last = tester.getTopLeft(find.text('last-unstaged')).dy;

      expect(
        middle,
        greaterThan(first),
        reason: 'index 50 comes after index 1',
      );
      expect(
        middle,
        lessThan(last),
        reason:
            'index 50 comes before index 100 -- concatenating the sides '
            'would have put the staged card last',
      );
    });

    // U3: the two column heads go, because in a merged list they would be
    // labelling a column that is not there. `2 file` keeps them, because
    // there they are still labelling a column.
    testWidgets('unified drops the column heads and 2 file keeps them', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      expect(
        find.byKey(const ValueKey<String>('column-head-dot')),
        findsNothing,
      );
      // U2: the dot did not disappear, it moved down a level. In a merged
      // list the card is the only thing that can say which direction it acts
      // in before the eye reaches the button at the far end of the row.
      expect(
        find.byKey(const ValueKey<String>('card-head-dot')),
        findsNWidgets(2),
      );

      await tester.tap(find.text('2 file'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('column-head-dot')),
        findsNWidgets(2),
      );
      // And it is a move, not an addition: with the heads back, a dot on
      // every card would be the same fact twice, inches apart.
      expect(find.byKey(const ValueKey<String>('card-head-dot')), findsNothing);
    });

    testWidgets('unified puts the two counts in the title bar instead', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _fileAt(<({int indexStart, String text})>[
          (indexStart: 1, text: 'a'),
          (indexStart: 100, text: 'b'),
        ], staged: false),
        staged: _fileAt(<({int indexStart, String text})>[
          (indexStart: 50, text: 'c'),
        ], staged: true),
      );

      expect(find.text('2 未暫存 · 1 已暫存'), findsOneWidget);

      // And it is the merged list's replacement, not an addition: `2 file`
      // still says it with its two heads, so saying it twice there would be
      // [UX-rubric] dimension D's redundancy.
      await tester.tap(find.text('2 file'));
      await tester.pump();

      expect(find.text('2 未暫存 · 1 已暫存'), findsNothing);
    });

    // U8, and it is the round's only change that crosses into `2 file`:
    // 「u8 影響樣式應該要跟 2 file 模式相同，所以應該要一起動，這是唯一會影響
    // 到 2file 的」. So both modes are asserted, not one -- the whole reason
    // for the change is that the two agree.
    //
    // **The finding was smaller than it was first written up.** 變體 B's
    // `.variant-B-btn-unstage` is `surface-panel-raised` ground,
    // `border-strong` ring, `text-primary` label; `GbmButtonKind.secondary`
    // already supplies the first and the third, and has since the scope cards
    // were written. The one token that differed is the ring, which sat at
    // `border-default`.
    BorderSide? sideOf(WidgetTester tester, String label) {
      final ButtonStyle? style = tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(TextButton),
            ),
          )
          .style;
      return style?.side?.resolve(<WidgetState>{});
    }

    testWidgets('the unstage button rings itself, in both modes', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

      expect(
        sideOf(tester, 'Unstage 1 line')?.color.toARGB32(),
        colors.borderStrong.toARGB32(),
        reason: 'unified: the unstage button carries variant-B-btn-unstage',
      );
      // The stage button is the accent fill, and has no ring at all -- which
      // is what makes the two tell each other apart at a glance, the whole
      // point of the change.
      expect(sideOf(tester, 'Stage 1 line'), isNull);

      await tester.tap(find.text('2 file'));
      await tester.pump();

      expect(
        sideOf(tester, 'Unstage 1 line')?.color.toARGB32(),
        colors.borderStrong.toARGB32(),
        reason:
            '2 file: the same button, so the same ring -- one button drawn '
            'two ways by mode would be a fresh defect, not a fix',
      );
      expect(sideOf(tester, 'Stage 1 line'), isNull);
    });

    testWidgets('a half-staged rename names both of its paths', (
      WidgetTester tester,
    ) async {
      // The work tree still calls it the old name while the index already
      // calls it the new one; naming only one would describe a file the
      // board is not selecting.
      await pump(tester, displayPath: 'old.dart → new.dart');

      expect(find.text('old.dart → new.dart'), findsOneWidget);
    });

    testWidgets('a side still waiting spins while the other one renders', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        stagedLoading: true,
      );

      expect(find.text('still editing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No pumpAndSettle: an indeterminate indicator never settles (#101).
    });
  });
}
