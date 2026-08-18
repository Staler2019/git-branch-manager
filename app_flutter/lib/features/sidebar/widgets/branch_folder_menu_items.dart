import 'package:flutter/material.dart';

import '../../../widgets/gbm_menu.dart';

/// `ctxItemsFor('branchFolder')` from gbm_context_menus.dart's 05-J
/// (Branch folder) -- 4 top-level items, danger last.
///
/// The spec's own item list gives the first item one combined label,
/// "Expand all / Collapse all" -- a design-doc convention for a toggle
/// whose real text is necessarily state-dependent at runtime. This splits
/// it into its two concrete per-state strings, the same way 05-F/05-K's
/// multi-select pluralization is documented as a deliberate divergence
/// from a literal compound spec label rather than an unimplemented gap.
///
/// [onFetchFolder] is nullable: `gbm_remote_fetch()` now supports fetching
/// specific refs (see FetchRequest.refs), but only from one remote per
/// call, so the caller (SidebarPanel, via
/// branch_tree_builder.dart's `fetchableRefsInFolder`) only wires this when
/// every fetchable branch in the folder tracks the same single remote --
/// `null` when there's nothing fetchable or the folder spans more than one
/// remote, the same "no unambiguous target" treatment 05-D's "Push tag"
/// gets for multiple remotes.
List<GbmMenuItem> branchFolderMenuItems({
  required bool isExpanded,
  required VoidCallback onToggleExpand,
  required VoidCallback onCopyPrefix,
  required VoidCallback onDeleteMerged,
  required VoidCallback? onFetchFolder,
}) {
  return <GbmMenuItem>[
    GbmMenuItem(
      label: isExpanded ? 'Collapse all' : 'Expand all',
      icon: isExpanded ? Icons.unfold_less : Icons.unfold_more,
      onTap: onToggleExpand,
    ),
    GbmMenuItem(
      label: 'Fetch branches in folder',
      icon: Icons.cloud_download_outlined,
      enabled: onFetchFolder != null,
      onTap: onFetchFolder,
    ),
    GbmMenuItem(
      label: 'Copy folder prefix',
      icon: Icons.copy,
      onTap: onCopyPrefix,
    ),
    const GbmMenuItem.separator(),
    GbmMenuItem(
      label: 'Delete merged branches…',
      icon: Icons.delete_outline,
      danger: true,
      onTap: onDeleteMerged,
    ),
  ];
}
