// History's own vertical budget: the search field on top, the commit list
// below, and what happens when the pane is too short to hold both.
//
// This is the *vertical* instance of the rule the narrow-window round wrote
// down horizontally: `RenderFlex` lays out non-flex children first and only
// then divides what is left. `_CommitSearchField` is a non-flex child of the
// Column at `commit_graph_view.dart`'s `build`, so once the pane is shorter
// than the field's own intrinsic height, `Expanded` is handed zero and the
// field overflows on its own -- `A RenderFlex overflowed by 2.3 pixels on the
// bottom`, reported from a real macOS run.
//
// The 2.3 is not a hardcoded number anywhere: it is what a
// `TextField(isDense: true)`'s font metrics come to. That is exactly why the
// fix is to give the field a height the layout can predict rather than to
// nudge a padding until the number goes away.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
const String _oid = 'abc12345def67890abc12345def67890abc12345';

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
        name: 'Ada',
        email: 'a@b.c',
        when: 0,
        tzOffsetMinutes: 0,
      ),
      committer: Signature(
        name: 'Ada',
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

/// Pumps History inside a pane of exactly [paneHeight] logical pixels, the
/// way the changed-files splitter hands it a height in the real workspace.
Future<void> _pumpAtPaneHeight(WidgetTester tester, double paneHeight) async {
  tester.view.physicalSize = const Size(1400, 900);
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
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: paneHeight,
              width: 1400,
              child: CommitGraphView(identity: _identity),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // The pane heights below are not hypothetical. `splitterMainFiles` protects
  // the filling pane (History) at `minExtent: 140`, so the splitter itself
  // cannot produce these -- but the *window* can, and so can a transient
  // first-frame constraint before macOS reports its real size, which is where
  // the reported run hit it (the assertion fired while `flutter run` was still
  // syncing). A view that asserts at any height its parent may legally hand it
  // is a view with a latent crash, so the defence belongs here rather than in
  // the splitter -- and the splitter's 140 is spec'd (`main.files`, min 140px),
  // so raising it would be a divergence, not a fix.
  for (final double h in <double>[36, 30, 26, 20, 10]) {
    testWidgets('a $h px pane lays out History without overflowing', (
      tester,
    ) async {
      await _pumpAtPaneHeight(tester, h);

      expect(
        tester.takeException(),
        isNull,
        reason:
            'History must degrade rather than assert: RenderFlex lays out '
            'non-flex children first, so a search field that insists on its '
            'intrinsic height overflows the moment the pane is shorter.',
      );
    });
  }

  testWidgets('the search field is one compact row tall, not its intrinsic '
      'height', (tester) async {
    await _pumpAtPaneHeight(tester, 400);

    // Measured before the fix: a `TextField(isDense: true)` inside the
    // field's padding came to 37px, which is both the overflow threshold and
    // 11px of vertical space spent on a filter nobody is reading. Pinning it
    // to the spec's own compact row height fixes the density and lowers the
    // threshold in one move.
    final Size size = tester.getSize(
      find.byKey(const ValueKey<String>('history-search-field')),
    );
    expect(size.height, GbmSpacing.rowHeightCompact);
  });

  testWidgets('a normal pane still renders the commit list', (tester) async {
    await _pumpAtPaneHeight(tester, 400);

    expect(tester.takeException(), isNull);
    expect(find.text('A commit'), findsOneWidget);
  });
}
