import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/repo_record.dart';
import '../../data/repositories/discovery_repository.dart';
import '../../routing/app_router.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_banner.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_panel.dart';
import '../../widgets/lucide_icon.dart';
import 'widgets/repo_list_tile.dart';

/// The dashboard: a multi-base-folder repository list, backed by the same
/// SQLite-cached discovery database the Qt app's `ManageBaseFoldersDialog` +
/// `RepoListModel` use (src/core/cache/RepoIndexDb.h). Route `/` -- see
/// routing/app_router.dart.
///
/// M1 known limitation: base folders are added here via a plain text field
/// rather than a native folder picker (that's `dialogs/manage_base_folders`,
/// M3) -- functionally real (it drives the real `gbm_discovery_*` FFI calls
/// and SQLite cache), just not the final UX.
class RepoListScreen extends ConsumerStatefulWidget {
  const RepoListScreen({super.key});

  @override
  ConsumerState<RepoListScreen> createState() => _RepoListScreenState();
}

class _RepoListScreenState extends ConsumerState<RepoListScreen> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DiscoveryState discovery = ref.watch(discoveryProvider);
    final GbmColors colors = context.gbmColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('git-branch-manager'),
        actions: <Widget>[
          IconButton(
            icon: LucideIcon('archive', size: 18, color: colors.textSecondary),
            tooltip: 'Manage base folders',
            onPressed: () => context.push(RoutePaths.manageBaseFoldersDialog),
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
          Padding(
            padding: const EdgeInsets.all(GbmSpacing.space4),
            child: GbmPanel(
              padding: const EdgeInsets.all(GbmSpacing.space3),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(
                        hintText:
                            'Add a base folder to scan (e.g. /home/you/code)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addAndScan(),
                    ),
                  ),
                  const SizedBox(width: GbmSpacing.space2),
                  GbmButton(
                    label: 'Add & Scan',
                    kind: GbmButtonKind.primary,
                    onPressed: discovery.isScanning ? null : _addAndScan,
                  ),
                  const SizedBox(width: GbmSpacing.space2),
                  GbmButton(
                    label: 'Rescan',
                    icon: LucideIcon(
                      'refresh-cw',
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    onPressed: discovery.isScanning || !discovery.isOpen
                        ? null
                        : () => ref.read(discoveryProvider.notifier).rescan(),
                  ),
                ],
              ),
            ),
          ),
          if (discovery.isScanning) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: discovery.repos.isEmpty
                ? Center(
                    child: Text(
                      'No repositories yet. Add a base folder above.',
                      style: TextStyle(color: colors.textTertiary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GbmSpacing.space4,
                    ),
                    itemCount: discovery.repos.length,
                    itemBuilder: (context, index) {
                      final RepoRecord repo = discovery.repos[index];
                      return RepoListTile(
                        repo: repo,
                        onTap: () => context.go(
                          RoutePaths.workspaceFor(repoIdFor(repo.workDir)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _addAndScan() {
    final String path = _pathController.text.trim();
    if (path.isEmpty) return;
    ref.read(discoveryProvider.notifier).addBaseFolderAndScan(path);
  }
}
