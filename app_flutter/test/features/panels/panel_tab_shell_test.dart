// Spec page 19's template shape: 分頁標題 → 工具列 → 左清單 → 右明細 →
// 狀態列, with rule 5's exception banner inside the panel.
//
// Every slot added here is optional and defaults to null, so the twelve
// panels keep compiling and rendering unchanged while they migrate one at a
// time. A null slot draws *nothing* rather than an empty shell -- a status
// bar reserving a strip it has no number for, or a filter field that
// filters nothing, would each be a control that lies.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/gbm_panel_tab_shell.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/split_pane.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  Widget? banner,
  Widget? listHeader,
  Widget? statusBar,
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
            height: 600,
            child: GbmPanelTabShell(
              storageId: 'test.shell.slots',
              toolbar: const <Widget>[Text('a toolbar button')],
              list: const Center(child: Text('the list')),
              detail: const Center(child: Text('the detail')),
              banner: banner,
              listHeader: listHeader,
              statusBar: statusBar,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('GbmPanelTabShell slot placement', () {
    testWidgets('banner sits under the toolbar and above the columns', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        banner: const GbmWarningBanner(message: 'gbm-lfs 的路徑已不存在。'),
      );

      final Rect toolbar = tester.getRect(find.text('a toolbar button'));
      final Rect banner = tester.getRect(find.byType(GbmWarningBanner));
      final Rect list = tester.getRect(find.text('the list'));

      expect(banner.top, greaterThanOrEqualTo(toolbar.bottom));
      expect(banner.bottom, lessThanOrEqualTo(list.top));
      // Relative to the shell, not to the 1000 the SizedBox asks for: the
      // widget-test canvas is 800x600 and silently clamps anything wider
      // ([TEST-canvas-is-800x600]).
      expect(
        banner.width,
        tester.getSize(find.byType(GbmPanelTabShell)).width,
        reason: 'rule 5 banners span the panel, not one column',
      );
    });

    testWidgets('status bar is the bottom-most thing in the panel', (
      tester,
    ) async {
      await _pumpShell(tester, statusBar: const Text('4 worktrees'));

      final Rect status = tester.getRect(find.text('4 worktrees'));
      final Rect list = tester.getRect(find.text('the list'));
      final Rect detail = tester.getRect(find.text('the detail'));

      expect(status.top, greaterThanOrEqualTo(list.bottom));
      expect(status.top, greaterThanOrEqualTo(detail.bottom));
      expect(
        status.bottom,
        tester.getRect(find.byType(GbmPanelTabShell)).bottom,
      );
    });

    testWidgets('list header sits above the list, inside the left column', (
      tester,
    ) async {
      await _pumpShell(tester, listHeader: const Text('Worktrees · 4'));

      final Rect header = tester.getRect(find.text('Worktrees · 4'));
      final Rect list = tester.getRect(find.text('the list'));
      final Rect detail = tester.getRect(find.text('the detail'));

      expect(header.bottom, lessThanOrEqualTo(list.top));
      expect(
        header.right,
        lessThanOrEqualTo(detail.left),
        reason: 'the header counts the left list, so it lives in that column',
      );
    });

    testWidgets('an absent slot leaves no gap where it would have been', (
      tester,
    ) async {
      await _pumpShell(tester);

      final Rect toolbar = tester.getRect(
        find
            .ancestor(
              of: find.text('a toolbar button'),
              matching: find.byType(Container),
            )
            .first,
      );
      final Rect columns = tester.getRect(find.byType(GbmSplitPane));
      final Rect shell = tester.getRect(find.byType(GbmPanelTabShell));

      expect(find.byType(GbmWarningBanner), findsNothing);
      // Equality, not "below": "the columns are somewhere under the toolbar"
      // is true whether or not a blank strip was reserved, so it proves
      // nothing ([TEST-fixture-cannot-disagree] shape 8). The columns begin
      // exactly at the toolbar's bottom edge and run to the panel's own,
      // which is only true when both absent slots collapse to zero.
      expect(columns.top, toolbar.bottom);
      expect(columns.bottom, shell.bottom);
    });

    testWidgets('all three slots coexist in spec order', (tester) async {
      await _pumpShell(
        tester,
        banner: const GbmWarningBanner(message: 'a path is gone'),
        listHeader: const Text('Worktrees · 4'),
        statusBar: const Text('4 worktrees · 掃描 118 ms'),
      );

      final double banner = tester
          .getRect(find.byType(GbmWarningBanner))
          .center
          .dy;
      final double header = tester
          .getRect(find.text('Worktrees · 4'))
          .center
          .dy;
      final double status = tester
          .getRect(find.text('4 worktrees · 掃描 118 ms'))
          .center
          .dy;

      expect(banner, lessThan(header));
      expect(header, lessThan(status));
    });
  });
}
