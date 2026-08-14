import 'package:flutter/material.dart';

import '../data/models/ref_snapshot.dart';
import '../theme/gbm_theme.dart';
import '../theme/ref_chip_colors.dart';
import '../theme/tokens.dart';

/// `.gbm-tag`/`.gbm-tag-branch`/`.gbm-tag-branch.current`/`.gbm-tag-tag`
/// (docs/design/tokens-reference.md's components.css).
class GbmTagChip extends StatelessWidget {
  const GbmTagChip({
    super.key,
    required this.label,
    required this.kind,
    this.isCurrent = false,
  });

  final String label;
  final RefKind kind;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final RefChipColors chip = refChipColorsFor(
      context.gbmColors,
      kind,
      isCurrent: isCurrent,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: chip.fill,
        border: Border.all(color: chip.border),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: GbmTypography.fontMono,
          fontSize: GbmTypography.textXs,
          fontWeight: GbmTypography.weightMedium,
          color: chip.text,
        ),
      ),
    );
  }
}
