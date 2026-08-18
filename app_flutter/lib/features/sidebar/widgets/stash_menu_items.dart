import 'package:flutter/material.dart';

import '../../../widgets/gbm_menu.dart';

/// `ctxItemsFor('stash')` from gbm_context_menus.dart's 05-H (Stash entry)
/// -- 6 top-level items, danger last.
///
/// [onApply]/[onPop]/[onCreateBranch] are nullable: like TabRow's
/// Merge/Cherry-pick/Reset (see its `conflictActive` doc comment), all
/// three touch the working tree/index (apply and pop the same way a merge
/// would, `git stash branch` additionally checks out a new branch), so the
/// caller passes `null` for each while a conflict is active rather than
/// this widget re-deriving `session.conflictActive` itself. [onViewDiff]/
/// [onCompare]/[onDrop] stay enabled regardless -- none of the three
/// touches the current HEAD, index, or working tree.
List<GbmMenuItem> stashMenuItems({
  required VoidCallback? onApply,
  required VoidCallback? onPop,
  required VoidCallback? onCreateBranch,
  required VoidCallback onViewDiff,
  required VoidCallback onCompare,
  required VoidCallback onDrop,
}) {
  return <GbmMenuItem>[
    GbmMenuItem(
      label: 'Apply stash',
      icon: Icons.unarchive_outlined,
      enabled: onApply != null,
      onTap: onApply,
    ),
    GbmMenuItem(
      label: 'Pop stash',
      icon: Icons.move_to_inbox_outlined,
      enabled: onPop != null,
      onTap: onPop,
    ),
    GbmMenuItem(
      label: 'Create branch from stash…',
      icon: Icons.call_split,
      enabled: onCreateBranch != null,
      onTap: onCreateBranch,
    ),
    GbmMenuItem(
      label: 'View diff',
      icon: Icons.difference_outlined,
      onTap: onViewDiff,
    ),
    GbmMenuItem(
      label: 'Compare with…',
      icon: Icons.compare_arrows,
      onTap: onCompare,
    ),
    const GbmMenuItem.separator(),
    GbmMenuItem(
      label: 'Drop stash…',
      icon: Icons.delete_outline,
      danger: true,
      onTap: onDrop,
    ),
  ];
}
