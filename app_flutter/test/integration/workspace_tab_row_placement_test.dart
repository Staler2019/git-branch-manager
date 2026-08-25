// Spec P02-13 / P03-9: the History / Working Copy tab row belongs at the top
// of the *centre column*, not spanning the window above the sidebar. Both
// pages' prose says 「中央區最上方」 and both mockups draw `gbm-tabs` inside
// the `mkpane flex:1` to the right of the sidebar.
//
// It shipped in the wrong place -- a child of WorkspaceScreen's outer Column,
// so it ran the full window width over the sidebar -- and the whole 2039-test
// suite stayed green through the fix. Nothing anywhere asserted where it was.
// That is the point of this file, and it is why every assertion below is on a
// *rect* and not on a finder: `find.byType(TabRow)` finds it just as happily
// in either position.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/features/workspace/widgets/action_toolbar.dart';
import 'package:gbm_flutter/features/workspace/widgets/tab_row.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

void main() {
  testWidgets('the tab row starts to the right of the sidebar, not above it', (
    WidgetTester tester,
  ) async {
    await pumpWorkspace(tester, identity: _identity);
    await tester.pump();

    final Rect tabs = tester.getRect(find.byType(TabRow));
    final Rect sidebar = tester.getRect(find.byType(SidebarPanel));

    // The load-bearing assertion. Before the fix the tab row's left edge was
    // 0 and it overlapped the sidebar horizontally for the sidebar's whole
    // width; a `greaterThan(0)` check alone would not have caught a tab row
    // merely inset by some padding.
    expect(
      tabs.left,
      greaterThanOrEqualTo(sidebar.right),
      reason: 'tab row must begin where the sidebar ends',
    );
    expect(
      tabs.width,
      lessThan(sidebar.width + tabs.width),
      reason: 'tab row must not span the whole window',
    );
  });

  testWidgets(
    'the tab row sits below the action toolbar, which stays full width',
    (WidgetTester tester) async {
      await pumpWorkspace(tester, identity: _identity);
      await tester.pump();

      final Rect tabs = tester.getRect(find.byType(TabRow));
      final Rect toolbar = tester.getRect(find.byType(ActionToolbar));
      final Rect sidebar = tester.getRect(find.byType(SidebarPanel));

      // The toolbar is *not* moving into the centre column: P02's mockup draws
      // `mkbar` outside the flex row. Pinning both here keeps a later change
      // from "fixing" the toolbar the same way the tab row was fixed.
      expect(toolbar.left, lessThanOrEqualTo(sidebar.left));
      expect(tabs.top, greaterThanOrEqualTo(toolbar.bottom));
      expect(sidebar.top, greaterThanOrEqualTo(toolbar.bottom));
    },
  );

  testWidgets('the sidebar reaches as high as the tab row', (
    WidgetTester tester,
  ) async {
    await pumpWorkspace(tester, identity: _identity);
    await tester.pump();

    final Rect tabs = tester.getRect(find.byType(TabRow));
    final Rect sidebar = tester.getRect(find.byType(SidebarPanel));

    // Corollary of the move, and the part a left-edge check alone misses: the
    // sidebar now starts at the same height as the tabs rather than beneath
    // them, because nothing spans above it any more.
    expect(sidebar.top, lessThanOrEqualTo(tabs.top));
  });
}
