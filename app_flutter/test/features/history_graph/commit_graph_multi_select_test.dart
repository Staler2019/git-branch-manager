// Drives CommitGraphView's spec page 13 multi-select through the real
// commitSelectionProvider seam rather than against ListSelection in
// isolation: the model's transitions already have unit coverage, what this
// tier proves is that a click carrying a modifier reaches the right one,
// that a range is measured in the *rendered* list, and that right-click
// normalises the selection before a menu can act on it.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

/// Newest-first, exactly as History renders it.
final List<String> _oids = <String>[
  for (final String seed in <String>['a', 'b', 'c', 'd', 'e']) seed * 40,
];

/// A full 40-char oid from a one-letter shorthand: CommitRow abbreviates to
/// eight characters, so a toy 3-char id would blow up in its own renderer
/// rather than in anything under test.
String _oid(String seed) => seed * 40;

GraphRow _row() => const GraphRow(
  parentOffset: 0,
  edgeOffset: 0,
  commitTime: 0,
  lane: 0,
  color: 0,
  flags: 0,
);

CommitMeta _meta(String oid, String subject) {
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
    subject: subject,
    body: '',
    signedCommit: false,
  );
}

RepoSessionState _state() => RepoSessionState(
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
    for (final String oid in _oids)
      oid: _meta(oid, 'subject ${oid.substring(0, 4)}'),
  },
);

late ProviderContainer _container;

Future<void> _pump(WidgetTester tester) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    _state(),
  );
  _container = ProviderContainer(
    overrides: <Override>[
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

ListSelection<String> get _selection =>
    _container.read(commitSelectionProvider(_identity));

Finder _rowFor(String oid) => find.byWidgetPredicate(
  (Widget widget) => widget is CommitRow && widget.oidHex == oid,
);

Future<void> _tap(WidgetTester tester, String oid) async {
  await tester.tap(_rowFor(oid));
  await tester.pumpAndSettle();
}

Future<void> _tapWith(
  WidgetTester tester,
  String oid,
  LogicalKeyboardKey modifier,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.tap(_rowFor(oid));
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(modifier);
}

void main() {
  // currentSelectionGesture() branches on defaultTargetPlatform, so the
  // toggle modifier under test has to match whatever platform the test
  // runner reports -- otherwise a Ctrl-click here would read as a plain
  // click and the assertion would pass or fail for the wrong reason.
  final LogicalKeyboardKey toggleKey =
      debugDefaultTargetPlatformOverride == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;

  group('MULTIKEYS mouse rows', () {
    testWidgets('a plain click selects only that row', (tester) async {
      await _pump(tester);
      await _tap(tester, _oid('c'));
      expect(_selection.items, <String>[_oid('c')]);
      expect(_selection.anchor, _oid('c'));
    });

    testWidgets('the toggle modifier adds a second, non-adjacent row', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, _oid('a'));
      await _tapWith(tester, _oid('c'), toggleKey);
      expect(_selection.items, <String>[_oid('a'), _oid('c')]);
      expect(_selection.anchor, _oid('c'));
    });

    testWidgets('the toggle modifier removes an already-selected row', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, _oid('a'));
      await _tapWith(tester, _oid('c'), toggleKey);
      await _tapWith(tester, _oid('a'), toggleKey);
      expect(_selection.items, <String>[_oid('c')]);
    });

    testWidgets('Shift selects the inclusive range from the anchor', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, _oid('b'));
      await _tapWith(tester, _oid('d'), LogicalKeyboardKey.shiftLeft);
      expect(_selection.items, <String>[_oid('b'), _oid('c'), _oid('d')]);
      expect(_selection.anchor, _oid('b'));
    });

    testWidgets('every selected row renders as selected, not just the anchor', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, _oid('b'));
      await _tapWith(tester, _oid('d'), LogicalKeyboardKey.shiftLeft);

      for (final String oid in <String>[_oid('b'), _oid('c'), _oid('d')]) {
        expect(
          tester.widget<CommitRow>(_rowFor(oid)).selected,
          isTrue,
          reason: '$oid should render selected',
        );
      }
      expect(tester.widget<CommitRow>(_rowFor(_oid('a'))).selected, isFalse);
    });
  });

  group('MULTIKEYS right-click rows', () {
    testWidgets('right-clicking an unselected row collapses to just it '
        'before the menu opens', (tester) async {
      await _pump(tester);
      await _tap(tester, _oid('a'));
      await _tapWith(tester, _oid('b'), toggleKey);
      expect(_selection.length, 2);

      await tester.tap(_rowFor(_oid('d')), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(_selection.items, <String>[_oid('d')]);
    });

    testWidgets('right-clicking an already-selected row leaves the '
        'selection alone', (tester) async {
      await _pump(tester);
      await _tap(tester, _oid('a'));
      await _tapWith(tester, _oid('b'), toggleKey);

      await tester.tap(_rowFor(_oid('a')), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(_selection.items, <String>[_oid('a'), _oid('b')]);
    });
  });

  group('MULTIKEYS keyboard rows', () {
    testWidgets('Shift+Down extends the range one row', (tester) async {
      await _pump(tester);
      await _tap(tester, _oid('b'));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(_selection.items, <String>[_oid('b'), _oid('c')]);
    });

    testWidgets('Shift+Up after Shift+Down shrinks the same range rather '
        'than jumping', (tester) async {
      await _pump(tester);
      await _tap(tester, _oid('b'));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(_selection.items, <String>[_oid('b'), _oid('c')]);
    });

    testWidgets('Ctrl/Cmd+A selects the whole list', (tester) async {
      await _pump(tester);
      await _tap(tester, _oid('c'));

      await tester.sendKeyDownEvent(toggleKey);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(toggleKey);
      await tester.pumpAndSettle();

      expect(_selection.items, _oids);
      expect(
        _selection.anchor,
        _oid('c'),
        reason: 'a present anchor stays put',
      );
    });

    testWidgets('Esc collapses to the anchor rather than clearing', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, _oid('b'));
      await _tapWith(tester, _oid('d'), LogicalKeyboardKey.shiftLeft);
      expect(_selection.length, 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(_selection.items, <String>[_oid('b')]);
      expect(_selection.anchor, _oid('b'));
    });
  });
}
