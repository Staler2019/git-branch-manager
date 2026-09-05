import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';
import 'package:gbm_flutter/widgets/file_list_mode_toggle_button.dart';
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

/// The paths whose row currently renders selected, read off each [GbmRow]'s
/// own key -- set equality against this is the only assertion that can see a
/// range spanning the wrong rows. `containsAll` cannot.
///
/// The key, not the row's first `Text`. That is what this used to read, and
/// it was a proxy that stopped being one the moment tree mode started
/// labelling a leaf with only the segment its folder rows had not already
/// written: the row for `lib/a.dart` now draws `a.dart`, which is
/// indistinguishable from a root-level `a.dart`. `working_copy_board.dart`
/// composes the key from `entry.path` itself, so it is the row's identity
/// rather than a rendering of it.
Set<String> _selectedPaths(WidgetTester tester) {
  final Set<String> paths = <String>{};
  for (final GbmRow row in tester.widgetList<GbmRow>(find.byType(GbmRow))) {
    if (!row.selected) continue;
    final String key = (row.key! as ValueKey<String>).value;
    // 'wc-file-{staged|unstaged}-{path}-selected'; every row collected here
    // is selected, so the suffix is always present.
    final String withoutSuffix = key.substring(
      0,
      key.length - '-selected'.length,
    );
    final int pathStart = withoutSuffix.indexOf('-', 'wc-file-'.length) + 1;
    paths.add(withoutSuffix.substring(pathStart));
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

      expect(find.text('Unstaged \u00b7 2'), findsOneWidget);
      expect(find.text('Staged \u00b7 1'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('lib/utils.dart'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);
    });

    // 「把水平 unstaged-staged file list 改成左側垂直，unstaged 一樣在上」.
    // Asserted on the two headers' rects against each other rather than
    // against any constant -- a finder proves existence, not position, and
    // the divider's own default is not what is being pinned here.
    testWidgets('the two columns are stacked, Unstaged on top', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: _ignorePaths,
            onUnstageRequested: _ignorePaths,
          ),
        ),
      );

      final Rect unstaged = tester.getRect(find.text('Unstaged · 2'));
      final Rect staged = tester.getRect(find.text('Staged · 1'));

      // Stacked, not side by side: the two headers start at the same x.
      // Side by side they would start at *different* x and the same y, so
      // this pair of assertions is what tells the two arrangements apart --
      // "Unstaged is above Staged" alone is vacuously true of a row whose
      // two headers share a baseline only by rounding.
      expect(unstaged.left, equals(staged.left));
      expect(unstaged.bottom, lessThanOrEqualTo(staged.top));
    });

    // Stacking put a floor under a column's *height* where there had only
    // ever been one under its width, and the column is
    // `Column[ header(26, non-flex), Expanded(list), dropHint(non-flex) ]`.
    // RenderFlex lays its non-flex children out first and divides only what
    // is left, so the Expanded list cannot rescue an overflow the header and
    // the hint cause between them -- which is the whole reason
    // `splitterWcStack.minExtent` is 96 rather than the 78px of exact
    // constants underneath it.
    testWidgets('a column at its height floor does not overflow', (
      tester,
    ) async {
      // Each pane gets half of what is left after the divider. 5 is
      // split_pane.dart's own `_kDividerWidth`, which is private -- if it
      // ever changes this test starts squeezing the panes below their floor
      // and GbmSplitPane's clamp overflows instead, which is a different and
      // equally visible red rather than a silent pass.
      //
      // This test was green the moment it was written, because the floor it
      // checks was set in the same round. What makes it non-vacuous is the
      // bisection: lowering `splitterWcStack.minExtent` reddens it at 85 and
      // passes at 86, and at 78 -- the exact-constant part of the floor --
      // RenderFlex reports "overflowed by 8.0 pixels on the bottom". So 86
      // is the real floor and the shipped 96 has 10px of headroom.
      final double boardHeight = GbmLayout.splitterWcStack.minExtent * 2 + 5;

      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: GbmLayout.splitterWcFiles.minExtent,
          height: boardHeight,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: _ignorePaths,
            onUnstageRequested: _ignorePaths,
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // Not enough on its own: an Expanded satisfies "no overflow" while
      // collapsing its child to zero height, and RenderFlex only reports
      // main-axis overflow anyway. So assert the two non-flex children are
      // still really drawn, with height.
      expect(tester.getRect(find.text('Unstaged · 2')).height, greaterThan(0));
      expect(
        tester.getRect(find.textContaining('= stage')).height,
        greaterThan(0),
      );
    });

    // Nothing anywhere asserted that a drop actually stages: the widget
    // tests only checked that a `Draggable` exists, and the device-tier
    // commit flow was still tapping a checkbox that 變體 B deleted. With
    // dragging now the *only* way a file changes side, an unexercised drop
    // is an unexercised product.
    testWidgets('dropping a row on the Staged column stages that file', (
      tester,
    ) async {
      final List<List<String>> staged = <List<String>>[];
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (List<String> paths) => staged.add(paths),
            onUnstageRequested: _ignorePaths,
          ),
        ),
      );

      final Offset from = tester.getCenter(find.text('lib/main.dart'));
      final Offset to = tester.getCenter(find.text('pubspec.yaml'));

      final TestGesture gesture = await tester.startGesture(from);
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Counted, not `.any`: a drop dispatched twice would stage the file
      // and then stage it again, which is the regression shape this repo
      // has recorded before.
      expect(staged.length, 1);
      expect(staged.single, <String>['lib/main.dart']);
    });

    // The case a real repository starts in: nothing staged yet. The empty
    // column used to render its "No staged changes" placeholder *instead of*
    // the DragTarget, so with no checkbox anywhere there was no way at all
    // to stage the first file by dragging -- the only way 變體 B leaves.
    testWidgets('an empty Staged column still accepts a drop', (tester) async {
      final List<List<String>> staged = <List<String>>[];
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: const <WorkingCopyEntry>[],
            onStageRequested: (List<String> paths) => staged.add(paths),
            onUnstageRequested: _ignorePaths,
          ),
        ),
      );

      expect(find.text('No staged changes'), findsOneWidget);

      final Offset from = tester.getCenter(find.text('lib/main.dart'));
      final Offset to = tester.getCenter(find.text('No staged changes'));

      final TestGesture gesture = await tester.startGesture(from);
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(staged.length, 1);
      expect(staged.single, <String>['lib/main.dart']);
    });

    testWidgets('the list/tree switch sits on the Unstaged header, once for '
        'the whole board', (tester) async {
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

      // P03-10's note enumerates "Working Copy 兩欄" as one subject of the
      // one shared preference, and the mockup draws the switch on the
      // Unstaged header only -- a second copy would be two controls for one
      // global setting.
      expect(find.byType(FileListModeToggleButton), findsOneWidget);
      // Which column it belongs to is asserted against the *other* column's
      // header, not against the board's own centre line. The centre-line
      // form ("it is in the left half") was a proxy that only worked while
      // the two columns sat side by side; once they were stacked both spanned
      // the full width and the switch measured at x=771 on the Unstaged
      // header -- correct, and failing an assertion that had stopped
      // describing the claim.
      expect(
        tester.getRect(find.byType(FileListModeToggleButton)).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Staged · 1')).top),
        reason: 'it belongs to the Unstaged column, which is the upper one',
      );
    });

    testWidgets('the Unstaged column says how files change side, since no row '
        'has a checkbox any more', (tester) async {
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

      expect(
        find.text('\u62d6\u66f3\u6a94\u6848\u5230\u4e0b\u6b04 = stage'),
        findsOneWidget,
      );
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

    // The two tests below are one claim in two modes: a range spans the rows
    // as *painted*, and the two modes paint different orders. They replace a
    // single test that pumped the default (list) mode while asserting tree
    // order, on the strength of a comment claiming both modes rendered
    // through FileTree.fromPaths. They do not: list mode hands `items`
    // straight to a ListView (see FileListModeSwitcher.build).
    final List<WorkingCopyEntry> interleaved = <WorkingCopyEntry>[
      _entry(path: 'lib/a.dart', hasUnstagedChange: true),
      _entry(path: 'zz.txt', hasUnstagedChange: true),
      _entry(path: 'lib/b.dart', hasUnstagedChange: true),
    ];

    testWidgets('in list mode a range spans the entry order, which is what '
        'list mode paints', (tester) async {
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
        <String>{'lib/a.dart', 'zz.txt', 'lib/b.dart'},
        reason:
            'zz.txt is painted between the two the user dragged across, so '
            'it is inside the range they drew; ranging over tree order here '
            'would skip a row that is visibly between them',
      );
    });

    testWidgets('in tree mode a range spans the tree order, which is what '
        'tree mode paints', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            mode: FileListViewMode.tree,
            unstagedEntries: interleaved,
            stagedEntries: const <WorkingCopyEntry>[],
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      // lib/ collapses to one folder row, so open it before ranging -- the
      // leaves have to be on screen for a range across them to mean anything.
      await tester.tap(find.byType(FileTreeFolderRow));
      await tester.pumpAndSettle();

      // The leaves are labelled `a.dart` / `b.dart` here, not `lib/a.dart`:
      // the `lib` folder row above them already carries the prefix. The
      // *assertion* is still on the full paths, because `_selectedPaths`
      // reads each row's key rather than the text it draws.
      await _tapWithModifier(tester, find.text('a.dart'), null);
      await _tapWithModifier(
        tester,
        find.text('b.dart'),
        LogicalKeyboardKey.shiftLeft,
      );

      expect(
        _selectedPaths(tester),
        <String>{'lib/a.dart', 'lib/b.dart'},
        reason:
            'the tree groups lib/ together, so zz.txt is painted after both '
            'and sits outside the range the user drew',
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
      // is GbmLayout.splitterWcFiles.minExtent for the whole board, and the
      // rows now carry two badges they did not before.
      //
      // It used to read `splitterWcColumns.minExtent * 2` -- two columns
      // side by side, each with its own width floor. Stacked, both columns
      // are as wide as the board, and the board is the fixed pane of the
      // files-vs-diff divider, so its floor is that divider's `minExtent`
      // and there is no `* 2`. The canvas is *narrower* than before (180
      // against 400), which makes this a stricter test, not a looser one.
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

      final double boardWidth = GbmLayout.splitterWcFiles.minExtent;
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
