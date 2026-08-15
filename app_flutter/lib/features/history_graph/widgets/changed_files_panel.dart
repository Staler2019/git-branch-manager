import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/changed_file.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';

/// Container: watches the changed-files providers for [identity] and wires
/// tap callbacks to request the tapped file's diff, plus right-click context
/// menu callbacks for 05-K (commit file) actions.
class ChangedFilesPanel extends ConsumerWidget {
  const ChangedFilesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ChangedFile> files = ref.watch(commitFilesProvider(identity));
    final String? selectedPath = ref.watch(
      selectedCommitFilePathProvider(identity),
    );
    final String? selectedCommitOid = ref.watch(
      selectedCommitProvider(identity),
    );

    return ChangedFilesPanelCore(
      hasSelectedCommit: selectedCommitOid != null,
      files: files,
      selectedPath: selectedPath,
      onFileTap: selectedCommitOid == null
          ? null
          : (String path) {
              ref
                      .read(selectedCommitFilePathProvider(identity).notifier)
                      .state =
                  path;
              requestCommitFileDiff(ref, identity, selectedCommitOid, path);
            },
      onFileHistory: selectedCommitOid == null
          ? null
          : (String path) => context.push(
              RoutePaths.fileHistoryDialogFor(identity.workDir, path: path),
            ),
      onBlame: selectedCommitOid == null
          ? null
          : (String path) => context.push(
              RoutePaths.blameDialogFor(identity.workDir, path: path),
            ),
      // 05-K → More actions → "Restore file to this state". Needs the
      // commit's oid as well as the path, which is why it is bound here
      // rather than inside the presentational half.
      onRestoreToThisState: selectedCommitOid == null
          ? null
          : (String path) => context.push(
              RoutePaths.restoreFileDialogFor(
                Uri.encodeComponent(identity.workDir),
                path: path,
                oid: selectedCommitOid,
              ),
            ),
    );
  }
}

/// Presentational: lists [files] for the selected commit, highlighting
/// [selectedPath] and firing [onFileTap] on row tap, plus right-click context
/// menu (05-K) with file history, blame, and copy-path actions. No Riverpod
/// dependency, so it's testable directly (mirrors `MenuBarRow`/`TopBar`/`TabRow`'s
/// container/presentational split).
class ChangedFilesPanelCore extends StatelessWidget {
  const ChangedFilesPanelCore({
    super.key,
    required this.hasSelectedCommit,
    required this.files,
    required this.selectedPath,
    required this.onFileTap,
    this.onFileHistory,
    this.onBlame,
    this.onRestoreToThisState,
  });

  final bool hasSelectedCommit;
  final List<ChangedFile> files;
  final String? selectedPath;
  final ValueChanged<String>? onFileTap;
  final ValueChanged<String>? onFileHistory;
  final ValueChanged<String>? onBlame;

  /// 05-K's second-level "Restore file to this state". Null hides the entry
  /// (no commit selected), rather than showing a restore that has no source
  /// revision to restore from.
  final ValueChanged<String>? onRestoreToThisState;

  @override
  Widget build(BuildContext context) {
    if (!hasSelectedCommit || files.isEmpty) {
      return Center(
        child: Text(
          'No files changed',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final GbmColors colors = context.gbmColors;

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final ChangedFile file = files[index];
        final bool isSelected = selectedPath == file.path;

        return GestureDetector(
          onSecondaryTapDown: (details) =>
              _openContextMenu(context, details, file.path),
          child: Container(
            color: isSelected ? colors.surfaceSelected : null,
            child: ListTile(
              dense: true,
              title: Text(
                file.path,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: onFileTap == null ? null : () => onFileTap!(file.path),
            ),
          ),
        );
      },
    );
  }

  /// 05-K (commit file) context menu items: view diff (via onFileTap), file
  /// history, blame, copy path, and the second-level "Restore file to this
  /// state". Still omits open-file-at-revision and save-this-revision, which
  /// have no backing capi entry point.
  List<GbmMenuItem> _buildMenuItems(String path) {
    return <GbmMenuItem>[
      GbmMenuItem(
        label: 'View diff in this commit',
        icon: Icons.difference,
        onTap: onFileTap == null ? null : () => onFileTap!(path),
      ),
      if (onFileHistory != null)
        GbmMenuItem(
          label: 'File history',
          icon: Icons.history,
          onTap: () => onFileHistory!(path),
        ),
      if (onBlame != null)
        GbmMenuItem(
          label: 'Blame at this commit',
          icon: Icons.person_outline,
          onTap: () => onBlame!(path),
        ),
      GbmMenuItem(
        label: 'Copy path',
        icon: Icons.copy,
        onTap: () => Clipboard.setData(ClipboardData(text: path)),
      ),
      if (onRestoreToThisState case final ValueChanged<String> restore)
        GbmMenuItem.submenu(
          label: 'More actions',
          children: <GbmMenuItem>[
            GbmMenuItem(
              label: 'Restore file to this state',
              icon: Icons.restore,
              onTap: () => restore(path),
            ),
          ],
        ),
    ];
  }

  void _openContextMenu(
    BuildContext context,
    TapDownDetails details,
    String path,
  ) {
    showGbmContextMenu(context, details.globalPosition, _buildMenuItems(path));
  }
}
