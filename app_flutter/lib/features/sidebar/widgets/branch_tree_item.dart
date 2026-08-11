import 'package:flutter/material.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/ref_chip_colors.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/lucide_icon.dart';

class BranchTreeItem extends StatelessWidget {
  const BranchTreeItem({super.key, required this.ref, required this.onCheckout});

  final RefInfo ref;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RefChipColors chip = refChipColorsFor(colors, ref.kind, isCurrent: ref.isHead);

    return InkWell(
      onTap: ref.isHead ? null : onCheckout,
      borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      child: Container(
        height: GbmSpacing.rowHeightCompact,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        decoration: BoxDecoration(
          color: ref.isHead ? colors.surfaceSelected : null,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
        ),
        child: Row(
          children: <Widget>[
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
          ],
        ),
      ),
    );
  }
}
