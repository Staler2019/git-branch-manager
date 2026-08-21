import 'package:flutter/material.dart';

import '../../../widgets/gbm_menu.dart';

/// Reason strings for the items spec page 13 keeps visible but disabled.
///
/// Spec writes these tooltips in Chinese because the spec itself is; the app
/// ships English labels throughout, so these are the same rules in the UI's
/// own language rather than a mixed-language menu.
const String kSingleCommitOnlyTooltip = 'Only works on a single commit';
const String kContiguousOnlyTooltip = 'Selection must be contiguous commits';
const String kTwoCommitsAtMostTooltip = 'Compare takes one or two commits';
const String kConflictActiveTooltip =
    'Finish or abort the operation in progress first';

/// `ctxItemsFor('commit')` from gbm_context_menus.dart's 05-E (Commit) --
/// 7 top-level items, no danger at top level, one "More actions" submenu.
///
/// One pure function shared by both render sites (a plain right-click on a
/// [CommitRow], and the multi-select-aware path in `commit_graph_view.dart`),
/// following the template 05-D/F/G/H/I/J already use: the parity test can
/// then assert exact label equality against the catalog instead of pumping a
/// widget and matching prefixes.
///
/// **Counts, not just enablement.** With more than one commit selected the
/// labels spell out how many they will act on, exactly as 05-F does for
/// files ("Stage 3 files") -- spec page 13: 「任何一次動作的按鈕與選單文字都
/// 會寫出實際數量」.
///
/// **Nothing is hidden.** Spec is explicit that a single-commit-only action
/// stays visible and disabled with a tooltip rather than disappearing
/// (「保留但 disabled，並附 tooltip 說明原因，不隱藏 — 隱藏會讓人以為功能不
/// 存在」). Every disabled item therefore sets `enabled: false` **and**
/// `onTap: null`: `enabled` alone is only a visual signal (see
/// [GbmMenuItem]'s doc comment), and `onTap: null` alone would leave a
/// full-brightness row that silently does nothing.
///
/// [contiguous] gates cherry-pick and revert per `MULTIACTS`: 「commit 多選只
/// 在連續範圍時開放 cherry-pick / revert / squash；不連續時這三項 disabled」.
/// Squash has no capi behind it anywhere in this app, so it is absent rather
/// than faked. The caller computes contiguity against the **unfiltered**
/// snapshot, so a range picked under a filter correctly reads as gappy.
///
/// [conflictActive] applies spec page 07's STATES rule to the items that
/// move HEAD or start a second sequencer operation. The read-only items
/// (Compare, Copy SHA, Export as patch) stay live -- nothing about a
/// conflict makes reading history unsafe.
List<GbmMenuItem> commitMenuItems({
  required int count,
  required bool contiguous,
  required bool conflictActive,
  required VoidCallback onCopySha,
  VoidCallback? onCheckout,
  VoidCallback? onMerge,
  VoidCallback? onCherryPick,
  VoidCallback? onCreateBranchHere,
  VoidCallback? onCompare,
  VoidCallback? onRebaseOntoHere,
  VoidCallback? onResetBranchHere,
  VoidCallback? onRevert,
  VoidCallback? onExportAsPatch,
  VoidCallback? onCompareWithWorkingCopy,
}) {
  final bool multiple = count > 1;

  /// Builds one item from a callback plus the reasons it might be off.
  /// [blockedReason] null means "nothing blocks this"; non-null both
  /// disables and explains.
  GbmMenuItem item(
    String label,
    IconData icon,
    VoidCallback? onTap,
    String? blockedReason,
  ) {
    final bool enabled = onTap != null && blockedReason == null;
    return GbmMenuItem(
      label: label,
      icon: icon,
      enabled: enabled,
      tooltip: onTap == null ? null : blockedReason,
      onTap: enabled ? onTap : null,
    );
  }

  String? singleOnly() => multiple ? kSingleCommitOnlyTooltip : null;
  String? conflictOrSingle() =>
      conflictActive ? kConflictActiveTooltip : singleOnly();
  String? conflictOrGappy() => conflictActive
      ? kConflictActiveTooltip
      : (multiple && !contiguous ? kContiguousOnlyTooltip : null);

  return <GbmMenuItem>[
    item(
      'Checkout this commit',
      Icons.call_split,
      onCheckout,
      conflictOrSingle(),
    ),
    item('Merge into current', Icons.call_merge, onMerge, conflictOrSingle()),
    item(
      multiple ? 'Cherry-pick $count commits' : 'Cherry-pick',
      Icons.content_paste_go,
      onCherryPick,
      conflictOrGappy(),
    ),
    // MULTIACTS lists Create branch alongside Reset here / Create tag as
    // needing a single target commit, regardless of contiguity.
    item(
      'Create branch here…',
      Icons.add,
      onCreateBranchHere,
      conflictOrSingle(),
    ),
    item(
      'Compare with…',
      Icons.compare_arrows,
      onCompare,
      // One commit opens a Compare tab with the ref picker on the right;
      // two fills both sides directly (COMPARES 3). Three or more has no
      // meaning -- a comparison has exactly two ends.
      count > 2 ? kTwoCommitsAtMostTooltip : null,
    ),
    item(
      multiple ? 'Copy $count SHAs' : 'Copy SHA',
      Icons.copy,
      onCopySha,
      null,
    ),
    GbmMenuItem.submenu(
      label: 'More actions',
      icon: Icons.more_horiz,
      children: <GbmMenuItem>[
        item(
          'Rebase onto here',
          Icons.merge_type,
          onRebaseOntoHere,
          conflictOrSingle(),
        ),
        item(
          'Reset branch to here…',
          Icons.restore,
          onResetBranchHere,
          conflictOrSingle(),
        ),
        item(
          multiple ? 'Revert $count commits' : 'Revert commit',
          Icons.undo,
          onRevert,
          conflictOrGappy(),
        ),
        // gbm_patch_export takes a list of commits, so a multi-selection
        // exports one patch file per commit in one call -- no contiguity
        // requirement, unlike replaying them.
        item(
          multiple ? 'Export $count patches…' : 'Export as patch…',
          Icons.description_outlined,
          onExportAsPatch,
          null,
        ),
        item(
          'Compare with working copy',
          Icons.difference_outlined,
          onCompareWithWorkingCopy,
          singleOnly(),
        ),
      ],
    ),
  ];
}
