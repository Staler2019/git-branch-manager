import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/widgets/file_list_mode_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('FileListModeToggleButton', () {
    testWidgets('renders button with list icon initially', (
      WidgetTester tester,
    ) async {
      final fakePrefs = _FakeSharedPreferences();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
          child: const MaterialApp(
            home: Scaffold(body: FileListModeToggleButton()),
          ),
        ),
      );

      // Should render the button
      expect(find.byType(FileListModeToggleButton), findsOneWidget);
      expect(find.byType(IconButton), findsWidgets);
    });

    testWidgets('toggles mode when button is tapped', (
      WidgetTester tester,
    ) async {
      final fakePrefs = _FakeSharedPreferences();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
          child: const MaterialApp(
            home: Scaffold(body: FileListModeToggleButton()),
          ),
        ),
      );

      // Find and tap the toggle button
      final buttons = find.byType(IconButton);
      expect(buttons, findsWidgets);

      await tester.tap(buttons.first);
      await tester.pumpAndSettle();

      // Default mode is list, so one tap should flip to tree.
      expect(fakePrefs.data['fileListViewMode'], 'tree');
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
