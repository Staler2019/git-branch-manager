// The seam that was missing entirely: GraphColumnsSelector -> shared state ->
// CommitGraphView -> CommitRow.
//
// The picker persisted its map to SharedPreferences and nothing on the render
// path ever read it, so switching Author off changed a stored preference and
// left the list untouched. A widget test of either end alone cannot see that
// -- the picker's own test passed throughout -- so this pumps both in one
// tree and taps the real checkbox.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
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

Future<ProviderContainer> _pump(WidgetTester tester) async {
  // Wide enough that nothing is given up for want of room -- this file is
  // about the picker, so any degradation here would be a confound.
  tester.view.physicalSize = const Size(1400, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
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
              const SizedBox(height: 460, child: GraphColumnsSelector()),
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

void main() {
  testWidgets('the author column is on before anything is toggled', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(_author), findsOneWidget);
  });

  testWidgets('unticking Author in the picker removes it from the rows', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Author'));
    await tester.pumpAndSettle();

    expect(find.text(_author), findsNothing);
  });

  testWidgets('re-ticking Author brings it back', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Author'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Author'));
    await tester.pumpAndSettle();

    expect(find.text(_author), findsOneWidget);
  });

  testWidgets('the toggle is persisted, not just held in the widget', (
    tester,
  ) async {
    final ProviderContainer container = await _pump(tester);

    await tester.tap(find.text('Author'));
    await tester.pumpAndSettle();

    expect(
      container.read(graphColumnsRepositoryProvider).readVisibility()['author'],
      isFalse,
    );
  });

  testWidgets('Graph and Message cannot be switched off', (tester) async {
    // Spec P02 item 16. The checkbox is rendered disabled, so tapping is a
    // no-op -- asserted through the derived set rather than through the
    // widget, because "disabled" is what is being trusted here.
    final ProviderContainer container = await _pump(tester);

    await tester.tap(find.text('Graph'), warnIfMissed: false);
    await tester.tap(find.text('Message'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(container.read(hiddenGraphColumnsProvider), isEmpty);
  });
}
