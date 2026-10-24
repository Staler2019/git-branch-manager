// The pane turns the full-context diffs it is handed into fill rows between
// the -U3 cards -- in both modes, only while the full-file view is on, and
// only when the full diff can be trusted and is small enough to draw.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool fullFile,
    int total = 40,
    Set<int> fullEdits = const <int>{5, 30},
    Set<int> long = const <int>{},
  }) => pumpGbmWidget(
    tester,
    child: WorkingCopyDiffPane(
      softWrap: false,
      displayPath: 'lib/a.dart',
      unstagedFile: replacementsDiff(total, const <int>{5, 30}, context: 3),
      stagedFile: null,
      unstagedFullFile: replacementsDiff(
        total,
        fullEdits,
        context: kAllContext,
        long: long,
      ),
      stagedFullFile: null,
      fullFile: fullFile,
      unstagedLoading: false,
      stagedLoading: false,
      onStageScope: (_, _, _) {},
      onDiscardScope: (_, _) {},
      onTemporaryScopeChanged: (_) {},
    ),
  );

  // Line 15 sits between the two cards' -U3 windows (2-8, 27-33): only a
  // fill row draws it.
  Finder filled() => find.text('L15', findRichText: true);

  testWidgets('on, unified: the lines between the cards are drawn', (
    WidgetTester tester,
  ) async {
    await pump(tester, fullFile: true);
    expect(filled(), findsOneWidget);
  });

  testWidgets('on, 2 file: the lines between the cards are drawn', (
    WidgetTester tester,
  ) async {
    await pump(tester, fullFile: true);
    await tester.tap(find.text('2 file'));
    await tester.pump();
    expect(filled(), findsOneWidget);
  });

  testWidgets('off: excerpt mode, whatever full diff it holds', (
    WidgetTester tester,
  ) async {
    await pump(tester, fullFile: false);
    expect(filled(), findsNothing);
    expect(find.text('L5', findRichText: true), findsOneWidget);
  });

  testWidgets('a full diff that disagrees with the -U3 one fills nothing', (
    WidgetTester tester,
  ) async {
    await pump(tester, fullFile: true, fullEdits: const <int>{5, 31});
    expect(filled(), findsNothing);
  });

  testWidgets('a file over the line cap stays in excerpt mode', (
    WidgetTester tester,
  ) async {
    await pump(tester, fullFile: true, total: kFullFileViewMaxLines + 1);
    expect(filled(), findsNothing);
  });

  testWidgets('a file at the line cap is filled', (WidgetTester tester) async {
    await pump(tester, fullFile: true, total: kFullFileViewMaxLines);
    expect(filled(), findsOneWidget);
  });

  // Line 15 is the file's longest, and only a fill row draws it: measured
  // from the -U3 diff alone, the content width stops short and clips it.
  testWidgets('the content is as wide as its widest fill row', (
    WidgetTester tester,
  ) async {
    await pump(tester, fullFile: true, long: const <int>{15});
    final ScrollableState sideways = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      ),
    );
    expect(sideways.position.maxScrollExtent, greaterThan(1000));
  });
}
