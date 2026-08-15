import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `AboutDialog` (src/app/dialogs/AboutDialog.cpp).
/// Routed as `/dialogs/about` -- see routing/app_router.dart.
class AboutDialogContent extends StatelessWidget {
  const AboutDialogContent({super.key});

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmDialogShell(
      title: 'About git-branch-manager',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'A fast Git client for very large repositories.',
            style: TextStyle(
              fontSize: GbmTypography.textBase,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          Text(
            'Flutter UI (Riverpod + go_router), talking to the existing C++ core '
            'through the gbm_capi FFI bridge -- see docs/ARCHITECTURE.md.',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space4),
        ],
      ),
    );
  }
}
