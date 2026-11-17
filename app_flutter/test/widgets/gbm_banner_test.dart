// read-failure-states-spec.html, candidate A: a panel's failed read is a
// `.gbm-banner-warning` with an `Open log` button after the message, the way
// P07's conflict mock puts its buttons after a `flex:1` message.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';

Future<void> _pump(WidgetTester tester, Widget banner) => tester.pumpWidget(
  MaterialApp(
    theme: buildGbmTheme(GbmThemeVariant.values.first),
    home: Scaffold(body: banner),
  ),
);

void main() {
  testWidgets('the action renders after the message, 8 apart', (tester) async {
    await _pump(
      tester,
      const GbmWarningBanner(
        message: 'blame failed',
        action: SizedBox(key: ValueKey<String>('act'), width: 40, height: 20),
      ),
    );

    final Rect message = tester.getRect(find.text('blame failed'));
    final Rect action = tester.getRect(
      find.byKey(const ValueKey<String>('act')),
    );
    expect(action.left - message.right, 8);
  });

  testWidgets('without an action the banner is unchanged', (tester) async {
    await _pump(tester, const GbmWarningBanner(message: 'm'));

    final Rect banner = tester.getRect(find.byType(GbmWarningBanner));
    final Rect message = tester.getRect(find.text('m'));
    expect(banner.right - message.right, 16);
  });
}
