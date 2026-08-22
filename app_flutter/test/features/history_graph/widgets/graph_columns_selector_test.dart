// The picker as spec draws it (`spec_raw.html:1354-1362`), rather than as a
// list of CheckboxListTiles.
//
// The previous version of this file addressed rows by their position among
// `find.byType(CheckboxListTile)` and asserted the two labels that had
// drifted from spec ("Hash", "Changed Files"). Both are gone: rows are found
// by their spec label, and the labels now come from GbmGraphColumnId.label,
// so a drift shows up here as a failure rather than as an agreed-upon typo.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_columns_selector.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/pump_app.dart';

late SharedPreferences _prefs;

Future<void> _pump(WidgetTester tester) async {
  await pumpGbmWidget(
    tester,
    overrides: <Override>[
      graphColumnsRepositoryProvider.overrideWithValue(
        GraphColumnsRepository(_prefs),
      ),
    ],
    child: const GraphColumnsSelector(),
  );
}

/// The labels of every row, top to bottom, read off the rendered tree rather
/// than off the provider -- what the user actually sees is the claim.
List<String> _rowOrder(WidgetTester tester) {
  final List<String> labels = <String>[
    for (final GbmGraphColumnId id in GbmGraphColumnId.values) id.label,
  ];
  final List<(double, String)> found = <(double, String)>[
    for (final String label in labels)
      if (tester.any(find.text(label)))
        (tester.getTopLeft(find.text(label)).dy, label),
  ];
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return <String>[for (final (double, String) entry in found) entry.$2];
}

/// The 20x24 grip at the trailing edge of the row labelled [label].
///
/// Found by walking out to the row and back down to its only [LucideIcon],
/// rather than by a key: the handle is what the user aims at, and a finder
/// that goes through the rendered row cannot drift away from it.
Finder _handle(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.byType(LucideIcon),
);

