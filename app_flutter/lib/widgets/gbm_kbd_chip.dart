import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// A small monospaced pill showing one keyboard shortcut's display label
/// (e.g. `⌘⇧B`), styled per worktree-dialogs-spec.html's kbd chip:
/// `surface-sunken` fill, 1px `border-default`, r4.
///
/// Extracted from `keyboard_shortcuts_dialog.dart`'s inline `Container`,
/// which `preferences_dialog.dart`'s `_ShortcutsSection` had re-implemented
/// a second time as bare, unboxed `Text` -- two renderings of the same fact
/// disagreeing is exactly [CULT-single-source-of-truth]'s failure shape.
/// Both now build this widget instead.
class GbmKbdChip extends StatelessWidget {
  const GbmKbdChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: Border.all(color: colors.borderDefault),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: GbmTypography.fontMono,
          fontSize: GbmTypography.textXs,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
