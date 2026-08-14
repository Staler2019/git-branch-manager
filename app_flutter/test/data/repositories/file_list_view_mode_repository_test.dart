import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('FileListViewModeRepository', () {
    test('read returns list mode by default when nothing is stored', () {
      final fakePrefs = _FakeSharedPreferences();

      final repo = FileListViewModeRepository(fakePrefs);
      final result = repo.read();

      expect(result, FileListViewMode.list);
    });

    test('read returns tree mode when stored as "tree"', () {
      final fakePrefs = _FakeSharedPreferences();
      fakePrefs.data['fileListViewMode'] = 'tree';

      final repo = FileListViewModeRepository(fakePrefs);
      final result = repo.read();

      expect(result, FileListViewMode.tree);
    });

    test('read returns list mode when stored value is invalid', () {
      final fakePrefs = _FakeSharedPreferences();
      fakePrefs.data['fileListViewMode'] = 'invalid';

      final repo = FileListViewModeRepository(fakePrefs);
      final result = repo.read();

      expect(result, FileListViewMode.list);
    });

    test('write persists tree mode to shared preferences', () async {
      final fakePrefs = _FakeSharedPreferences();

      final repo = FileListViewModeRepository(fakePrefs);
      await repo.write(FileListViewMode.tree);

      expect(fakePrefs.data['fileListViewMode'], 'tree');
    });

    test('write persists list mode to shared preferences', () async {
      final fakePrefs = _FakeSharedPreferences();

      final repo = FileListViewModeRepository(fakePrefs);
      await repo.write(FileListViewMode.list);

      expect(fakePrefs.data['fileListViewMode'], 'list');
    });
  });

  group('fileListViewModeProvider', () {
    test('default value is list mode', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_FakeSharedPreferences()),
        ],
      );
      addTearDown(container.dispose);

      final result = container.read(fileListViewModeProvider);

      expect(result, FileListViewMode.list);
    });

    test('read persisted tree mode from shared preferences', () {
      final fakePrefs = _FakeSharedPreferences();
      fakePrefs.data['fileListViewMode'] = 'tree';

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
      );
      addTearDown(container.dispose);

      final result = container.read(fileListViewModeProvider);

      expect(result, FileListViewMode.tree);
    });

    test(
      'setMode updates the state and persists to shared preferences',
      () async {
        final fakePrefs = _FakeSharedPreferences();

        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
        );
        addTearDown(container.dispose);

        final notifier = container.read(fileListViewModeProvider.notifier);
        await notifier.setMode(FileListViewMode.tree);

        final result = container.read(fileListViewModeProvider);

        expect(result, FileListViewMode.tree);
        expect(fakePrefs.data['fileListViewMode'], 'tree');
      },
    );
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
