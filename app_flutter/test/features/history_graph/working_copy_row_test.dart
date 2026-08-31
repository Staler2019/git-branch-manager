// History's uncommitted-changes row: the pinned header above the commit list.
//
// It is deliberately **not** a list item. Prepending a row to the ListView
// would shift every index the graph's edge lookups, span index and selection
// ranges are keyed on -- `UnfilteredRowIndices` is an O(1) identity view for
// exactly the commonest case -- so the row lives above the scrollable and the
// list is untouched. These tests pin both halves: that it appears, and that
// nothing inside the list moved.
//
// It also has no spec entry: the 21-page spec has no uncommitted row anywhere
// (searched 未提交 / 虛擬 / uncommitted / 工作區, and `spec_logic.js`'s own
// History mock starts at a real commit). This is a user-requested addition,
// like the soft-wrap preference, not a conformance item.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_column_painter.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

final List<String> _oids = <String>[
  for (final String seed in <String>['a', 'b', 'c']) seed * 40,
];

GraphRow _row() => const GraphRow(
  parentOffset: 0,
  edgeOffset: 0,
  commitTime: 0,
  lane: 0,
  color: 0,
  flags: 0,
);

CommitMeta _meta(String oid) {
  const Signature author = Signature(
    name: 'Tester',
    email: 'tester@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  );
  return CommitMeta(
    oid: oid,
    tree: '',
    parents: const <String>[],
    author: author,
    committer: author,
    subject: 'subject ${oid.substring(0, 4)}',
    body: '',
    signedCommit: false,
  );
}

WorkingCopyEntry _entry(String path) =>
    WorkingCopyEntry.fromJson(<String, dynamic>{
      'path': path,
      'staged': false,
      'untracked': false,
      'hasUnstagedChange': true,
      'worktreeStatus': 'modified',
      'unstagedAdded': 1,
      'unstagedRemoved': 0,
      'stagedAdded': 0,
      'stagedRemoved': 0,
      'conflict': 'none',
      'ancestorBlob': '',
      'oursBlob': '',
      'theirsBlob': '',
      'similarity': 0,
      'isSubmodule': false,
      'isConflicted': false,
      'oldPath': '',
    });

RepoSessionState _state({required int pendingFiles}) => RepoSessionState(
  isOpen: true,
  graph: GraphSnapshotView(
    rows: <GraphRow>[for (final _ in _oids) _row()],
    oidsHex: _oids,
    parentPool: const <int>[],
    laneCount: 1,
    complete: true,
    truncated: false,
  ),
  commitMetaCache: <String, CommitMeta>{
    for (final String oid in _oids) oid: _meta(oid),
  },
  workingCopyStatus: WorkingCopyStatus(
    entries: <WorkingCopyEntry>[
      for (int i = 0; i < pendingFiles; i++) _entry('file$i.txt'),
    ],
  ),
);

late ProviderContainer _container;

Future<void> _pump(WidgetTester tester, {required int pendingFiles}) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    _state(pendingFiles: pendingFiles),
  );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  _container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(_identity).overrideWith((ref) => fake),
    ],
  );
  addTearDown(_container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(body: CommitGraphView(identity: _identity)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final Finder _workingCopyRow = find.byKey(
  const Key('history-working-copy-row'),
);

void main() {
  testWidgets('a clean working copy draws no row', (WidgetTester tester) async {
    await _pump(tester, pendingFiles: 0);
    expect(_workingCopyRow, findsNothing);
  });

  testWidgets('a dirty working copy draws one row naming the file count', (
    WidgetTester tester,
  ) async {
    await _pump(tester, pendingFiles: 3);

    expect(_workingCopyRow, findsOneWidget);
    expect(
      find.descendant(of: _workingCopyRow, matching: find.text('3')),
      findsOneWidget,
      reason:
          'the count comes from WorkingCopyStatus.pendingChangeCount, the '
          'same getter the Working Copy tab badge reads',
    );
  });

  testWidgets('the row sits above the list, not inside it', (
    WidgetTester tester,
  ) async {
    await _pump(tester, pendingFiles: 2);

    expect(
      find.byType(CommitRow),
      findsNWidgets(_oids.length),
      reason:
          'prepending to the ListView would shift every row index the '
          'graph edge lookups and selection ranges are keyed on',
    );
    expect(
      tester.getRect(_workingCopyRow).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(CommitRow).first).top),
      reason:
          'asserted against the first commit row rather than a pixel '
          'constant -- a finder proves existence, never position',
    );
  });

  testWidgets('its dot sits in lane 0, aligned with the commit below it', (
    WidgetTester tester,
  ) async {
    await _pump(tester, pendingFiles: 1);

    final Finder dot = find.byKey(const Key('history-working-copy-dot'));
    expect(dot, findsOneWidget);
    // `kGraphLaneInset` rather than a pixel literal, and imported from the
    // painter the commit rows below use: lane 0's centre is the inset plus
    // zero pitches, so if that constant moves both the row and the commits
    // move with it. A number typed in here would pin the two apart.
    expect(
      tester.getCenter(dot).dx - tester.getRect(_workingCopyRow).left,
      moreOrLessEquals(kGraphLaneInset, epsilon: 0.5),
      reason:
          'lane 0 is a single column: the row hands off to the commit '
          'below it, so its dot must sit where a lane-0 dot sits',
    );
  });

  testWidgets('selecting it deselects any commit, so commit actions cannot '
      'act on it', (WidgetTester tester) async {
    await _pump(tester, pendingFiles: 1);

    // Start from a real commit selection, so the assertion below cannot pass
    // merely because nothing was ever selected.
    _container
        .read(commitSelectionProvider(_identity).notifier)
        .state = ListSelection<String>(
      items: <String>[_oids.first],
      anchor: _oids.first,
    );
    await tester.pumpAndSettle();
    expect(_container.read(selectedCommitProvider(_identity)), isNotNull);

    await tester.tap(_workingCopyRow);
    await tester.pumpAndSettle();

    expect(
      _container.read(selectedCommitProvider(_identity)),
      isNull,
      reason:
          'every one-commit action gates on this being non-null, so the '
          'uncommitted row must not present itself as a commit',
    );
  });
}
