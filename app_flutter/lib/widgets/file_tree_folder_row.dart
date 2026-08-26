import 'package:flutter/material.dart';

import '../data/models/file_tree.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';
import 'gbm_row.dart';

/// A folder row for [FileTreeList]'s tree mode: an expand/collapse chevron
/// plus the folder's display name, no checkbox.
///
/// Used by every tree-mode file list in the app, including the Working Copy
/// board -- which wraps this row in a `Draggable` rather than replacing it,
/// since dropping the tri-state folder checkbox left the chevron and the
/// name as the whole row.
///
/// Built on [GbmRow] rather than a bare [InkWell] for the reason [GbmRow]
/// exists: a hand-rolled InkWell silently inherits `ThemeData.hoverColor`
/// (~4% black/white, invisible on a real display), and this row sits in the
/// same list as file rows that *are* GbmRows -- so the folders were the only
/// rows in a tree-mode list that did not light up under the pointer.
///
/// [GbmRow]'s horizontal padding is dropped to zero here: [FileTreeList]
/// already indents each level with `EdgeInsets.only(left: level * 16)`, and a
/// second inset would put the chevron out of line with the file rows beside
/// it, which carry the same zero-padding treatment.
class FileTreeFolderRow extends StatelessWidget {
  const FileTreeFolderRow({super.key, required this.node, this.onToggle});

  final FileTreeNode node;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      onTap: onToggle,
      height: GbmSpacing.rowHeightCompact,
      padding: EdgeInsets.zero,
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
    );
  }
}
