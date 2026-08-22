// The column picker's state, and the derived set CommitGraphView consumes.
//
// Before this existed, GraphColumnsSelector held the visibility map in its
// own State and wrote it straight to SharedPreferences. Nothing under lib/
// ever read it back for rendering, so switching Author off changed the
// stored preference and nothing else -- the picker was a no-op UI. These
// tests pin both halves: that a change is persisted, and that it is
// broadcast in the shape the render path asks for.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

void main() {
  group('graphColumnVisibilityProvider', () {
    test('starts from what the repository has persisted', () async {
      final ProviderContainer c = await _container(<String, Object>{
        '${GraphColumnsRepository.keyPrefix}visibility':
            '{"author":false,"date":true}',
      });

      expect(c.read(graphColumnVisibilityProvider)['author'], isFalse);
      expect(c.read(graphColumnVisibilityProvider)['date'], isTrue);
    });

    test('an unseen column defaults to visible', () async {
      final ProviderContainer c = await _container();
      expect(
        isGraphColumnVisible(c.read(graphColumnVisibilityProvider), 'hash'),
        isTrue,
      );
    });

    test('setVisible publishes a new state', () async {
      final ProviderContainer c = await _container();
      await c
          .read(graphColumnVisibilityProvider.notifier)
          .setVisible('author', false);

      expect(c.read(graphColumnVisibilityProvider)['author'], isFalse);
    });

    test('setVisible persists through the repository', () async {
      final ProviderContainer c = await _container();
      await c
          .read(graphColumnVisibilityProvider.notifier)
          .setVisible('author', false);

      expect(
        c.read(graphColumnsRepositoryProvider).readVisibility()['author'],
        isFalse,
      );
    });

    test('refuses to hide a locked column', () async {
      // Spec P02 item 16: Graph and Message are 固定不可關. The picker
      // already renders them disabled, but the store is the place that has
      // to hold the line -- a disabled checkbox is a UI affordance, not an
      // invariant.
      final ProviderContainer c = await _container();
      await c
          .read(graphColumnVisibilityProvider.notifier)
          .setVisible('graph', false);

      expect(
        isGraphColumnVisible(c.read(graphColumnVisibilityProvider), 'graph'),
        isTrue,
      );
    });
  });

  group('hiddenGraphColumnsProvider', () {
    test('is empty by default', () async {
      final ProviderContainer c = await _container();
      expect(c.read(hiddenGraphColumnsProvider), isEmpty);
    });

    test('collects the columns switched off', () async {
      final ProviderContainer c = await _container();
      final GraphColumnVisibilityNotifier n = c.read(
        graphColumnVisibilityProvider.notifier,
      );
      await n.setVisible('author', false);
      await n.setVisible('date', false);

      expect(c.read(hiddenGraphColumnsProvider), <String>{'author', 'date'});
    });

    test('never reports a locked column as hidden', () async {
      // Even if a corrupt or hand-edited preferences file says otherwise.
      final ProviderContainer c = await _container(<String, Object>{
        '${GraphColumnsRepository.keyPrefix}visibility':
            '{"graph":false,"message":false,"date":false}',
      });

      expect(c.read(hiddenGraphColumnsProvider), <String>{'date'});
    });
  });
}
