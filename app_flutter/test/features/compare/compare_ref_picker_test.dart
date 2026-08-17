// CompareRefPicker is presentational (plain option list in, ValueChanged<String?>
// out) so it's driven directly with a MaterialApp host, no Riverpod/FFI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/compare/widgets/compare_ref_picker.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<CompareRefOption> options,
  String? value,
  required ValueChanged<String?> onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: CompareRefPicker(
          options: options,
          value: value,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

const List<CompareRefOption> _options = <CompareRefOption>[
  CompareRefOption(
    kind: CompareRefOptionKind.branch,
    label: 'main',
    value: 'main',
  ),
  CompareRefOption(
    kind: CompareRefOptionKind.branch,
    label: 'feature/foo',
    value: 'feature/foo',
  ),
  CompareRefOption(
    kind: CompareRefOptionKind.tag,
    label: 'v1.0.0',
    value: 'v1.0.0',
  ),
  CompareRefOption(
    kind: CompareRefOptionKind.stash,
    label: 'stash@{0}: WIP',
    value: 'stash@{0}',
  ),
  CompareRefOption(
    kind: CompareRefOptionKind.workingCopy,
    label: 'Working Copy',
  ),
];

void main() {
  testWidgets('shows the current value as field text', (tester) async {
    await _pump(tester, options: _options, value: 'main', onChanged: (_) {});
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('shows "Working Copy" as field text when value is null', (
    tester,
  ) async {
    await _pump(tester, options: _options, value: null, onChanged: (_) {});
    expect(find.text('Working Copy'), findsOneWidget);
  });

  testWidgets('typing filters the option list by substring', (tester) async {
    await _pump(tester, options: _options, value: 'main', onChanged: (_) {});
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'feat');
    await tester.pumpAndSettle();

    expect(find.text('feature/foo'), findsOneWidget);
    expect(find.text('v1.0.0'), findsNothing);
  });

  testWidgets('selecting an option calls onChanged with its value', (
    tester,
  ) async {
    String? selected = 'unset';
    await _pump(
      tester,
      options: _options,
      value: 'main',
      onChanged: (v) => selected = v,
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'v1.0.0');
    await tester.pumpAndSettle();
    await tester.tap(find.text('v1.0.0').last);
    await tester.pumpAndSettle();

    expect(selected, 'v1.0.0');
  });

  testWidgets('selecting Working Copy calls onChanged with null', (
    tester,
  ) async {
    String? selected = 'unset';
    await _pump(
      tester,
      options: _options,
      value: 'main',
      onChanged: (v) => selected = v,
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Working');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Working Copy').last);
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });
}
