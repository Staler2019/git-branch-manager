// Regression coverage for the action-row overflow flagged in CLAUDE.md's
// Known gaps: GbmDialogShell's actions row sits inside a fixed ~480px-wide
// Container, so "Cancel" alongside a long enough primary-action label
// overflows a plain end-aligned Row -- OverflowBar (below) is what avoids
// it, wrapping to a column once the row does not fit.
//
// The label here is a synthetic worst case, not a real one: measured
// (`[TEST-canvas-is-800x600]`'s "every glyph fontSize wide" test font,
// `GbmButton`'s 12.5px textSm + 12px horizontal padding per side), the two
// real recovery labels this shell now carries -- "Stash and checkout" /
// "Discard and checkout" -- both fit under 480px and do NOT reproduce the
// overflow (confirmed by temporarily reverting OverflowBar to a plain Row
// and re-running: green either way). At ~26+ characters the primary label
// alone pushes the row past the container width regardless of Cancel; this
// fixture is deliberately past that line so the test still reddens if
// OverflowBar is ever reverted to Row.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_shortcuts.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_shell.dart';
import 'package:gbm_flutter/widgets/gbm_kbd_chip.dart';
import 'package:go_router/go_router.dart';

Future<void> _pump(WidgetTester tester, {GbmActionId? actionId}) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => GbmDialogShell(
          title: 'Checkout blocked',
          actionId: actionId,
          actions: <Widget>[
            GbmButton(label: 'Cancel', onPressed: () {}),
            const SizedBox(width: GbmSpacing.space2),
            GbmButton(
              // Synthetic -- see header comment. Not a real button label.
              label: 'Stash all uncommitted changes before switching',
              kind: GbmButtonKind.primary,
              onPressed: () {},
            ),
          ],
          child: const SizedBox(),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a long primary action label alongside Cancel does not overflow '
      'RenderFlex', (tester) async {
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      find.text('Stash all uncommitted changes before switching'),
      findsOneWidget,
    );
  });

  // G5: worktree-dialogs-spec.html draws no ✕ in the title bar, and
  // dialog_escape_dismiss_test.dart pinned that Escape already closes every
  // routed dialog (via Flutter's own barrierDismissible DismissIntent
  // wiring) before this button was removed -- so the affordance being
  // dropped is not the only way out.
  testWidgets('draws no close (✕) button in the title bar', (tester) async {
    await _pump(tester);

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
  });

  // G5b: worktree-dialogs-spec.html's title bar carries an optional
  // shortcut chip. Only dialogs with an unambiguous GbmActionId pass one --
  // the default (no actionId) must draw nothing, and an actionId with no
  // bound shortcut is an empty slot too, not a fallback of any kind.
  group('the optional actionId shortcut chip', () {
    testWidgets('draws no chip when actionId is not given', (tester) async {
      await _pump(tester);

      expect(find.byType(GbmKbdChip), findsNothing);
    });

    testWidgets('draws no chip when actionId has no bound shortcut', (
      tester,
    ) async {
      await _pump(tester, actionId: GbmActionId.toolsStashes);

      expect(find.byType(GbmKbdChip), findsNothing);
    });

    testWidgets('draws the bound shortcut as a GbmKbdChip', (tester) async {
      await _pump(tester, actionId: GbmActionId.branchStashChanges);

      final bool isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
      final String expectedLabel = gbmActionShortcuts(
        isMacOS,
      )[GbmActionId.branchStashChanges]!.displayLabel;

      expect(find.byType(GbmKbdChip), findsOneWidget);
      expect(find.text(expectedLabel), findsOneWidget);
    });
  });

  // G6: worktree-dialogs-spec.html's Shell/Title bar rows -- surface-panel-
  // raised fill, 1px border-default around the whole shell, 13px semibold
  // title, and a border-bottom under the title bar. surfacePanelRaised is
  // measured to be a genuinely different colour from the shell's previous
  // surfaceOverlay fill (dark theme: #161B22 vs #1C2128), not a rounding.
  group('G6: the shell chrome matches the P6 full-size mock', () {
    testWidgets('the outer shell has a 1px border-default border', (
      tester,
    ) async {
      await _pump(tester);
      final GbmColors colors = buildGbmTheme(
        GbmThemeVariant.darkTechnical,
      ).extension<GbmColors>()!;

      final Container outer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GbmDialogShell),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration decoration = outer.decoration! as BoxDecoration;

      expect(decoration.border, Border.all(color: colors.borderDefault));
    });

    testWidgets('the shell fill is surfacePanelRaised, not surfaceOverlay', (
      tester,
    ) async {
      await _pump(tester);
      final GbmColors colors = buildGbmTheme(
        GbmThemeVariant.darkTechnical,
      ).extension<GbmColors>()!;

      final Material material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(GbmDialogShell),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(material.color, colors.surfacePanelRaised);
    });

    testWidgets('the title text is drawn at 13px, per the spec\'s literal '
        'number (not rounded to the existing 13.5px textBase)', (tester) async {
      await _pump(tester);

      final Text title = tester.widget<Text>(find.text('Checkout blocked'));

      expect(title.style!.fontSize, GbmTypography.dialogTitleText);
      expect(GbmTypography.dialogTitleText, 13);
      expect(title.style!.fontWeight, GbmTypography.weightSemibold);
    });

    testWidgets('the title bar has a border-bottom, separating it from the '
        'body', (tester) async {
      await _pump(tester);
      final GbmColors colors = buildGbmTheme(
        GbmThemeVariant.darkTechnical,
      ).extension<GbmColors>()!;

      final Container titleBar = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GbmDialogShell),
              matching: find.byType(Container),
            )
            .at(1),
      );
      final BoxDecoration decoration = titleBar.decoration! as BoxDecoration;

      expect(
        decoration.border,
        Border(bottom: BorderSide(color: colors.borderSubtle)),
      );
    });
  });
}
