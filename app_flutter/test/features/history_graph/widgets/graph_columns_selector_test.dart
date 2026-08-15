import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_columns_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/pump_app.dart';

void main() {
  group('GraphColumnsSelector', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    testWidgets('displays Title Case labels not raw ids', (tester) async {
      await pumpGbmWidget(
        tester,
        overrides: <Override>[
          graphColumnsRepositoryProvider.overrideWithValue(
            GraphColumnsRepository(prefs),
          ),
        ],
        child: const GraphColumnsSelector(),
      );

      expect(find.text('Graph'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Hash'), findsOneWidget);
      expect(find.text('Committer'), findsOneWidget);
      expect(find.text('Changed Files'), findsOneWidget);
      expect(find.text('Refs'), findsOneWidget);

      // Raw ids should not appear
      expect(find.text('graph'), findsNothing);
      expect(find.text('changedFiles'), findsNothing);
    });

    testWidgets(
      'toggling a checkbox updates its own displayed state synchronously '
      '-- the regression test for the reactivity bug',
      (tester) async {
        await pumpGbmWidget(
          tester,
          overrides: <Override>[
            graphColumnsRepositoryProvider.overrideWithValue(
              GraphColumnsRepository(prefs),
            ),
          ],
          child: const GraphColumnsSelector(),
        );

        // Author is the 4th checkbox (index 3: Graph, Message, Refs, Author).
        final Finder authorTile = find.byType(CheckboxListTile).at(3);
        expect(tester.widget<CheckboxListTile>(authorTile).value, true);

        await tester.tap(authorTile);
        // A single pump (not pumpAndSettle) -- the old buggy widget read
        // visibility once in build() and never rebuilt on toggle, so this
        // would still read true here even though persistence completes
        // eventually. Asserting the flip after just one frame proves the
        // rebuild is synchronous (setState), not incidental.
        await tester.pump();

        expect(
          tester.widget<CheckboxListTile>(authorTile).value,
          false,
          reason:
              'The checkbox must flip synchronously via setState, not only '
              'after persistence completes and something else happens to '
              'rebuild the widget.',
        );
      },
    );

    testWidgets('toggling Author checkbox persists to SharedPreferences', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        overrides: <Override>[
          graphColumnsRepositoryProvider.overrideWithValue(
            GraphColumnsRepository(prefs),
          ),
        ],
        child: const GraphColumnsSelector(),
      );

      // Author is the 4th checkbox (index 3: Graph, Message, Refs, Author)
      await tester.tap(find.byType(CheckboxListTile).at(3));
      await tester.pumpAndSettle();

      final repo = GraphColumnsRepository(prefs);
      final visibility = repo.readVisibility();
      expect(visibility['author'], false);
    });

    testWidgets('Graph column is not clickable', (tester) async {
      await pumpGbmWidget(
        tester,
        overrides: <Override>[
          graphColumnsRepositoryProvider.overrideWithValue(
            GraphColumnsRepository(prefs),
          ),
        ],
        child: const GraphColumnsSelector(),
      );

      // Graph is the first CheckboxListTile and should be disabled
      final graphTile = find.byType(CheckboxListTile).first;
      expect(graphTile, findsOneWidget);

      // Verify that after tapping, Graph remains visible
      await tester.tap(graphTile);
      await tester.pump();

      final repo = GraphColumnsRepository(prefs);
      final visibility = repo.readVisibility();
      expect(visibility['graph'] ?? true, true);
    });

    testWidgets('Message column is not clickable', (tester) async {
      await pumpGbmWidget(
        tester,
        overrides: <Override>[
          graphColumnsRepositoryProvider.overrideWithValue(
            GraphColumnsRepository(prefs),
          ),
        ],
        child: const GraphColumnsSelector(),
      );

      // Message is the second CheckboxListTile and should be disabled
      final messageTile = find.byType(CheckboxListTile).at(1);
      expect(messageTile, findsOneWidget);

      // Verify that after tapping, Message remains visible
      await tester.tap(messageTile);
      await tester.pump();

      final repo = GraphColumnsRepository(prefs);
      final visibility = repo.readVisibility();
      expect(visibility['message'] ?? true, true);
    });

    testWidgets('toggling Date checkbox persists to SharedPreferences', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        overrides: <Override>[
          graphColumnsRepositoryProvider.overrideWithValue(
            GraphColumnsRepository(prefs),
          ),
        ],
        child: const GraphColumnsSelector(),
      );

      // Date is the 5th checkbox (index 4: Graph, Message, Refs, Author, Date)
      await tester.tap(find.byType(CheckboxListTile).at(4));
      await tester.pumpAndSettle();

      final repo = GraphColumnsRepository(prefs);
      final visibility = repo.readVisibility();
      expect(visibility['date'], false);
    });

    testWidgets('toggling multiple columns persists all changes', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        overrides: <Override>[
          graphColumnsRepositoryProvider.overrideWithValue(
            GraphColumnsRepository(prefs),
          ),
        ],
        child: const GraphColumnsSelector(),
      );

      // Toggle Author (index 3)
      await tester.tap(find.byType(CheckboxListTile).at(3));
      await tester.pumpAndSettle();

      // Toggle Hash (index 5)
      await tester.tap(find.byType(CheckboxListTile).at(5));
      await tester.pumpAndSettle();

      final repo = GraphColumnsRepository(prefs);
      final visibility = repo.readVisibility();
      expect(visibility['author'], false);
      expect(visibility['hash'], false);
    });
  });
}
