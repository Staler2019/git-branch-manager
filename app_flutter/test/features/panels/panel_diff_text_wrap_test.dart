// PanelDiffText under the two wrap modes.
//
// This surface has no line-number gutter -- a raw unified diff carries its
// own `+`/`-` in the line text -- so there is nothing to pin here and the
// whole line scrolls. What is worth asserting is that the preference reaches
// it at all: the panel reads `appPreferencesProvider` itself rather than
// taking a parameter, because its two callers pass it nothing else either.
//
// Widths are test-font units (`flutter_test` draws every glyph `fontSize`
// wide), so the fixture's "long" line overflows far more readily here than
// the same string would in JetBrains Mono. That is the safe direction for a
// test that needs the overflow to exist.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/panel_diff_text.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _diff =
    '@@ -1,2 +1,2 @@\n'
    '-const before = oldValue(alpha, beta, gamma, delta, epsilon, zeta);\n'
    '+const after = newValue(alpha, beta, gamma, delta, epsilon, zeta, eta);';

Future<void> _pump(
  WidgetTester tester, {
  required bool softWrap,
  String text = _diff,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'appPrefs.softWrapEnabled': softWrap,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: PanelDiffText(text: text),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a diff wider than the panel scrolls sideways by default', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('turning soft wrap on removes the sideways scroll', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: true);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('a diff that already fits gets no scroller either way', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false, text: '@@ -1 +1 @@\n+x');
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('the rendered lines say which mode they are in', (
    WidgetTester tester,
  ) async {
    // The scroller's presence is a property of the pane; this is the property
    // of the *rows*, and the two are set from the same read but on different
    // widgets. Asserting only the pane left the row flag free to be wrong.
    await _pump(tester, softWrap: false);
    for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.softWrap, isFalse);
    }

    await _pump(tester, softWrap: true);
    for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.softWrap, isTrue);
    }
  });
}
