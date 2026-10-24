// Render-site tests for DiffLineView's 05-G context menu. The item list's
// own label/order contract lives in `diff_line_menu_items_test.dart`; what
// this file checks is which of those items DiffLineView asks for given the
// line kind and callbacks it was handed, and that tapping a live one
// dispatches while a disabled one does not.
//
// Since 05-G was brought to spec, the menu no longer *hides* inapplicable
// items -- spec's own list has both `Stage hunk` and `Unstage hunk`, so both
// always render and the one that does not apply is disabled (dimmed, inert).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/code_line_metrics.dart';

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

    Future<void> pumpLine(
      WidgetTester tester, {
      required DiffLine line,
      bool staged = false,
      VoidCallback? onStageLine,
      VoidCallback? onStageHunk,
      VoidCallback? onDiscardLine,
      int selectionCount = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: DiffLineView(
              softWrap: true,
              line: line,
              staged: staged,
              onStageLine: onStageLine,
              onStageHunk: onStageHunk,
              onDiscardLine: onDiscardLine,
              selectionCount: selectionCount,
            ),
          ),
        ),
      );
      await tester.tap(
        find.byType(DiffLineView),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
    }

    DiffLine added({String text = 'added line'}) =>
        DiffLine(kind: DiffLineKind.added, oldLine: 0, newLine: 42, text: text);

    testWidgets('an unstaged added line shows all five spec items', (
      tester,
    ) async {
      await pumpLine(
        tester,
        line: added(),
        onStageLine: () {},
        onStageHunk: () {},
        onDiscardLine: () {},
      );

      for (final String label in <String>[
        'Stage',
        'Stage hunk',
        'Unstage hunk',
        'Copy lines',
        'Discard…',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('a staged line reads Unstage and offers no Discard', (
      tester,
    ) async {
      await pumpLine(
        tester,
        line: DiffLine(
          kind: DiffLineKind.removed,
          oldLine: 42,
          newLine: 0,
          text: 'removed line',
        ),
        staged: true,
        onStageLine: () {},
        onStageHunk: () {},
      );

      expect(find.text('Unstage'), findsOneWidget);
      expect(find.text('Stage'), findsNothing);
      expect(find.text('Unstage hunk'), findsOneWidget);
      expect(find.text('Discard…'), findsNothing);
    });

    testWidgets('a multi-line selection puts the count in both labels', (
      tester,
    ) async {
      await pumpLine(
        tester,
        line: added(),
        onStageLine: () {},
        onStageHunk: () {},
        onDiscardLine: () {},
        selectionCount: 12,
      );

      expect(find.text('Stage 12 lines'), findsOneWidget);
      expect(find.text('Discard 12 lines…'), findsOneWidget);
      expect(
        find.text('Copy lines'),
        findsOneWidget,
        reason: 'spec\'s Copy label is plural regardless of the count',
      );
    });

    testWidgets('a context line still renders Stage, but inert', (
      tester,
    ) async {
      await pumpLine(
        tester,
        line: DiffLine(
          kind: DiffLineKind.context,
          oldLine: 42,
          newLine: 42,
          text: 'context line',
        ),
        onStageLine: () {},
        onStageHunk: () {},
        onDiscardLine: () {},
      );

      // Present (spec keeps the item) but nothing to stage on a context
      // line, so it is disabled rather than omitted -- and, being a context
      // line, there is nothing to discard either.
      expect(find.text('Stage'), findsOneWidget);
      expect(find.text('Discard…'), findsNothing);
      expect(find.text('Stage hunk'), findsOneWidget);
    });

    testWidgets('Copy lines puts the line text on the clipboard', (
      tester,
    ) async {
      await pumpLine(tester, line: added(text: 'my added line'));

      await tester.tap(find.text('Copy lines'));
      await tester.pumpAndSettle();

      expect(clipboardText, equals('my added line'));
    });

    testWidgets('tapping Stage calls onStageLine', (tester) async {
      bool stageCalled = false;
      await pumpLine(
        tester,
        line: added(),
        onStageLine: () => stageCalled = true,
      );

      await tester.tap(find.text('Stage'));
      await tester.pumpAndSettle();

      expect(stageCalled, isTrue);
    });

    testWidgets('tapping Stage hunk calls onStageHunk', (tester) async {
      bool stageHunkCalled = false;
      await pumpLine(
        tester,
        line: added(),
        onStageHunk: () => stageHunkCalled = true,
      );

      await tester.tap(find.text('Stage hunk'));
      await tester.pumpAndSettle();

      expect(stageHunkCalled, isTrue);
    });

    testWidgets('tapping Discard… calls onDiscardLine', (tester) async {
      bool discardCalled = false;
      await pumpLine(
        tester,
        line: added(),
        onDiscardLine: () => discardCalled = true,
      );

      await tester.tap(find.text('Discard…'));
      await tester.pumpAndSettle();

      expect(discardCalled, isTrue);
    });

    testWidgets(
      'the inapplicable hunk direction renders but does not dispatch',
      (tester) async {
        bool hunkCalled = false;
        await pumpLine(
          tester,
          line: added(),
          onStageHunk: () => hunkCalled = true,
        );

        await tester.tap(find.text('Unstage hunk'));
        await tester.pumpAndSettle();

        expect(
          hunkCalled,
          isFalse,
          reason:
              'an unstaged diff has nothing to unstage; the item is '
              'shown because spec lists it, with onTap null',
        );
      },
    );

    testWidgets('a read-only diff leaves both hunk items inert', (
      tester,
    ) async {
      bool anyTapped = false;
      await pumpLine(
        tester,
        line: added(),
        onStageLine: () => anyTapped = true,
      );

      await tester.tap(find.text('Stage hunk'));
      await tester.pumpAndSettle();
      expect(anyTapped, isFalse);
    });
  });

  // 使用者裁定 2026-10-24 (wc-full-file-view-spec.html §03): the row's
  // horizontal padding is KIT `.gbm-diffline`'s `padding: 1px 10px`, not
  // `space3`. Measured on the painted text, in both wrap modes, because the
  // unwrapped row moves its left padding into the pinned gutter.
  group('DiffLineView horizontal padding is .gbm-diffline\'s 10px', () {
    const DiffLine line = DiffLine(
      kind: DiffLineKind.context,
      oldLine: 7,
      newLine: 7,
      text: 'ctx',
    );

    Future<void> pump(WidgetTester tester, {required bool softWrap}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  child: DiffLineView(softWrap: softWrap, line: line),
                ),
              ),
            ),
          ),
        );

    for (final bool softWrap in <bool>[true, false]) {
      testWidgets('code starts 10 + 36 + 36 + 14 from the row edge '
          '(softWrap: $softWrap)', (WidgetTester tester) async {
        await pump(tester, softWrap: softWrap);
        final Rect row = tester.getRect(find.byType(DiffLineView));
        final Rect code = tester.getRect(find.text('ctx'));
        expect(code.left - row.left, 10 + 36 + 36 + 14);
      });

      testWidgets('line numbers end 10 + 36 from the row edge '
          '(softWrap: $softWrap)', (WidgetTester tester) async {
        await pump(tester, softWrap: softWrap);
        final Rect row = tester.getRect(find.byType(DiffLineView));
        final Rect oldNumber = tester.getRect(find.text('7').first);
        expect(oldNumber.right - row.left, 10 + 36);
      });
    }

    testWidgets('the unwrapped scroll extent leaves 10 after the widest line', (
      WidgetTester tester,
    ) async {
      final DiffFile file = DiffFile(
        oldPath: 'a.dart',
        newPath: 'a.dart',
        kind: FileChangeKind.modified,
        oldMode: '',
        newMode: '',
        oldBlob: '',
        newBlob: '',
        binary: false,
        similarity: 0,
        addedLines: 0,
        removedLines: 0,
        displayPath: 'a.dart',
        hunks: const <DiffHunk>[
          DiffHunk(
            oldStart: 7,
            oldCount: 1,
            newStart: 7,
            newCount: 1,
            heading: '',
            lines: <DiffLine>[line],
          ),
        ],
      );
      expect(
        diffFileContentWidth(file, softWrap: false, memo: CodeWidthMemo()),
        kDiffGutterWidth + widestLineWidth('ctx', kDiffCodeTextStyle) + 10,
      );
    });

    testWidgets('the wrapped code stops 10 short of the row\'s right edge', (
      WidgetTester tester,
    ) async {
      await pump(tester, softWrap: true);
      final Rect row = tester.getRect(find.byType(DiffLineView));
      final Rect code = tester.getRect(
        find.ancestor(of: find.text('ctx'), matching: find.byType(Expanded)),
      );
      expect(row.right - code.right, 10);
    });
  });
}
