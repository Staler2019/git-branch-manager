// Verifies ChangedFileRow's right-click menu against the design doc's
// `ctxItemsFor('unstaged-file'|'staged-file')`: the Stage/Unstage label
// flips with `checked`, Discard changes is danger-styled and only present
// when `onDiscard` is given, and taps wire through to the right callback.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/working_copy/widgets/changed_file_row.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

WorkingCopyEntry _entry({String path = 'src/main.dart'}) {
  return WorkingCopyEntry(
    path: path,
    oldPath: '',
    untracked: false,
    staged: false,
    indexStatus: FileChangeKind.modified,
    hasUnstagedChange: true,
    worktreeStatus: FileChangeKind.modified,
    conflict: ConflictKind.none,
    ancestorBlob: '',
    oursBlob: '',
    theirsBlob: '',
    similarity: 0,
    isSubmodule: false,
    isConflicted: false,
  );
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(finder));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('an unchecked (unstaged) file offers "Stage file"', (
    tester,
  ) async {
    await _pump(
      tester,
      ChangedFileRow(
        entry: _entry(),
        checked: false,
        selected: false,
        onCheckToggle: () {},
        onTap: () {},
        onDiscard: () {},
      ),
    );
    await _rightClick(tester, find.byType(ChangedFileRow));
    expect(find.text('Stage file'), findsOneWidget);
    expect(find.text('Unstage file'), findsNothing);
    expect(find.text('View diff'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);
    expect(find.text('Discard changes'), findsOneWidget);
  });

  testWidgets('a checked (staged) file offers "Unstage file"', (tester) async {
    await _pump(
      tester,
      ChangedFileRow(
        entry: _entry(),
        checked: true,
        selected: false,
        onCheckToggle: () {},
        onTap: () {},
      ),
    );
    await _rightClick(tester, find.byType(ChangedFileRow));
    expect(find.text('Unstage file'), findsOneWidget);
    expect(find.text('Stage file'), findsNothing);
  });

  testWidgets('Discard changes is omitted when onDiscard is null', (
    tester,
  ) async {
    await _pump(
      tester,
      ChangedFileRow(
        entry: _entry(),
        checked: false,
        selected: false,
        onCheckToggle: () {},
        onTap: () {},
      ),
    );
    await _rightClick(tester, find.byType(ChangedFileRow));
    expect(find.text('Discard changes'), findsNothing);
  });

  testWidgets('Discard changes is styled danger', (tester) async {
    await _pump(
      tester,
      ChangedFileRow(
        entry: _entry(),
        checked: false,
        selected: false,
        onCheckToggle: () {},
        onTap: () {},
        onDiscard: () {},
      ),
    );
    await _rightClick(tester, find.byType(ChangedFileRow));
    final Text label = tester.widget<Text>(find.text('Discard changes'));
    expect(label.style?.color, tokensFor(GbmThemeVariant.darkTechnical).danger);
  });

  testWidgets('tapping "Stage file" invokes onCheckToggle', (tester) async {
    int toggled = 0;
    await _pump(
      tester,
      ChangedFileRow(
        entry: _entry(),
        checked: false,
        selected: false,
        onCheckToggle: () => toggled++,
        onTap: () {},
      ),
    );
    await _rightClick(tester, find.byType(ChangedFileRow));
    await tester.tap(find.text('Stage file'));
    await tester.pumpAndSettle();
    expect(toggled, 1);
  });

  testWidgets(
    'the trailing "File actions" button offers Blame/File History/Line History/Discard changes',
    (tester) async {
      int blamed = 0;
      int fileHistoried = 0;
      int lineHistoried = 0;
      int discarded = 0;
      await _pump(
        tester,
        ChangedFileRow(
          entry: _entry(),
          checked: false,
          selected: false,
          onCheckToggle: () {},
          onTap: () {},
          onBlame: () => blamed++,
          onFileHistory: () => fileHistoried++,
          onLineHistory: () => lineHistoried++,
          onDiscard: () => discarded++,
        ),
      );
      await tester.tap(find.byTooltip('File actions'));
      await tester.pumpAndSettle();

      // Not a Material PopupMenuButton overlay -- see _FileActionsMenu's doc
      // comment on why this must go through showGbmMenu.
      expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
      expect(find.text('Blame…'), findsOneWidget);
      expect(find.text('File History…'), findsOneWidget);
      expect(find.text('Line History…'), findsOneWidget);
      final Text discardLabel = tester.widget<Text>(
        find.text('Discard changes'),
      );
      expect(
        discardLabel.style?.color,
        tokensFor(GbmThemeVariant.darkTechnical).danger,
      );

      await tester.tap(find.text('Blame…'));
      await tester.pumpAndSettle();
      expect(blamed, 1);

      await tester.tap(find.byTooltip('File actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File History…'));
      await tester.pumpAndSettle();
      expect(fileHistoried, 1);

      await tester.tap(find.byTooltip('File actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Line History…'));
      await tester.pumpAndSettle();
      expect(lineHistoried, 1);

      await tester.tap(find.byTooltip('File actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(discarded, 1);
    },
  );
}
