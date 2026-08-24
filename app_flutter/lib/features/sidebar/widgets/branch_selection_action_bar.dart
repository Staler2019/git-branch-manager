import 'package:flutter/material.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// The bar that appears above the branch tree once a multi-selection exists:
/// 「N selected」 plus Clear and Delete.
///
/// Presentational, in the same sense as `features/workspace/widgets/` -- it
/// takes a count and two callbacks and holds no Riverpod dependency, so the
/// selection state machine stays in `SidebarPanel` and this can be pumped
/// directly.
class BranchSelectionActionBar extends StatelessWidget {
  const BranchSelectionActionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onDelete,
  });

  /// How many branches are selected. The caller only renders this bar when
  /// the selection is non-empty, so this is never zero in practice.
  final int count;

  final VoidCallback onClear;
  final VoidCallback onDelete;

  /// Shared by the two TextButtons.
  ///
  /// Default TextButton padding plus its 64px minimum width put the pair at
  /// ~150px, which does not leave the count label anything at the sidebar's
  /// 180px minimum. The buttons stay full-width targets vertically; only the
  /// horizontal padding and the minimum are given up.
  static final ButtonStyle _compactActionStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space1,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$count selected',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          TextButton(
            style: _compactActionStyle,
            onPressed: onClear,
            child: Text(
              'Clear',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            style: _compactActionStyle,
            onPressed: onDelete,
            child: Text(
              'Delete',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
