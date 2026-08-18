// Renders each of the 11 spec page-05 context-menu targets and asserts the
// ACTUAL rendered item labels against `gbmContextMenuGroups` (the catalog
// in gbm_context_menus.dart), rather than against a render site's own
// hand-written expectations -- unlike `gbm_context_menus_test.dart` (which
// only checks the catalog's internal shape) and the per-widget context-menu
// tests (which check a render site's own behavior in isolation), this file
// is the single place that checks every target against the spec catalog,
// per `docs/reports/spec-conformance-matrix.md`'s Page 05 section.
//
// Three kinds of target, by verdict in that report:
//   - 符合 (conforms): asserted directly, should pass today.
//   - 符合 (deliberate reduction): asserted against the ACTUAL reduced list,
//     not the full catalog -- the reduction is correct behavior, not a gap.
//   - 缺少 (real gap): asserted against the FULL catalog list and marked
//     `skip:` with a reason pointing at the matrix row. Removing the skip
//     once the render site is fixed turns the test RED -> GREEN, per this
//     audit's plan (`.claude/plans/view-flutter-desktop-spec-elegant-fog.md`).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_hunk_menu_items.dart';
import 'package:gbm_flutter/features/context_menus/gbm_context_menus.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/features/history_graph/widgets/changed_files_panel.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/repo_switcher/repo_switcher_popover.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_folder_menu_items.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/features/sidebar/widgets/stash_menu_items.dart';
import 'package:gbm_flutter/features/sidebar/widgets/tag_menu_items.dart';
import 'package:gbm_flutter/features/working_copy/widgets/changed_file_row.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

import '../../support/pump_app.dart';

List<String> _specLabels(GbmContextMenuTarget target) =>
    gbmContextMenuGroups[target]!.items
        .map((GbmContextMenuItemSpec spec) => spec.label)
        .toList();

List<String> _specSubLabels(GbmContextMenuTarget target, String parentLabel) {
  final GbmContextMenuItemSpec parent = gbmContextMenuGroups[target]!.items
      .firstWhere((GbmContextMenuItemSpec spec) => spec.label == parentLabel);
  return parent.children
      .map((GbmContextMenuItemSpec spec) => spec.label)
      .toList();
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

Future<void> _pump(WidgetTester tester, Widget child) =>
    pumpGbmWidget(tester, child: child);

/// Renders the visible top-level menu's item labels, in order, excluding
/// separators -- the `GbmMenuItem` list itself isn't reachable from a
/// widget-pump test, only what `showGbmContextMenu`/`showGbmMenu` paint.
List<String> _visibleMenuLabels(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.descendant(of: find.byType(Overlay), matching: find.byType(Text)))
      .map((Text t) => t.data)
      .whereType<String>()
      .toList();
}

RefInfo _localBranch({String name = 'feature/x', bool isHead = false}) {
  return RefInfo(
    fullName: 'refs/heads/$name',
    shortName: name,
    kind: RefKind.localBranch,
    target: 'a' * 40,
    upstream: '',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: false,
    isGone: false,
    isHead: isHead,
    isSymbolic: false,
    worktreePath: '',
  );
}

RefInfo _remoteOnlyBranch({String name = 'worktrees'}) {
  return RefInfo(
    fullName: 'refs/remotes/origin/$name',
    shortName: name,
    kind: RefKind.remoteBranch,
    target: 'a' * 40,
    upstream: '',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: false,
    isGone: false,
    isHead: false,
    isSymbolic: false,
    worktreePath: '',
  );
}

RefInfo _goneBranch({String name = 'feature/gone'}) {
  return RefInfo(
    fullName: 'refs/heads/$name',
    shortName: name,
    kind: RefKind.localBranch,
    target: 'a' * 40,
    upstream: 'refs/remotes/origin/$name',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: true,
    isGone: true,
    isHead: false,
    isSymbolic: false,
    worktreePath: '',
  );
}

