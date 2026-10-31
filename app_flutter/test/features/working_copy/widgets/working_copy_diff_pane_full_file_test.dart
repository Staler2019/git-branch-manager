// The pane turns the full-context diffs it is handed into fill rows between
// the -U3 cards -- in both modes, only while the full-file view is on, and
// only when the full diff can be trusted and is small enough to draw.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import 'package:gbm_flutter/widgets/gbm_icon_button.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool fullFile,
    int total = 40,
    Set<int> fullEdits = const <int>{5, 30},
    Set<int> long = const <int>{},
    VoidCallback? onToggleFullFile,
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
      onToggleFullFile: onToggleFullFile ?? () {},
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

  // 「自動暫停這個檔案的全檔檢視，但不影響全局設定」: the pause is this file's,
  // so the next file under the cap is filled again by the same pane, the
  // preference untouched in between.
  testWidgets('the pause ends with the file: a smaller one is filled again', (
    WidgetTester tester,
  ) async {
    int toggles = 0;
    await pump(
      tester,
      fullFile: true,
      total: kFullFileViewMaxLines + 1,
      onToggleFullFile: () => toggles++,
    );
    expect(filled(), findsNothing);
    await pump(tester, fullFile: true, onToggleFullFile: () => toggles++);
    expect(filled(), findsOneWidget);
    expect(toggles, 0);
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

  group('the titlebar button', () {
    Finder button() => find.byWidgetPredicate(
      (Widget w) =>
          w is GbmIconButton &&
          w.icon is Icon &&
          (w.icon as Icon).icon == Icons.expand,
    );
    GbmIconButton widgetOf(WidgetTester tester) =>
        tester.widget<GbmIconButton>(button());

    testWidgets('is `Full file`, pressed while the view is on', (
      WidgetTester tester,
    ) async {
      await pump(tester, fullFile: true);
      expect(widgetOf(tester).tooltip, 'Full file');
      expect(widgetOf(tester).active, isTrue);
    });

    testWidgets('is not pressed while the view is off', (
      WidgetTester tester,
    ) async {
      await pump(tester, fullFile: false);
      expect(widgetOf(tester).active, isFalse);
    });

    testWidgets('a press toggles the view, once', (WidgetTester tester) async {
      int toggles = 0;
      await pump(tester, fullFile: false, onToggleFullFile: () => toggles++);
      await tester.tap(button());
      await tester.pump();
      expect(toggles, 1);
    });

    // Disabled, not hidden: 隱藏會讓人以為功能不存在 ([FLU-menu-enabled-is-
    // visual-only]); and not pressed, since this file is in excerpt mode.
    testWidgets('over the line cap it is disabled and says why', (
      WidgetTester tester,
    ) async {
      int toggles = 0;
      await pump(
        tester,
        fullFile: true,
        total: kFullFileViewMaxLines + 1,
        onToggleFullFile: () => toggles++,
      );
      expect(widgetOf(tester).tooltip, 'File too large for full view');
      expect(widgetOf(tester).onPressed, isNull);
      expect(widgetOf(tester).active, isFalse);
      await tester.tap(button(), warnIfMissed: false);
      expect(toggles, 0);
    });
  });
}
