import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/discovery_repository.dart';
import '../../data/repositories/recents_repository.dart';
import '../../routing/app_router.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_dialog_shell.dart';

/// Cmd/Ctrl+R (`GbmActionId.fileSwitchRepository`, see
/// workspace_screen.dart) opens this: recently-opened repos plus a link to
/// the full repo list. `context.go(...)` alone (no extra `Navigator.pop()`)
/// is this codebase's established pattern for "navigate and dismiss a
/// routed dialog" -- see repo_list_screen.dart's `RepoListTile.onTap` --
/// since `go()` replaces the whole route stack, which already removes this
/// dialog route; popping afterward would be redundant/racing against a
/// context that `go()` may have already deactivated.
class RepoSwitcherDialog extends ConsumerWidget {
  const RepoSwitcherDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final List<RecentRepoEntry> recents = ref
        .watch(recentsRepositoryProvider)
        .read();
    final DiscoveryState discoveryState = ref.watch(discoveryProvider);

    final Map<String, String?> repoNames = <String, String?>{
      for (final repo in discoveryState.repos) repo.workDir: repo.name,
    };

    return GbmDialogShell(
      title: 'Switch Repository',
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (recents.isNotEmpty) ...<Widget>[
            Text(
              'Recently Opened',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                fontWeight: GbmTypography.weightSemibold,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: recents.length,
                itemBuilder: (context, index) {
                  final RecentRepoEntry recent = recents[index];
                  final String name =
                      repoNames[recent.workDir] ?? recent.workDir;
                  // A nested transparent Material is required here: this
                  // ListTile's nearest Material ancestor is GbmDialogShell's
                  // (also transparent), but the dialog's opaque background
                  // Container sits between the two, which would otherwise
                  // hide this ListTile's hover/tap ink splashes.
                  return Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      title: Text(
                        name,
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      subtitle: Text(
                        recent.workDir,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textTertiary),
                      ),
                      onTap: () => context.go(
                        RoutePaths.workspaceFor(repoIdFor(recent.workDir)),
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(color: colors.borderSubtle),
          ],
          TextButton.icon(
            onPressed: () => context.go(RoutePaths.repoList),
            icon: Icon(Icons.folder_open, color: colors.textSecondary),
            label: Text(
              'View All Repositories',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
        ],
      ),
    );
  }
}
