import 'package:flutter/material.dart';

import '../data/models/file_tree.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// A folder row for [FileTreeList]'s tree mode: an expand/collapse chevron
/// plus the folder's display name, no checkbox.
///
/// Used by every tree-mode file list in the app, including the Working Copy
/// board -- which wraps this row in a `Draggable` rather than replacing it,
/// since dropping the tri-state folder checkbox left the chevron and the
/// name as the whole row.
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
