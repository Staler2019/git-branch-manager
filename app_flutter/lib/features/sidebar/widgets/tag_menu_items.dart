import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/gbm_menu.dart';

/// `ctxItemsFor('tag')` from gbm_context_menus.dart's 05-D (Tag) -- 5
/// top-level items, danger last.
///
/// [onCheckoutDetached] is nullable: like TabRow's Merge/Cherry-pick/Reset
/// (see its `conflictActive` doc comment), checking out a tag moves HEAD,
/// so the caller passes `null` while a conflict is active rather than this
/// widget re-deriving `session.conflictActive` itself.
///
/// [onPush] is nullable for a different reason: unlike a repository-level
/// push (`gbm_push`, where an empty remote name falls back to the branch's
/// configured remote), `gbm_tag_push` runs
/// `git push <remoteName> refs/tags/<name>` with whatever remote name it's
/// given -- there is no "empty means default" support, and picking the
/// right one among several needs a picker this menu doesn't have. The
/// caller passes `null` when there isn't exactly one remote to push to
/// unambiguously.
List<GbmMenuItem> tagMenuItems({
  required String tagName,
  required VoidCallback? onCheckoutDetached,
  required VoidCallback? onPush,
  required VoidCallback onCompare,
  required VoidCallback onDelete,
}) {
  return <GbmMenuItem>[
    GbmMenuItem(
      label: 'Checkout tag (detached)',
      icon: Icons.call_split,
      enabled: onCheckoutDetached != null,
      onTap: onCheckoutDetached,
    ),
    GbmMenuItem(
      label: 'Push tag',
      icon: Icons.cloud_upload_outlined,
      enabled: onPush != null,
      onTap: onPush,
    ),
    GbmMenuItem(
      label: 'Compare with…',
      icon: Icons.compare_arrows,
      onTap: onCompare,
    ),
    GbmMenuItem(
      label: 'Copy tag name',
      icon: Icons.copy,
      onTap: () => Clipboard.setData(ClipboardData(text: tagName)),
    ),
    const GbmMenuItem.separator(),
    GbmMenuItem(
      label: 'Delete tag…',
      icon: Icons.delete_outline,
      danger: true,
      onTap: onDelete,
    ),
  ];
}
