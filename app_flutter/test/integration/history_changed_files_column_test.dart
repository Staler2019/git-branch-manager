// The Changed files column's request gate.
//
// The column is off by default (spec's own GRAPH_COLS `on: false`), and the
// cost it carries is a real `git log --raw` over the viewport. So the claim
// worth pinning is not "the number renders" but "nothing is requested until
// the user asks for the column, and everything visible is requested the
// moment they do" -- a gate that only fired on the next *scroll* would leave
// the rows already on screen blank until the user touched the wheel, which
// reads as the feature being broken.
//
// Only an integration test can see either half: the request goes
// CommitGraphView -> requestCommitFileCounts -> the controller, and no widget
// test crosses that.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

String _oid(int i) => '${i.toString().padLeft(2, '0')}${'a' * 38}';

const int _rowCount = 4;

RepoSessionState _state() {
  return RepoSessionState(
    isOpen: true,
    graph: GraphSnapshotView(
      rows: <GraphRow>[
        for (int i = 0; i < _rowCount; i++)
          const GraphRow(
            parentOffset: 0,
            edgeOffset: 0,
            commitTime: 0,
            lane: 0,
            color: 0,
            flags: 0,
          ),
      ],
      oidsHex: <String>[for (int i = 0; i < _rowCount; i++) _oid(i)],
      parentPool: const <int>[],
      laneCount: 1,
      complete: true,
      truncated: false,
      edges: const <GraphEdge>[],
    ),
    commitMetaCache: <String, CommitMeta>{
      for (int i = 0; i < _rowCount; i++)
        _oid(i): CommitMeta(
          oid: _oid(i),
          tree: 'b',
          parents: const <String>[],
          author: const Signature(
            name: 'Ada',
            email: 'a@b.c',
            when: 0,
            tzOffsetMinutes: 0,
          ),
          committer: const Signature(
            name: 'Ada',
            email: 'a@b.c',
            when: 0,
            tzOffsetMinutes: 0,
          ),
          subject: 'commit $i',
          body: '',
          signedCommit: false,
        ),
    },
  );
}

class _Pumped {
  const _Pumped(this.container, this.controller);
  final ProviderContainer container;
  final FakeRepoSessionController controller;
}

Future<_Pumped> _pump(WidgetTester tester, {bool columnOn = false}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    _state(),
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(_identity).overrideWith((ref) => controller),
    ],
  );
  addTearDown(container.dispose);

  if (columnOn) {
    container
        .read(graphColumnVisibilityProvider.notifier)
        .setVisible(GbmGraphColumnId.changedFiles.storageId, true);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(body: CommitGraphView(identity: _identity)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Pumped(container, controller);
}

int _countRequests(FakeRepoSessionController controller) => controller
    .commandLog
    .where((c) => c.name == 'requestCommitFileCounts')
    .length;

List<String> _requestedOids(FakeRepoSessionController controller) => <String>[
  for (final FakeCommand c in controller.commandLog)
    if (c.name == 'requestCommitFileCounts')
      ...(c.args['oids']! as List<String>),
];

void main() {
  testWidgets('with the column off, no counts are requested at all', (
    tester,
  ) async {
    final _Pumped pumped = await _pump(tester);

    // Counted, not `any`: a gate that fired once and then stopped would be a
    // different bug from one that never fires, and only a count sees it.
    expect(_countRequests(pumped.controller), 0);
    // Proof that "nothing requested" is not true for the boring reason that
    // nothing was on screen. Deliberately *not* asserted via a
    // requestCommitMeta call: the fixture pre-seeds commitMetaCache, so that
    // request is correctly deduped away and would report empty here whether
    // the viewport logic ran or not.
    expect(find.text('commit 0'), findsOneWidget);
    expect(find.text('commit ${_rowCount - 1}'), findsOneWidget);
  });

  testWidgets('with the column on, the visible rows are requested', (
    tester,
  ) async {
    final _Pumped pumped = await _pump(tester, columnOn: true);

    expect(_countRequests(pumped.controller), greaterThan(0));
    expect(
      _requestedOids(pumped.controller),
      containsAll(<String>[for (int i = 0; i < _rowCount; i++) _oid(i)]),
    );
  });

  testWidgets('switching the column on counts the rows already on screen', (
    tester,
  ) async {
    // The half that a scroll-driven gate would fail. Nothing is scrolled
    // here on purpose: the request has to come from the toggle's own rebuild.
    final _Pumped pumped = await _pump(tester);
    expect(_countRequests(pumped.controller), 0);

    pumped.container
        .read(graphColumnVisibilityProvider.notifier)
        .setVisible(GbmGraphColumnId.changedFiles.storageId, true);
    await tester.pumpAndSettle();

    expect(_requestedOids(pumped.controller), contains(_oid(0)));
  });

  testWidgets('the count reaches the row, and 0 is not a skeleton', (
    tester,
  ) async {
    final _Pumped pumped = await _pump(tester, columnOn: true);

    pumped.controller.emit(
      pumped.controller.state.withCommitFileCounts(<String, int>{
        _oid(0): 7,
        _oid(1): 0,
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);
    // An empty commit really changes nothing, and a commit git never answered
    // for is absent from the cache -- so these must not render the same way.
    expect(find.text('0'), findsOneWidget);
  });
}
