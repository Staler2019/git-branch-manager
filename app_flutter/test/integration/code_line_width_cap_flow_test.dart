// Slice W: `AppPreferences.maxCodeLineChars` reaches every code view, and a
// line past it ends in an ellipsis inside the clip width
// (code-line-width-cap-spec.html, ruled 「c, ok」). Each test flips the
// preference while the view is on screen
// ([FLU-listen-misses-the-current-value]): a surface that read it once per
// mount would pass a seeded test.
//
// Blame and conflict resolve need a session and a router; their cases are in
// blame_panel_wrap_test.dart and conflict_resolve_window_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/features/diff/diff_page.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/side_by_side_diff_view.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/features/diff/widgets/side_by_side_cell.dart';
import 'package:gbm_flutter/features/panels/panel_diff_text.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';
import 'package:gbm_flutter/widgets/code_line_metrics.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

import '../support/pump_app.dart';

const String _long =
    'final result = compute(alpha, beta, gamma, delta, epsilon, zeta, eta);';
const String _short = 'ok();';
const int _cap = 10;

DiffFile _file({String added = _long}) => DiffFile(
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
  removedLines: 1,
  displayPath: 'lib/a.dart',
  hunks: <DiffHunk>[
    DiffHunk(
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 1,
      heading: '',
      lines: <DiffLine>[
        const DiffLine(
          kind: DiffLineKind.removed,
          oldLine: 1,
          newLine: 0,
          text: _short,
        ),
        DiffLine(kind: DiffLineKind.added, oldLine: 0, newLine: 1, text: added),
      ],
    ),
  ],
);

RenderParagraph _paragraphOf(WidgetTester tester, String text) => tester
    .renderObjectList<RenderParagraph>(find.byType(RichText))
    .singleWhere((RenderParagraph p) => p.text.toPlainText() == text);

/// The line is cut: it ends in an ellipsis and paints no wider than [clip].
void _expectCut(WidgetTester tester, String text, double clip) {
  final RenderParagraph p = _paragraphOf(tester, text);
  expect(p.didExceedMaxLines, isTrue, reason: '"$text" should be cut');
  expect(p.size.width, lessThanOrEqualTo(clip + 0.01));
}

void _expectWhole(WidgetTester tester, String text) {
  expect(_paragraphOf(tester, text).didExceedMaxLines, isFalse);
}

Future<void> _setCap(ProviderContainer c, WidgetTester tester, int n) async {
  await c
      .read(appPreferencesProvider.notifier)
      .update((AppPreferences p) => p.copyWith(maxCodeLineChars: n));
  await tester.pump();
}

double _clipFor(TextStyle style, int n) =>
    n * CjkCharWidthMemo().widthOf(style);

