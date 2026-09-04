import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/app_version.dart';
import '../../../data/repositories/build_version_repository.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `AboutDialog` (src/app/dialogs/AboutDialog.cpp).
/// Routed as `/dialogs/about` -- see routing/app_router.dart.
///
/// This is also the app's only version readout that is reachable with **no
/// repository open**: `WelcomeScreen` renders no menu bar at all (both
/// `MenuBarRow` and `PlatformMenuBarHost` are built inside
/// `WorkspaceScreen`), so its three AppBar buttons — one of which opens
/// this dialog — are the whole entry surface in that state. That is also
/// why the update check hangs off this dialog rather than off Help alone.
class AboutDialogContent extends ConsumerWidget {
  const AboutDialogContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final AppVersion? version = ref.watch(buildVersionProvider);
    return GbmDialogShell(
      title: 'About git-branch-manager',
      actions: <Widget>[
        // The only route to the update check with no repository open --
        // `WelcomeScreen` builds no menu bar, so Help → Check for updates…
        // does not exist there. pushReplacement rather than push: two
        // stacked non-opaque dialog routes would render one scrim over
        // another with this one still visible underneath.
        GbmButton(
          label: 'Check for updates…',
          kind: GbmButtonKind.primary,
          onPressed: () => context.pushReplacement(RoutePaths.updateDialog),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '給超大型 repository 用的快速 Git 客戶端。',
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
            version == null ? '開發版本' : '版本 $version',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          Text(
            '透過 gbm_capi FFI 橋接，跟既有的 C++ core 溝通的 Flutter UI'
            '（Riverpod + go_router）——詳見 docs/ARCHITECTURE.md。',
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
