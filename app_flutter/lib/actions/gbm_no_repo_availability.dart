import 'package:flutter/foundation.dart';

import 'gbm_action_id.dart';
import 'gbm_menu_model.dart';

/// The actions a window with no repository open still offers -- spec page 15
/// A #1: 「menu bar 不隱藏，只把需要 repo 的選單 disabled」. View, Repository,
/// Branch, Remote and Tools are drawn disabled; File, Edit and Help are not.
///
/// Within those, an id that acts on a repository is still off: Close window
/// (there is no repository to close back from), and Edit's three finds, which
/// search a history, a working copy and a branch list that do not exist.
///
/// View → Log is the one View item kept: the welcome screen has a Log (R13)
/// and `Ctrl/Cmd+Shift+L` must open it, and the keyboard and the menus read
/// one map ([ACT-one-handler-map]), so the shortcut working means the menu
/// item is enabled too.
const Set<GbmActionId> noRepoActionIds = <GbmActionId>{
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
};

/// The no-repository window's handler map: one entry per [gbmMenus] item,
/// [callbacks]' handler where [noRepoActionIds] allows it, null otherwise --
/// a null is what greys the item out on every dispatch path.
Map<GbmActionId, VoidCallback?> noRepoActionHandlers(
  Map<GbmActionId, VoidCallback> callbacks,
) => <GbmActionId, VoidCallback?>{
  for (final GbmMenuModel menu in gbmMenus)
    for (final GbmMenuItemModel item in menu.items)
      item.id: noRepoActionIds.contains(item.id) ? callbacks[item.id] : null,
};
