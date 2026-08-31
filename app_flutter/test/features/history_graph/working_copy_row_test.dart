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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/features/history_graph/commit_search.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_column_painter.dart';
import 'package:gbm_flutter/features/history_graph/widgets/working_copy_row.dart';
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

/// Hoisted, and reused by every [_state] rather than rebuilt per call, so two
/// states differ in `workingCopyStatus` **and nothing else**.
///
/// This is load-bearing, not tidiness. A fresh `GraphSnapshotView` per call is
/// a new object, `repoGraphProvider` selects that object, and the resulting
/// rebuild repaints the row for reasons that have nothing to do with the
/// working copy -- which masks the very defect the discard tests below exist
/// to catch. Measured: with these rebuilt per call, mutating the row's
/// `ref.watch` to `ref.read` left the whole file green.
final GraphSnapshotView _graph = GraphSnapshotView(
  rows: <GraphRow>[for (final _ in _oids) _row()],
  oidsHex: _oids,
  parentPool: const <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
);

final Map<String, CommitMeta> _metaCache = <String, CommitMeta>{
  for (final String oid in _oids) oid: _meta(oid),
};

/// HEAD points at the topmost row, which is what makes the uncommitted row's
/// connector legal to draw. **Every fixture in this file used to leave `refs`
/// at its default**, so `head.target` was the empty string, `connectsDown` was
/// false in all eight tests, and the connector -- both the half that was drawn
/// and the half that was not -- was covered by nothing at all.
final RefSnapshot _refs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: _oids.first,
  ),
  refs: const <RefInfo>[],
  refCountGuardTripped: false,
  totalRefCount: 0,
);

RepoSessionState _state({required int pendingFiles}) => RepoSessionState(
  isOpen: true,
  refs: _refs,
  graph: _graph,
  commitMetaCache: _metaCache,
  workingCopyStatus: WorkingCopyStatus(
    entries: <WorkingCopyEntry>[
      for (int i = 0; i < pendingFiles; i++) _entry('file$i.txt'),
    ],
  ),
);

late ProviderContainer _container;

/// Kept so a test can publish a *new* state into a tree that is already on
/// screen. Pumping a second fixture is not the same thing: the eight tests
/// below each pump one fixed `pendingFiles`, so in none of them can the row
/// ever stop existing -- [TEST-fixture-cannot-disagree]'s shape 4, a fixture
/// that cannot shrink.
late FakeRepoSessionController _fake;

