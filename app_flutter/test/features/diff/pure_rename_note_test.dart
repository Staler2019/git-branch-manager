// A rename with no content change arrives as a Renamed DiffFile with zero
// hunks. Every diff surface used to draw that as an empty body, which reads
// as "the diff failed to load". Spec:
// docs/claude-design-demo/rename-diff-display-spec.html, 畫面 3 --
// 「純移動（0 hunk）body 畫一行說明，不畫 No changes」, and Working Copy
// 「完全比照 binary」.
//
// The negative cases are the load-bearing half: a note drawn for every
// rename, or for every empty file, would pass the positive ones as well.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_page.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/side_by_side_diff_view.dart';

import '../../support/pump_app.dart';

const DiffHunk _oneLine = DiffHunk(
  oldStart: 1,
  oldCount: 1,
  newStart: 1,
  newCount: 1,
  heading: '',
  lines: <DiffLine>[
    DiffLine(kind: DiffLineKind.added, oldLine: 0, newLine: 1, text: 'edited'),
  ],
);

DiffFile _file({
  FileChangeKind kind = FileChangeKind.renamed,
  bool binary = false,
  List<DiffHunk> hunks = const <DiffHunk>[],
}) => DiffFile(
  oldPath: 'lib/a.dart',
  newPath: 'lib/b.dart',
  kind: kind,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'aaa',
  binary: binary,
  similarity: 100,
  addedLines: 0,
  removedLines: 0,
  displayPath: 'lib/b.dart',
  hunks: hunks,
);

ParsedDiff _diff(DiffFile file) =>
    ParsedDiff(files: <DiffFile>[file], truncated: false, inputBytes: 0);

ScopedDiffSource _source(
  String title,
  DiffFile? file, {
  required bool staged,
}) => ScopedDiffSource(
  title: title,
  file: file,
  staged: staged,
  onStageScope: (int h, List<int> l) {},
);

Future<void> _pump(WidgetTester tester, Widget child) => pumpGbmWidget(
  tester,
  child: SizedBox(width: 600, height: 400, child: child),
);

void main() {
  group('DiffFile.isPureRename', () {
    test('a rename with no hunks is a pure rename', () {
      expect(_file().isPureRename, isTrue);
    });

    test('a rename with an edit is not', () {
      expect(_file(hunks: const <DiffHunk>[_oneLine]).isPureRename, isFalse);
    });

    test('a binary rename is not: binary is checked first', () {
      expect(_file(binary: true).isPureRename, isFalse);
    });

    test('an empty file of any other kind is not', () {
      expect(_file(kind: FileChangeKind.modified).isPureRename, isFalse);
      expect(_file(kind: FileChangeKind.copied).isPureRename, isFalse);
    });
  });

  group('DiffPage', () {
    testWidgets('a pure rename says so instead of drawing an empty body', (
      tester,
    ) async {
      await _pump(tester, DiffPage(diff: _diff(_file())));

      expect(find.text(kPureRenameNote), findsOneWidget);
      expect(find.text('No changes'), findsNothing);
    });

    testWidgets('a rename with an edit draws its hunk and no note', (
      tester,
    ) async {
      await _pump(
        tester,
        DiffPage(diff: _diff(_file(hunks: const <DiffHunk>[_oneLine]))),
      );

      expect(find.text(kPureRenameNote), findsNothing);
      expect(find.textContaining('edited'), findsWidgets);
    });

    testWidgets('a binary rename keeps the binary notice', (tester) async {
      await _pump(tester, DiffPage(diff: _diff(_file(binary: true))));

      expect(find.text(kPureRenameNote), findsNothing);
      expect(find.text('lib/b.dart (binary file)'), findsOneWidget);
    });
  });

  group('SideBySideDiffView', () {
    testWidgets('a pure rename says so instead of drawing an empty body', (
      tester,
    ) async {
      await _pump(tester, SideBySideDiffView(diff: _diff(_file())));

      expect(find.text(kPureRenameNote), findsOneWidget);
    });

    testWidgets('a rename with an edit draws no note', (tester) async {
      await _pump(
        tester,
        SideBySideDiffView(
          diff: _diff(_file(hunks: const <DiffHunk>[_oneLine])),
        ),
      );

      expect(find.text(kPureRenameNote), findsNothing);
    });
  });

  group('ScopedDiffView', () {
    testWidgets('a staged pure rename alone gets the note as its placeholder', (
      tester,
    ) async {
      await _pump(
        tester,
        ScopedDiffView(
          softWrap: false,
          sources: <ScopedDiffSource>[
            _source('Unstaged', null, staged: false),
            _source('Staged', _file(), staged: true),
          ],
        ),
      );

      expect(find.text(kPureRenameNote), findsOneWidget);
      expect(find.text('No changes'), findsNothing);
    });

    testWidgets('beside an edited side, the pure rename gets a notice', (
      tester,
    ) async {
      await _pump(
        tester,
        ScopedDiffView(
          softWrap: false,
          sources: <ScopedDiffSource>[
            _source(
              'Unstaged',
              _file(
                kind: FileChangeKind.modified,
                hunks: const <DiffHunk>[_oneLine],
              ),
              staged: false,
            ),
            _source('Staged', _file(), staged: true),
          ],
        ),
      );

      expect(find.textContaining('edited'), findsWidgets);
      expect(find.text(kPureRenameNote), findsOneWidget);
    });

    testWidgets('a binary rename keeps the binary placeholder', (tester) async {
      await _pump(
        tester,
        ScopedDiffView(
          softWrap: false,
          sources: <ScopedDiffSource>[
            _source('Staged', _file(binary: true), staged: true),
          ],
        ),
      );

      expect(find.text(kPureRenameNote), findsNothing);
      expect(find.text('lib/b.dart (binary file)'), findsOneWidget);
    });
  });
}
