import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';

import '../../../support/pump_app.dart';

/// A const-friendly no-op, so a test case can build the board with `const`
/// and still pass the two required callbacks.
void _ignorePaths(List<String> _) {}

WorkingCopyEntry _entry({
  required String path,
  String oldPath = '',
  bool staged = false,
  bool hasUnstagedChange = false,
  bool untracked = false,
}) => WorkingCopyEntry(
  path: path,
  oldPath: oldPath,
  untracked: untracked,
  staged: staged,
  indexStatus: oldPath.isEmpty
      ? FileChangeKind.modified
      : FileChangeKind.renamed,
  hasUnstagedChange: hasUnstagedChange,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: 0,
  isSubmodule: false,
  isConflicted: false,
);

/// The paths whose row currently renders selected, read straight off the
/// [GbmRow]s -- set equality against this is the only assertion that can see
/// a range spanning the wrong rows. `containsAll` cannot.
Set<String> _selectedPaths(WidgetTester tester) {
  final Set<String> paths = <String>{};
  for (final GbmRow row in tester.widgetList<GbmRow>(find.byType(GbmRow))) {
    if (!row.selected) continue;
    // Read the first Text under the row rather than casting through the
    // row's widget shape: a layout change should red the layout test, not
    // every selection test at once.
    final Text label = tester
        .widgetList<Text>(
          find.descendant(of: find.byWidget(row), matching: find.byType(Text)),
        )
        .first;
    paths.add(label.data!);
  }
  return paths;
}

Future<void> _tapWithModifier(
  WidgetTester tester,
  Finder target,
  LogicalKeyboardKey? modifier,
) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  await tester.tap(target);
  await tester.pump();
  if (modifier != null) await tester.sendKeyUpEvent(modifier);
}

