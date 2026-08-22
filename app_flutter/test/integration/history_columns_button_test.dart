// Spec page 02 item 16's entry point: the button at the right of History's
// own top row, and the popover it opens.
//
// The seam worth crossing here is not "does a button render" but "does the
// picker inside a `showGeneralDialog` route still reach the same providers".
// It is pushed onto the root Navigator, so it leaves the widget subtree the
// rows live in -- if the ProviderScope did not enclose it, every toggle would
// land on a fresh container and the rows would never change. A widget test of
// either end alone cannot see that.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_columns_selector.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
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

Future<void> _pump(WidgetTester tester) async {
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
        home: Scaffold(body: CommitGraphView(identity: _identity)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _button => find.byTooltip('Graph columns');

/// Set by [_pumpShortWindow] so its test can read a provider without
/// threading the container through. [_pump] deliberately does not set it --
/// nothing else in this file reads a provider directly, and a global that
/// two helpers both write is a global that goes stale across tests.
ProviderContainer? container;

/// Same tree as [_pump] but in a window short enough that the History header
/// button sits in the lower half -- the real desktop case, see the
/// low-button test below.
Future<void> _pumpShortWindow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 420);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(
        _identity,
      ).overrideWith((ref) => FakeRepoSessionController(_identity, _state())),
    ],
  );
  container = c;
  addTearDown(c.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              // Pushes the History panel -- and therefore its header button --
              // down the window, the way the workspace chrome and the changed
              // files splitter do in the real app.
              const SizedBox(height: 280),
              Expanded(child: CommitGraphView(identity: _identity)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('History carries the button, and the picker is not open yet', (
    tester,
  ) async {
    await _pump(tester);

    expect(_button, findsOneWidget);
    expect(find.byType(GraphColumnsSelector), findsNothing);
  });

  testWidgets('the button sits at the right of the History top row', (
    tester,
  ) async {
    await _pump(tester);

    // Spec's "History 標題列右側一顆按鈕" -- right of the filter field, not
    // in the tab row above it.
    expect(
      tester.getCenter(_button).dx,
      greaterThan(tester.getCenter(find.byType(TextField)).dx),
    );
    expect(
      tester.getCenter(_button).dy,
      lessThan(tester.getCenter(find.byType(CommitGraphView)).dy),
    );
  });

  testWidgets('tapping it opens the picker', (tester) async {
    await _pump(tester);

    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(find.byType(GraphColumnsSelector), findsOneWidget);
    expect(find.text('Commit hash'), findsOneWidget);
  });

  testWidgets('a toggle made inside the popover reaches the rows', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(_author), findsOneWidget);

    await tester.tap(_button);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(GraphColumnsSelector),
        matching: find.text('Author'),
      ),
    );
    await tester.pumpAndSettle();

    // The popover is a root-Navigator route, so this is the assertion that
    // the ProviderScope still encloses it. Asserted while the popover is
    // still open, deliberately: a toggle that only took effect after the
    // route was torn down would be a different, worse behaviour.
    expect(find.text(_author), findsNothing);
  });

  testWidgets('the popover survives being clicked more than once', (
    tester,
  ) async {
    // The falsifiable half of "showGeneralDialog, not showGbmMenu": a menu
    // closes on the first click, and this panel exists to be clicked eight
    // times and then dragged. Nothing else in the suite would notice the
    // carrier being swapped back.
    await _pump(tester);
    await tester.tap(_button);
    await tester.pumpAndSettle();

    for (final String label in <String>['Author', 'Date', 'Commit hash']) {
      await tester.tap(
        find.descendant(
          of: find.byType(GraphColumnsSelector),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(GraphColumnsSelector),
        findsOneWidget,
        reason: 'closed after ticking $label',
      );
    }
  });

  testWidgets('every row is reachable when the button sits low', (
    tester,
  ) async {
    // The placement defect this closes, found on the device tier rather than
    // by reading: at 1440x900 the History header button lands at y ~= 681, so
    // a popover that always opens downward gets ~175px for ~230px of rows.
    // The bottom two -- Committer and Changed files, the two the picker
    // gained this round -- were then inside a scroll view, present in the
    // tree and *not hit-testable*, which is the failure mode a findsOneWidget
    // assertion cannot see.
    await _pumpShortWindow(tester);

    await tester.tap(_button);
    await tester.pumpAndSettle();

    // Reachability, not presence: tapping is the claim, so the assertion is
    // that the tap lands and the row actually flips.
    await tester.tap(
      find.descendant(
        of: find.byType(GraphColumnsSelector),
        matching: find.text('Changed files'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      isGraphColumnVisible(
        container!.read(graphColumnVisibilityProvider),
        GbmGraphColumnId.changedFiles.storageId,
      ),
      isTrue,
    );
    // And it went up rather than merely scrolling: the panel's top edge is
    // above the button it hangs off.
    expect(
      tester.getRect(find.byType(GraphColumnsSelector)).top,
      lessThan(tester.getRect(_button).top),
    );
  });

  testWidgets('tapping outside closes it without undoing the toggle', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(_button);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(GraphColumnsSelector),
        matching: find.text('Author'),
      ),
    );
    await tester.pumpAndSettle();

    // The transparent barrier fills the window; the top-left corner is
    // outside the popover, which hangs below a right-edge button.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byType(GraphColumnsSelector), findsNothing);
    expect(find.text(_author), findsNothing);
  });
}
