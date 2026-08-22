// The other half of the seam `history_column_picker_test.dart` closes for
// visibility: GraphColumnsSelector's drag -> graphColumnOrderProvider ->
// CommitGraphView -> CommitRow's left-to-right layout.
//
// `GraphColumnsRepository.readOrder()` had no reader on the render path at
// all, exactly as `readVisibility()` once had none -- a drag would have
// rewritten a stored list and left the row untouched. Neither end's own
// widget test can see that: the picker's passes as long as the rows move,
// and CommitRow's passes as long as it honours whatever order it is handed.
// Only pumping both in one tree and dragging the real row can.
import 'dart:convert';

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
import 'package:gbm_flutter/features/history_graph/widgets/graph_columns_selector.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
const String _oid = 'abc12345def67890abc12345def67890abc12345';
const String _shortOid = 'abc12345';
const String _author = 'Ada Lovelace';

RepoSessionState _state() => RepoSessionState(
  isOpen: true,
  graph: const GraphSnapshotView(
    rows: <GraphRow>[
      GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 0,
        color: 0,
        flags: 0,
      ),
    ],
    oidsHex: <String>[_oid],
    parentPool: <int>[],
    laneCount: 1,
    complete: true,
    truncated: false,
    edges: <GraphEdge>[],
  ),
  commitMetaCache: <String, CommitMeta>{
    _oid: const CommitMeta(
      oid: _oid,
      tree: 'b',
      parents: <String>[],
      author: Signature(
        name: _author,
        email: 'a@b.c',
        when: 0,
        tzOffsetMinutes: 0,
      ),
      committer: Signature(
        name: _author,
        email: 'a@b.c',
        when: 0,
        tzOffsetMinutes: 0,
      ),
      subject: 'A commit',
      body: '',
      signedCommit: false,
    ),
  },
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<String>? storedOrder,
}) async {
  // Wide enough that the degradation ladder gives nothing up -- a dropped
  // column would read as a reorder failure.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{
    if (storedOrder != null) 'graphColumns.order': jsonEncode(storedOrder),
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(
        _identity,
      ).overrideWith((ref) => FakeRepoSessionController(_identity, _state())),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const SizedBox(height: 300, child: GraphColumnsSelector()),
              Expanded(child: CommitGraphView(identity: _identity)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The x of a commit-row cell, found inside [CommitGraphView] so the picker's
/// own copy of the same label (`Author`, `Commit hash`) cannot be picked up
/// by mistake -- they are two different words here, but not in every case
/// this file may grow.
double _cellX(WidgetTester tester, String text) {
  return tester
      .getTopLeft(
        find.descendant(
          of: find.byType(CommitGraphView),
          matching: find.text(text),
        ),
      )
      .dx;
}

Future<void> _dragPickerRow(
  WidgetTester tester,
  String label,
  double dy,
) async {
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(
      find.descendant(
        of: find.byType(GraphColumnsSelector),
        matching: find.text(label),
      ),
    ),
  );
  await tester.pump();
  for (int i = 0; i < 8; i++) {
    await gesture.moveBy(Offset(0, dy / 8));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the shipped order puts the hash right of the author', (
    tester,
  ) async {
    await _pump(tester);
    // Spec's own GRAPH_COLS order: graph, message, refs, author, date, hash.
    expect(_cellX(tester, _author), lessThan(_cellX(tester, _shortOid)));
  });

  testWidgets('dragging Commit hash to the top moves the column left', (
    tester,
  ) async {
    await _pump(tester);
    final double rowHeight =
        tester
            .getCenter(
              find.descendant(
                of: find.byType(GraphColumnsSelector),
                matching: find.text('Author'),
              ),
            )
            .dy -
        tester
            .getCenter(
              find.descendant(
                of: find.byType(GraphColumnsSelector),
                matching: find.text('Refs'),
              ),
            )
            .dy;

    // Three rows up: hash is the fourth movable row, refs the first.
    await _dragPickerRow(tester, 'Commit hash', -rowHeight * 3.5);

    expect(_cellX(tester, _shortOid), lessThan(_cellX(tester, _author)));
  });

  testWidgets('the drag is persisted, not just held in the widget', (
    tester,
  ) async {
    final ProviderContainer container = await _pump(tester);
    final double rowHeight =
        tester
            .getCenter(
              find.descendant(
                of: find.byType(GraphColumnsSelector),
                matching: find.text('Author'),
              ),
            )
            .dy -
        tester
            .getCenter(
              find.descendant(
                of: find.byType(GraphColumnsSelector),
                matching: find.text('Refs'),
              ),
            )
            .dy;

    await _dragPickerRow(tester, 'Commit hash', -rowHeight * 3.5);

    expect(container.read(graphColumnsRepositoryProvider).readOrder(), <String>[
      'graph',
      'message',
      'hash',
      'refs',
      'author',
      'date',
      'committer',
      'changedFiles',
    ]);
  });

  testWidgets('a stored order that moves Graph or Message is re-pinned', (
    tester,
  ) async {
    // The invariant the picker's own list only *looks* like it enforces by
    // excluding those two rows from its children. Seeded straight into
    // SharedPreferences instead of dragged, because a preferences file
    // written by an older build -- or by hand -- reaches this state without
    // the widget ever being involved, and that is the case a disabled
    // affordance cannot cover.
    final ProviderContainer container = await _pump(
      tester,
      storedOrder: <String>[
        'hash',
        'graph',
        'refs',
        'message',
        'author',
        'date',
      ],
    );

    expect(
      container
          .read(graphColumnOrderProvider)
          .map((GbmGraphColumnId id) => id.storageId),
      <String>[
        'graph',
        'message',
        'hash',
        'refs',
        'author',
        'date',
        'committer',
        'changedFiles',
      ],
    );
    // And the rows agree: hash is the first thing after the locked pair, so
    // it sits left of the author.
    expect(_cellX(tester, _shortOid), lessThan(_cellX(tester, _author)));
  });
}
