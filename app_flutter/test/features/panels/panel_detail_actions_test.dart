// Spec page 19 樣板規則 4, second half: 「動作列在明細底部，danger 靠右」.
//
// The slot lives on GbmPanelTabShell rather than on PanelDetailColumn
// because five of the twelve panels (stashes, patches, lfs, file-history,
// line-history) have a diff-shaped detail and never build a
// PanelDetailColumn at all -- stashes' `Drop` is one of the danger buttons
// rule 2 moves out of the toolbar, so a slot on the column alone could not
// receive it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/gbm_panel_tab_shell.dart';
import 'package:gbm_flutter/features/panels/panel_toolbar_spec.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  required Widget detail,
  Widget? detailActions,
  bool detailIsEmpty = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 500,
            child: GbmPanelTabShell(
              storageId: 'test.detail.actions',
              toolbar: const PanelToolbarSpec(),
              list: const SizedBox.shrink(),
              detail: detail,
              detailActions: detailActions,
              detailIsEmpty: detailIsEmpty,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The button itself, not the Text inside it -- see the right-edge test.
Finder _button(String label) => find.widgetWithText(GbmButton, label);

/// An action row with one ordinary and one danger action, the shape every
/// panel's detail ends in.
Widget _actions() => PanelDetailActions(
  actions: <Widget>[GbmButton(label: 'Switch to', onPressed: () {})],
  dangerActions: <Widget>[
    GbmButton(
      label: 'Remove worktree…',
      kind: GbmButtonKind.danger,
      onPressed: () {},
    ),
  ],
);

void main() {
  group('PanelDetailActions pins danger to the right', () {
    testWidgets('the danger button right edge is the row right edge', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        detail: const PanelDetailColumn(
          children: <Widget>[PanelDetailField(label: 'Path', value: '/tmp/wt')],
        ),
        detailActions: _actions(),
      );

      final Rect row = tester.getRect(find.byType(PanelDetailActions));
      final Rect danger = tester.getRect(_button('Remove worktree…'));

      // The tight form of the claim. "danger is to the right of the others"
      // holds under both MainAxisAlignment.spaceBetween and .start, so it
      // proves neither ([TEST-fixture-cannot-disagree] shape 8).
      //
      // Measured on the button, not on its Text: the Text sits inside the
      // button's own padding, so asserting against it would be off by that
      // padding and tempt a loose epsilon that stops proving anything.
      expect(
        row.right - danger.right,
        GbmSpacing.space3,
        reason: 'danger sits at the row right edge, less the row padding',
      );

      final Rect ordinary = tester.getRect(_button('Switch to'));
      expect(ordinary.right, lessThan(danger.left));
    });

    testWidgets('the action row does not scroll away with the fields', (
      tester,
    ) async {
      // Enough fields to overflow the 500px-tall pane several times over.
      await _pumpShell(
        tester,
        detail: PanelDetailColumn(
          children: List<Widget>.generate(
            40,
            (int i) => PanelDetailField(label: 'Field $i', value: 'value $i'),
          ),
        ),
        detailActions: _actions(),
      );

      final Rect before = tester.getRect(find.byType(PanelDetailActions));
      await tester.drag(find.byType(PanelDetailColumn), const Offset(0, -400));
      await tester.pumpAndSettle();
      final Rect after = tester.getRect(find.byType(PanelDetailActions));

      expect(
        after,
        before,
        reason:
            'appending the buttons inside the scroll view is the bug this '
            'slot exists to avoid',
      );
      expect(find.text('Remove worktree…'), findsOneWidget);
    });

    testWidgets('it works for a diff-shaped detail with no PanelDetailColumn', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        detail: const Center(child: Text('a diff lives here')),
        detailActions: _actions(),
      );

      expect(find.byType(PanelDetailColumn), findsNothing);
      final Rect row = tester.getRect(find.byType(PanelDetailActions));
      final Rect danger = tester.getRect(_button('Remove worktree…'));
      expect(row.right - danger.right, GbmSpacing.space3);
    });

    testWidgets('nothing is drawn when no item is selected', (tester) async {
      await _pumpShell(
        tester,
        detail: const SizedBox.shrink(),
        detailActions: _actions(),
        detailIsEmpty: true,
      );

      expect(
        find.byType(PanelDetailActions),
        findsNothing,
        reason: 'an action row with no subject would act on nothing',
      );
    });
  });
}
