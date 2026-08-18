import 'package:flutter/material.dart';

import '../../widgets/gbm_menu.dart';

/// `ctxItemsFor('conflictHunk')` from gbm_context_menus.dart's 05-I
/// (Conflict hunk) -- 5 top-level items, danger last.
///
/// [onDiscardFromResult] is nullable: it maps onto the region's existing
/// whole-region Reset (`_ResultPane`'s "Reset" button, `_resetRegion()`),
/// which only makes sense once the region actually has something in the
/// result -- the caller passes `null` when this region's result is still
/// empty, the same way `_ResultPane` itself only renders its own Reset
/// button `if (resolved)`.
///
/// [onOpenInExternalTool] has no backing capability -- nothing in this app
/// launches an external diff/merge tool with the conflict's content
/// pre-filled (`desktop_launcher.dart` only opens a terminal or a URL) --
/// so it always renders `enabled: false` rather than being wired to
/// something that would silently do the wrong thing, the same treatment
/// 05-C's "Fetch this branch" and 05-J's "Fetch branches in folder" get
/// for their own missing capabilities.
List<GbmMenuItem> conflictHunkMenuItems({
  required VoidCallback onTakeThisSide,
  required VoidCallback onTakeThisLineOnly,
  required VoidCallback onTakeBoth,
  required VoidCallback? onDiscardFromResult,
}) {
  return <GbmMenuItem>[
    GbmMenuItem(
      label: 'Take this side',
      icon: Icons.check_circle_outline,
      onTap: onTakeThisSide,
    ),
    GbmMenuItem(
      label: 'Take this line only',
      icon: Icons.fact_check_outlined,
      onTap: onTakeThisLineOnly,
    ),
    GbmMenuItem(
      label: 'Take both — this side first',
      icon: Icons.merge_type,
      onTap: onTakeBoth,
    ),
    const GbmMenuItem(
      label: 'Open in external merge tool',
      icon: Icons.open_in_new,
      enabled: false,
      onTap: null,
    ),
    const GbmMenuItem.separator(),
    GbmMenuItem(
      label: 'Discard from result',
      icon: Icons.delete_outline,
      danger: true,
      enabled: onDiscardFromResult != null,
      onTap: onDiscardFromResult,
    ),
  ];
}
