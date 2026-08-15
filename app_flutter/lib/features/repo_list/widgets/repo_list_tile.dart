import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/repo_record.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import '../../../widgets/lucide_icon.dart';

class RepoListTile extends StatelessWidget {
  const RepoListTile({
    super.key,
    required this.repo,
    required this.onTap,
    this.onOpenInFileManager,
  });

  final RepoRecord repo;
  final VoidCallback onTap;

  /// Reveals the repository in the OS file manager (context menu 05-A).
  ///
  /// Injected rather than reading `desktopLauncherProvider` here, so this
  /// tile stays presentational and keeps being widget-testable against a
  /// bare `GoRouter` with no `ProviderScope` -- the same split
  /// `MenuBarRow`/`TopBar`/`TabRow` follow. Null renders the item disabled.
  final VoidCallback? onOpenInFileManager;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Semantics(
      button: true,
      label: repo.isMissing
          ? '${repo.name}, ${repo.workDir}, missing'
          : '${repo.name}, ${repo.workDir}',
      child: GestureDetector(
        onSecondaryTapDown: (details) => _openContextMenu(context, details),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          child: Container(
            height: GbmSpacing.rowHeightComfortable,
            padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
            child: Row(
              children: <Widget>[
                LucideIcon(
                  repo.kind == RepoKind.bare ? 'archive' : 'git-fork',
                  size: 15,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: GbmSpacing.space2),
                Expanded(
                  child: Text(
                    repo.name,
                    style: TextStyle(
                      fontSize: GbmTypography.textBase,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  repo.workDir,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (repo.isMissing) ...<Widget>[
                  const SizedBox(width: GbmSpacing.space2),
                  Text(
                    'missing',
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: colors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `ctxItemsFor('repo')` from the design doc. "Open in file manager" and
  /// "Remove from list" have no backing implementation in this app today
  /// (no OS-reveal launcher is wired anywhere, and `DiscoveryController`
  /// only supports removing a whole base folder, not one repo within it)
  /// -- left as visual-only entries that close the menu, the same inert
  /// state the design mockup's own JS gives many of its items, rather than
  /// silently doing nothing dangerous-sounding or something unintended.
  void _openContextMenu(BuildContext context, TapDownDetails details) {
    showGbmContextMenu(context, details.globalPosition, <GbmMenuItem>[
      GbmMenuItem(
        label: 'Open',
        icon: Icons.folder_open_outlined,
        onTap: onTap,
      ),
      GbmMenuItem(
        label: 'Open in file manager',
        icon: Icons.folder_outlined,
        onTap: onOpenInFileManager,
      ),
      GbmMenuItem(
        label: 'Repository settings',
        icon: Icons.settings_outlined,
        onTap: () => context.push(
          RoutePaths.repositorySettingsDialogFor(
            Uri.encodeComponent(repo.workDir),
          ),
        ),
      ),
      const GbmMenuItem.separator(),
      const GbmMenuItem(
        label: 'Remove from list',
        icon: Icons.delete_outline,
        danger: true,
        // Explicitly disabled rather than a silent no-op: `gbm_discovery`
        // can only remove a whole base folder, never one repository found
        // inside it, so there is nothing for this to call. Rendering it
        // disabled says that; a no-op looked like a working destructive
        // action that quietly did nothing.
        onTap: null,
      ),
    ]);
  }
}
