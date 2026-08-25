import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/file_list_mode_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<_FakeSharedPreferences> pump(WidgetTester tester) async {
    final _FakeSharedPreferences fakePrefs = _FakeSharedPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(fakePrefs)],
        child: MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: const Scaffold(body: FileListModeToggleButton()),
        ),
      ),
    );
    return fakePrefs;
  }

  group('FileListModeToggleButton', () {
    testWidgets('renders both keys of P03-10\'s two-key switch', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      // A single toggling button showed the mode you were *not* in, so the
      // control contradicted the list it sat above. Both keys are always
      // present; which one is lit is the state.
      expect(find.byIcon(Icons.list), findsOneWidget);
      expect(find.byIcon(Icons.account_tree), findsOneWidget);
    });

    testWidgets('the key for the current mode is the lit one', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

      Color? fillBehind(IconData icon) {
        final Container box = tester.widget<Container>(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
              .first,
        );
        return (box.decoration as BoxDecoration?)?.color;
      }

      // Default mode is list.
      expect(fillBehind(Icons.list)?.toARGB32(), colors.accent.toARGB32());
      expect(
        fillBehind(Icons.account_tree),
        isNull,
        reason: 'only the active key carries the accent fill',
      );
    });

    testWidgets('tapping the other key switches and persists the mode', (
      WidgetTester tester,
    ) async {
      final _FakeSharedPreferences fakePrefs = await pump(tester);

      await tester.tap(find.byIcon(Icons.account_tree));
      await tester.pumpAndSettle();

      expect(fakePrefs.data['fileListViewMode'], 'tree');
    });

    testWidgets('tapping the key you are already on does nothing', (
      WidgetTester tester,
    ) async {
      final _FakeSharedPreferences fakePrefs = await pump(tester);

      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();

      expect(
        fakePrefs.data.containsKey('fileListViewMode'),
        isFalse,
        reason:
            'the list key is already active -- with a single toggling button '
            'this same tap flipped the mode instead',
      );
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
