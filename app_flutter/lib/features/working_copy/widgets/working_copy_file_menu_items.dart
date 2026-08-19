import 'package:flutter/material.dart';

import '../../../widgets/gbm_menu.dart';

/// `ctxItemsFor('unstaged-file'|'staged-file')` from gbm_context_menus.dart's
/// 05-F (File, staged / unstaged) -- 6 top-level items, danger last.
///
/// Spec 05-F: "有多選時全部動作改為複數並帶數量，例如 Stage 3 files" -- but
/// only for the actions that genuinely operate on the batch. The spec's own
/// mock renders `Open file` and `Show in file manager` singular right next to
/// `Stage 3 files`, so those two act on the right-clicked row; [count] only
/// pluralizes Stage/Unstage and Discard.
///
/// [onDiscard] is nullable and is the only omittable item: discarding
/// restores the work tree from the index, so there is nothing for it to do
/// on the staged side. Every other callback is required -- none of them
/// depends on repository state.
///
/// Blame / File History / Line History used to sit between `Copy path` and
/// the danger item. They are beyond-spec and had to go when the two missing
/// spec items were added: `showGbmContextMenu` asserts spec page 05's own
/// "最多 8 項" cap, and 6 + 3 is 9. `GbmMenuItem.submenu`'s flyout is not
/// implemented (see gbm_menu.dart's doc comment), so nesting them was not an
/// option either. All three stay reachable from `tab_row.dart`'s overflow
/// menu; what is lost is only the pre-filled path, not the feature.
List<GbmMenuItem> workingCopyFileMenuItems({
  required int count,
  required bool fromStaged,
  required VoidCallback onStageToggle,
  required VoidCallback onOpenFile,
  required VoidCallback onShowInFileManager,
  required VoidCallback onOpenTerminal,
  required VoidCallback onCopyPath,
  required VoidCallback? onDiscard,
}) {
  final String countSuffix = count == 1 ? '' : ' $count files';
  return <GbmMenuItem>[
    GbmMenuItem(
      label: '${fromStaged ? 'Unstage' : 'Stage'}$countSuffix',
      icon: fromStaged ? Icons.remove : Icons.add,
      onTap: onStageToggle,
    ),
    GbmMenuItem(label: 'Open file', icon: Icons.open_in_new, onTap: onOpenFile),
    GbmMenuItem(
      label: 'Show in file manager',
      icon: Icons.folder_open,
      onTap: onShowInFileManager,
    ),
    GbmMenuItem(
      label: 'Open terminal here',
      icon: Icons.terminal,
      onTap: onOpenTerminal,
    ),
    GbmMenuItem(label: 'Copy path', icon: Icons.copy, onTap: onCopyPath),
    if (onDiscard != null) ...<GbmMenuItem>[
      const GbmMenuItem.separator(),
      GbmMenuItem(
        label: 'Discard changes${count == 1 ? '' : ' in $count files'}…',
        icon: Icons.delete_outline,
        danger: true,
        onTap: onDiscard,
      ),
    ],
  ];
}
