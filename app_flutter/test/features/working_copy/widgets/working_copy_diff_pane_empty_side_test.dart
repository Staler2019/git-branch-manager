// plan: Slice E, E3. In `2 file` with the full-file view on, a column whose
// own direction has no change draws the index -- the file both of its ends
// hold -- from the other side's full diff, aligned with the other column.
// Only while the other column itself draws its full file; excerpt mode is
// untouched (使用者裁定 2026-10-31「片段模式就維持跟現在一樣」).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

/// A whole new file of [lines] as one hunk of added rows.
DiffFile _newFile(List<String> lines) => DiffFile(
  oldPath: 'n.dart',
  newPath: 'n.dart',
  kind: FileChangeKind.added,
  oldMode: '',
  newMode: '100644',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: lines.length,
  removedLines: 0,
  displayPath: 'n.dart',
  hunks: <DiffHunk>[
    DiffHunk(
      oldStart: 0,
      oldCount: 0,
      newStart: 1,
      newCount: lines.length,
      heading: '',
      lines: <DiffLine>[
        for (int i = 0; i < lines.length; i++)
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: 0,
            newLine: i + 1,
            text: lines[i],
          ),
      ],
    ),
  ],
);

/// A changed binary file: no hunk to draw on either side.
const DiffFile _binary = DiffFile(
  oldPath: 'a.png',
  newPath: 'a.png',
  kind: FileChangeKind.modified,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: '',
  newBlob: '',
  binary: true,
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
  displayPath: 'a.png',
  hunks: <DiffHunk>[],
);

