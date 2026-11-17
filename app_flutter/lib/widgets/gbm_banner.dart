import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';
import 'lucide_icon.dart';

/// `.gbm-banner-warning` (docs/design/tokens-reference.md's components.css)
/// -- used to surface a [GitError.message] near the top of a screen.
class GbmWarningBanner extends StatelessWidget {
  const GbmWarningBanner({super.key, required this.message, this.action});

  final String message;

  /// Drawn after the message, the way P07's conflict mock puts `gbm-btn-sm`
  /// buttons after its `flex:1` text; a panel's failed read puts
  /// `GbmOpenLogButton` here (read-failure-states-spec.html, candidate A).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space4,
        vertical: GbmSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: colors.diffDelBg,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          LucideIcon('alert-triangle', size: 14, color: colors.diffDelText),
          const SizedBox(width: GbmSpacing.space2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.diffDelText,
              ),
            ),
          ),
          if (action case final Widget action) ...<Widget>[
            const SizedBox(width: GbmSpacing.space2),
            action,
          ],
        ],
      ),
    );
  }
}
