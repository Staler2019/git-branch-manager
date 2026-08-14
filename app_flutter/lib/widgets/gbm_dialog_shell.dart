import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// Shared chrome for every routed dialog (see routing/dialog_route.dart):
/// title bar with a close button, scrollable body, optional action row.
/// One shared widget rather than each dialog re-implementing this, since
/// ~30 dialogs (see docs/FEATURES.md) will use it by the time the rewrite
/// reaches parity.
class GbmDialogShell extends StatelessWidget {
  const GbmDialogShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.width = 480,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          constraints: const BoxConstraints(maxHeight: 560),
          decoration: BoxDecoration(
            color: colors.surfaceOverlay,
            borderRadius: BorderRadius.circular(GbmSpacing.radiusLg),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GbmSpacing.space4,
                  GbmSpacing.space4,
                  GbmSpacing.space3,
                  GbmSpacing.space2,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: GbmTypography.textLg,
                          fontWeight: GbmTypography.weightSemibold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: colors.textSecondary,
                      ),
                      onPressed: () => context.pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GbmSpacing.space4,
                  ),
                  child: child,
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(GbmSpacing.space4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                )
              else
                const SizedBox(height: GbmSpacing.space4),
            ],
          ),
        ),
      ),
    );
  }
}
