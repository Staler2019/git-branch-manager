// Spec page 19 樣板規則 2: 「工具列固定四段：主要建立動作（primary）、批次
// 維護動作（ghost）、分隔線、跳出去的動作；右端固定是 filter。破壞性動作
// 不放工具列，只在明細區或右鍵。」
//
// What is fixed is the *order*, not the occupancy. A read-only panel
// (blame, line-history) genuinely has no 主要建立動作, and pinning that
// reading here is what stops every read-only panel from growing a
// placeholder primary button to fill a segment the spec never said had to
// be full.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/gbm_panel_tab_shell.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_toolbar_spec.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpToolbar(WidgetTester tester, PanelToolbarSpec spec) async {
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
            width: 800,
            height: 400,
            child: GbmPanelTabShell(
              storageId: 'test.toolbar.spec',
              toolbarSpec: spec,
              list: const SizedBox.shrink(),
              detail: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PanelToolbarSpec _fullSpec({bool withFilter = true}) => PanelToolbarSpec(
  primary: <Widget>[
    GbmButton(
      label: 'Add worktree…',
      kind: GbmButtonKind.primary,
      onPressed: () {},
    ),
  ],
  maintenance: <Widget>[
    GbmButton(label: 'Prune', kind: GbmButtonKind.ghost, onPressed: () {}),
  ],
  external: <Widget>[GbmButton(label: 'Open in terminal', onPressed: () {})],
  filter: withFilter
      ? PanelFilterField(
          query: '',
          onChanged: (_) {},
          hintText: 'Filter worktrees',
        )
      : null,
);

Finder _button(String label) => find.widgetWithText(GbmButton, label);

void main() {
  group('PanelToolbarSpec lays out P19 rule 2的四段', () {
    testWidgets('order is primary, maintenance, separator, external, filter', (
      tester,
    ) async {
      await _pumpToolbar(tester, _fullSpec());

      final double primary = tester.getRect(_button('Add worktree…')).right;
      final double maintenance = tester.getRect(_button('Prune')).left;
      final double separator = tester
          .getRect(find.byType(PanelToolbarSeparator))
          .left;
      final double external = tester.getRect(_button('Open in terminal')).left;
      final double filter = tester.getRect(find.byType(PanelFilterField)).left;

      expect(primary, lessThanOrEqualTo(maintenance));
      expect(
        tester.getRect(_button('Prune')).right,
        lessThanOrEqualTo(separator),
      );
      expect(separator, lessThanOrEqualTo(external));
      expect(external, lessThan(filter));
    });

    testWidgets('the filter is pinned to the toolbar right end', (
      tester,
    ) async {
      await _pumpToolbar(tester, _fullSpec());

      final Rect toolbar = tester.getRect(find.byType(PanelToolbarRow));
      final Rect filter = tester.getRect(find.byType(PanelFilterField));

      expect(
        toolbar.right - filter.right,
        GbmSpacing.space3,
        reason: '「右端固定是 filter」, less the toolbar padding',
      );
    });

    testWidgets('an empty segment draws nothing, not a placeholder', (
      tester,
    ) async {
      // A read-only panel: no create action, no external action.
      await _pumpToolbar(
        tester,
        PanelToolbarSpec(
          maintenance: <Widget>[
            GbmButton(
              label: 'Ignore whitespace',
              kind: GbmButtonKind.ghost,
              onPressed: () {},
            ),
          ],
          filter: PanelFilterField(query: '', onChanged: (_) {}),
        ),
      );

      expect(find.byType(GbmButton), findsOneWidget);
      expect(
        find.byType(PanelToolbarSeparator),
        findsNothing,
        reason: 'a separator with nothing on one side of it separates nothing',
      );
    });

    testWidgets('the separator appears only between two occupied segments', (
      tester,
    ) async {
      await _pumpToolbar(
        tester,
        PanelToolbarSpec(
          primary: <Widget>[GbmButton(label: 'Start', onPressed: () {})],
          maintenance: <Widget>[
            GbmButton(label: 'Reset order', onPressed: () {}),
          ],
          filter: PanelFilterField(query: '', onChanged: (_) {}),
        ),
      );

      expect(find.byType(PanelToolbarSeparator), findsNothing);
    });

    testWidgets('a panel whose list cannot be filtered says so', (
      tester,
    ) async {
      // blame and line-history list file *content*, not a named collection,
      // and interactive-rebase and bisect have writable lists where a
      // filtered order is not the real order. Disabled with a reason beats
      // hidden -- 隱藏會讓人以為功能不存在 ([FLU-menu-enabled-is-visual-only]).
      await _pumpToolbar(
        tester,
        PanelToolbarSpec(
          filter: const PanelFilterField(
            query: '',
            onChanged: null,
            disabledReason: '這個清單是檔案內容，沒有可篩選的名稱',
          ),
        ),
      );

      final PanelFilterField field = tester.widget(
        find.byType(PanelFilterField),
      );
      expect(field.enabled, isFalse);
      expect(field.disabledReason, isNotEmpty);
      expect(
        find.byType(Tooltip),
        findsWidgets,
        reason: 'the reason has to be reachable, not just stored',
      );
    });
  });

  group('the two toolbar APIs cannot both be supplied', () {
    test('exactly one of toolbar / toolbarSpec is required', () {
      expect(
        () => GbmPanelTabShell(
          storageId: 'x',
          toolbar: const <Widget>[],
          toolbarSpec: const PanelToolbarSpec(),
          list: const SizedBox.shrink(),
          detail: const SizedBox.shrink(),
        ),
        throwsAssertionError,
      );
      expect(
        () => GbmPanelTabShell(
          storageId: 'x',
          list: const SizedBox.shrink(),
          detail: const SizedBox.shrink(),
        ),
        throwsAssertionError,
      );
    });
  });
}
