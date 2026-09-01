// The pane that carries spec P03 變體 B's titlebar and its `2 file` /
// `unified` switch. What this file is really for is the payoff of holding
// both replies at once: before `workingCopyDiffs` replaced the single
// `lastDiff` slot, one of these two panes could not have had content.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';
import 'package:gbm_flutter/widgets/split_pane.dart';

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

    late List<void Function()?> submitters;

    setUp(() {
      stageCalls = <({bool staged, int hunkIndex, List<int> lines})>[];
      submitters = <void Function()?>[];
    });

    Future<void> pump(
      WidgetTester tester, {
      DiffFile? unstaged,
      DiffFile? staged,
      bool unstagedLoading = false,
      bool stagedLoading = false,
      bool unstagedTruncated = false,
      bool stagedTruncated = false,
      String displayPath = 'lib/a.dart',
    }) async {
      await pumpGbmWidget(
        tester,
        child: WorkingCopyDiffPane(
          softWrap: false,
          displayPath: displayPath,
          unstagedFile: unstaged,
          stagedFile: staged,
          unstagedLoading: unstagedLoading,
          stagedLoading: stagedLoading,
          unstagedTruncated: unstagedTruncated,
          stagedTruncated: stagedTruncated,
          onStageScope: (bool s, int h, List<int> l) =>
              stageCalls.add((staged: s, hunkIndex: h, lines: l)),
          onDiscardScope: (_, _) {},
          onTemporaryScopeChanged: (void Function()? submit) =>
              submitters.add(submit),
        ),
      );
    }

    testWidgets(
      'a side refused for its size says so, and only that side does',
      (WidgetTester tester) async {
        // Both sides drawn at once is the whole point of this pane, so the
        // refusal has to be per side. Pinned here rather than only in
        // ScopedDiffView's own tests because this is where the Working Copy's
        // wording lives -- and "Nothing unstaged" over a file that has changes
        // is the exact sentence this round exists to remove.
        await pump(
          tester,
          unstaged: null,
          unstagedTruncated: true,
          staged: _file('already staged', added: true),
        );

        expect(find.text('Diff too large to display'), findsOneWidget);
        expect(find.text('Nothing unstaged'), findsNothing);
        // The other side is untouched: it still draws its own diff.
        expect(find.text('already staged'), findsOneWidget);
      },
    );

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

    // C18's reuse audit: the two sides were a fixed 50/50 `Row` with a
    // hairline `Container` divider -- a hand-rolled GbmSplitPane. Every
    // other two-pane surface in the app is a real splitter, including
    // `wc.columns` in the board directly above this pane, so this was the
    // one place where a divider the user could see refused to move.
    testWidgets('2 file mode: the divider between the two sides drags', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      final double before = tester.getCenter(find.text('already staged')).dx;

      await tester.drag(
        find.byKey(const Key('gbm-split-divider-0')),
        const Offset(80, 0),
      );
      // Past kDoubleTapTimeout: the divider carries a double-tap recogniser
      // (double-click resets the split), whose timer is still pending after
      // a drag. pumpAndSettle is avoided on principle here (#101).
      await tester.pump(const Duration(milliseconds: 400));

      // Assert the content moved, not the persisted flex: a stored number
      // no layout reads would satisfy the latter and change nothing on
      // screen.
      expect(
        tester.getCenter(find.text('already staged')).dx,
        greaterThan(before),
        reason:
            'dragging right widens the unstaged side, pushing the '
            'staged side right',
      );
    });

    testWidgets('unified mode has no splitter between the sides', (
      WidgetTester tester,
    ) async {
      // Deliberate, not an oversight: unified is one scrollable holding
      // both sides, so there is no second pane to size.
      await pump(
        tester,
        unstaged: _file('still editing', added: true),
        staged: _file('already staged', added: true),
      );

      await tester.tap(find.text('unified'));
      await tester.pump();

      expect(find.byType(GbmSplitPane), findsNothing);
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
