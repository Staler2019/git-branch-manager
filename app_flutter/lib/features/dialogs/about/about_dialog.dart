import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/app_version.dart';
import '../../../data/repositories/build_version_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `AboutDialog` (src/app/dialogs/AboutDialog.cpp).
/// Routed as `/dialogs/about` -- see routing/app_router.dart.
///
/// This is also the app's only version readout that is reachable with **no
/// repository open**: `WelcomeScreen` renders no menu bar at all (both
/// `MenuBarRow` and `PlatformMenuBarHost` are built inside
/// `WorkspaceScreen`), so its three AppBar buttons — one of which opens
/// this dialog — are the whole entry surface in that state.
class AboutDialogContent extends ConsumerWidget {
  const AboutDialogContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final AppVersion? version = ref.watch(buildVersionProvider);
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
          const SizedBox(height: GbmSpacing.space2),
          // A build with no injected version says so rather than rendering
          // a number. `0.0.0` would misreport which build is running, and
          // it is the same reading the update check uses to refuse to
          // replace a developer build -- the two must not disagree.
          Text(
            version == null ? 'Development build' : 'Version $version',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
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
