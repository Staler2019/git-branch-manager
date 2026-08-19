import 'package:flutter/material.dart';

import '../../../widgets/gbm_menu.dart';

/// `ctxItemsFor('diff-line')` from gbm_context_menus.dart's 05-G (Diff line /
/// line selection) -- 5 top-level items, danger last.
///
/// Spec's target note is "有拖選多行時第一項變成 Stage 12 lines", so [count]
/// pluralizes the first item and the danger item. `Copy lines` is plural in
/// the spec regardless of how many lines are involved, so it does not take a
/// count.
///
/// **Both hunk directions are always rendered**, with whichever one does not
/// apply disabled rather than omitted -- spec's own 05-G list has `Stage
/// hunk` and `Unstage hunk` as two separate entries. Note that
/// `GbmMenuItem.enabled` is a purely visual signal (see gbm_menu.dart's doc
/// comment), so a disabled item must also be given `onTap: null` or it still
/// dispatches; `branch_tree_item.dart`'s gone-row menu is the same pattern.
///
/// [onStageLines] is null for a context / no-newline-marker line (there is
/// nothing to stage on one), [onStageHunk] is null in a read-only diff, and
/// [onDiscardLines] is null on the staged side -- discarding rewrites the
/// work tree, and a staged-side line has nothing there to rewrite (that is
/// unstaging, which the first item already does).
List<GbmMenuItem> diffLineMenuItems({
  required int count,
  required bool staged,
  required VoidCallback? onStageLines,
  required VoidCallback? onStageHunk,
  required VoidCallback onCopyLines,
  required VoidCallback? onDiscardLines,
}) {
  final String lineSuffix = count == 1 ? '' : ' $count lines';
  final bool canStageHunk = onStageHunk != null && !staged;
  final bool canUnstageHunk = onStageHunk != null && staged;
  return <GbmMenuItem>[
    GbmMenuItem(
      label: '${staged ? 'Unstage' : 'Stage'}$lineSuffix',
      icon: staged ? Icons.remove : Icons.add,
      enabled: onStageLines != null,
      onTap: onStageLines,
    ),
    GbmMenuItem(
      label: 'Stage hunk',
      icon: Icons.playlist_add,
      enabled: canStageHunk,
      onTap: canStageHunk ? onStageHunk : null,
    ),
    GbmMenuItem(
      label: 'Unstage hunk',
      icon: Icons.playlist_remove,
      enabled: canUnstageHunk,
      onTap: canUnstageHunk ? onStageHunk : null,
    ),
    GbmMenuItem(label: 'Copy lines', icon: Icons.copy, onTap: onCopyLines),
    if (onDiscardLines != null) ...<GbmMenuItem>[
      const GbmMenuItem.separator(),
      GbmMenuItem(
        label: 'Discard$lineSuffix…',
        icon: Icons.delete_outline,
        danger: true,
        onTap: onDiscardLines,
      ),
    ],
  ];
}
