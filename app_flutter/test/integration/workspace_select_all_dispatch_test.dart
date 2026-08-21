// The three-path invariant for GbmActionId.editSelectAll, plus the focus
// routing that makes one Ctrl/Cmd+A mean two different things.
//
// CLAUDE.md's Intent / Action layer: keyboard, macOS system menu and the
// in-window menu all read the ONE map WorkspaceScreen._buildActionHandlers()
// builds. A null entry greys the macOS item and silently no-ops the
// keyboard path while the in-window menu keeps working -- the shape a real
// shipped bug already took once. Ctrl/Cmd+A is the riskiest id to get wrong
// here, because it is also every TextField's "select all text": binding it
// app-wide with a list-only handler would break typing everywhere.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_menu_model.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/workspace/widgets/menu_bar_row.dart';

import '../support/pump_workspace.dart';

void main() {
  final RepoIdentity identity = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );

  testWidgets('editSelectAll is a real, non-null entry in the one shared '
      'handler map', (tester) async {
    await pumpWorkspace(tester, identity: identity);

    final MenuBarRow menuBar = tester.widget<MenuBarRow>(
      find.byType(MenuBarRow),
    );
    expect(
      menuBar.actionHandlers.containsKey(GbmActionId.editSelectAll),
      isTrue,
      reason: 'the map every dispatch path reads must carry the id',
    );
    expect(
      menuBar.actionHandlers[GbmActionId.editSelectAll],
      isNotNull,
      reason:
          'a null here greys the macOS menu item and no-ops the keyboard '
          'path while the in-window menu still works',
    );
  });

  testWidgets('Edit -> Select all renders in the in-window menu', (
    tester,
  ) async {
    await pumpWorkspace(tester, identity: identity);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('the menu model lists it under Edit, right after Paste', (
    tester,
  ) async {
    final GbmMenuModel edit = gbmMenus.firstWhere(
      (GbmMenuModel menu) => menu.title == 'Edit',
    );
    final List<GbmActionId> ids = <GbmActionId>[
      for (final GbmMenuItemModel item in edit.items) item.id,
    ];
    expect(
      ids.indexOf(GbmActionId.editSelectAll),
      ids.indexOf(GbmActionId.editPaste) + 1,
    );
  });

  testWidgets('Ctrl+A over a focused text field still selects its text, '
      'not anything else', (tester) async {
    // The handler routes by focus rather than owning the key outright, so
    // a field keeps the behaviour the OS trained the user to expect.
    final TextEditingController controller = TextEditingController(
      text: 'hello world',
    );
    addTearDown(controller.dispose);

    await pumpWorkspace(
      tester,
      identity: identity,
      historyBuilder: (BuildContext context, _) => Scaffold(
        body: TextField(key: const Key('subject'), controller: controller),
      ),
    );

    // By key, not by type: the sidebar's own branch filter is also a
    // TextField, so `find.byType` matches two.
    await tester.tap(find.byKey(const Key('subject')));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(controller.selection.start, 0);
    expect(controller.selection.end, controller.text.length);
  });
}
