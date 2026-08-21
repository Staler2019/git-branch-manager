import 'package:flutter/material.dart';

import '../../../widgets/gbm_menu.dart';

/// `ctxItemsFor('unstaged-file'|'staged-file')` from gbm_context_menus.dart's
/// 05-F (File, staged / unstaged) -- 7 top-level items, danger last.
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
/// Blame / File history / Line history are back, as a `History` flyout.
///
/// Tier 1 had to drop them: `showGbmContextMenu` asserts spec page 05's own
/// "最多 8 項" cap, 6 + 3 is 9, and `GbmMenuItem.submenu`'s flyout was not
/// implemented yet, so nesting was not an option either. Tier 4 built the
/// flyout, and spec page 14 then named this exact remedy in its rule 3:
/// "context menu 的 8 項上限保留。要塞第 9 項時，作法是把同族動作收成一個
/// flyout（如 History ▸），不是把項目擠掉。" Children are P14's `FILECTXSUB`
/// verbatim. Back to 7 top-level items, cap intact, and the pre-filled path
/// Tier 1 lost is restored.
///
/// Not adopted from P14's `FILECTX` table: `Open diff`, `Ignore ▸`, and
/// renaming `Show in file manager` to `Reveal in Finder`. That table and
/// page 05's own 05-F list two different menus and `REVISIONS` never
/// reconciled them -- tracked as issue #88. Only the flyout is taken here,
/// because it is the one item page 14's *prose* calls for, and #60's lesson
/// is that a conformance verdict has to rest on the prose.
List<GbmMenuItem> workingCopyFileMenuItems({
  required int count,
  required bool fromStaged,
  required VoidCallback onStageToggle,
  required VoidCallback onOpenFile,
  required VoidCallback onShowInFileManager,
  required VoidCallback onOpenTerminal,
  required VoidCallback onCopyPath,
  required VoidCallback? onDiscard,
  required VoidCallback onFileHistory,
  required VoidCallback onBlame,
  required VoidCallback onLineHistory,
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
    GbmMenuItem.submenu(
      label: 'History',
      icon: Icons.history,
      children: <GbmMenuItem>[
        GbmMenuItem(label: 'File history…', onTap: onFileHistory),
        GbmMenuItem(label: 'Blame…', onTap: onBlame),
        GbmMenuItem(label: 'Line history…', onTap: onLineHistory),
      ],
    ),
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
