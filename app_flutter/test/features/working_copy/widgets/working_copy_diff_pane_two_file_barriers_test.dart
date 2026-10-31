// plan: Slice B. In `2 file` each column's cards are cut where the other
// side changes the file, the way `unified` cuts them (使用者裁定 ①②,
// docs/records/2026-10-04-merged-diff-region-order.md), so the sync gives
// the other side's change a segment of its own and this column a blank
// there. 使用者回報 2026-10-31「the stage panel didn't split two part and
// leave blank line for unstaged part index match」; ruled 「所有檔案都套用」.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import '../../../support/pump_app.dart';

typedef _Row = (DiffLineKind kind, int oldLine, int newLine, String text);

DiffFile _diff(
  FileChangeKind kind,
  int oldStart,
  int oldCount,
  int newStart,
  int newCount,
  List<_Row> rows,
) => DiffFile(
  oldPath: 'n.txt',
  newPath: 'n.txt',
  kind: kind,
  oldMode: '',
  newMode: '100644',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: rows.where((_Row r) => r.$1 == DiffLineKind.added).length,
  removedLines: rows.where((_Row r) => r.$1 == DiffLineKind.removed).length,
  displayPath: 'n.txt',
  hunks: <DiffHunk>[
    DiffHunk(
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      heading: '',
      lines: <DiffLine>[
        for (final _Row r in rows)
          DiffLine(kind: r.$1, oldLine: r.$2, newLine: r.$3, text: r.$4),
      ],
    ),
  ],
);

const DiffLineKind _add = DiffLineKind.added;
const DiffLineKind _ctx = DiffLineKind.context;

// The reported case: a new file staged whole, then L3 and L4 unstaged
// again. HEAD has no file; the index holds L1 L2 L5 L6; the work tree all
// six.
final DiffFile _staged = _diff(FileChangeKind.added, 0, 0, 1, 4, <_Row>[
  (_add, 0, 1, 'L1'),
  (_add, 0, 2, 'L2'),
  (_add, 0, 3, 'L5'),
  (_add, 0, 4, 'L6'),
]);
final DiffFile _unstaged = _diff(FileChangeKind.modified, 1, 4, 1, 6, <_Row>[
  (_ctx, 1, 1, 'L1'),
  (_ctx, 2, 2, 'L2'),
  (_add, 0, 3, 'L3'),
  (_add, 0, 4, 'L4'),
  (_ctx, 3, 5, 'L5'),
  (_ctx, 4, 6, 'L6'),
]);

