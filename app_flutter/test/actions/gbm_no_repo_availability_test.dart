// What the window offers with no repository open (spec page 15 A #1: 「menu
// bar 不隱藏，只把需要 repo 的選單 disabled」). One map, read by the in-window
// menu, the macOS system menu and the keyboard alike ([ACT-one-handler-map]).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_menu_model.dart';
import 'package:gbm_flutter/actions/gbm_no_repo_availability.dart';

void main() {
  final List<GbmActionId> menuIds = <GbmActionId>[
    for (final GbmMenuModel menu in gbmMenus)
      for (final GbmMenuItemModel item in menu.items) item.id,
  ];

  // Every id gets a callback, so a null in the result can only come from
  // the no-repository rule.
  final Map<GbmActionId, VoidCallback> everything = <GbmActionId, VoidCallback>{
    for (final GbmActionId id in menuIds) id: () {},
  };

  test('exactly the ids that need no repository keep their handler', () {
    final Map<GbmActionId, VoidCallback?> handlers = noRepoActionHandlers(
      everything,
    );
    final Set<GbmActionId> enabled = <GbmActionId>{
      for (final MapEntry<GbmActionId, VoidCallback?> e in handlers.entries)
        if (e.value != null) e.key,
    };
    expect(enabled, <GbmActionId>{
      GbmActionId.fileNewRepository,
      GbmActionId.fileOpenRepository,
      GbmActionId.fileCloneRepository,
      GbmActionId.fileSwitchRepository,
      GbmActionId.fileAddLocalRepository,
      GbmActionId.filePreferences,
      GbmActionId.fileExit,
      GbmActionId.editUndo,
      GbmActionId.editRedo,
      GbmActionId.editCut,
      GbmActionId.editCopy,
      GbmActionId.editPaste,
      GbmActionId.editSelectAll,
      GbmActionId.viewLog,
      GbmActionId.helpDocumentation,
      GbmActionId.helpKeyboardShortcuts,
      GbmActionId.helpReportAnIssue,
      GbmActionId.helpAbout,
    });
  });

  test('every menu id is present, so a missing one cannot look enabled', () {
    expect(noRepoActionHandlers(everything).keys.toSet(), menuIds.toSet());
  });

  test('an allowed id with no callback stays null', () {
    expect(
      noRepoActionHandlers(
        <GbmActionId, VoidCallback>{},
      )[GbmActionId.fileOpenRepository],
      isNull,
    );
  });

  test('Repository, Branch, Remote, Tools are disabled whole', () {
    final Map<GbmActionId, VoidCallback?> handlers = noRepoActionHandlers(
      everything,
    );
    for (final GbmMenuModel menu in gbmMenus.where(
      (GbmMenuModel m) =>
          <String>{'Repository', 'Branch', 'Remote', 'Tools'}.contains(m.title),
    )) {
      for (final GbmMenuItemModel item in menu.items) {
        expect(handlers[item.id], isNull, reason: '${menu.title} ${item.id}');
      }
    }
  });
}
