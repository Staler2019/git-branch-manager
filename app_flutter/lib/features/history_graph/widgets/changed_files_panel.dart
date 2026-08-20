import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/changed_file.dart';
import '../../../data/repositories/compare_tabs_repository.dart';
import '../../../data/repositories/file_list_view_mode_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../data/services/desktop_launcher.dart';
import '../../../data/services/file_save_picker.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/file_list_mode_switcher.dart';
import '../../../widgets/file_list_mode_toggle_button.dart';
import '../../../widgets/gbm_menu.dart';

/// What to do with an export once its bytes land on disk. The capi echoes
/// the destination back, so a listener keys on that to tell one in-flight
/// export from another.
enum _ExportPurpose {
  /// Written to a temp path so the OS file association can open it.
  openWithOs,

  /// Written where the user chose; only the confirmation is left to show.
  saveAs,
}

/// Container: watches the changed-files providers for [identity] and wires
/// tap callbacks to request the tapped file's diff, plus right-click context
/// menu callbacks for 05-K (commit file) actions.
///
/// Stateful because two of those actions ("Open file at this revision",
/// "Save this revision as…") are two-step: the export is asked for now and
/// answered later on an FFI event, so the widget has to remember what it
/// meant to do with each destination while that round trip is in flight.
class ChangedFilesPanel extends ConsumerStatefulWidget {
  const ChangedFilesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ChangedFilesPanel> createState() => _ChangedFilesPanelState();
}

class _ChangedFilesPanelState extends ConsumerState<ChangedFilesPanel> {
  /// Destination path -> why it was exported. Populated *before* the export
  /// is requested, because a reply can arrive synchronously (it does under
  /// the test fake) and would otherwise find nothing to match.
  final Map<String, _ExportPurpose> _pendingExports =
      <String, _ExportPurpose>{};

  /// Repository-relative, forward-slashed path -> a filename carrying the
  /// revision, so two revisions of the same file do not collide in the temp
  /// directory and the user can tell them apart in whatever app opens them.
  /// The extension is preserved deliberately: without it the OS has no file
  /// association to open.
  String _revisionFileName(String path, String oid) {
    final String base = path.split('/').last;
    final String shortOid = oid.length > 7 ? oid.substring(0, 7) : oid;
    final int dot = base.lastIndexOf('.');
    if (dot <= 0) return '$base-$shortOid';
    return '${base.substring(0, dot)}-$shortOid${base.substring(dot)}';
  }

  void _export(
    String revision,
    String path,
    String destPath,
    _ExportPurpose purpose,
  ) {
    _pendingExports[destPath] = purpose;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .exportFileAtRevision(
          revision: revision,
          path: path,
          destPath: destPath,
        );
  }

