import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/discovery_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_banner.dart';
import '../../widgets/gbm_panel.dart';
import '../../widgets/lucide_icon.dart';
import '../../widgets/theme_switcher_buttons.dart';
import '../repo_switcher/repo_switcher_popover.dart';

/// What the window shows when no repository is open -- route `/`.
///
/// This is *not* the repository dashboard it replaced. The spec has no
/// repository-list page at all: the window is a repository workspace (pages
/// 01-03), repository selection is the sidebar's switcher popover (page 02
/// item 15), and where repositories are discovered from is Preferences →
/// Repository sources (page 11). So the only thing left for this screen to
/// do is pick the first repository of the session, which it does with the
/// very same [RepoSwitcherList] the popover shows -- there is just no
/// sidebar yet to hang it off.
///
/// The app normally never lands here: [appRouterProvider] opens straight
/// into the most recently used repository, and this is where File → Close
/// window comes back to.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DiscoveryState discovery = ref.watch(discoveryProvider);
    final GbmColors colors = context.gbmColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('git-branch-manager'),
        actions: <Widget>[
          const ThemeSwitcherButtons(),
          const SizedBox(width: GbmSpacing.space2),
          IconButton(
            icon: const Icon(Icons.tune, size: 18),
            tooltip: 'Preferences',
            onPressed: () => context.push(RoutePaths.preferencesDialog),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_outlined, size: 18),
            tooltip: 'Keyboard shortcuts',
            onPressed: () => context.push(RoutePaths.keyboardShortcutsDialog),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18),
            tooltip: 'About',
            onPressed: () => context.push(RoutePaths.aboutDialog),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (discovery.lastError case final error?)
            GbmWarningBanner(message: error.message),
          if (discovery.isScanning) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(GbmSpacing.space6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          LucideIcon(
                            'git-fork',
                            size: 18,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: GbmSpacing.space2),
                          Text(
                            'No repository open',
                            style: TextStyle(
                              fontSize: GbmTypography.textLg,
                              fontWeight: GbmTypography.weightSemibold,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: GbmSpacing.space2),
                      Text(
                        'Choose one below, or add the folders to scan for '
                        'repositories in Preferences → Repository sources.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: GbmTypography.textSm,
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: GbmSpacing.space4),
                      GbmPanel(
                        padding: const EdgeInsets.all(GbmSpacing.space2),
                        // No onDismiss: nothing is stacked over this screen,
                        // so popping would take the screen itself with it.
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: const RepoSwitcherList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