/// Drags the row labelled [label] by [dy] using an explicit gesture.
///
/// `tester.drag` would do, but the reorder needs the intermediate frames:
/// the list only decides where the dragged row lands as the pointer crosses
/// its neighbours' midpoints, and a single synthetic move is easy to get
/// wrong in a way that reads as "reorder is broken" rather than "the test
/// never moved the pointer".
///
/// The gesture starts on the grip, not on the label: only the grip is wired
/// to the reorder listener, and a drag started anywhere else is by design a
/// plain click that toggles the row.
Future<void> _dragRow(WidgetTester tester, String label, double dy) async {
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(_handle(label)),
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
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _prefs = await SharedPreferences.getInstance();
  });

  group('rows', () {
    testWidgets("labels are spec's, and there are eight of them", (
      tester,
    ) async {
      await _pump(tester);

      expect(_rowOrder(tester), <String>[
        'Graph',
        'Message',
        'Refs',
        'Author',
        'Date',
        'Commit hash',
        'Committer',
        'Changed files',
      ]);
      // The two that used to be spelled "Hash" and "Changed Files".
      expect(find.text('Hash'), findsNothing);
      expect(find.text('Changed Files'), findsNothing);
      // And never the storage ids.
      expect(find.text('changedFiles'), findsNothing);
    });

    testWidgets('only the locked rows carry the 固定 hint', (tester) async {
      await _pump(tester);

      // Two, not "some": the hint is the sole visible marker of the pin, so
      // a third would mean a column silently became unmovable.
      expect(find.text('固定'), findsNWidgets(2));

      // Vertical centres, not top edges: the label is 11px and the hint
      // 10.5px, so within one row the two Texts start at different y.
      final double graphY = tester.getCenter(find.text('Graph')).dy;
      final double messageY = tester.getCenter(find.text('Message')).dy;
      final List<double> hintYs =
          tester
              .widgetList<Text>(find.text('固定'))
              .map((Text t) => tester.getCenter(find.byWidget(t)).dy)
              .toList()
            ..sort();
      expect(hintYs, <double>[graphY, messageY]);
    });

    testWidgets('a column off by default renders an unfilled box', (
      tester,
    ) async {
      await _pump(tester);

      // Committer starts off (spec's GRAPH_COLS `on: false`), Refs starts
      // on. Asserting the fill rather than a Checkbox's value, because the
      // box is a plain Container now -- and the fill is the only thing that
      // tells the user which state a row is in.
      expect(_boxIsFilled(tester, 'Refs'), isTrue);
      expect(_boxIsFilled(tester, 'Committer'), isFalse);
    });
  });

  group('toggling', () {
    testWidgets('a tap flips the row synchronously, before persistence', (
      tester,
    ) async {
      await _pump(tester);
      expect(_boxIsFilled(tester, 'Author'), isTrue);

      await tester.tap(find.text('Author'));
      // A single pump, not pumpAndSettle: the widget this replaced read
      // visibility once in build() and never rebuilt on toggle, so it would
      // still read filled here even though the write completes eventually.
      await tester.pump();

      expect(_boxIsFilled(tester, 'Author'), isFalse);
    });

    testWidgets('a tap persists to SharedPreferences', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Author'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commit hash'));
      await tester.pumpAndSettle();

      final Map<String, bool> visibility = GraphColumnsRepository(
        _prefs,
      ).readVisibility();
      expect(visibility['author'], isFalse);
      expect(visibility['hash'], isFalse);
    });

    testWidgets('a wobbly mouse click still toggles', (tester) async {
      // The reason the grip exists. When the whole row was the drag surface,
      // `ImmediateMultiDragGestureRecognizer` took the pointer after
      // `computeHitSlop(mouse)` == kPrecisePointerHitSlop == 1px of travel --
      // so a 2px wobble, which is nothing on a real mouse or trackpad, lifted
      // the row, dropped it back, and swallowed the toggle. Measured on this
      // widget before the fix: mouse lost it at 2px, touch (18px slop) did
      // not, which is why every other gesture in this file was blind to it.
      //
      // `kind: PointerDeviceKind.mouse` is the whole point -- the default is
      // touch, and this test passes vacuously without it.
      await _pump(tester);
      expect(_boxIsFilled(tester, 'Author'), isTrue);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Author')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_boxIsFilled(tester, 'Author'), isFalse);
    });

    testWidgets('the two locked rows cannot be switched off', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Graph'), warnIfMissed: false);
      await tester.tap(find.text('Message'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_boxIsFilled(tester, 'Graph'), isTrue);
      expect(_boxIsFilled(tester, 'Message'), isTrue);
      final Map<String, bool> visibility = GraphColumnsRepository(
        _prefs,
      ).readVisibility();
      expect(visibility['graph'] ?? true, isTrue);
      expect(visibility['message'] ?? true, isTrue);
    });
  });

  group('reordering', () {
    // Both directions, because the two halves of the index conversion fail
    // differently: a missing locked-count offset silently no-ops a drag of
    // the first movable row, while a stale onReorder-style off-by-one only
    // shows up when dragging downward.
    testWidgets('dragging a row down moves it past its neighbours', (
      tester,
    ) async {
      await _pump(tester);
      final double rowHeight =
          tester.getTopLeft(find.text('Author')).dy -
          tester.getTopLeft(find.text('Refs')).dy;

      await _dragRow(tester, 'Refs', rowHeight * 2.5);

      expect(_rowOrder(tester), <String>[
        'Graph',
        'Message',
        'Author',
        'Date',
        'Commit hash',
        'Refs',
        'Committer',
        'Changed files',
      ]);
    });

    testWidgets('dragging a row up moves it toward the top', (tester) async {
      await _pump(tester);
      final double rowHeight =
          tester.getTopLeft(find.text('Author')).dy -
          tester.getTopLeft(find.text('Refs')).dy;

      await _dragRow(tester, 'Committer', -rowHeight * 2.5);

      expect(_rowOrder(tester), <String>[
        'Graph',
        'Message',
        'Refs',
        'Committer',
        'Author',
        'Date',
        'Commit hash',
        'Changed files',
      ]);
    });

    testWidgets('a reorder persists to SharedPreferences', (tester) async {
      await _pump(tester);
      final double rowHeight =
          tester.getTopLeft(find.text('Author')).dy -
          tester.getTopLeft(find.text('Refs')).dy;

      await _dragRow(tester, 'Refs', rowHeight * 2.5);

      expect(GraphColumnsRepository(_prefs).readOrder(), <String>[
        'graph',
        'message',
        'author',
        'date',
        'hash',
        'refs',
        'committer',
        'changedFiles',
      ]);
    });

    testWidgets('a locked row has no grip and stays put', (tester) async {
      await _pump(tester);
      final double rowHeight =
          tester.getTopLeft(find.text('Author')).dy -
          tester.getTopLeft(find.text('Refs')).dy;

      // The hint slot holds either `固定` or a grip, never both -- so the
      // absence of a handle is the same fact as the presence of the hint.
      expect(_handle('Graph'), findsNothing);
      expect(_handle('Message'), findsNothing);

      // And dragging the row body does nothing, because the row body is not
      // a drag surface for any row.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Graph')),
      );
      await tester.pump();
      for (int i = 0; i < 8; i++) {
        await gesture.moveBy(Offset(0, rowHeight * 3 / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_rowOrder(tester).first, 'Graph');
      expect(_rowOrder(tester)[1], 'Message');
    });
  });
}

/// Whether the 12x12 check box on the row labelled [label] is filled.
///
/// Located by geometry rather than by a key: the box is the only 12x12
/// Container in the row, and finding it by position is what keeps this
/// assertion about what the user sees.
bool _boxIsFilled(WidgetTester tester, String label) {
  final Finder box = find.ancestor(
    of: find.text(label),
    matching: find.byType(Row),
  );
  final Finder container = find.descendant(
    of: box.first,
    matching: find.byWidgetPredicate(
      (Widget w) =>
          w is Container &&
          w.constraints == BoxConstraints.tightFor(width: 12, height: 12) &&
          w.decoration is BoxDecoration,
    ),
  );
  final Container found = tester.widget<Container>(container.first);
  final BoxDecoration decoration = found.decoration! as BoxDecoration;
  final Color border = (decoration.border! as Border).top.color;
  return decoration.color == border;
}
