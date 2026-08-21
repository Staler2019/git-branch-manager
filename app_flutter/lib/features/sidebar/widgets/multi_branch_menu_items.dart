import 'package:flutter/material.dart';

import '../../../widgets/gbm_menu.dart';
import 'local_branch_menu_items.dart';

/// Spec page 13's `MULTIBRANCHMENU`: what a right-click offers when more
/// than one branch is selected.
///
/// The spec's own mock lists seven rows for a three-branch selection —
/// Fetch, Push, Checkout, Rename…, Set upstream…, Copy branch names and
/// `Delete 3 branches…` — with the middle three struck through as 單項
/// (single-item-only). `MULTIACTS` gives the rule behind that split:
/// Delete and Push/Fetch are 支援, while Rename / Checkout / Set upstream
/// are 「disabled — 單項專屬，tooltip：「只能對單一分支執行」」.
///
/// Kept and disabled, never hidden — same rule and the same
/// `enabled: false` **plus** `onTap: null` pairing as
/// [localBranchMenuItems].
///
/// `Set upstream…` has no backing entry point anywhere in this app (no capi
/// call, no dialog), so it renders permanently disabled here rather than
/// being omitted: it is one of the three items the spec explicitly wants
/// visible-but-off for a multi-selection, and hiding it would read as "this
/// feature does not exist" — which for a single branch would be misleading
/// once it does.
///
/// [count] is what the counted labels report, matching spec's own mock
/// ("Delete 3 branches…") and 05-F's counted file labels.
///
/// [conflictActive] applies spec page 07 to the two live verbs: a batch
/// delete rewrites refs and a push moves remote-tracking refs, neither of
/// which should run mid-sequencer.
///
/// [fetchBlockedReason] / [pushBlockedReason] carry the caller's own reason
/// for an unavailable Fetch/Push, because spec's rule is that a disabled row
/// must say *why*. A plain `null` callback with no reason would render the
/// row grey and mute, which is the failure mode the 不隱藏 rule exists to
/// prevent. The remote-resolution rules that produce these strings are the
/// caller's business — spec page 13 says nothing about how a multi-branch
/// Fetch/Push picks its remote, so `sidebar_panel.dart` owns that decision
/// and documents it there.
List<GbmMenuItem> multiBranchMenuItems({
  required int count,
  required bool conflictActive,
  required VoidCallback onCopyNames,
  VoidCallback? onFetch,
  VoidCallback? onPush,
  String? fetchBlockedReason,
  String? pushBlockedReason,
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
      tooltip: blockedReason,
      onTap: enabled ? onTap : null,
    );
  }

  String? conflict() => conflictActive ? kBranchConflictTooltip : null;

  return <GbmMenuItem>[
    item(
      'Fetch $count branches',
      Icons.cloud_download_outlined,
      onFetch,
      fetchBlockedReason,
    ),
    item(
      'Push $count branches',
      Icons.cloud_upload_outlined,
      onPush,
      conflict() ?? pushBlockedReason,
    ),
    item('Checkout', Icons.call_split, null, kSingleBranchOnlyTooltip),
    item('Rename…', Icons.edit_outlined, null, kSingleBranchOnlyTooltip),
    item('Set upstream…', Icons.link, null, kSingleBranchOnlyTooltip),
    // Not in MULTIBRANCHMENU's mock, but COMPARES 1's entry is literally
    // 「同時選兩個分支 → 右鍵 Compare」, so the two-branch case needs a way
    // to reach it. Disabled with a reason for any other count, since a
    // comparison has exactly two ends.
    item(
      'Compare',
      Icons.compare_arrows,
      onCompare,
      count == 2 ? null : 'Compare takes exactly two branches',
    ),
    GbmMenuItem(
      label: 'Copy branch names',
      icon: Icons.copy,
      onTap: onCopyNames,
    ),
    const GbmMenuItem.separator(),
    item(
      'Delete $count branches…',
      Icons.delete_outline,
      onDelete,
      conflict(),
      danger: true,
    ),
  ];
}
