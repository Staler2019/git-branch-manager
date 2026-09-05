// GbmKbdChip is extracted from keyboard_shortcuts_dialog.dart's inline
// Container (worktree-dialogs-spec.html G5b) -- surface-sunken fill, 1px
// border-default, r4. This pins the widget's own rendering directly, so a
// future edit to the shared widget is caught here rather than only via its
// two call sites' own tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_kbd_chip.dart';

Future<void> _pump(WidgetTester tester, String label) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: Center(child: GbmKbdChip(label: label)),
      ),
    ),
  );
}

void main() {
  group('GbmKbdChip', () {
    testWidgets('renders the given label', (tester) async {
      await _pump(tester, '⌘⇧B');

      expect(find.text('⌘⇧B'), findsOneWidget);
    });

    testWidgets('is a surface-sunken pill with a 1px border-default and r4', (
      tester,
    ) async {
      await _pump(tester, 'Ctrl+S');

      final Container box = tester.widget<Container>(
        find.descendant(
          of: find.byType(GbmKbdChip),
          matching: find.byType(Container),
        ),
      );
      final BoxDecoration decoration = box.decoration! as BoxDecoration;
      final BuildContext context = tester.element(find.byType(GbmKbdChip));
      final GbmColors colors = context.gbmColors;

      expect(decoration.color, colors.surfaceSunken);
      expect(decoration.border, Border.all(color: colors.borderDefault));
      expect(
        decoration.borderRadius,
        BorderRadius.circular(GbmSpacing.radiusSm),
      );
    });
  });
}
