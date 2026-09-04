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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_shell.dart';
import 'package:go_router/go_router.dart';

Future<void> _pump(WidgetTester tester) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => GbmDialogShell(
          title: 'Checkout blocked',
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
}