void main() {
  // Edits at 5 and 30 of 40 lines: line 15 is outside both -U3 windows
  // (2-8, 27-33), so in the unstaged column only a fill row draws it.
  final DiffFile unstaged = replacementsDiff(40, <int>{5, 30}, context: 3);
  final DiffFile unstagedFull = replacementsDiff(40, <int>{
    5,
    30,
  }, context: kAllContext);

  Future<void> pump(
    WidgetTester tester, {
    required bool fullFile,
    DiffFile? unstagedFile,
    DiffFile? unstagedFullFile,
    DiffFile? stagedFile,
    DiffFile? stagedFullFile,
    bool stagedLoading = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpGbmWidget(
      tester,
      child: WorkingCopyDiffPane(
        softWrap: false,
        displayPath: 'lib/a.dart',
        unstagedFile: unstagedFile,
        stagedFile: stagedFile,
        unstagedFullFile: unstagedFullFile,
        stagedFullFile: stagedFullFile,
        fullFile: fullFile,
        unstagedLoading: false,
        stagedLoading: stagedLoading,
        onStageScope: (_, _, _) {},
        onDiscardScope: (_, _) {},
        onTemporaryScopeChanged: (_) {},
        onToggleFullFile: () {},
      ),
    );
    await tester.pump();
  }

  Future<void> twoFile(WidgetTester tester) async {
    await tester.tap(find.text('2 file'));
    await tester.pump();
    await tester.pump();
  }

  /// [text] inside column [c] (0 unstaged, 1 staged).
  Finder inColumn(int c, String text) => find.descendant(
    of: find.byType(ScopedDiffView).at(c),
    matching: find.text(text, findRichText: true),
  );

  testWidgets('nothing staged: the staged column draws the index from the '
      "unstaged diff's old side, never its added rows", (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      fullFile: true,
      unstagedFile: unstaged,
      unstagedFullFile: unstagedFull,
    );
    await twoFile(tester);

    for (final String line in <String>['L1', 'L5', 'L15', 'L30', 'L40']) {
      expect(inColumn(1, line), findsOneWidget, reason: line);
    }
    expect(inColumn(1, 'edited L5'), findsNothing);
    expect(inColumn(1, 'edited L30'), findsNothing);
  });

  testWidgets('a new file staged whole: the unstaged column draws every line', (
    WidgetTester tester,
  ) async {
    final DiffFile file = _newFile(<String>['alpha', 'beta', 'gamma']);
    await pump(tester, fullFile: true, stagedFile: file, stagedFullFile: file);
    await twoFile(tester);

    for (final String line in <String>['alpha', 'beta', 'gamma']) {
      expect(inColumn(0, line), findsOneWidget, reason: line);
    }
    expect(find.text('Not in Git'), findsNothing);
  });

  testWidgets('a row both columns draw outside any card sits at one height', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      fullFile: true,
      unstagedFile: unstaged,
      unstagedFullFile: unstagedFull,
    );
    await twoFile(tester);

    expect(
      tester.getRect(inColumn(1, 'L15')).top,
      moreOrLessEquals(tester.getRect(inColumn(0, 'L15')).top, epsilon: 0.5),
    );
  });

  testWidgets('full-file view off: the empty column draws nothing, as before', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      fullFile: false,
      unstagedFile: unstaged,
      unstagedFullFile: unstagedFull,
    );
    await twoFile(tester);

    expect(inColumn(1, 'L5'), findsNothing);
    expect(inColumn(1, 'L15'), findsNothing);
  });

  testWidgets('over the line cap: the empty column draws nothing', (
    WidgetTester tester,
  ) async {
    const int total = kFullFileViewMaxLines + 1;
    await pump(
      tester,
      fullFile: true,
      unstagedFile: replacementsDiff(total, <int>{5, 30}, context: 3),
      unstagedFullFile: replacementsDiff(total, <int>{
        5,
        30,
      }, context: kAllContext),
    );
    await twoFile(tester);

    expect(inColumn(1, 'L1'), findsNothing);
    expect(inColumn(1, 'L5'), findsNothing);
  });

  testWidgets('the staged side landing empty after the unstaged one, with '
      'the unstaged diffs unchanged, still lines the columns up', (
    WidgetTester tester,
  ) async {
    // The two replies are separate events, and the side already there
    // keeps its instance (`_mergedDiffReply`): only the loading flag moves.
    await pump(
      tester,
      fullFile: true,
      unstagedFile: unstaged,
      unstagedFullFile: unstagedFull,
      stagedLoading: true,
    );
    await twoFile(tester);
    expect(inColumn(1, 'L15'), findsNothing);

    await pump(
      tester,
      fullFile: true,
      unstagedFile: unstaged,
      unstagedFullFile: unstagedFull,
    );
    await tester.pump();

    expect(inColumn(1, 'L15'), findsOneWidget);
    expect(
      tester.getRect(inColumn(1, 'L15')).top,
      moreOrLessEquals(tester.getRect(inColumn(0, 'L15')).top, epsilon: 0.5),
    );
  });

  /// The well's frame -- sunken ground inside a subtle border -- drawn in
  /// column [c].
  Finder wellFrames(WidgetTester tester, int c) {
    final GbmColors colors = tester
        .element(find.byType(ScopedDiffView).at(c))
        .gbmColors;
    return find.descendant(
      of: find.byType(ScopedDiffView).at(c),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == colors.surfaceSunken &&
            (w.decoration as BoxDecoration).border != null,
      ),
    );
  }

  // 使用者回報 2026-10-31「binary這種無法顯示內容的，unstage下方還是會有空行
  // panel，不應該有」: a column with nothing to draw still ended each sync
  // segment in a spacer, and the spacer was framed as the well's only item.
  for (final bool fullFile in <bool>[false, true]) {
    testWidgets('a binary file draws no empty well in either column '
        '(full file ${fullFile ? 'on' : 'off'})', (WidgetTester tester) async {
      await pump(
        tester,
        fullFile: fullFile,
        unstagedFile: _binary,
        unstagedFullFile: _binary,
      );
      await twoFile(tester);

      expect(find.text('a.png (binary file)'), findsOneWidget);
      expect(wellFrames(tester, 0), findsNothing);
      expect(wellFrames(tester, 1), findsNothing);
    });
  }

  testWidgets('full file off: the side with nothing draws no empty well, '
      'the side with cards keeps its own', (WidgetTester tester) async {
    await pump(
      tester,
      fullFile: false,
      unstagedFile: unstaged,
      unstagedFullFile: unstagedFull,
    );
    await twoFile(tester);

    expect(wellFrames(tester, 1), findsNothing);
    // The side with cards keeps every item of its well painted, the
    // spacers included: the last one draws the well's bottom edge.
    expect(
      wellFrames(tester, 0).evaluate().length,
      find
          .descendant(
            of: find.byType(ScopedDiffView).at(0),
            matching: find.byWidgetPredicate(
              (Widget w) => w.runtimeType.toString() == '_FrameSegment',
            ),
          )
          .evaluate()
          .length,
    );
    expect(
      find.descendant(
        of: find.byType(ScopedDiffView).at(0),
        matching: find.byType(SyncSlotSpacer),
      ),
      findsWidgets,
    );
  });
}
