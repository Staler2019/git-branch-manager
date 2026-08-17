import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/conflict_resolution/original_operation_message_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

void main() {
  group('splitOriginalOperationMessage', () {
    test('splits summary and body across the blank separator line', () {
      final result = splitOriginalOperationMessage(
        'Fix lane overflow\n\nBody line 1\nBody line 2',
      );
      expect(result.summary, 'Fix lane overflow');
      expect(result.description, 'Body line 1\nBody line 2');
    });

    test('treats the whole remainder as body when no blank separator', () {
      final result = splitOriginalOperationMessage('Subject\nBody line');
      expect(result.summary, 'Subject');
      expect(result.description, 'Body line');
    });

    test('returns empty description for a summary-only message', () {
      final result = splitOriginalOperationMessage('Just a summary');
      expect(result.summary, 'Just a summary');
      expect(result.description, '');
    });

    test('returns empty summary and description for an empty message', () {
      final result = splitOriginalOperationMessage('');
      expect(result.summary, '');
      expect(result.description, '');
    });
  });

  group('promptOriginalOperationMessage', () {
    testWidgets('pre-fills summary/description and disables submit when '
        'summary is cleared', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await promptOriginalOperationMessage(
                  context,
                  title: 'Cherry-pick message',
                  initialMessage:
                      'Fix overflow\n\nBody text\n# Conflicts:\n#\tf.txt',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Cherry-pick message'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Summary'), findsOneWidget);
      expect(find.text('Fix overflow'), findsOneWidget);

      final TextButton continueButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Continue'),
      );
      expect(continueButton.onPressed, isNotNull);

      await tester.enterText(find.widgetWithText(TextField, 'Summary'), '');
      await tester.pump();

      final TextButton disabledButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Continue'),
      );
      expect(disabledButton.onPressed, isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
