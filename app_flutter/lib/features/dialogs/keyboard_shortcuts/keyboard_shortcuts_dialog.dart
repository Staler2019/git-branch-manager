import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_dialog_shell.dart';

const List<(String, String)> _kShortcuts = <(String, String)>[
  ('Refresh', 'R'),
  ('Checkout selected branch', 'Enter'),
  ('Stage file', 'S'),
  ('Unstage file', 'U'),
  ('Commit', 'Ctrl+Enter'),
  ('Switch to Working Copy tab', 'Ctrl+2'),
  ('Switch to History tab', 'Ctrl+1'),
];

/// The Dart analog of `KeyboardShortcutsDialog`
/// (src/app/dialogs/KeyboardShortcutsDialog.cpp). Routed as
/// `/dialogs/keyboard-shortcuts`. Only the M0-M3 shortcuts are listed so
/// far; grows alongside the features that define them.
class KeyboardShortcutsDialogContent extends StatelessWidget {
  const KeyboardShortcutsDialogContent({super.key});

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmDialogShell(
      title: 'Keyboard Shortcuts',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (action, keys) in _kShortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: GbmSpacing.space1,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        action,
                        style: TextStyle(
                          fontSize: GbmTypography.textSm,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GbmSpacing.space2,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceSunken,
                        borderRadius: BorderRadius.circular(
                          GbmSpacing.radiusSm,
                        ),
                      ),
                      child: Text(
                        keys,
                        style: TextStyle(
                          fontFamily: GbmTypography.fontMono,
                          fontSize: GbmTypography.textXs,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: GbmSpacing.space2),
          ],
        ),
      ),
    );
  }
}
