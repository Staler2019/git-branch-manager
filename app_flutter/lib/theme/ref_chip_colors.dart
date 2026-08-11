import 'package:flutter/material.dart';

import '../data/models/ref_snapshot.dart';
import 'tokens.dart';

/// Fill/text color for one ref chip -- the Dart analog of
/// `PillPainter::colorsForRef` (src/app/models/PillPainter.cpp). Branch
/// chips use [GbmColors.refChipFill]/[refChipText] (see that field's doc
/// comment for why, not `accentSubtle`); the current branch gets a solid
/// accent fill instead (`.gbm-tag-branch.current` in components.css); tags
/// use `warning`; everything else (remote branches, stashes, ...) uses
/// `textTertiary` on a transparent/panel-raised background.
class RefChipColors {
  const RefChipColors({required this.fill, required this.text, required this.border});

  final Color fill;
  final Color text;
  final Color border;
}

RefChipColors refChipColorsFor(GbmColors colors, RefKind kind, {bool isCurrent = false}) {
  switch (kind) {
    case RefKind.localBranch:
      if (isCurrent) {
        return RefChipColors(fill: colors.accent, text: colors.textOnAccent, border: colors.accent);
      }
      return RefChipColors(fill: colors.refChipFill, text: colors.refChipText, border: colors.refChipFill);
    case RefKind.tag:
      return RefChipColors(fill: Colors.transparent, text: colors.warning, border: colors.borderDefault);
    case RefKind.remoteBranch:
    case RefKind.note:
    case RefKind.stash:
    case RefKind.other:
      return RefChipColors(fill: colors.surfacePanelRaised, text: colors.textTertiary, border: colors.borderDefault);
  }
}
