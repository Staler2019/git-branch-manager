import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/working_copy/widgets/commit_message_box.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../../support/pump_app.dart';

void main() {
  group('CommitMessageBox', () {
    testWidgets('renders summary and description fields', (tester) async {
      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: TextEditingController(),
          descriptionController: TextEditingController(),
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
      );

      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('no char-count warning is shown at 49 chars', (tester) async {
      final summaryController = TextEditingController();
      summaryController.text = 'a' * 49;

      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: summaryController,
          descriptionController: TextEditingController(),
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
      );

      await tester.pump();

      final charCountText = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data?.contains('chars') == true,
      );
      expect(
        charCountText,
        findsNothing,
        reason: 'overLimit is only true above 50 chars, not at 49',
      );
    });

    testWidgets('summary text color changes at 50 chars boundary', (
      tester,
    ) async {
      final summaryController = TextEditingController();
      // Set to exactly 50 chars - at boundary
      summaryController.text = 'a' * 50;

      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: summaryController,
          descriptionController: TextEditingController(),
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
        variant: GbmThemeVariant.darkTechnical,
      );

      await tester.pump();

      // At exactly 50 chars, the warning should NOT be shown (overLimit checks > 50)
      var charCountText = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data?.contains('chars') == true,
      );
      expect(charCountText, findsNothing);

      // Now test with 51 chars - should show warning
      summaryController.text = 'a' * 51;
      await tester.pump();

      charCountText = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data?.contains('chars') == true,
      );
      expect(charCountText, findsOneWidget);
    });

    testWidgets('warning text reports the exact character count', (
      tester,
    ) async {
      final summaryController = TextEditingController();
      summaryController.text = 'a' * 51;

      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: summaryController,
          descriptionController: TextEditingController(),
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
      );

      await tester.pump();

      expect(find.text('51 chars'), findsOneWidget);
    });

    testWidgets('pressing Tab in summary moves focus to description', (
      tester,
    ) async {
      final summaryController = TextEditingController();
      final descriptionController = TextEditingController();

      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: summaryController,
          descriptionController: descriptionController,
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
      );

      // Tap the summary field to focus it.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      final TextField summaryField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(
        summaryField.focusNode?.hasFocus,
        true,
        reason: 'summary field should be focused after tapping it',
      );

      // Simulate pressing Tab by sending the key event through the test harness.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      final TextField descriptionField = tester.widget<TextField>(
        find.byType(TextField).last,
      );
      expect(
        descriptionField.focusNode?.hasFocus,
        true,
        reason: 'Tab should move focus from summary to description',
      );
      expect(
        summaryField.focusNode?.hasFocus,
        false,
        reason: 'focus should have moved away from summary',
      );
    });

    testWidgets('description field uses monospace font', (tester) async {
      final descriptionController = TextEditingController();

      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: TextEditingController(),
          descriptionController: descriptionController,
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
      );

      await tester.pump();

      final TextField descriptionField = tester.widget<TextField>(
        find.byType(TextField).last,
      );
      expect(descriptionField.style?.fontFamily, GbmTypography.fontMono);
    });

    testWidgets('description field shows 72-char ruler', (tester) async {
      final descriptionController = TextEditingController();

      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: TextEditingController(),
          descriptionController: descriptionController,
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
      );

      await tester.pump();

      // The "72" ruler label is the most distinguishing marker of the ruler
      // overlay -- the ruler line itself is a bare Container that isn't
      // reliably distinguishable from other Containers in the tree.
      expect(find.text('72'), findsOneWidget);
    });

    testWidgets('onSummaryChanged callback is called on summary input', (
      tester,
    ) async {
      final summaryController = TextEditingController();
      String? lastSummary;

      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: summaryController,
          descriptionController: TextEditingController(),
          onSummaryChanged: (text) => lastSummary = text,
          onDescriptionChanged: (_) {},
        ),
      );

      // Type in summary field
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      summaryController.text = 'test commit';
      await tester.pump();

      // Verify callback was invoked with the text
      expect(summaryController.text, contains('test commit'));
      expect(lastSummary, 'test commit');
    });

    testWidgets(
      'onDescriptionChanged callback is called on description input',
      (tester) async {
        final descriptionController = TextEditingController();
        String? lastDescription;

        await pumpGbmWidget(
          tester,
          child: CommitMessageBox(
            summaryController: TextEditingController(),
            descriptionController: descriptionController,
            onSummaryChanged: (_) {},
            onDescriptionChanged: (text) => lastDescription = text,
          ),
        );

        // Type in description field
        await tester.tap(find.byType(TextField).last);
        await tester.pump();
        descriptionController.text = 'description text';
        await tester.pump();

        // Verify callback was invoked
        expect(descriptionController.text, contains('description text'));
        expect(lastDescription, 'description text');
      },
    );

    testWidgets('summary field shows 50-char warning text', (tester) async {
      final summaryController = TextEditingController();
      summaryController.text = 'a' * 60;

      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: summaryController,
          descriptionController: TextEditingController(),
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
      );

      await tester.pump();

      expect(find.text('60 chars'), findsOneWidget);
    });

    testWidgets('empty summary and description work correctly', (tester) async {
      await pumpGbmWidget(
        tester,
        child: CommitMessageBox(
          summaryController: TextEditingController(),
          descriptionController: TextEditingController(),
          onSummaryChanged: (_) {},
          onDescriptionChanged: (_) {},
        ),
      );

      await tester.pump();

      expect(find.byType(CommitMessageBox), findsOneWidget);
    });
  });

  // Ruling ⑫ (prepared-commit-message-spec.html 02-D): the box is a kit
  // `.gbm-input` -- the app's own helpers, not Material's bare outline.
  group('CommitMessageBox kit styling', () {
    Future<GbmColors> pump(WidgetTester tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 200,
          child: CommitMessageBox(
            summaryController: TextEditingController(),
            descriptionController: TextEditingController(),
            onSummaryChanged: (_) {},
            onDescriptionChanged: (_) {},
          ),
        ),
      );
      return tester.element(find.byType(CommitMessageBox)).gbmColors;
    }

    TextField field(WidgetTester tester, int i) =>
        tester.widget<TextField>(find.byType(TextField).at(i));

    void expectKitBox(InputDecoration d, GbmColors colors) {
      final OutlineInputBorder resting = d.enabledBorder! as OutlineInputBorder;
      final OutlineInputBorder focused = d.focusedBorder! as OutlineInputBorder;
      expect(resting.borderRadius, BorderRadius.circular(GbmSpacing.radiusMd));
      expect(
        resting.borderSide.color.toARGB32(),
        colors.borderDefault.toARGB32(),
      );
      expect(focused.borderSide.color.toARGB32(), colors.accent.toARGB32());
      expect(d.filled, isTrue);
      expect(d.fillColor!.toARGB32(), colors.surfacePanel.toARGB32());
    }

    testWidgets('the summary is a 30px text-sm kit input', (tester) async {
      final GbmColors colors = await pump(tester);

      expectKitBox(field(tester, 0).decoration!, colors);
      expect(field(tester, 0).style?.fontSize, GbmTypography.textSm);
      expect(
        tester.getSize(find.byType(TextField).at(0)).height,
        GbmSpacing.inputHeight,
      );
    });

    testWidgets('the description is a kit multiline input', (tester) async {
      final GbmColors colors = await pump(tester);

      expectKitBox(field(tester, 1).decoration!, colors);
    });

    // The ruler sits 72 monospace columns in from the text's left edge,
    // which moved with the new content padding.
    testWidgets('the 72 ruler follows the space3 content padding', (
      tester,
    ) async {
      await pump(tester);

      final Positioned ruler = tester.widget<Positioned>(
        find.byWidgetPredicate(
          (Widget w) => w is Positioned && w.left != null && w.left! > 0,
        ),
      );
      expect(ruler.left, GbmSpacing.space3 + 72 * 8.0);
    });
  });
}