void main() {
  Future<List<(bool, int, List<int>)>> pump(
    WidgetTester tester, {
    required DiffFile unstaged,
    required DiffFile staged,
    bool fullFile = false,
    bool twoFile = true,
  }) async {
    final List<(bool, int, List<int>)> calls = <(bool, int, List<int>)>[];
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpGbmWidget(
      tester,
      child: WorkingCopyDiffPane(
        softWrap: false,
        displayPath: 'n.txt',
        unstagedFile: unstaged,
        stagedFile: staged,
        unstagedFullFile: unstaged,
        stagedFullFile: staged,
        fullFile: fullFile,
        unstagedLoading: false,
        stagedLoading: false,
        onStageScope: (bool s, int hunk, List<int> lines) =>
            calls.add((s, hunk, List<int>.of(lines))),
        onDiscardScope: (_, _) {},
        onTemporaryScopeChanged: (_) {},
        onToggleFullFile: () {},
      ),
    );
    await tester.pump();
    if (twoFile) {
      await tester.tap(find.text('2 file'));
      for (int i = 0; i < 4; i++) {
        await tester.pump();
      }
    }
    return calls;
  }

  /// [text] in column [c] (0 unstaged, 1 staged).
  Finder inColumn(int c, String text) => find.descendant(
    of: find.byType(ScopedDiffView).at(c),
    matching: find.text(text, findRichText: true),
  );

  for (final bool fullFile in <bool>[false, true]) {
    final String mode = fullFile ? 'full file' : 'excerpts';

    testWidgets('$mode: the staged card is cut where the unstaged lines go, '
        'and the gap is left blank beside them', (WidgetTester tester) async {
      await pump(
        tester,
        unstaged: _unstaged,
        staged: _staged,
        fullFile: fullFile,
      );

      expect(
        find.descendant(
          of: find.byType(ScopedDiffView).at(1),
          matching: find.text('Unstage 2 lines'),
        ),
        findsNWidgets(2),
      );
      // Nothing staged sits level with the unstaged L3-L4.
      expect(
        tester.getRect(inColumn(1, 'L2')).bottom,
        lessThanOrEqualTo(tester.getRect(inColumn(0, 'L3')).top),
      );
      expect(
        tester.getRect(inColumn(1, 'L5')).top,
        greaterThanOrEqualTo(tester.getRect(inColumn(0, 'L4')).bottom),
      );
      expect(find.text('2 個 scope'), findsOneWidget);
      expect(find.text('1 個 scope'), findsOneWidget);
    });
  }

  // The card is the payload: each half acts on its own two lines, exactly
  // as the same card does in `unified`.
  testWidgets('each staged card unstages its own lines, the same as in '
      'unified', (WidgetTester tester) async {
    Future<List<(bool, int, List<int>)>> press(bool twoFile) async {
      final List<(bool, int, List<int>)> calls = await pump(
        tester,
        unstaged: _unstaged,
        staged: _staged,
        twoFile: twoFile,
      );
      final Finder buttons = find.text('Unstage 2 lines');
      expect(buttons, findsNWidgets(2));
      for (int i = 0; i < 2; i++) {
        await tester.tap(buttons.at(i));
        await tester.pump();
      }
      return calls;
    }

    // As strings: a record compares its List field by identity.
    List<String> shown(List<(bool, int, List<int>)> calls) => <String>[
      for (final (bool s, int h, List<int> l) in calls) '$s:$h:$l',
    ];
    final List<String> twoFile = shown(await press(true));
    expect(twoFile, <String>['true:0:[0, 1]', 'true:0:[2, 3]']);
    expect(shown(await press(false)), twoFile);
  });

  // A modified file: the staged run inserted at index 10-14, and an
  // unstaged line inserted after index 12 -- and the other way round, a
  // staged insertion inside an unstaged run.
  testWidgets('a modified file is cut the same way, in either column', (
    WidgetTester tester,
  ) async {
    final DiffFile staged = _diff(FileChangeKind.modified, 7, 6, 7, 11, <_Row>[
      (_ctx, 7, 7, 'c7'),
      (_ctx, 8, 8, 'c8'),
      (_ctx, 9, 9, 'c9'),
      for (int i = 10; i <= 14; i++) (_add, 0, i, 's$i'),
      (_ctx, 10, 15, 'c10'),
      (_ctx, 11, 16, 'c11'),
      (_ctx, 12, 17, 'c12'),
    ]);
    final DiffFile unstaged = _diff(
      FileChangeKind.modified,
      10,
      6,
      10,
      7,
      <_Row>[
        (_ctx, 10, 10, 's10'),
        (_ctx, 11, 11, 's11'),
        (_ctx, 12, 12, 's12'),
        (_add, 0, 13, 'u'),
        (_ctx, 13, 14, 's13'),
        (_ctx, 14, 15, 's14'),
        (_ctx, 15, 16, 'c10'),
      ],
    );
    await pump(tester, unstaged: unstaged, staged: staged);

    expect(
      find.descendant(
        of: find.byType(ScopedDiffView).at(1),
        matching: find.text('Unstage 3 lines'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ScopedDiffView).at(1),
        matching: find.text('Unstage 2 lines'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(inColumn(1, 's13')).top,
      greaterThanOrEqualTo(tester.getRect(inColumn(0, 'u')).bottom),
    );

    // The mirror: x staged at index 10, and unstaged runs either side of
    // it. One unchanged line apart, the gap rule alone would fold them into
    // one card; x is a change of the other side's, so it may not.
    final DiffFile stagedOne = _diff(
      FileChangeKind.modified,
      7,
      6,
      7,
      7,
      <_Row>[
        (_ctx, 7, 7, 'c7'),
        (_ctx, 8, 8, 'c8'),
        (_ctx, 9, 9, 'c9'),
        (_add, 0, 10, 'x'),
        (_ctx, 10, 11, 'c10'),
        (_ctx, 11, 12, 'c11'),
        (_ctx, 12, 13, 'c12'),
      ],
    );
    final DiffFile unstagedAround = _diff(
      FileChangeKind.modified,
      9,
      3,
      9,
      7,
      <_Row>[
        (_ctx, 9, 9, 'c9'),
        (_add, 0, 10, 'w10'),
        (_add, 0, 11, 'w11'),
        (_ctx, 10, 12, 'x'),
        (_add, 0, 13, 'w13'),
        (_add, 0, 14, 'w14'),
        (_ctx, 11, 15, 'c10'),
      ],
    );
    await pump(tester, unstaged: unstagedAround, staged: stagedOne);
    // Two unstaged cards either side of the staged x, which is a change
    // of the other side's inside what was one gap-merged scope.
    expect(
      find.descendant(
        of: find.byType(ScopedDiffView).at(0),
        matching: find.text('Stage 2 lines'),
      ),
      findsNWidgets(2),
    );
  });
}
