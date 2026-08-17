// Regression coverage for the action-row overflow flagged in CLAUDE.md's
// Known gaps: GbmDialogShell's actions Row (mainAxisAlignment: end, no
// Flexible/Wrap) sits inside a fixed ~480px-wide Container, so "Cancel"
// alongside a long primary-action label overflows RenderFlex -- reproduced
// here with CheckoutRecoveryDialogContent's real label
// ("Stash changes and checkout"), the exact case
// workspace_interrupt_overlay_test.dart deliberately worked around with a
// shorter fixture label to avoid tripping this bug.
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
              label: 'Stash changes and checkout',
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
    expect(find.text('Stash changes and checkout'), findsOneWidget);
  });
}