  void _openAtRevision(String path, String oid) {
    // Directory.systemTemp rather than path_provider's getTemporaryDirectory:
    // this needs no plugin channel (so it works in a widget test as well as
    // on a device), it is synchronous, and the OS temp dir is exactly the
    // right place for a scratch copy the user is about to open. A named
    // subdirectory keeps these out of the temp root; the macOS build does not
    // run under App Sandbox (docs/ARCHITECTURE.md), so it is writable.
    final Directory dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}gbm-revisions',
    )..createSync(recursive: true);
    _export(
      oid,
      path,
      '${dir.path}${Platform.pathSeparator}${_revisionFileName(path, oid)}',
      _ExportPurpose.openWithOs,
    );
  }

  Future<void> _saveRevisionAs(String path, String oid) async {
    final String? destPath = await ref
        .read(fileSavePickerProvider)
        .saveFile(suggestedName: _revisionFileName(path, oid));
    if (destPath == null || !mounted) return;
    _export(oid, path, destPath, _ExportPurpose.saveAs);
  }

  Future<void> _exportAsPatch(String oid) async {
    final String? dir = await ref.read(fileSavePickerProvider).pickDirectory();
    if (dir == null || !mounted) return;
    // Commit-level, not per-file: gbm_patch_export is `git format-patch -1
    // <commit>`, so what lands is the whole commit's patch even though the
    // menu was opened on one file's row. Spec lists the item under 05-K
    // regardless, and a single-file patch would be a different capi.
    ref.read(repoSessionProvider(widget.identity).notifier).exportPatches(
      <String>[oid],
      dir,
    );
  }

  /// Acts on a finished export, matched by the destination the capi echoed
  /// back. A failure is surfaced rather than swallowed -- the user asked for
  /// a file and there is no file, and spec's own rule for the terminal
  /// launcher ("找不到指定的終端機時不靜默失敗") is the same idea.
  void _onExportFinished(FileAtRevisionExport export) {
    final _ExportPurpose? purpose = _pendingExports.remove(export.destPath);
    if (purpose == null) return;

    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    if (!export.succeeded) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            export.error?.message ??
                'Could not read ${export.path} at that revision.',
          ),
        ),
      );
      return;
    }

    switch (purpose) {
      case _ExportPurpose.openWithOs:
        ref.read(desktopLauncherProvider).openFile(export.destPath);
      case _ExportPurpose.saveAs:
        messenger?.showSnackBar(
          SnackBar(content: Text('Saved to ${export.destPath}')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final RepoIdentity identity = widget.identity;
    final List<ChangedFile> files = ref.watch(commitFilesProvider(identity));
    final String? selectedPath = ref.watch(
      selectedCommitFilePathProvider(identity),
    );
    final String? selectedCommitOid = ref.watch(
      selectedCommitProvider(identity),
    );
    final FileListViewMode viewMode = ref.watch(fileListViewModeProvider);

    ref.listen<FileAtRevisionExport?>(
      repoSessionProvider(
        identity,
      ).select((RepoSessionState s) => s.lastFileAtRevisionExport),
      (FileAtRevisionExport? previous, FileAtRevisionExport? next) {
        if (next != null) _onExportFinished(next);
      },
    );

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
      // 05-K → "Open file at this revision". The commit's version is written
      // to a temp file and handed to the OS file association, which is what
      // 05-F's "Open file" does for the working copy -- a historical blob
      // has no path of its own to open.
      onOpenAtRevision: selectedCommitOid == null
          ? null
          : (String path) => _openAtRevision(path, selectedCommitOid),
      // 05-K → "Open terminal here". The repository work dir, matching what
      // 05-A and 05-F already open -- a historical commit's file has no
      // directory of its own to open a terminal in.
      onOpenTerminal: (String _) =>
          ref.read(desktopLauncherProvider).openTerminal(identity.workDir),
      // 05-K → More actions → "Restore file to this state" and "Restore and
      // stage". Both need the commit's oid as well as the path, which is why
      // they are bound here rather than inside the presentational half, and
      // both open the *same* dialog on purpose: restore_file_dialog.dart
      // offers the two as two buttons because the confirmation text is
      // identical, so a second dialog would be the same dialog.
      onRestoreToThisState: selectedCommitOid == null
          ? null
          : (String path) => context.push(
              RoutePaths.restoreFileDialogFor(
                Uri.encodeComponent(identity.workDir),
                path: path,
                oid: selectedCommitOid,
              ),
            ),
      onRestoreAndStage: selectedCommitOid == null
          ? null
          : (String path) => context.push(
              RoutePaths.restoreFileDialogFor(
                Uri.encodeComponent(identity.workDir),
                path: path,
                oid: selectedCommitOid,
              ),
            ),
      onSaveRevisionAs: selectedCommitOid == null
          ? null
          : (String path) => _saveRevisionAs(path, selectedCommitOid),
      onExportAsPatch: selectedCommitOid == null
          ? null
          : (String _) => _exportAsPatch(selectedCommitOid),
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
    this.onOpenAtRevision,
    this.onFileHistory,
    this.onBlame,
    this.onOpenTerminal,
    this.onRestoreToThisState,
    this.onRestoreAndStage,
    this.onSaveRevisionAs,
    this.onExportAsPatch,
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

  /// 05-K's "Open file at this revision". Null with no commit selected --
  /// there is no revision to read the file at.
  final ValueChanged<String>? onOpenAtRevision;
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

  /// 05-K's second-level "Restore and stage". Separate from
  /// [onRestoreToThisState] so the menu can list both items spec lists, even
  /// though the container points them at the same dialog -- see its comment
  /// there for why that is deliberate.
  final ValueChanged<String>? onRestoreAndStage;

  /// 05-K's second-level "Save this revision as…".
  final ValueChanged<String>? onSaveRevisionAs;

  /// 05-K's second-level "Export as patch…". Takes the path for signature
  /// symmetry with its neighbours even though the patch it writes is the
  /// whole commit's; see the container half for why.
  final ValueChanged<String>? onExportAsPatch;

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
  /// onFileTap), compare with working copy, open file at this revision, file
  /// history, blame, open terminal here, copy path, and a "More actions"
  /// submenu holding restore-to-this-state, restore-and-stage, save-this-
  /// revision-as and export-as-patch.
  ///
  /// Eight top-level items with a commit selected, which is exactly spec
  /// page 05's cap (`showGbmContextMenu` asserts it) -- nothing further can
  /// be added here without moving something into the submenu.
  List<GbmMenuItem> _buildMenuItems(String path) {
    final List<GbmMenuItem> moreActions = <GbmMenuItem>[
      if (onRestoreToThisState case final ValueChanged<String> restore)
        GbmMenuItem(
          label: 'Restore file to this state',
          icon: Icons.restore,
          onTap: () => restore(path),
        ),
      if (onRestoreAndStage case final ValueChanged<String> restoreAndStage)
        GbmMenuItem(
          label: 'Restore and stage',
          icon: Icons.playlist_add_check,
          onTap: () => restoreAndStage(path),
        ),
      if (onSaveRevisionAs case final ValueChanged<String> saveAs)
        GbmMenuItem(
          label: 'Save this revision as…',
          icon: Icons.save_alt,
          onTap: () => saveAs(path),
        ),
      if (onExportAsPatch case final ValueChanged<String> exportPatch)
        GbmMenuItem(
          label: 'Export as patch…',
          icon: Icons.attachment,
          onTap: () => exportPatch(path),
        ),
    ];

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
      if (onOpenAtRevision != null)
        GbmMenuItem(
          label: 'Open file at this revision',
          icon: Icons.open_in_new,
          onTap: () => onOpenAtRevision!(path),
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
      if (moreActions.isNotEmpty)
        GbmMenuItem.submenu(label: 'More actions', children: moreActions),
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
