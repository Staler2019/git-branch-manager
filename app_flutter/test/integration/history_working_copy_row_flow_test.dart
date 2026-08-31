// History's uncommitted-changes row, through the real containers.
//
// The widget tests next door feed `CommitDetailPanelCore` and
// `ChangedFilesPanelCore` their params by hand, which proves the two faces
// render -- never that anything produces those params. This file crosses that
// seam: it pumps the real `HistoryPage`, so `CommitDetailPanel` and
// `ChangedFilesPanel` resolve `workingCopyRowSelectedProvider` themselves, and
// the selection arrives the way a user makes it, by tapping the row.
//
// One correction to the round's own plan, recorded here because the plan said
// otherwise: selecting this row does **not** disable the commit context
// menu's Cherry-pick / Revert / Reset here. Those are 05-E items carrying the
// right-clicked row's own oid (`commit_menu_items.dart`), and nothing about
// them reads `selectedCommitProvider` -- only the two panels do. They are also
// squarely in the spec, on three separate pages (p5's 05-E submenu, p13's
// `MULTIACTS`, p6's dialog catalog), so nothing about them was ever in
// question.
//
// What really goes away is every 05-K action, because the changed-files list
// they hang off is replaced by the placeholder. **User-ratified**: under this
// row 05-K gets no dialog and no functionality, 「之後有需要再設計」.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_detail_panel.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

const int _kRowCount = 3;

String _oidAt(int i) => '${i.toRadixString(16).padLeft(4, '0')}${'a' * 36}';

GraphSnapshotView _graph() => GraphSnapshotView(
  rows: <GraphRow>[
    for (int i = 0; i < _kRowCount; i++)
      const GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 0,
        color: 0,
        flags: 0,
      ),
  ],
  oidsHex: <String>[for (int i = 0; i < _kRowCount; i++) _oidAt(i)],
  parentPool: const <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
  edges: const <GraphEdge>[],
);

CommitMeta _meta(String oid) => CommitMeta(
  oid: oid,
  tree: 'b' * 40,
  parents: const <String>[],
  author: const Signature(
    name: 'Ada Lovelace',
    email: 'a@b.c',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: const Signature(
    name: 'Ada Lovelace',
    email: 'a@b.c',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: 'Subject of ${oid.substring(0, 4)}',
  body: '',
  signedCommit: false,
);

ChangedFile _file(String path) => ChangedFile(
  path: path,
  oldPath: path,
  kind: FileChangeKind.modified,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'bbb',
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
);

WorkingCopyEntry _entry(String path) => WorkingCopyEntry(
  path: path,
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 1,
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

const String _kWorkingCopySentinel = 'WORKING COPY TAB';

Future<PumpedWorkspace> _pump(WidgetTester tester) async {
  final PumpedWorkspace pumped = await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: RepoSessionState(
      isOpen: true,
      graph: _graph(),
      commitMetaCache: <String, CommitMeta>{
        for (int i = 0; i < _kRowCount; i++) _oidAt(i): _meta(_oidAt(i)),
      },
      // The previously-selected commit's files. They must survive in the
      // provider, because the placeholder's whole job is to suppress a list
      // that is still there rather than one that emptied itself.
      commitFiles: <ChangedFile>[_file('lib/kept.dart')],
      workingCopyStatus: WorkingCopyStatus(
        entries: <WorkingCopyEntry>[
          _entry('lib/a.dart'),
          _entry('lib/b.dart'),
          _entry('lib/c.dart'),
        ],
      ),
    ),
    surfaceSize: const ui.Size(1600, 900),
    overrides: <Override>[
      commitSelectionProvider(_identity).overrideWith(
        (Ref ref) => ListSelection<String>(
          items: <String>[_oidAt(0)],
          anchor: _oidAt(0),
        ),
      ),
    ],
    historyBuilder: (context, state) => HistoryPage(identity: _identity),
    workingCopyBuilder: (context, state) =>
        const Scaffold(body: Center(child: Text(_kWorkingCopySentinel))),
  );
  await tester.pumpAndSettle();
  return pumped;
}

final Finder _row = find.byKey(const Key('history-working-copy-row'));

/// Scoped to the detail panel: a commit's subject is also drawn by its row in
/// the list, so an unscoped finder counts two and cannot tell which surface
/// changed.
Finder _inDetail(String text) => find.descendant(
  of: find.byType(CommitDetailPanel),
  matching: find.text(text),
);

void main() {
  testWidgets('tapping the row swaps both panels to the summary, and picking '
      'a commit again restores them', (WidgetTester tester) async {
    final PumpedWorkspace pumped = await _pump(tester);

    // Before: a real commit is selected and both panels say so.
    expect(_inDetail('Subject of 0000'), findsOneWidget);
    expect(find.text('lib/kept.dart'), findsOneWidget);

    await tester.tap(_row);
    await tester.pumpAndSettle();

    expect(
      pumped.container.read(selectedCommitProvider(_identity)),
      isNull,
      reason:
          'the row is not a commit, and this is what the one-commit '
          'surfaces gate on',
    );
    expect(find.text('3 changed files'), findsOneWidget);
    expect(find.text('Open in Working Copy'), findsOneWidget);
    expect(
      find.text('Uncommitted files are listed in the Working Copy tab'),
      findsOneWidget,
    );
    expect(
      find.text('lib/kept.dart'),
      findsNothing,
      reason:
          'commitFilesProvider still holds them -- History asks for no '
          'diff-tree against a row with no oid -- so the flag, not an empty '
          'list, has to suppress them',
    );
    expect(
      _inDetail('Subject of 0000'),
      findsNothing,
      reason:
          'the detail panel must not keep showing the commit that was '
          'selected a moment ago',
    );

    await tester.tap(find.byType(CommitRow).at(1));
    await tester.pumpAndSettle();

    expect(pumped.container.read(selectedCommitProvider(_identity)), _oidAt(1));
    expect(_inDetail('Subject of 0001'), findsOneWidget);
    expect(find.text('3 changed files'), findsNothing);
    expect(
      find.text('Uncommitted files are listed in the Working Copy tab'),
      findsNothing,
    );
  });

  testWidgets('the summary\'s one button lands on the Working Copy tab', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    await tester.tap(_row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in Working Copy'));
    await tester.pumpAndSettle();

    // `go`, not `push`: the Working Copy is a ShellRoute child, so a push
    // would stack it over History rather than switch tab to it. A sentinel
    // route rather than the real view, so this fails on the destination
    // being wrong and not on anything the real view needs.
    expect(find.text(_kWorkingCopySentinel), findsOneWidget);
    expect(find.byType(HistoryPage), findsNothing);
  });
}
