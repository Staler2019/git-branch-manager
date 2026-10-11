import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_field_kinds.dart';
import 'package:gbm_flutter/widgets/gbm_ref_picker.dart';
import 'package:gbm_flutter/widgets/gbm_ref_read_only_field.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

Future<void> _pump(WidgetTester tester, GbmRefKind kind) => tester.pumpWidget(
  MaterialApp(
    theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
    home: Scaffold(
      body: GbmRefReadOnlyField(label: '基於', name: 'origin/main', kind: kind),
    ),
  ),
);

void main() {
  for (final GbmRefKind kind in GbmRefKind.values) {
    testWidgets('draws the ${kind.name} icon the picker rows use', (
      tester,
    ) async {
      await _pump(tester, kind);
      expect(
        tester.widget<LucideIcon>(find.byType(LucideIcon)).name,
        kind.iconName,
      );
    });
  }

  testWidgets('is a labelled GbmDialogReadOnlyField with the name in mono', (
    tester,
  ) async {
    await _pump(tester, GbmRefKind.remoteBranch);
    expect(
      tester
          .widget<GbmDialogReadOnlyField>(find.byType(GbmDialogReadOnlyField))
          .label,
      '基於',
    );
    expect(
      tester.widget<Text>(find.text('origin/main')).style!.fontFamily,
      GbmTypography.fontMono,
    );
  });
}
