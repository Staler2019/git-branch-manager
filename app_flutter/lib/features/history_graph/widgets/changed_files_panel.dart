import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/changed_file.dart';
import '../../../data/repositories/compare_tabs_repository.dart';
import '../../../data/repositories/file_list_view_mode_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/services/desktop_launcher.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/file_list_mode_switcher.dart';
import '../../../widgets/file_list_mode_toggle_button.dart';
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
    final FileListViewMode viewMode = ref.watch(fileListViewModeProvider);

    return ChangedFilesPanelCore(
      hasSelectedCommit: selectedCommitOid != null,
      files: files,
      viewMode: viewMode,
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
      // 05-K → "Compare with working copy". Opens a Compare tab with the
      // commit on the left and Working Copy on the right (a null `right` is
      // what CompareTabSpec means by that), then navigates to it -- the
      // same two steps `sidebar_panel.dart`'s _compareStash/_compareTag take,
      // `context.go` included: a Compare tab is a ShellRoute child, so
      // pushing would stack it over History instead of switching to it.
      //
      // The right-clicked path is not passed along: gbm_capi's compare is
      // per-ref, not per-file, and the tab's own file list lands on the file
      // one click later.
      onCompareWithWorkingCopy: selectedCommitOid == null
          ? null
          : (String _) {
              final String tabId = ref
                  .read(compareTabsProvider(identity).notifier)
                  .open(left: selectedCommitOid);
              context.go(
                RoutePaths.compareFor(
                  Uri.encodeComponent(identity.workDir),
                  tabId,
                ),
              );
            },
      // 05-K → "Open terminal here". The repository work dir, matching what
      // 05-A and 05-F already open -- a historical commit's file has no
      // directory of its own to open a terminal in.
      onOpenTerminal: (String _) =>
          ref.read(desktopLauncherProvider).openTerminal(identity.workDir),
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
    this.onCompareWithWorkingCopy,
    this.onFileHistory,
    this.onBlame,
    this.onOpenTerminal,
    this.onRestoreToThisState,
    this.viewMode = FileListViewMode.list,
  });

  final bool hasSelectedCommit;
  final List<ChangedFile> files;
  final String? selectedPath;

  /// List vs Tree display, from the shared [fileListViewModeProvider]
  /// (spec page 03 item 10 -- "同一個設定套用到...History 的 Changed
  /// files"). Defaults to list so existing callers/tests that don't pass it
  /// keep their prior behavior unchanged.
  final FileListViewMode viewMode;
  final ValueChanged<String>? onFileTap;

  /// 05-K's "Compare with working copy". Null with no commit selected --
  /// there is no left-hand ref to compare against.
  final ValueChanged<String>? onCompareWithWorkingCopy;
  final ValueChanged<String>? onFileHistory;
  final ValueChanged<String>? onBlame;

  /// 05-K's "Open terminal here". Takes the path for signature symmetry with
  /// the others even though it opens the repository work dir; see the
  /// container half for why.
  final ValueChanged<String>? onOpenTerminal;

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

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GbmSpacing.space3,
            GbmSpacing.space1,
            GbmSpacing.space1,
            GbmSpacing.space1,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'CHANGED FILES',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    fontWeight: GbmTypography.weightSemibold,
                    color: colors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // Spec page 03 item 10: same List/Tree preference as Working
              // Copy, Compare, and the Conflict window's file lists.
              const FileListModeToggleButton(),
            ],
          ),
        ),
        Expanded(
          child: FileListModeSwitcher<ChangedFile>(
            mode: viewMode,
            items: files,
            pathOf: (ChangedFile file) => file.path,
            leafBuilder: (BuildContext context, ChangedFile file) =>
                _buildFileRow(context, file),
          ),
        ),
      ],
    );
  }

  Widget _buildFileRow(BuildContext context, ChangedFile file) {
    final GbmColors colors = context.gbmColors;
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
  }

  /// 05-K (commit file) context menu items, in spec order: view diff (via
  /// onFileTap), compare with working copy, file history, blame, open
  /// terminal here, copy path, and the second-level "Restore file to this
  /// state".
  ///
  /// Still omits "Open file at this revision" and "Save this revision as…"
  /// (top level) and "Restore and stage"/"Export as patch…" (submenu):
  /// reading a blob at a revision has no capi entry point at all, and the
  /// `GbmMenuItem.submenu` flyout does not render yet (see gbm_menu.dart),
  /// so the two submenu items would be unreachable even if they existed.
  List<GbmMenuItem> _buildMenuItems(String path) {
    return <GbmMenuItem>[
      GbmMenuItem(
        label: 'View diff in this commit',
        icon: Icons.difference,
        onTap: onFileTap == null ? null : () => onFileTap!(path),
      ),
      if (onCompareWithWorkingCopy != null)
        GbmMenuItem(
          label: 'Compare with working copy',
          icon: Icons.compare_arrows,
          onTap: () => onCompareWithWorkingCopy!(path),
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
      if (onOpenTerminal != null)
        GbmMenuItem(
          label: 'Open terminal here',
          icon: Icons.terminal,
          onTap: () => onOpenTerminal!(path),
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
