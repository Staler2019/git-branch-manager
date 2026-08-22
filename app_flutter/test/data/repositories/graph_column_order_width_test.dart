// The order and width halves of spec page 02 item 16, as live state.
//
// Sibling of graph_column_visibility_test.dart, and it exists for the same
// reason: `readOrder()` and `readWidths()` were written months ago and had
// no reader on the render path at all -- the orphan-wiring shape this
// repository's audits keep finding. These tests pin both halves for each:
// that a change is broadcast, and that it reaches SharedPreferences.
//
// The width notifier splits those two on purpose (setWidth vs commitWidths),
// because a drag updates state on every frame and must not write to
// SharedPreferences on every frame. So "changed" and "persisted" are
// genuinely separate assertions here, not one restated twice.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([
  Map<String, Object> initial = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

List<String> _ids(List<GbmGraphColumnId> order) => <String>[
  for (final GbmGraphColumnId c in order) c.storageId,
];

void main() {
  group('graphColumnOrderProvider', () {
    test('starts from the default when nothing is persisted', () async {
      final ProviderContainer c = await _container();
      expect(c.read(graphColumnOrderProvider), kGraphColumnOrderDefault);
    });

    test('starts from what the repository has persisted', () async {
      final ProviderContainer c = await _container(<String, Object>{
        '${GraphColumnsRepository.keyPrefix}order':
            '["graph","message","hash","refs","author","date","committer","changedFiles"]',
      });
      expect(_ids(c.read(graphColumnOrderProvider)).sublist(2, 4), <String>[
        'hash',
        'refs',
      ]);
    });

    test('move() broadcasts the new order', () async {
      final ProviderContainer c = await _container();
      // Default movable order is refs, author, date, hash, committer,
      // changedFiles at indices 2..7. Move hash (5) up to index 2.
      await c.read(graphColumnOrderProvider.notifier).move(5, 2);
      expect(_ids(c.read(graphColumnOrderProvider)), <String>[
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

    test('move() persists, so a fresh container sees it', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer first = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      await first.read(graphColumnOrderProvider.notifier).move(5, 2);
      first.dispose();

      final ProviderContainer second = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(second.dispose);
      expect(_ids(second.read(graphColumnOrderProvider))[2], 'hash');
    });

    test('move() refuses to touch either locked slot', () async {
      final ProviderContainer c = await _container();
      // Dragging a column onto index 0 or 1 would displace graph/message,
      // which spec pins. The picker keeps them out of its reorderable list,
      // but the store is where the invariant actually lives.
      await c.read(graphColumnOrderProvider.notifier).move(5, 0);
      expect(_ids(c.read(graphColumnOrderProvider))[0], 'graph');
      expect(_ids(c.read(graphColumnOrderProvider))[1], 'message');

      await c.read(graphColumnOrderProvider.notifier).move(0, 5);
      expect(_ids(c.read(graphColumnOrderProvider))[0], 'graph');
    });

    test('move() with an out-of-range index is a no-op, not a crash', () async {
      final ProviderContainer c = await _container();
      final List<String> before = _ids(c.read(graphColumnOrderProvider));
      await c.read(graphColumnOrderProvider.notifier).move(99, 2);
      await c.read(graphColumnOrderProvider.notifier).move(2, -1);
      expect(_ids(c.read(graphColumnOrderProvider)), before);
    });
  });

  group('graphColumnWidthProvider', () {
    test('starts from the defaults when nothing is persisted', () async {
      final ProviderContainer c = await _container();
      final Map<GbmGraphColumnId, double> widths = c.read(
        graphColumnWidthProvider,
      );
      expect(
        widths[GbmGraphColumnId.author],
        GbmGraphColumnId.author.defaultWidth,
      );
    });

    test('starts from what the repository has persisted', () async {
      final ProviderContainer c = await _container(<String, Object>{
        '${GraphColumnsRepository.keyPrefix}widths': '{"author":150}',
      });
      expect(c.read(graphColumnWidthProvider)[GbmGraphColumnId.author], 150);
    });

    test('setWidth() broadcasts immediately', () async {
      final ProviderContainer c = await _container();
      c
          .read(graphColumnWidthProvider.notifier)
          .setWidth(GbmGraphColumnId.author, 150);
      expect(c.read(graphColumnWidthProvider)[GbmGraphColumnId.author], 150);
    });

    test('setWidth() clamps to the column range', () async {
      final ProviderContainer c = await _container();
      c
          .read(graphColumnWidthProvider.notifier)
          .setWidth(GbmGraphColumnId.author, 5);
      expect(
        c.read(graphColumnWidthProvider)[GbmGraphColumnId.author],
        GbmGraphColumnId.author.minWidth,
      );
    });

    test('setWidth() alone does NOT persist', () async {
      // The point of the split: a drag calls setWidth every frame, and
      // writing SharedPreferences at 60Hz is what this avoids.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(c.dispose);

      c
          .read(graphColumnWidthProvider.notifier)
          .setWidth(GbmGraphColumnId.author, 150);
      expect(
        prefs.getString('${GraphColumnsRepository.keyPrefix}widths'),
        isNull,
      );
    });

    test('commitWidths() persists, so a fresh container sees it', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer first = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      first
          .read(graphColumnWidthProvider.notifier)
          .setWidth(GbmGraphColumnId.author, 150);
      await first.read(graphColumnWidthProvider.notifier).commitWidths();
      first.dispose();

      final ProviderContainer second = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(second.dispose);
      expect(
        second.read(graphColumnWidthProvider)[GbmGraphColumnId.author],
        150,
      );
    });

    test('setWidth() ignores a non-resizable column', () async {
      // Message is the only one left: it is the flex column, so it has no
      // width of its own to set. Graph moved out of this case when it became
      // draggable -- see the companion below.
      final ProviderContainer c = await _container();
      c
          .read(graphColumnWidthProvider.notifier)
          .setWidth(GbmGraphColumnId.message, 400);
      expect(
        c.read(graphColumnWidthProvider)[GbmGraphColumnId.message],
        GbmGraphColumnId.message.defaultWidth,
      );
    });

    test('setWidth() accepts graph, which is locked but resizable', () async {
      final ProviderContainer c = await _container();
      c
          .read(graphColumnWidthProvider.notifier)
          .setWidth(GbmGraphColumnId.graph, 200);
      expect(c.read(graphColumnWidthProvider)[GbmGraphColumnId.graph], 200);
    });
  });

  group('graphColumnLayoutProvider', () {
    test('combines order, width and visibility into one view', () async {
      final ProviderContainer c = await _container(<String, Object>{
        '${GraphColumnsRepository.keyPrefix}visibility': '{"date":false}',
        '${GraphColumnsRepository.keyPrefix}widths': '{"author":150}',
      });

      final GraphColumnLayout layout = c.read(graphColumnLayoutProvider);
      expect(layout.order, kGraphColumnOrderDefault);
      expect(layout.widthOf(GbmGraphColumnId.author), 150);
      expect(layout.isVisible(GbmGraphColumnId.date), isFalse);
      expect(layout.isVisible(GbmGraphColumnId.author), isTrue);
    });

    test('a locked column is visible however the stored map reads', () async {
      final ProviderContainer c = await _container(<String, Object>{
        '${GraphColumnsRepository.keyPrefix}visibility':
            '{"graph":false,"message":false}',
      });
      final GraphColumnLayout layout = c.read(graphColumnLayoutProvider);
      expect(layout.isVisible(GbmGraphColumnId.graph), isTrue);
      expect(layout.isVisible(GbmGraphColumnId.message), isTrue);
    });

    test(
      'rebuilds when any of the three underlying providers changes',
      () async {
        final ProviderContainer c = await _container();
        final GraphColumnLayout before = c.read(graphColumnLayoutProvider);

        await c.read(graphColumnOrderProvider.notifier).move(5, 2);
        expect(c.read(graphColumnLayoutProvider).order, isNot(before.order));

        c
            .read(graphColumnWidthProvider.notifier)
            .setWidth(GbmGraphColumnId.author, 150);
        expect(
          c.read(graphColumnLayoutProvider).widthOf(GbmGraphColumnId.author),
          150,
        );

        await c
            .read(graphColumnVisibilityProvider.notifier)
            .setVisible('author', false);
        expect(
          c.read(graphColumnLayoutProvider).isVisible(GbmGraphColumnId.author),
          isFalse,
        );
      },
    );

    // The map is partial on every existing install: the old picker wrote a
    // key only when a column was toggled, so nobody has one for these two.
    // Whether they are on therefore rests entirely on the fallback.
    test('an empty map hides exactly Committer and Changed files', () async {
      final ProviderContainer c = await _container();
      final GraphColumnLayout layout = c.read(graphColumnLayoutProvider);

      expect(layout.hiddenStorageIds, <String>{'committer', 'changedFiles'});
      expect(_ids(layout.visibleOrder), <String>[
        'graph',
        'message',
        'refs',
        'author',
        'date',
        'hash',
      ]);
    });

    // Two derivations of "which columns are off" is how the picker and the
    // row stop agreeing, so they are asserted equal rather than separately.
    test(
      'hiddenGraphColumnsProvider agrees with the layout, including defaults',
      () async {
        final ProviderContainer c = await _container(<String, Object>{
          '${GraphColumnsRepository.keyPrefix}visibility': '{"date":false}',
        });
        expect(
          c.read(hiddenGraphColumnsProvider),
          c.read(graphColumnLayoutProvider).hiddenStorageIds,
        );
        expect(c.read(hiddenGraphColumnsProvider), <String>{
          'date',
          'committer',
          'changedFiles',
        });
      },
    );

    // The other direction of the migration: someone who went looking for
    // Committer and switched it on must keep it.
    test('a stored true beats the default-hidden flag', () async {
      final ProviderContainer c = await _container(<String, Object>{
        '${GraphColumnsRepository.keyPrefix}visibility': '{"committer":true}',
      });
      final GraphColumnLayout layout = c.read(graphColumnLayoutProvider);
      expect(layout.isVisible(GbmGraphColumnId.committer), isTrue);
      expect(layout.hiddenStorageIds, <String>{'changedFiles'});
    });

    test('visibleOrder drops hidden columns but keeps the order', () async {
      final ProviderContainer c = await _container(<String, Object>{
        '${GraphColumnsRepository.keyPrefix}visibility': '{"author":false}',
      });
      final List<GbmGraphColumnId> visible = c
          .read(graphColumnLayoutProvider)
          .visibleOrder;
      expect(visible.contains(GbmGraphColumnId.author), isFalse);
      expect(_ids(visible).take(3), <String>['graph', 'message', 'refs']);
    });
  });
}
