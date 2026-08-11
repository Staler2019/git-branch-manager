import 'package:flutter/material.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/ref_chip_colors.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/lucide_icon.dart';

class BranchTreeItem extends StatelessWidget {
  const BranchTreeItem({
    super.key,
    required this.ref,
    required this.onCheckout,
    this.selected = false,
    this.onSelectedChanged,
    this.onRename,
    this.onDelete,
  });

  final RefInfo ref;
  final VoidCallback onCheckout;
  final bool selected;
  /// Null hides the selection checkbox entirely (HEAD can't be
  /// multi-selected for deletion -- see SidebarPanel's doc comment).
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RefChipColors chip = refChipColorsFor(colors, ref.kind, isCurrent: ref.isHead);

    final StringBuffer label = StringBuffer(ref.shortName);
    if (ref.isHead) label.write(', current branch');
    if (ref.isGone) {
      label.write(', upstream gone');
    } else if (ref.hasTrackingInfo && (ref.ahead > 0 || ref.behind > 0)) {
      if (ref.ahead > 0) label.write(', ${ref.ahead} ahead');
      if (ref.behind > 0) label.write(', ${ref.behind} behind');
    }

    final Widget row = Container(
      height: GbmSpacing.rowHeightCompact,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
      decoration: BoxDecoration(
        color: ref.isHead ? colors.surfaceSelected : null,
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          if (onSelectedChanged != null)
            Semantics(
              label: 'Select ${ref.shortName} for bulk delete',
              child: Checkbox(
                value: selected,
                onChanged: (value) => onSelectedChanged!(value ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          LucideIcon('git-branch', size: 13, color: chip.text == colors.textOnAccent ? colors.accent : chip.text),
          const SizedBox(width: GbmSpacing.space2),
          Expanded(
            child: Text(
              ref.shortName,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                fontWeight: ref.isHead ? GbmTypography.weightSemibold : GbmTypography.weightRegular,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ref.isGone)
            Text('gone', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.danger))
          else if (ref.hasTrackingInfo && (ref.ahead > 0 || ref.behind > 0))
            Text(
              '${ref.ahead > 0 ? '↑${ref.ahead}' : ''}${ref.behind > 0 ? ' ↓${ref.behind}' : ''}',
              style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary),
            ),
          if (onRename != null || onDelete != null)
            PopupMenuButton<VoidCallback>(
              tooltip: 'Branch actions',
              icon: Icon(Icons.more_vert, size: 16, color: colors.textTertiary),
              padding: EdgeInsets.zero,
              onSelected: (action) => action(),
              itemBuilder: (context) => <PopupMenuEntry<VoidCallback>>[
                if (onRename != null) PopupMenuItem<VoidCallback>(value: onRename!, child: const Text('Rename…')),
                if (onDelete != null) PopupMenuItem<VoidCallback>(value: onDelete!, child: const Text('Delete…')),
              ],
            ),
        ],
      ),
    );

    final Widget maybeTooltip = ref.isGone && ref.upstream.isNotEmpty
        ? Tooltip(message: 'Upstream gone: ${ref.upstream}', child: row)
        : row;

    return Semantics(
      button: !ref.isHead,
      label: label.toString(),
      child: InkWell(
        onTap: ref.isHead ? null : onCheckout,
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
        child: maybeTooltip,
      ),
    );
  }
}
