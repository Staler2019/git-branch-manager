import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/gbm_menu.dart';

/// Reason strings for items spec keeps visible but disabled. Spec writes
/// these in Chinese because the spec is; the app ships English labels, so
/// these are the same rules in the UI's own language.
const String kAlreadyOnBranchTooltip = 'Already on this branch';
const String kBranchConflictTooltip =
    'Finish or abort the operation in progress first';
const String kSingleBranchOnlyTooltip = 'Only works on a single branch';

/// `ctxItemsFor('branch')` from gbm_context_menus.dart's 05-B (Local
/// branch) -- 8 top-level items, at the spec's own ceiling, danger last, no
/// submenu.
///
/// Extracted from `branch_tree_item.dart`'s hand-written list, which had
/// drifted from the catalog in three ways at once: "Rebase current onto
/// here" and "Compare with…" were missing entirely, and two labels had
/// wandered ("Rename branch" for "Rename…", "Merge into current branch" for
/// "Merge into current"). The parity test could not see the wording drift
/// because it matched on prefixes; against this function it asserts exact
/// equality, the same way 05-D/F/G/H/I/J already do.
///
/// Only the **local-branch** path goes through here. A remote-only row
/// (05-C), a "gone" row (05-C's disabled subset) and a tag row (05-D) keep
/// their own builders in `branch_tree_item.dart`, each with its own passing
/// tests.
///
/// Every item stays visible. Spec page 13: 「保留但 disabled，並附 tooltip 說
/// 明原因，不隱藏 — 隱藏會讓人以為功能不存在」. Disabled items therefore set
/// `enabled: false` **and** `onTap: null` -- `enabled` alone is only a
/// visual signal (see [GbmMenuItem]'s doc comment).
///
/// [conflictActive] applies spec page 07's STATES rule. All six actions
/// that move HEAD, start a sequencer operation, or rewrite a ref are gated:
/// checkout, new-branch-from-here, rename, merge, rebase and delete.
/// Compare and Copy are read-only and stay live. Before this extraction
/// only Checkout and Rename were gated here, leaving New branch / Merge /
/// Delete live mid-conflict against spec.
///
/// [isCurrent] disables Checkout with its own reason: you cannot check out
/// the branch you are already on. It used to be omitted outright, which
/// made the menu one item shorter than the catalog on the HEAD row.
List<GbmMenuItem> localBranchMenuItems({
  required String branchName,
  required bool isCurrent,
  required bool conflictActive,
  VoidCallback? onCheckout,
  VoidCallback? onNewBranchFromHere,
  VoidCallback? onRename,
  VoidCallback? onMerge,
  VoidCallback? onRebaseOntoHere,
  VoidCallback? onCompare,
  VoidCallback? onDelete,
}) {
  GbmMenuItem item(
    String label,
    IconData icon,
    VoidCallback? onTap,
    String? blockedReason, {
    bool danger = false,
  }) {
    final bool enabled = onTap != null && blockedReason == null;
    return GbmMenuItem(
      label: label,
      icon: icon,
      danger: danger,
      enabled: enabled,
      tooltip: onTap == null ? null : blockedReason,
      onTap: enabled ? onTap : null,
    );
  }

  String? conflict() => conflictActive ? kBranchConflictTooltip : null;

  return <GbmMenuItem>[
    item(
      'Checkout',
      Icons.call_split,
      onCheckout,
      isCurrent ? kAlreadyOnBranchTooltip : conflict(),
    ),
    item('New branch from here…', Icons.add, onNewBranchFromHere, conflict()),
    item('Rename…', Icons.edit_outlined, onRename, conflict()),
    item('Merge into current', Icons.call_merge, onMerge, conflict()),
    item(
      'Rebase current onto here',
      Icons.merge_type,
      onRebaseOntoHere,
      conflict(),
    ),
    item('Compare with…', Icons.compare_arrows, onCompare, null),
    GbmMenuItem(
      label: 'Copy branch name',
      icon: Icons.copy,
      onTap: () => Clipboard.setData(ClipboardData(text: branchName)),
    ),
    const GbmMenuItem.separator(),
    item(
      'Delete branch…',
      Icons.delete_outline,
      onDelete,
      conflict(),
      danger: true,
    ),
  ];
}
