import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

void main() {
  group('DiffLineView', () {
    late String? clipboardText;

    setUp(() {
      clipboardText = null;
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall methodCall,
          ) async {
            if (methodCall.method == 'Clipboard.setData') {
              clipboardText =
                  (methodCall.arguments as Map<Object?, Object?>)['text']
                      as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets(
      'shows Stage line and Stage hunk when unstaged with callbacks',
      (tester) async {
        final line = DiffLine(
          kind: DiffLineKind.added,
          oldLine: 0,
          newLine: 42,
          text: 'added line',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: DiffLineView(
                line: line,
                staged: false,
                onStageLine: () {},
                onStageHunk: () {},
              ),
            ),
          ),
        );

        await tester.tap(
          find.byType(DiffLineView),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Stage line'), findsOneWidget);
        expect(find.text('Stage hunk'), findsOneWidget);
        expect(find.text('Copy line'), findsOneWidget);
      },
    );

    testWidgets(
      'shows Unstage line and Unstage hunk when staged with callbacks',
      (tester) async {
        final line = DiffLine(
          kind: DiffLineKind.removed,
          oldLine: 42,
          newLine: 0,
          text: 'removed line',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: DiffLineView(
                line: line,
                staged: true,
                onStageLine: () {},
                onStageHunk: () {},
              ),
            ),
          ),
        );

        await tester.tap(
          find.byType(DiffLineView),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Unstage line'), findsOneWidget);
        expect(find.text('Unstage hunk'), findsOneWidget);
        expect(find.text('Copy line'), findsOneWidget);
      },
    );

    testWidgets('hides line stage/unstage for context lines', (tester) async {
      final line = DiffLine(
        kind: DiffLineKind.context,
        oldLine: 42,
        newLine: 42,
        text: 'context line',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: DiffLineView(
              line: line,
              staged: false,
              onStageLine: () {},
              onStageHunk: () {},
            ),
          ),
        ),
      );

      await tester.tap(
        find.byType(DiffLineView),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Stage line'), findsNothing);
      expect(find.text('Unstage line'), findsNothing);
      expect(find.text('Stage hunk'), findsOneWidget);
      expect(find.text('Copy line'), findsOneWidget);
    });

    testWidgets('shows only Copy line when no callbacks provided', (
      tester,
    ) async {
      final line = DiffLine(
        kind: DiffLineKind.added,
        oldLine: 0,
        newLine: 42,
        text: 'added line',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: DiffLineView(line: line, staged: false)),
        ),
      );

      await tester.tap(
        find.byType(DiffLineView),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Copy line'), findsOneWidget);
      expect(find.text('Stage line'), findsNothing);
      expect(find.text('Stage hunk'), findsNothing);
    });

    testWidgets('Copy line puts line text on clipboard', (tester) async {
      final line = DiffLine(
        kind: DiffLineKind.added,
        oldLine: 0,
        newLine: 42,
        text: 'my added line',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: DiffLineView(line: line, staged: false)),
        ),
      );

      await tester.tap(
        find.byType(DiffLineView),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy line'));
      await tester.pumpAndSettle();

      expect(clipboardText, equals('my added line'));
    });

    testWidgets('tapping Stage line calls onStageLine', (tester) async {
      final line = DiffLine(
        kind: DiffLineKind.added,
        oldLine: 0,
        newLine: 42,
        text: 'added line',
      );

      bool stageCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: DiffLineView(
              line: line,
              staged: false,
              onStageLine: () => stageCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(
        find.byType(DiffLineView),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stage line'));
      await tester.pumpAndSettle();

      expect(stageCalled, isTrue);
    });

    testWidgets('tapping Stage hunk calls onStageHunk', (tester) async {
      final line = DiffLine(
        kind: DiffLineKind.added,
        oldLine: 0,
        newLine: 42,
        text: 'added line',
      );

      bool stageHunkCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: DiffLineView(
              line: line,
              staged: false,
              onStageHunk: () => stageHunkCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(
        find.byType(DiffLineView),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stage hunk'));
      await tester.pumpAndSettle();

      expect(stageHunkCalled, isTrue);
    });

    testWidgets(
      'hides line stage/unstage when onStageLine is null but onStageHunk is set',
      (tester) async {
        final line = DiffLine(
          kind: DiffLineKind.added,
          oldLine: 0,
          newLine: 42,
          text: 'added line',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: DiffLineView(line: line, staged: false, onStageHunk: () {}),
            ),
          ),
        );

        await tester.tap(
          find.byType(DiffLineView),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Stage line'), findsNothing);
        expect(find.text('Stage hunk'), findsOneWidget);
        expect(find.text('Copy line'), findsOneWidget);
      },
    );
  });
}
