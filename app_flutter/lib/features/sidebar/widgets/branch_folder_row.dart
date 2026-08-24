import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// One folder row in the branch tree: its chevron and its name.
///
/// Presentational -- the expanded set, the recursion into children and the
/// 05-J context menu all stay in `SidebarPanel`, which is where the tree's
/// state lives. This draws exactly one row.
class BranchFolderRow extends StatelessWidget {
  const BranchFolderRow({
    super.key,
    required this.folderName,
    required this.isExpanded,
    required this.onToggle,
    required this.onSecondaryTapDown,
  });

  /// The single segment this row prints (`feature`, not `feature/sub`) --
  /// the same folding P02 item 12 applies to leaves.
  final String folderName;

  /// Comes from the built node, never re-derived from the panel's expanded
  /// set: `buildBranchTree` already decided this, and while a filter is
  /// active it decides `expandAll` -- a second reading of the set would draw
  /// a closed chevron over an open folder.
  final bool isExpanded;

  /// Single-level toggle. Both the chevron and the name are wired to it,
  /// distinct from the context menu's recursive "Expand all".
  final VoidCallback onToggle;

  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        height: GbmSpacing.rowHeightCompact,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: Icon(
                isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: colors.textSecondary,
              ),
              onPressed: onToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Text(
                  folderName,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textSecondary,
                  ),
                  // Without these the Text soft-wraps to a second line
                  // inside a fixed-height rowHeightCompact (26px)
                  // Container. That is a *cross-axis* overflow, which
                  // RenderFlex does not report -- so it never threw, it
                  // just silently painted over the neighbouring rows.
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
