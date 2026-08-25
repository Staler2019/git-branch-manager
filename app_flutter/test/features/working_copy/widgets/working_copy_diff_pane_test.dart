// The pane that carries spec P03 變體 B's titlebar and its `2 file` /
// `unified` switch. What this file is really for is the payoff of holding
// both replies at once: before `workingCopyDiffs` replaced the single
// `lastDiff` slot, one of these two panes could not have had content.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import '../../../support/pump_app.dart';

DiffFile _file(String text, {required bool added}) => DiffFile(
  oldPath: 'lib/a.dart',
  newPath: 'lib/a.dart',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: 1,
  removedLines: 0,
  displayPath: 'lib/a.dart',
  hunks: <DiffHunk>[
    DiffHunk(
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 1,
      heading: '',
      lines: <DiffLine>[
        DiffLine(
          kind: added ? DiffLineKind.added : DiffLineKind.removed,
          oldLine: 1,
          newLine: 1,
          text: text,
        ),
      ],
    ),
  ],
);

void main() {
  group('WorkingCopyDiffPane', () {
    late List<({bool staged, int hunkIndex, List<int> lines})> stageCalls;

    setUp(() {
      stageCalls = <({bool staged, int hunkIndex, List<int> lines})>[];
    });

    Future<void> pump(
      WidgetTester tester, {
      DiffFile? unstaged,
      DiffFile? staged,
      bool unstagedLoading = false,
      bool stagedLoading = false,
      String displayPath = 'lib/a.dart',
    }) async {
      await pumpGbmWidget(
        tester,
        child: WorkingCopyDiffPane(
          displayPath: displayPath,
          unstagedFile: unstaged,
          stagedFile: staged,
          unstagedLoading: unstagedLoading,
          stagedLoading: stagedLoading,
          onStageScope: (bool s, int h, List<int> l) =>
              stageCalls.add((staged: s, hunkIndex: h, lines: l)),
          onDiscardScope: (_, _) {},
        ),
      );
    }

    testWidgets('2 file mode shows both sides of the same file at once', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      // Distinct text on each side: identical content would let the two
      // panes be swapped, or one of them be drawn twice, and still pass.
      expect(find.text('still editing'), findsOneWidget);
      expect(find.text('already staged'), findsOneWidget);
      expect(find.text('Unstaged'), findsOneWidget);
      expect(find.text('Staged'), findsOneWidget);
    });

    testWidgets('the left side is the unstaged one', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      expect(
        tester.getCenter(find.text('still editing')).dx,
        lessThan(tester.getCenter(find.text('already staged')).dx),
      );
    });

    testWidgets('a press on the staged side unstages, on the unstaged side '
        'stages', (WidgetTester tester) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      await tester.tap(find.text('Stage 1 line'));
      await tester.tap(find.text('Unstage 1 line'));

      expect(stageCalls.length, 2);
      expect(stageCalls[0].staged, isFalse);
      expect(stageCalls[1].staged, isTrue);
    });

    testWidgets('unified mode stacks the sides in one column', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      await tester.tap(find.text('unified'));
      await tester.pump();

      expect(find.text('still editing'), findsOneWidget);
      expect(find.text('already staged'), findsOneWidget);
      expect(
        tester.getCenter(find.text('still editing')).dy,
        lessThan(tester.getCenter(find.text('already staged')).dy),
        reason:
            'unified is one column, so the sides stack rather than sit '
            'beside each other',
      );
    });

    testWidgets('a half-staged rename names both of its paths', (
      WidgetTester tester,
    ) async {
      // The work tree still calls it the old name while the index already
      // calls it the new one; naming only one would describe a file the
      // board is not selecting.
      await pump(tester, displayPath: 'old.dart → new.dart');

      expect(find.text('old.dart → new.dart'), findsOneWidget);
    });

    testWidgets('a side still waiting spins while the other one renders', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        stagedLoading: true,
      );

      expect(find.text('still editing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No pumpAndSettle: an indeterminate indicator never settles (#101).
    });
  });
}