void main() {
  testWidgets('panel diff text', (WidgetTester tester) async {
    final ProviderContainer c = await pumpGbmWidget(
      tester,
      child: const SizedBox(
        width: 1200,
        height: 200,
        child: PanelDiffText(text: '@@ -1 +1 @@\n-$_short\n+$_long'),
      ),
    );
    _expectWhole(tester, '+$_long');

    await _setCap(c, tester, _cap);
    _expectCut(tester, '+$_long', _clipFor(kPanelDiffTextStyle, _cap));
    _expectWhole(tester, '-$_short');

    await _setCap(c, tester, 200);
    _expectWhole(tester, '+$_long');
  });

  testWidgets('history diff page', (WidgetTester tester) async {
    final ProviderContainer c = await pumpGbmWidget(
      tester,
      child: SizedBox(
        width: 1200,
        height: 300,
        child: DiffPage(
          diff: ParsedDiff(
            files: <DiffFile>[_file()],
            truncated: false,
            inputBytes: 0,
          ),
        ),
      ),
    );
    _expectWhole(tester, _long);
    await _setCap(c, tester, _cap);
    _expectCut(tester, _long, _clipFor(kDiffCodeTextStyle, _cap));
    _expectWhole(tester, _short);
  });

  testWidgets('side by side caps each column at its own edge', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await pumpGbmWidget(
      tester,
      child: SizedBox(
        width: 300,
        height: 300,
        child: SideBySideDiffView(
          diff: ParsedDiff(
            files: <DiffFile>[_file()],
            truncated: false,
            inputBytes: 0,
          ),
        ),
      ),
    );
    await _setCap(c, tester, _cap);
    final double clip = _clipFor(kSideBySideCodeTextStyle, _cap);
    final GbmCodeHScroll scroller = tester.widget(find.byType(GbmCodeHScroll));
    expect(
      scroller.contentWidth,
      closeTo(2 * (sideBySideColumnWidth(0) + clip) + 1, 0.01),
    );
    // The long line is on the right (added); the left holds the short one.
    _expectCut(tester, _long, clip);

    // Scrolled all the way, the right column's cut line stays inside the
    // right half, and nothing of it reaches the left half.
    final ScrollPosition h = tester
        .state<ScrollableState>(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Scrollable && w.axisDirection == AxisDirection.right,
          ),
        )
        .position;
    h.jumpTo(h.maxScrollExtent);
    await tester.pump();
    final Rect left = tester.getRect(find.byType(SideBySideCell).first);
    final Rect line = tester.getRect(
      find.byWidgetPredicate(
        (Widget w) => w is RichText && w.text.toPlainText() == _long,
      ),
    );
    expect(line.left, greaterThanOrEqualTo(left.right - 0.01));
  });

  group('working copy pane', () {
    Future<void> pumpPane(WidgetTester tester, {required double width}) =>
        pumpGbmWidget(
          tester,
          child: SizedBox(
            width: width,
            height: 400,
            child: WorkingCopyDiffPane(
              softWrap: false,
              maxCodeLineChars: _cap,
              displayPath: 'lib/a.dart',
              unstagedFile: _file(),
              stagedFile: null,
              unstagedLoading: false,
              stagedLoading: false,
              onStageScope: (_, _, _) {},
              onDiscardScope: (_, _) {},
              onTemporaryScopeChanged: (_) {},
            ),
          ),
        );

    testWidgets('a card row is cut, and the view reads one capped width', (
      WidgetTester tester,
    ) async {
      await pumpPane(tester, width: 800);
      final double clip = _clipFor(kDiffCodeTextStyle, _cap);
      _expectCut(tester, _long, clip);
      _expectWhole(tester, _short);
      // WB4/WC2: the scroller and the view (whose pinned one-shot head reads
      // `contentWidth`) hold the same capped width.
      for (final Element e in find.byType(ScopedDiffView).evaluate()) {
        final ScopedDiffView v = e.widget as ScopedDiffView;
        final GbmCodeHScroll s = tester.widget(
          find.descendant(
            of: find.byWidget(v),
            matching: find.byType(GbmCodeHScroll),
          ),
        );
        expect(s.contentWidth, v.contentWidth);
        if (v.sources.any((ScopedDiffSource s) => s.file != null)) {
          expect(
            v.contentWidth,
            closeTo(kDiffGutterWidth + kDiffLinePaddingX + clip, 0.01),
          );
          expect(v.codeClipWidth, closeTo(clip, 0.01));
        }
      }
    });

    testWidgets('2 file cuts each side at the cap', (
      WidgetTester tester,
    ) async {
      await pumpPane(tester, width: 800);
      await tester.tap(find.text('2 file'));
      await tester.pump();
      expect(find.byType(ScopedDiffView), findsNWidgets(2));
      final double clip = _clipFor(kDiffCodeTextStyle, _cap);
      _expectCut(tester, _long, clip);
      for (final Element e in find.byType(ScopedDiffView).evaluate()) {
        final ScopedDiffView v = e.widget as ScopedDiffView;
        if (v.sources.any((ScopedDiffSource s) => s.file != null)) {
          expect(v.codeClipWidth, closeTo(clip, 0.01));
        }
      }
    });

    testWidgets('the cut holds when the view is wider than the cap', (
      WidgetTester tester,
    ) async {
      // WB1: no scroller is built here, and the line still stops at the
      // cap rather than at the view's edge.
      await pumpPane(tester, width: 2400);
      expect(find.byType(SingleChildScrollView), findsNothing);
      _expectCut(tester, _long, _clipFor(kDiffCodeTextStyle, _cap));
    });
  });
}