void main() {
  group('WorkingCopyBoard', () {
    final unstagedEntries = <WorkingCopyEntry>[
      const WorkingCopyEntry(
        path: 'lib/main.dart',
        oldPath: '',
        untracked: false,
        staged: false,
        indexStatus: FileChangeKind.modified,
        hasUnstagedChange: true,
        worktreeStatus: FileChangeKind.modified,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      ),
      const WorkingCopyEntry(
        path: 'lib/utils.dart',
        oldPath: '',
        untracked: false,
        staged: false,
        indexStatus: FileChangeKind.added,
        hasUnstagedChange: true,
        worktreeStatus: FileChangeKind.added,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      ),
    ];

    final stagedEntries = <WorkingCopyEntry>[
      const WorkingCopyEntry(
        path: 'pubspec.yaml',
        oldPath: '',
        untracked: false,
        staged: true,
        indexStatus: FileChangeKind.modified,
        hasUnstagedChange: false,
        worktreeStatus: FileChangeKind.modified,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      ),
    ];

    testWidgets('renders both columns with headers and entries', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.text('UNSTAGED'), findsOneWidget);
      expect(find.text('STAGED'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('lib/utils.dart'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);
    });

    testWidgets('shows file count in headers', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.text('2'), findsWidgets); // 2 unstaged + 1 staged
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('empty column shows placeholder', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: const [],
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.text('No unstaged changes'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);
    });

    testWidgets(
      'no checkbox anywhere -- not on a row, a column header, or a folder row',
      (tester) async {
        for (final FileListViewMode mode in FileListViewMode.values) {
          await pumpGbmWidget(
            tester,
            child: SizedBox(
              width: 800,
              height: 600,
              child: WorkingCopyBoard(
                unstagedEntries: unstagedEntries,
                stagedEntries: stagedEntries,
                mode: mode,
                onStageRequested: (_) {},
                onUnstageRequested: (_) {},
              ),
            ),
          );

          expect(
            find.byType(Checkbox),
            findsNothing,
            reason:
                'files change column by dragging; a checkbox reintroduces a '
                'second way to say the same thing (mode: $mode)',
          );
          expect(find.byIcon(Icons.drag_handle), findsNothing);
        }
      },
    );

    testWidgets('rows are GbmRow, so hover and selected come from the design '
        'system rather than a hand-rolled InkWell', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.byType(GbmRow), findsNWidgets(3));

      final Finder mainRow = find.ancestor(
        of: find.text('lib/main.dart'),
        matching: find.byType(GbmRow),
      );
      expect(tester.widget<GbmRow>(mainRow).selected, isFalse);

      await tester.tap(find.text('lib/main.dart'));
      await tester.pump();

      expect(
        tester.widget<GbmRow>(mainRow).selected,
        isTrue,
        reason:
            'a plain click selects the row it hit -- with the checkbox gone '
            'the selected background is the only thing that says so',
      );
    });

    testWidgets('tree mode makes the folder row itself draggable, carrying '
        'every file underneath it', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            mode: FileListViewMode.tree,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      // `byType` cannot name this one: the payload class is private to
      // working_copy_board.dart, and Draggable<_DraggedFiles> is a different
      // runtimeType from Draggable<Object>.
      final Finder folderRow = find.ancestor(
        of: find.byType(FileTreeFolderRow),
        matching: find.byWidgetPredicate((Widget w) => w is Draggable),
      );
      expect(
        folderRow,
        findsOneWidget,
        reason:
            'dragging a whole folder is what replaced the tri-state folder '
            'checkbox; without it the folder scope has no entry point at all',
      );
    });

    testWidgets('one file on both sides lights up in both columns at once', (
      tester,
    ) async {
      // A partly-staged file is a single entry that appears in both lists.
      final WorkingCopyEntry both = _entry(
        path: 'lib/main.dart',
        staged: true,
        hasUnstagedChange: true,
      );

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: <WorkingCopyEntry>[both],
            stagedEntries: <WorkingCopyEntry>[both],
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      await _tapWithModifier(tester, find.text('lib/main.dart').first, null);

      final Iterable<GbmRow> rows = tester.widgetList<GbmRow>(
        find.byType(GbmRow),
      );
      expect(rows.length, 2);
      expect(
        rows.where((GbmRow r) => r.selected).length,
        2,
        reason:
            'one selection set means clicking either row selects the file, '
            'not the row -- two per-column sets is how the sides disagree',
      );
    });

    testWidgets("a rename's two differently-named rows select together", (
      tester,
    ) async {
      // `git mv old new` staged, then the old name reappears in the work
      // tree: two rows, two names, one logical file.
      final WorkingCopyEntry stagedRename = _entry(
        path: 'lib/new.dart',
        oldPath: 'lib/old.dart',
        staged: true,
      );
      final WorkingCopyEntry worktreeOld = _entry(
        path: 'lib/old.dart',
        untracked: true,
        hasUnstagedChange: true,
      );

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: <WorkingCopyEntry>[worktreeOld],
            stagedEntries: <WorkingCopyEntry>[stagedRename],
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      await _tapWithModifier(tester, find.text('lib/new.dart'), null);

      expect(
        _selectedPaths(tester),
        <String>{'lib/new.dart', 'lib/old.dart'},
        reason:
            'path equality alone calls these two different files; only '
            'logicalFileKey pairs them',
      );
    });

    testWidgets('Shift+click ranges over the order the rows are painted in, '
        'not the order the status listed them', (tester) async {
      // FileTree.fromPaths groups lib/ together, so the painted order is
      // lib/a.dart, lib/b.dart, zz.txt -- while `entries` interleaves them.
      final List<WorkingCopyEntry> interleaved = <WorkingCopyEntry>[
        _entry(path: 'lib/a.dart', hasUnstagedChange: true),
        _entry(path: 'zz.txt', hasUnstagedChange: true),
        _entry(path: 'lib/b.dart', hasUnstagedChange: true),
      ];

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: interleaved,
            stagedEntries: const <WorkingCopyEntry>[],
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      await _tapWithModifier(tester, find.text('lib/a.dart'), null);
      await _tapWithModifier(
        tester,
        find.text('lib/b.dart'),
        LogicalKeyboardKey.shiftLeft,
      );

      expect(
        _selectedPaths(tester),
        <String>{'lib/a.dart', 'lib/b.dart'},
        reason:
            'zz.txt sits between them in `entries` but is painted after '
            'both; ranging over entry order would sweep it in',
      );
    });

    testWidgets('Shift+click with the anchor in the other column selects the '
        'clicked row instead of doing nothing', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      await _tapWithModifier(tester, find.text('lib/main.dart'), null);
      await _tapWithModifier(
        tester,
        find.text('pubspec.yaml'),
        LogicalKeyboardKey.shiftLeft,
      );

      expect(
        _selectedPaths(tester),
        <String>{'pubspec.yaml'},
        reason:
            'there is no range between two independent columns; a silent '
            'no-op leaves the user with nothing on screen to explain it',
      );
    });

    testWidgets('each column reads its own side of a partly-staged file', (
      tester,
    ) async {
      // Four independent numbers on one entry: the work tree has +3/-1 that
      // is not staged yet, the index has +7/-2 that is.
      const WorkingCopyEntry partly = WorkingCopyEntry(
        path: 'lib/main.dart',
        oldPath: '',
        untracked: false,
        staged: true,
        indexStatus: FileChangeKind.modified,
        hasUnstagedChange: true,
        worktreeStatus: FileChangeKind.modified,
        unstagedAdded: 3,
        unstagedRemoved: 1,
        stagedAdded: 7,
        stagedRemoved: 2,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      );

      await pumpGbmWidget(
        tester,
        child: const SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: <WorkingCopyEntry>[partly],
            stagedEntries: <WorkingCopyEntry>[partly],
            onStageRequested: _ignorePaths,
            onUnstageRequested: _ignorePaths,
          ),
        ),
      );

      expect(find.text('+3'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
      expect(find.text('+7'), findsOneWidget);
      expect(find.text('-2'), findsOneWidget);
    });

    testWidgets('a zero count draws no badge at all', (tester) async {
      // Binary blobs, mode-only changes and over-cap untracked files all
      // arrive as 0, which means "not measured" -- a `+0` would claim a
      // measurement that never happened.
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.byType(GbmBadge), findsNothing);
      expect(find.textContaining('+0'), findsNothing);
      expect(find.textContaining('-0'), findsNothing);
    });

    testWidgets('badges still fit at the column splitter\'s minExtent', (
      tester,
    ) async {
      // The default 800x600 test canvas hides width overflow: the real floor
      // is GbmLayout.splitterWcColumns.minExtent per column, and the rows now
      // carry two badges they did not before.
      const WorkingCopyEntry longPath = WorkingCopyEntry(
        path: 'lib/features/working_copy/widgets/working_copy_board.dart',
        oldPath: '',
        untracked: false,
        staged: false,
        indexStatus: FileChangeKind.modified,
        hasUnstagedChange: true,
        worktreeStatus: FileChangeKind.modified,
        unstagedAdded: 128,
        unstagedRemoved: 256,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      );

      final double boardWidth = GbmLayout.splitterWcColumns.minExtent * 2;
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: boardWidth,
          height: 600,
          child: const WorkingCopyBoard(
            unstagedEntries: <WorkingCopyEntry>[longPath],
            stagedEntries: <WorkingCopyEntry>[],
            onStageRequested: _ignorePaths,
            onUnstageRequested: _ignorePaths,
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // Not just "no exception": Expanded happily collapses its child to zero
      // and calls that a fit. And the bound has to be the *row*, not the
      // board -- a badge can run off the end of a 200px column and still sit
      // well inside a 400px board, so board.right would pass with the layout
      // broken.
      final Rect row = tester.getRect(find.byType(GbmRow));
      for (final String label in <String>['+128', '-256']) {
        final Rect badge = tester.getRect(find.text(label));
        expect(badge.width, greaterThan(0), reason: '$label collapsed to zero');
        expect(
          badge.right,
          lessThanOrEqualTo(row.right),
          reason: '$label is painted past the right edge of its own row',
        );
      }
      expect(
        tester.getRect(find.text(longPath.path)).width,
        greaterThan(0),
        reason: 'the file name must not be squeezed out by the two badges',
      );
    });
  });
}