Future<void> _pump(WidgetTester tester, {required int pendingFiles}) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    _state(pendingFiles: pendingFiles),
  );
  _fake = fake;
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

  testWidgets('the first commit + arrow up reaches the row, and down returns', (
    WidgetTester tester,
  ) async {
    await _pump(tester, pendingFiles: 1);

    // Click the first commit rather than seeding the provider: the focus the
    // shortcuts are scoped to is requested by _publish, and a seeded
    // selection never asks for it.
    await tester.tap(find.byType(CommitRow).first);
    await tester.pumpAndSettle();
    expect(_container.read(selectedCommitProvider(_identity)), _oids.first);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      _container.read(workingCopyRowSelectedProvider(_identity)),
      isTrue,
      reason:
          'the uncommitted row is index 0 of the painted order, above the '
          'first commit',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      _container.read(workingCopyRowSelectedProvider(_identity)),
      isTrue,
      reason: 'it is the top: another up must clamp, not wrap round',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_container.read(selectedCommitProvider(_identity)), _oids.first);
  });

  testWidgets('with a clean working copy arrow up stops at the first commit', (
    WidgetTester tester,
  ) async {
    await _pump(tester, pendingFiles: 0);

    await tester.tap(find.byType(CommitRow).at(1));
    await tester.pumpAndSettle();
    expect(_container.read(selectedCommitProvider(_identity)), _oids[1]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_container.read(selectedCommitProvider(_identity)), _oids.first);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      _container.read(selectedCommitProvider(_identity)),
      _oids.first,
      reason:
          'there is no row above it when the working copy is clean -- the '
          'navigable order must not carry a phantom entry',
    );
  });

  testWidgets('a commit search hides the row, because the lanes are hidden '
      'too', (WidgetTester tester) async {
    await _pump(tester, pendingFiles: 2);
    expect(_workingCopyRow, findsOneWidget);

    // Any query at all: under one, CommitRowColumnPlan.drawsGraph goes false
    // and every row below draws a bare spacer instead of lanes, because
    // graph.edges connect rows of the *unfiltered* snapshot. A dot with no
    // lanes under it, and a connector descending into a filtered list, are
    // the same false claim that suppression exists to avoid.
    _container.read(commitSearchQueryProvider(_identity).notifier).state =
        'subject';
    await tester.pumpAndSettle();

    expect(_workingCopyRow, findsNothing);
    expect(
      find.byType(CommitRow),
      findsWidgets,
      reason:
          'the list itself still has matches -- it is only the row that '
          'goes away',
    );

    _container.read(commitSearchQueryProvider(_identity).notifier).state = '';
    await tester.pumpAndSettle();
    expect(_workingCopyRow, findsOneWidget);
  });

  testWidgets('discarding every change removes the row, and leaves the list '
      'alone', (WidgetTester tester) async {
    await _pump(tester, pendingFiles: 3);
    expect(_workingCopyRow, findsOneWidget);

    // A discard is an ordinary working-copy status publish: the entries go
    // away and the core emits workingCopyStatusUpdated. Driven through the
    // fake's emit rather than by pumping a clean fixture, because only a
    // transition on a tree that is already on screen can see a surface that
    // reads its provider once per *mount* instead of once per build
    // ([FLU-listen-misses-the-current-value]'s mirror case).
    _fake.emit(_state(pendingFiles: 0));
    await tester.pumpAndSettle();

    expect(_workingCopyRow, findsNothing);
    expect(
      find.byType(CommitRow),
      findsNWidgets(_oids.length),
      reason:
          'the row is pinned above the ListView, so its arrival and its '
          'departure must both leave every commit row index untouched',
    );
  });

  testWidgets('discarding while the row is selected does not leave the panels '
      'claiming changes that are gone', (WidgetTester tester) async {
    await _pump(tester, pendingFiles: 3);
    await tester.tap(_workingCopyRow);
    await tester.pumpAndSettle();
    expect(_container.read(workingCopyRowSelectedProvider(_identity)), isTrue);

    _fake.emit(_state(pendingFiles: 0));
    await tester.pumpAndSettle();

    expect(
      _container.read(workingCopyRowSelectedProvider(_identity)),
      isFalse,
      reason:
          'the row it points at is no longer drawn, so a selection still '
          'anchored on it is a selection of nothing -- and every surface '
          'that gates on it would go on drawing an uncommitted summary for '
          'a working copy that is now clean',
    );
  });

  /// The painter the first commit row actually hands the framework -- not a
  /// flag read back off the widget that produced it. Asserting the wiring
  /// this way is the difference between proving the gate exists and proving
  /// somebody opened it ([SPEC-cell-names-capability]).
  GraphRowPainter headRowPainter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(CommitRow).first,
          matching: find.byType(CustomPaint),
        ),
      )
      .map((CustomPaint c) => c.painter)
      .whereType<GraphRowPainter>()
      .single;

  testWidgets('the first commit row closes the connector up to the row', (
    WidgetTester tester,
  ) async {
    await _pump(tester, pendingFiles: 2);

    expect(
      headRowPainter(tester).connectsUpToUncommitted,
      isTrue,
      reason:
          'the row paints dot-centre to its own bottom edge and can paint no '
          'further -- commit_row.dart wraps its graph column in a ClipRect -- '
          'so the top half of the join has to be drawn by this row',
    );
    expect(
      tester
          .widget<HistoryWorkingCopyRow>(find.byType(HistoryWorkingCopyRow))
          .connectsDown,
      isTrue,
      reason:
          'and the other half, asserted in the same test on purpose: these '
          'two come from one boolean, and a test that pinned only one of '
          'them is what a half-drawn line looks like from the suite',
    );
  });

  testWidgets('and does not when the working copy is clean', (
    WidgetTester tester,
  ) async {
    await _pump(tester, pendingFiles: 0);

    expect(
      headRowPainter(tester).connectsUpToUncommitted,
      isFalse,
      reason: 'a stub with nothing above it is a line to nowhere',
    );
  });
}
