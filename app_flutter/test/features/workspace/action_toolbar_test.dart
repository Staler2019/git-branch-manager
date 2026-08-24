// Spec page 02's numbered item 2: the toolbar row under the menu bar --
// Fetch / Pull / Push (Push primary), a divider, then Branch / Stash.
//
// This is the widget tier, so it proves the row renders and dispatches;
// that the *real* WorkspaceScreen hands it the same handler map every other
// dispatch path reads, and that conflict state greys it out, is
// workspace_conflict_transition_test.dart's job (a widget test feeds the
// callbacks in directly and so can never see that seam -- CLAUDE.md's
// testing-tiers note).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/workspace/widgets/action_toolbar.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';

/// [width] null means "the full test canvas" (800 logical px, the default
/// surface -- a SizedBox wider than it is silently clamped, so a layout
/// assertion has to be made at or below that number to mean anything).
Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onFetch,
  VoidCallback? onPull,
  VoidCallback? onPush,
  VoidCallback? onBranch,
  VoidCallback? onStash,
  double? width,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ActionToolbar(
              onFetch: onFetch,
              onPull: onPull,
              onPush: onPush,
              onBranch: onBranch,
              onStash: onStash,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A no-op that still reads as "enabled" to [GbmButton] -- distinct from
/// null, which is what disables it.
void _noop() {}

GbmButton _button(WidgetTester tester, String label) =>
    tester.widget<GbmButton>(find.widgetWithText(GbmButton, label));

void main() {
  const List<String> labels = <String>[
    'Fetch',
    'Pull',
    'Push',
    'Branch',
    'Stash',
  ];

  testWidgets('renders the five buttons spec P02-2 draws', (tester) async {
    await _pump(
      tester,
      onFetch: _noop,
      onPull: _noop,
      onPush: _noop,
      onBranch: _noop,
      onStash: _noop,
    );

    for (final String label in labels) {
      expect(
        find.widgetWithText(GbmButton, label),
        findsOneWidget,
        reason: '$label is one of P02 item 2\'s toolbar buttons',
      );
    }
    expect(find.byType(GbmButton), findsNWidgets(labels.length));
  });

  testWidgets('Push is the primary button and the rest are secondary', (
    tester,
  ) async {
    // 「三顆同組。Push 為主要樣式。」-- the emphasis is the spec's, and it is
    // the only thing distinguishing the push button from its neighbours.
    await _pump(
      tester,
      onFetch: _noop,
      onPull: _noop,
      onPush: _noop,
      onBranch: _noop,
      onStash: _noop,
    );

    expect(_button(tester, 'Push').kind, GbmButtonKind.primary);
    for (final String label in <String>['Fetch', 'Pull', 'Branch', 'Stash']) {
      expect(
        _button(tester, label).kind,
        GbmButtonKind.secondary,
        reason: '$label must not compete with Push for emphasis',
      );
    }
  });

  testWidgets('every button is sm-sized, matching the mockup', (tester) async {
    await _pump(
      tester,
      onFetch: _noop,
      onPull: _noop,
      onPush: _noop,
      onBranch: _noop,
      onStash: _noop,
    );

    for (final String label in labels) {
      expect(_button(tester, label).size, GbmButtonSize.sm);
    }
  });

  testWidgets('a null callback disables only its own button', (tester) async {
    // The disabled state is GbmButton's own `onPressed == null` rendering --
    // there is deliberately no separate `enabled` flag to fall out of sync
    // with it (the GbmMenuItem.enabled trap, CLAUDE.md).
    await _pump(
      tester,
      onFetch: null,
      onPull: _noop,
      onPush: _noop,
      onBranch: _noop,
      onStash: _noop,
    );

    expect(_button(tester, 'Fetch').onPressed, isNull);
    for (final String label in <String>['Pull', 'Push', 'Branch', 'Stash']) {
      expect(
        _button(tester, label).onPressed,
        isNotNull,
        reason: 'one null handler must not disable the whole row',
      );
    }
  });

  testWidgets('all five disabled when every handler is null', (tester) async {
    await _pump(tester);

    for (final String label in labels) {
      expect(_button(tester, label).onPressed, isNull);
    }
  });

  group('dispatch', () {
    // Counts, not `.any()`: a double dispatch (e.g. an InkWell nested inside
    // another tappable) is exactly the regression this shape hides.
    for (final String label in labels) {
      testWidgets('tapping $label calls its own callback exactly once', (
        tester,
      ) async {
        final Map<String, int> calls = <String, int>{
          for (final String l in labels) l: 0,
        };
        await _pump(
          tester,
          onFetch: () => calls['Fetch'] = calls['Fetch']! + 1,
          onPull: () => calls['Pull'] = calls['Pull']! + 1,
          onPush: () => calls['Push'] = calls['Push']! + 1,
          onBranch: () => calls['Branch'] = calls['Branch']! + 1,
          onStash: () => calls['Stash'] = calls['Stash']! + 1,
        );

        await tester.tap(find.widgetWithText(GbmButton, label));
        await tester.pump();

        expect(calls[label], 1);
        for (final MapEntry<String, int> e in calls.entries) {
          if (e.key == label) continue;
          expect(e.value, 0, reason: 'tapping $label must not fire ${e.key}');
        }
      });
    }
  });

  group('narrow window', () {
    testWidgets('the whole row fits the default 800px canvas', (tester) async {
      await _pump(
        tester,
        onFetch: _noop,
        onPull: _noop,
        onPush: _noop,
        onBranch: _noop,
        onStash: _noop,
      );

      expect(tester.takeException(), isNull);
      // "No exception" alone would also pass on a row scrolled so far that
      // the last button sits off-screen, so assert the trailing edge -- the
      // app's own default window is 1280 wide and this row must not need
      // scrolling anywhere near it.
      expect(tester.getRect(find.text('Stash')).right, lessThanOrEqualTo(800));
    });

    testWidgets('scrolls instead of overflowing at 320px', (tester) async {
      // Below any real window, but this is the guard MenuBarRow already has
      // and TopBar (per the ledger) does not: a RenderFlex overflow is a
      // thrown error in debug/test builds, not a visual clip.
      await _pump(
        tester,
        onFetch: _noop,
        onPull: _noop,
        onPush: _noop,
        onBranch: _noop,
        onStash: _noop,
        width: 320,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(GbmButton), findsNWidgets(labels.length));
    });

    testWidgets('the first button stays visible at 320px', (tester) async {
      // Expanded satisfies "no overflow" while collapsing its child to zero
      // (ledger, History column round), so the absence of an exception is
      // not the same claim as "Fetch is reachable".
      await _pump(
        tester,
        onFetch: _noop,
        onPull: _noop,
        onPush: _noop,
        onBranch: _noop,
        onStash: _noop,
        width: 320,
      );

      final Rect fetch = tester.getRect(find.text('Fetch'));
      expect(fetch.width, greaterThan(0));
      expect(fetch.left, greaterThanOrEqualTo(0));
      expect(fetch.right, lessThanOrEqualTo(320));
    });
  });
}
