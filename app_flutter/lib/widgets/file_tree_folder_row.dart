import 'package:flutter/material.dart';

import '../data/models/file_tree.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// A read-only folder row for [FileTreeList]'s tree mode: an expand/collapse
/// chevron plus the folder's display name, no checkbox. For views whose file
/// list has no staging semantics (History's Changed files panel, Compare's
/// Files, the Conflict window's file rail) -- unlike
/// `working_copy_board.dart`'s own folder row, which needs a tri-state
/// checkbox for bulk stage/unstage and so isn't reused here.
class FileTreeFolderRow extends StatelessWidget {
  const FileTreeFolderRow({super.key, required this.node, this.onToggle});

  final FileTreeNode node;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return InkWell(
      onTap: onToggle,
      child: SizedBox(
        height: GbmSpacing.rowHeightCompact,
        child: Row(
          children: <Widget>[
            Icon(Icons.arrow_right, size: 16, color: colors.textTertiary),
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
