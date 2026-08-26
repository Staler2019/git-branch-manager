// Mirrors file_list_view_mode_repository_test.dart case for case -- the two
// preferences have the same shape (one enum, one flat key, a Notifier that
// writes through), so they are worth reading side by side when either moves.
//
// What they are NOT is the same setting: this one is History's diff 舊/新
// 並排 vs 統一, and `fileListViewMode` is a file *list*'s flat-vs-tree. The
// Working Copy's own `2 file` switch is a third thing again (unstaged vs
// staged, not old vs new) and deliberately shares neither.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/diff_view_mode_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DiffViewModeRepository', () {
    test('read returns unified by default when nothing is stored', () {
      final fakePrefs = _FakeSharedPreferences();

      final repo = DiffViewModeRepository(fakePrefs);

      expect(repo.read(), DiffViewMode.unified);
    });

    test('read returns side-by-side when stored as "sideBySide"', () {
      final fakePrefs = _FakeSharedPreferences();
      fakePrefs.data['diffViewMode'] = 'sideBySide';

      final repo = DiffViewModeRepository(fakePrefs);

      expect(repo.read(), DiffViewMode.sideBySide);
    });

    test('read returns unified when the stored value is unrecognised', () {
      final fakePrefs = _FakeSharedPreferences();
      fakePrefs.data['diffViewMode'] = 'invalid';

      final repo = DiffViewModeRepository(fakePrefs);

      expect(repo.read(), DiffViewMode.unified);
    });

    test('write persists side-by-side to shared preferences', () async {
      final fakePrefs = _FakeSharedPreferences();

      final repo = DiffViewModeRepository(fakePrefs);
      await repo.write(DiffViewMode.sideBySide);

      expect(fakePrefs.data['diffViewMode'], 'sideBySide');
    });

    test('write persists unified to shared preferences', () async {
      final fakePrefs = _FakeSharedPreferences();

      final repo = DiffViewModeRepository(fakePrefs);
      await repo.write(DiffViewMode.unified);

      expect(fakePrefs.data['diffViewMode'], 'unified');
    });

    test('the key is not the one the file-list switch already owns', () async {
      // Both are flat keys on the same store. Sharing one by accident would
      // make switching a file list to Tree also flip History's diff to
      // side-by-side, which no test asserting only its own key would see.
      final fakePrefs = _FakeSharedPreferences();

      await DiffViewModeRepository(fakePrefs).write(DiffViewMode.sideBySide);

      expect(fakePrefs.data.keys, contains('diffViewMode'));
      expect(fakePrefs.data.keys, isNot(contains('fileListViewMode')));
    });
  });

  group('diffViewModeProvider', () {
    test('default value is unified', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_FakeSharedPreferences()),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(diffViewModeProvider), DiffViewMode.unified);
    });

    test('reads persisted side-by-side from shared preferences', () {
      final fakePrefs = _FakeSharedPreferences();
      fakePrefs.data['diffViewMode'] = 'sideBySide';

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(diffViewModeProvider), DiffViewMode.sideBySide);
    });

    test('setMode updates the state and persists it', () async {
      final fakePrefs = _FakeSharedPreferences();

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
      );
      addTearDown(container.dispose);

      await container
          .read(diffViewModeProvider.notifier)
          .setMode(DiffViewMode.sideBySide);

      expect(container.read(diffViewModeProvider), DiffViewMode.sideBySide);
      expect(fakePrefs.data['diffViewMode'], 'sideBySide');
    });

    test('a mode set in one container survives into the next one', () async {
      // The whole point of persisting: this is the app-restart case, and the
      // only assertion here that a widget-local `setState` could not pass.
      final fakePrefs = _FakeSharedPreferences();

      final first = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
      );
      await first
          .read(diffViewModeProvider.notifier)
          .setMode(DiffViewMode.sideBySide);
      first.dispose();

      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
      );
      addTearDown(second.dispose);

      expect(second.read(diffViewModeProvider), DiffViewMode.sideBySide);
    });
  });
}

class _FakeSharedPreferences implements SharedPreferences {
  _FakeSharedPreferences() : data = {};

  final Map<String, dynamic> data;

  @override
  String? getString(String key) => data[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Set<String> getKeys() => data.keys.toSet();

  @override
  bool? getBool(String key) => throw UnimplementedError();

  @override
  double? getDouble(String key) => throw UnimplementedError();

  @override
  int? getInt(String key) => throw UnimplementedError();

  @override
  List<String>? getStringList(String key) => throw UnimplementedError();

  @override
  Future<bool> setBool(String key, bool value) => throw UnimplementedError();

  @override
  Future<bool> setDouble(String key, double value) =>
      throw UnimplementedError();

  @override
  Future<bool> setInt(String key, int value) => throw UnimplementedError();

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      throw UnimplementedError();

  @override
  Future<void> reload() => throw UnimplementedError();

  @override
  Future<bool> commit() async => true;

  @override
  bool containsKey(String key) => data.containsKey(key);

  @override
  Object? get(String key) => data[key];
}