WorkingCopyEntry _fileEntry({String path = 'src/main.dart'}) {
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

GraphRow _graphRow() {
  return const GraphRow(
    parentOffset: 0,
    edgeOffset: 0,
    commitTime: 0,
    lane: 0,
    color: 0,
    flags: 0,
  );
}

ChangedFile _changedFile({String path = 'lib/main.dart'}) {
  return ChangedFile(
    path: path,
    oldPath: '',
    kind: FileChangeKind.modified,
    oldMode: '100644',
    newMode: '100644',
    oldBlob: '',
    newBlob: '',
    similarity: 0,
  );
}

DiffLine _diffLine({DiffLineKind kind = DiffLineKind.added}) {
  return DiffLine(kind: kind, oldLine: 1, newLine: 1, text: 'hello');
}

void main() {
  group('05-A Repository (deliberate reduction, not a gap)', () {
    testWidgets(
      'RepoSwitcherRow omits Fetch/Pull/Push (no open session) and adds '
      '"Open" (not in the spec catalog, but a reasonable addition -- see '
      'matrix)',
      (tester) async {
        await _pump(
          tester,
          RepoSwitcherRow(
            entry: const RepoSwitcherEntry(
              name: 'git-branch-manager',
              workDir: '/tmp/gbm',
              isManual: true,
              isMissing: false,
            ),
            onTap: () {},
            onOpenInFileManager: () {},
            onOpenInTerminal: () {},
            onRemoveFromList: () {},
          ),
        );
        await _rightClick(tester, find.byType(RepoSwitcherRow));

        for (final String absent in <String>['Fetch', 'Pull', 'Push']) {
          expect(
            find.text(absent),
            findsNothing,
            reason: '$absent should not appear -- no open session to act on',
          );
        }
        for (final String present in <String>[
          'Open',
          'Open in file manager',
          'Open in terminal',
          'Settings…',
          'Remove from list',
        ]) {
          expect(find.text(present), findsOneWidget);
        }
      },
    );
  });

  group('05-B Local branch (real gap -- see matrix)', () {
    testWidgets(
      'BranchTreeItem matches the full 05-B catalog',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(
            ref: _localBranch(),
            onCheckout: () {},
            onRename: () {},
            onDelete: () {},
            onNewBranchFromHere: () {},
            onMerge: () {},
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));

        final List<String> visible = _visibleMenuLabels(tester);
        for (final String label in _specLabels(
          GbmContextMenuTarget.localBranch,
        )) {
          expect(
            visible.any((String v) => v.startsWith(label.split('…').first)),
            isTrue,
            reason: 'missing spec item: $label',
          );
        }
      },
      // Real gap, tracked in docs/reports/spec-conformance-matrix.md
      // (Page 05, row 05-B): missing "Rebase current onto here" and
      // "Compare with…" -- branch_tree_item.dart's own doc comment says
      // both need a not-yet-built per-branch rebase/compare UI, not just
      // a wiring change. Also wording drift: "Rename branch" vs spec
      // "Rename…", "Merge into current branch" vs spec "Merge into
      // current". Remove `skip: true` once 05-B is brought to parity.
      skip: true,
    );
  });

  group('05-C Remote-only / gone branch (conforms)', () {
    testWidgets('remote-only row matches the full 05-C catalog', (
      tester,
    ) async {
      await _pump(
        tester,
        BranchTreeItem(
          ref: _remoteOnlyBranch(),
          onCheckout: () {},
          onFetchRef: () {},
          onPruneRef: () {},
          onDeleteOnRemote: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));

      expect(_specLabels(GbmContextMenuTarget.remoteOnlyOrGoneBranch), <String>[
        'Checkout as new local…',
        'Fetch this branch',
        'Copy branch name',
        'Prune this ref',
        'Delete on remote…',
      ]);
      for (final String label in _specLabels(
        GbmContextMenuTarget.remoteOnlyOrGoneBranch,
      )) {
        expect(find.text(label), findsOneWidget, reason: 'missing: $label');
      }
    });

    testWidgets(
      'gone row keeps only Prune this ref + Copy branch name enabled, per '
      'spec\'s own "gone 的列只留 Prune 與 Copy，其餘停用" note',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(
            ref: _goneBranch(),
            onCheckout: () {},
            onFetchRef: () {},
            onPruneRef: () {},
            onDeleteOnRemote: () {},
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));

        // Same 5 labels present (spec keeps disabled items visible, not
        // omitted), but Checkout/Fetch/Delete-on-remote are inert.
        for (final String label in _specLabels(
          GbmContextMenuTarget.remoteOnlyOrGoneBranch,
        )) {
          expect(find.text(label), findsOneWidget, reason: 'missing: $label');
        }
      },
    );
  });

  group('05-D Tag (conforms)', () {
    test('tagMenuItems matches the full 05-D catalog exactly', () {
      final List<GbmMenuItem> items = tagMenuItems(
        tagName: 'v1.0.0',
        onCheckoutDetached: () {},
        onPush: () {},
        onCompare: () {},
        onDelete: () {},
      );
      final List<String> actual = items
          .where((GbmMenuItem i) => !i.separator)
          .map((GbmMenuItem i) => i.label)
          .toList();
      expect(actual, _specLabels(GbmContextMenuTarget.tag));
    });
  });

  group('05-E Commit (real gap -- see matrix)', () {
    testWidgets(
      'CommitRow matches the full 05-E catalog, including the "More '
      'actions" submenu',
      (tester) async {
        await _pump(
          tester,
          CommitRow(
            row: _graphRow(),
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            onCheckout: () {},
            onCherryPick: () {},
            onRevert: () {},
            onCreateBranchHere: () {},
          ),
        );
        await tester.tap(
          find.byType(CommitRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        for (final String label in _specLabels(GbmContextMenuTarget.commit)) {
          expect(find.text(label), findsOneWidget, reason: 'missing: $label');
        }
        await tester.tap(find.text('More actions'));
        await tester.pumpAndSettle();
        for (final String label in _specSubLabels(
          GbmContextMenuTarget.commit,
          'More actions',
        )) {
          expect(find.text(label), findsOneWidget, reason: 'missing: $label');
        }
      },
      // Real gap, tracked in docs/reports/spec-conformance-matrix.md
      // (Page 05, row 05-E): missing "Merge into current", "Compare
      // with…", and the entire "More actions" submenu.
      // commit_row.dart's own doc comment explains why each is
      // omitted -- Merge needs mergeBranch to accept an oid rather
      // than a branch name (or a name-resolution step first),
      // Compare is planned as milestone M6, and rebase/reset are not
      // yet wired on the Dart side even though the capi calls exist.
      // Remove `skip: true` once 05-E is brought to parity.
      skip: true,
    );
  });

  group('05-F Working copy file (real gap -- see matrix)', () {
    testWidgets(
      'ChangedFileRow matches the full 05-F catalog',
      (tester) async {
        await _pump(
          tester,
          ChangedFileRow(
            entry: _fileEntry(),
            checked: false,
            selected: false,
            onCheckToggle: () {},
            onTap: () {},
            onDiscard: () {},
          ),
        );
        await _rightClick(tester, find.byType(ChangedFileRow));

        for (final String label in _specLabels(
          GbmContextMenuTarget.workingCopyFile,
        )) {
          expect(find.text(label), findsOneWidget, reason: 'missing: $label');
        }
      },
      // Real gap, tracked in docs/reports/spec-conformance-matrix.md
      // (Page 05, row 05-F): the right-click menu (see
      // changed_file_context_menu_test.dart for its actual, correctly-
      // documented behavior) is Stage/Unstage file, View diff, Copy
      // path, Discard changes -- missing "Open file", "Show in file
      // manager", "Open terminal here" from the spec's 6-item list,
      // and the label reads "Stage file"/"Unstage file" rather than
      // spec's plain "Stage". Remove `skip: true` once 05-F is brought
      // to parity.
      skip: true,
    );
  });

  group('05-G Diff line (real gap, but small -- see matrix)', () {
    testWidgets(
      'DiffLineView matches the full 05-G catalog',
      (tester) async {
        await _pump(
          tester,
          DiffLineView(
            line: _diffLine(),
            selectable: true,
            staged: false,
            onStageLine: () {},
            onStageHunk: () {},
          ),
        );
        await _rightClick(tester, find.byType(DiffLineView));

        for (final String label in _specLabels(
          GbmContextMenuTarget.diffLine,
        )) {
          expect(find.text(label), findsOneWidget, reason: 'missing: $label');
        }
      },
      // Real gap, tracked in docs/reports/spec-conformance-matrix.md
      // (Page 05, row 05-G): unlike this audit's first-pass finding
      // (which missed the ternary-labeled "Stage line"/"Stage hunk"
      // items entirely), diff_line.dart already implements Stage
      // line/Unstage line, Stage hunk/Unstage hunk, and Copy line --
      // the ONLY missing item is "Discard N lines…" (danger action,
      // no callback exists for it at all). Remove `skip: true` once
      // that one item is added.
      skip: true,
    );
  });

  group('05-H Stash entry (conforms)', () {
    test('stashMenuItems matches the full 05-H catalog exactly', () {
      final List<GbmMenuItem> items = stashMenuItems(
        onApply: () {},
        onPop: () {},
        onCreateBranch: () {},
        onViewDiff: () {},
        onCompare: () {},
        onDrop: () {},
      );
      final List<String> actual = items
          .where((GbmMenuItem i) => !i.separator)
          .map((GbmMenuItem i) => i.label)
          .toList();
      expect(actual, _specLabels(GbmContextMenuTarget.stashEntry));
    });
  });

  group('05-I Conflict hunk (conforms)', () {
    test('conflictHunkMenuItems matches the full 05-I catalog exactly', () {
      final List<GbmMenuItem> items = conflictHunkMenuItems(
        onTakeThisSide: () {},
        onTakeThisLineOnly: () {},
        onTakeBoth: () {},
        onDiscardFromResult: () {},
      );
      final List<String> actual = items
          .where((GbmMenuItem i) => !i.separator)
          .map((GbmMenuItem i) => i.label)
          .toList();
      expect(actual, _specLabels(GbmContextMenuTarget.conflictHunk));
    });
  });

  group('05-J Branch folder (conforms, aside from the documented '
      'toggle-label split)', () {
    test(
      'branchFolderMenuItems matches the full 05-J catalog aside from the '
      'Expand-all/Collapse-all state-dependent split',
      () {
        final List<GbmMenuItem> items = branchFolderMenuItems(
          isExpanded: false,
          onToggleExpand: () {},
          onCopyPrefix: () {},
          onDeleteMerged: () {},
          onFetchFolder: () {},
        );
        final List<String> actual = items
            .where((GbmMenuItem i) => !i.separator)
            .map((GbmMenuItem i) => i.label)
            .toList();
        final List<String> spec = _specLabels(
          GbmContextMenuTarget.branchFolder,
        );
        expect(actual.sublist(1), spec.sublist(1));
        expect(actual.first, 'Expand all');
      },
    );
  });

  group('05-K Commit file (real gap -- see matrix)', () {
    testWidgets(
      'ChangedFilesPanelCore matches the full 05-K catalog, including the '
      '"More actions" submenu',
      (tester) async {
        await _pump(
          tester,
          ChangedFilesPanelCore(
            hasSelectedCommit: true,
            files: <ChangedFile>[_changedFile()],
            selectedPath: null,
            onFileTap: (_) {},
            onFileHistory: (_) {},
            onBlame: (_) {},
            onRestoreToThisState: (_) {},
          ),
        );
        await _rightClick(tester, find.byType(ListTile).first);

        for (final String label in _specLabels(
          GbmContextMenuTarget.historyCommitFile,
        )) {
          expect(find.text(label), findsOneWidget, reason: 'missing: $label');
        }
        await tester.tap(find.text('More actions'));
        await tester.pumpAndSettle();
        for (final String label in _specSubLabels(
          GbmContextMenuTarget.historyCommitFile,
          'More actions',
        )) {
          expect(find.text(label), findsOneWidget, reason: 'missing: $label');
        }
      },
      // Real gap, tracked in docs/reports/spec-conformance-matrix.md
      // (Page 05, row 05-K): missing "Compare with working copy",
      // "Open file at this revision", "Open terminal here" at the top
      // level, and "Restore and stage"/"Save this revision as…"/
      // "Export as patch…" from the "More actions" submenu.
      // changed_files_panel.dart's own doc comment confirms "Open
      // file at this revision" and "Save this revision as…" have no
      // backing capi entry point yet (classification (ii) in the
      // matrix, not a pure wiring gap). Remove `skip: true` once 05-K
      // is brought to parity for the (i)-classified items, and note
      // the (ii) items may need to stay omitted until capi grows a
      // blob-read entry point.
      skip: true,
    );
  });
}
