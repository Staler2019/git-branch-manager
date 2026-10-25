// The full-file view's overview ruler (G1 design `wc-full-file-view-spec.html`
// §04 #3 / #4, 使用者裁定): one mark per card, placed and sized by the card's
// share of the painted rows (a card head counts as one row), in the card's
// direction colour; a press on a mark scrolls to its card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

import '../../support/full_file_diffs.dart';
import '../../support/pump_app.dart';

void main() {
  late ScrollController vertical;
  setUp(() => vertical = ScrollController());
  tearDown(() => vertical.dispose());

  /// [total] lines with [edited] replaced, as the unstaged (or [staged]) side;
  /// filled from its full diff when [full].
  Future<void> pump(
    WidgetTester tester, {
    int total = 40,
    Set<int> edited = const <int>{5, 30},
    bool full = true,
    bool softWrap = false,
    Set<int> long = const <int>{},
    double width = 500,
    bool staged = false,
  }) {
    final DiffFile excerpt = replacementsDiff(
      total,
      edited,
      context: 3,
      long: long,
    );
    final List<DiffFillRow>? fill = full
        ? fullFileFillRows(<DiffFillSource>[
            (
              excerpt: excerpt,
              full: replacementsDiff(
                total,
                edited,
                context: kAllContext,
                long: long,
              ),
              staged: staged,
            ),
          ])
        : null;
    return pumpGbmWidget(
      tester,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 300,
          child: ScopedDiffView(
            softWrap: softWrap,
            verticalController: vertical,
            fill: fill,
            sources: <ScopedDiffSource>[
              ScopedDiffSource(
                title: 'Unstaged',
                file: excerpt,
                staged: staged,
                onStageScope: (_, _) {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Finder ruler() => find.byKey(const ValueKey<String>('diff-overview-ruler'));
  Finder mark(int n) => find.byKey(ValueKey<String>('ruler-mark-$n'));
  Rect view(WidgetTester tester) => tester.getRect(find.byType(ScopedDiffView));

  testWidgets('excerpt mode draws no ruler', (WidgetTester tester) async {
    await pump(tester, full: false);
    expect(ruler(), findsNothing);
  });

  testWidgets('the ruler is 10 wide, 13 in from the right, 17 from the top '
      'and bottom, on a sunken pill track', (WidgetTester tester) async {
    await pump(tester);
    final Rect r = tester.getRect(ruler());
    final Rect v = view(tester);
    // The well's 8 margin + 1 border, then the ruler's own 4 / 8 (§04 #4).
    expect(r.width, 10);
    expect(v.right - r.right, 13);
    expect(r.top - v.top, 17);
    expect(v.bottom - r.bottom, 17);
    final BoxDecoration track =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: ruler(),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    final BuildContext context = tester.element(ruler());
    expect(track.color, context.gbmColors.surfaceSunken);
    expect(track.borderRadius, BorderRadius.circular(999));
  });

  testWidgets('one mark per card, at the card\'s share of the painted rows', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(mark(1), findsOneWidget);
    expect(mark(2), findsOneWidget);
    expect(mark(3), findsNothing);

    // Painted rows, top to bottom: fill 1, gap 2-4, card 1 (head + -L5 +L5),
    // gap 6-8, fill 9-26, gap 27-29, card 2 (head + -L30 +L30), gap 31-33,
    // fill 34-40 -- 42 rows (an edited line is two) plus 2 heads = 44
    // units. Card 1 starts after 4
    // rows and spans 3 units; card 2 starts after 4 + 3 + 3 + 18 + 3 = 31.
    final Rect r = tester.getRect(ruler());
    final Rect m1 = tester.getRect(mark(1));
    final Rect m2 = tester.getRect(mark(2));
    expect(m1.top - r.top, closeTo(r.height * 4 / 44, 0.01));
    expect(m1.height, closeTo(r.height * 3 / 44, 0.01));
    expect(m2.top - r.top, closeTo(r.height * 31 / 44, 0.01));
    // Inset 1 on either side.
    expect(m1.left - r.left, 1);
    expect(r.right - m1.right, 1);
  });

  testWidgets('an unstaged mark is accent, radius 2', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final BoxDecoration d =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: mark(1),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(d.color, tester.element(mark(1)).gbmColors.accent);
    expect(d.borderRadius, BorderRadius.circular(2));
  });

  testWidgets('a staged mark is success', (WidgetTester tester) async {
    await pump(tester, staged: true);
    final BoxDecoration d =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: mark(1),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(d.color, tester.element(mark(1)).gbmColors.success);
  });

  testWidgets('a card too small for its share still gets a 4px mark', (
    WidgetTester tester,
  ) async {
    await pump(tester, total: 4000, edited: const <int>{2000});
    expect(tester.getRect(mark(1)).height, 4);
  });

  testWidgets('the rows leave room for the ruler: 22, not 8, of padding on '
      'the right', (WidgetTester tester) async {
    Future<double> rightGap({required bool full}) async {
      await pump(tester, full: full);
      final Rect row = tester.getRect(find.byType(GbmCodeHScroll));
      final Finder text = find.text('L2', findRichText: true);
      final Element line = tester.element(text);
      final RenderBox box = line.findAncestorRenderObjectOfType<RenderBox>()!;
      expect(box.hasSize, isTrue);
      final Rect lineRect = tester.getRect(
        find.ancestor(of: text, matching: find.byType(Row)).first,
      );
      return row.right - lineRect.right;
    }

    final double excerpt = await rightGap(full: false);
    final double full = await rightGap(full: true);
    expect(full - excerpt, 14);
  });

  testWidgets('a press on a mark scrolls its card on screen, even one the '
      'list has never built', (WidgetTester tester) async {
    await pump(tester, total: 3000, edited: const <int>{5, 2900});
    expect(find.text('edited L2900', findRichText: true), findsNothing);

    await tester.tap(mark(2));
    for (int i = 0; i < 8; i++) {
      await tester.pump();
    }
    final Finder card = find.byKey(const ValueKey<String>('scope-card-2'));
    expect(card, findsOneWidget);
    final Rect c = tester.getRect(card);
    final Rect v = view(tester);
    expect(c.top - v.top, closeTo(0, 0.5), reason: 'scrolled to its top');
  });

  Future<void> jumpTo(WidgetTester tester, int n) async {
    await tester.tap(mark(n));
    for (int i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  void expectCardAtTop(WidgetTester tester, int n) {
    final Finder card = find.byKey(ValueKey<String>('scope-card-$n'));
    expect(card, findsOneWidget);
    expect(
      tester.getRect(card).top - view(tester).top,
      closeTo(0, 0.5),
      reason: 'scrolled to its top',
    );
  }

  // Every other line is 300+ characters, so wrapped it is many lines tall:
  // an estimate that counts each row as one line is short by most of the
  // file, further than a few measured passes can make up.
  testWidgets('with soft wrap on, a wrapped file still jumps to its card', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      total: 3000,
      edited: const <int>{5, 2900},
      softWrap: true,
      long: <int>{for (int i = 1; i <= 3000; i += 2) i},
    );
    await jumpTo(tester, 2);
    expectCardAtTop(tester, 2);
  });

  // In a narrow view each card's head wraps, so every card is taller than
  // its estimate; over 150 cards the estimate of the last one is off by far
  // more than the 300px view. Only a jump measured from what is on screen
  // gets there.
  testWidgets('a jump corrects an estimate that drifts across many cards', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      total: 3000,
      edited: <int>{for (int i = 10; i <= 3000; i += 20) i},
      width: 220,
    );
    await jumpTo(tester, 150);
    expectCardAtTop(tester, 150);
  });
}
