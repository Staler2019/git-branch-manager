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
/// [onFetchFolder] has no backing capi capability -- `gbm_remote_fetch()`
/// takes a remote name, not a ref prefix, the same limitation 05-C's
/// "Fetch this branch" already documents for a single ref -- so it always
/// renders `enabled: false` rather than being wired to something that
/// would silently do the wrong thing (or omitted, which would look like a
/// rendering bug rather than a real absence).
List<GbmMenuItem> branchFolderMenuItems({
  required bool isExpanded,
  required VoidCallback onToggleExpand,
  required VoidCallback onCopyPrefix,
  required VoidCallback onDeleteMerged,
}) {
  return <GbmMenuItem>[
    GbmMenuItem(
      label: isExpanded ? 'Collapse all' : 'Expand all',
      icon: isExpanded ? Icons.unfold_less : Icons.unfold_more,
      onTap: onToggleExpand,
    ),
    const GbmMenuItem(
      label: 'Fetch branches in folder',
      icon: Icons.cloud_download_outlined,
      enabled: false,
      onTap: null,
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
