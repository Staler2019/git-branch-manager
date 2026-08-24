import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_badge.dart';

/// The BRANCHES header: the label, the pending-cleanup badge, and the
/// select-all-gone / new-branch buttons.
///
/// Presentational -- it takes a count, a flag and two callbacks and holds no
/// Riverpod dependency, so which refs are gone and what "select all" does to
/// the selection both stay in `SidebarPanel`.
///
/// Deliberately not built from `SidebarSectionLabel`: this one sits directly
/// under the repository button rather than after a preceding section, so it
/// takes a larger top inset, and it is the only header with trailing
/// controls.
class BranchesSectionHeader extends StatelessWidget {
  const BranchesSectionHeader({
    super.key,
    required this.pendingCleanup,
    required this.canSelectAllGone,
    required this.onSelectAllGone,
    required this.onNewBranch,
  });

  /// How many remote-tracking refs are waiting to be pruned. Zero hides the
  /// badge entirely.
  final int pendingCleanup;

  final bool canSelectAllGone;

  /// Null-safe by construction: the caller passes a callback and this widget
  /// disables the button off [canSelectAllGone], so the two cannot disagree.
  final VoidCallback onSelectAllGone;
  final VoidCallback onNewBranch;

  static const BoxConstraints _iconButtonSize = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
  );

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GbmSpacing.space3,
        GbmSpacing.space3,
        GbmSpacing.space1,
        GbmSpacing.space1,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'BRANCHES',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontWeight: GbmTypography.weightSemibold,
                color: colors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // A bare count, not a sentence: spec asks for 「待清理數量」, and
          // prose here is what made this header overflow. A RenderFlex sizes
          // non-flex children first, so a wider label beside two 28px icon
          // buttons pushed past the sidebar's width instead of letting the
          // Expanded 'BRANCHES' yield -- the same shape as the narrow-window
          // round's findings. The meaning lives in the tooltip.
          if (pendingCleanup > 0)
            Padding(
              padding: const EdgeInsets.only(right: GbmSpacing.space1),
              child: Tooltip(
                message:
                    '$pendingCleanup remote-tracking '
                    '${pendingCleanup == 1 ? 'ref no longer exists' : 'refs no longer exist'} '
                    'upstream. Remote → Prune remote branches removes '
                    '${pendingCleanup == 1 ? 'it' : 'them'}.',
                child: Semantics(
                  label: '$pendingCleanup branches pending cleanup',
                  child: GbmBadge(
                    label: '$pendingCleanup',
                    kind: GbmBadgeKind.removed,
                  ),
                ),
              ),
            ),
          Tooltip(
            message: 'Select all branches with a gone upstream',
            child: IconButton(
              icon: Icon(
                Icons.playlist_add_check,
                size: 16,
                color: canSelectAllGone
                    ? colors.textSecondary
                    : colors.textTertiary,
              ),
              padding: EdgeInsets.zero,
              constraints: _iconButtonSize,
              onPressed: canSelectAllGone ? onSelectAllGone : null,
            ),
          ),
          Tooltip(
            message: 'New branch…',
            child: IconButton(
              icon: Icon(Icons.add, size: 16, color: colors.textSecondary),
              padding: EdgeInsets.zero,
              constraints: _iconButtonSize,
              onPressed: onNewBranch,
            ),
          ),
        ],
      ),
    );
  }
}
