import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/working_copy_status.dart';
import '../../data/repositories/file_list_view_mode_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart'
    show RepoSessionController, WorkingCopyDiffReply, repoSessionProvider;
import '../../data/repositories/working_copy_draft_repository.dart';
import '../../data/repositories/working_copy_repository.dart' as wc;
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/split_pane.dart';
import '../diff/diff_page.dart';
import '../diff/side_by_side_diff_view.dart';
import '../workspace/workspace_screen.dart' show repoIdForRoute;
import 'widgets/commit_message_box.dart';
import 'widgets/working_copy_board.dart';

/// Changed-file list (staged/unstaged/untracked) + diff pane + commit box.
/// The Dart analog of `WorkingCopyView` (src/app/views/pages/
/// WorkingCopyView.cpp). Route `/repo/:repoId/working-copy`.
///
/// State architecture:
/// - File selection: local Widget state (re-initializes on widget rebuild, not persisted)
/// - Commit message draft: [workingCopyDraftProvider] (survives tab switches)
/// - Diff scroll position: [workingCopyDraftProvider] (survives tab switches)
/// - Display mode (List/Tree): [fileListViewModeProvider] (global, all views)
/// - Tree-mode expanded folders: local Widget state (per-view)
class WorkingCopyView extends ConsumerStatefulWidget {
  const WorkingCopyView({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<WorkingCopyView> createState() => _WorkingCopyViewState();
}

class _WorkingCopyViewState extends ConsumerState<WorkingCopyView> {
  String? _selectedPath;
  bool _selectedStaged = false;
  // Side-by-side is read-only here, mirroring Qt's own WorkingCopyView --
  // see side_by_side_diff_view.dart's doc comment.
  bool _sideBySide = false;
  late TextEditingController _summaryController;
  late TextEditingController _descriptionController;
  late ScrollController _diffScrollController;
  late Set<String> _expandedFolders;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(workingCopyDraftProvider(widget.identity));
    _summaryController = TextEditingController(text: draft.summary);
    _descriptionController = TextEditingController(text: draft.description);
    _diffScrollController = ScrollController(
      initialScrollOffset: draft.diffScrollOffset,
    )..addListener(_onDiffScroll);
    _expandedFolders = <String>{};
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    _diffScrollController.dispose();
    super.dispose();
  }

  /// Persists the diff pane's scroll offset into [workingCopyDraftProvider]
  /// on every scroll event, so it survives the [ShellRoute] rebuild that
  /// happens when switching to the History tab and back -- without this,
  /// [initState] would always re-seed [_diffScrollController] from a
  /// diffScrollOffset that was never actually updated past its 0.0 default.
  void _onDiffScroll() {
    ref
        .read(workingCopyDraftProvider(widget.identity).notifier)
        .updateDiffScrollOffset(_diffScrollController.offset);
  }

  @override
  Widget build(BuildContext context) {
    final WorkingCopyStatus status = ref.watch(
      wc.repoWorkingCopyStatusProvider(widget.identity),
    );
    final WorkingCopyDiffReply? diffReply = ref.watch(
      wc.repoLastDiffProvider(widget.identity),
    );
    final FileListViewMode viewMode = ref.watch(fileListViewModeProvider);
    final GbmColors colors = context.gbmColors;

    // Combine unstaged + untracked (filtered) into a single list
    final unstagedAndUntracked = <WorkingCopyEntry>[
      ...status.unstaged,
      ...status.untrackedFiles.where((e) => !e.hasUnstagedChange),
    ];

    // A hunk/line stage or unstage action only refreshes the working-copy
    // status (see Session::stageHunk() et al.'s doc comments) -- the diff
    // pane itself is stale until re-requested, so re-fetch it for whatever
    // is currently selected whenever status changes (covers ordinary
    // whole-file stage/unstage too, which has the same staleness).
    ref.listen(wc.repoWorkingCopyStatusProvider(widget.identity), (
      previous,
      next,
    ) {
      final String? path = _selectedPath;
      if (path != null) {
        wc.requestWorkingCopyDiff(
          ref,
          widget.identity,
          path,
          staged: _selectedStaged,
        );
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // File board + diff pane (top)
        Expanded(
          flex: 5,
          child: GbmSplitPane(
            axis: Axis.vertical,
            spec: GbmLayout.splitterWcDiff,
            storageId: 'wc.diff',
            children: <Widget>[
              // File board (staged/unstaged columns)
              _buildFileBoard(
                context,
                status: status,
                unstagedAndUntracked: unstagedAndUntracked,
                viewMode: viewMode,
              ),
              // Diff pane
              _buildDiffPane(context, status: status, diffReply: diffReply),
            ],
          ),
        ),
        // Commit message box (bottom)
        Container(
          height: 200,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: _buildCommitBox(context, status: status),
        ),
      ],
    );
  }

  /// Builds the file board (two-column staged/unstaged).
  Widget _buildFileBoard(
    BuildContext context, {
    required WorkingCopyStatus status,
    required List<WorkingCopyEntry> unstagedAndUntracked,
    required FileListViewMode viewMode,
  }) {
    if (status.isClean) {
      final GbmColors colors = context.gbmColors;
      return Center(
        child: Text('No changes', style: TextStyle(color: colors.textTertiary)),
      );
    }

    return WorkingCopyBoard(
      unstagedEntries: unstagedAndUntracked,
      stagedEntries: status.staged,
      mode: viewMode,
      expandedFolders: _expandedFolders,
      onFileActivated: (path, fromStaged) {
        setState(() {
          _selectedPath = path;
          _selectedStaged = fromStaged;
        });
        wc.requestWorkingCopyDiff(
          ref,
          widget.identity,
          path,
          staged: fromStaged,
        );
      },
      onStageRequested: (paths) {
        wc.stageFiles(ref, widget.identity, paths);
      },
      onUnstageRequested: (paths) {
        wc.unstageFiles(ref, widget.identity, paths);
      },
      rowWrapper: (context, entry, fromStaged, child) {
        final String repoId = repoIdForRoute(widget.identity);
        return GestureDetector(
          onSecondaryTapDown: (details) {
            _openContextMenu(
              context,
              entry: entry,
              fromStaged: fromStaged,
              position: details.globalPosition,
              repoId: repoId,
            );
          },
          child: child,
        );
      },
    );
  }

  /// Builds the diff pane with scroll position preservation.
  Widget _buildDiffPane(
    BuildContext context, {
    required WorkingCopyStatus status,
    required WorkingCopyDiffReply? diffReply,
  }) {
    final GbmColors colors = context.gbmColors;

    if (_selectedPath == null) {
      return Center(
        child: Text(
          'Select a file',
          style: TextStyle(color: colors.textTertiary),
        ),
      );
    }

    if (diffReply == null ||
        diffReply.path != _selectedPath ||
        diffReply.staged != _selectedStaged) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Side-by-side toggle
        if (_selectedPath != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Checkbox(
                  value: _sideBySide,
                  onChanged: (value) =>
                      setState(() => _sideBySide = value ?? false),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  'Side by side',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        // Diff view
        Expanded(
          child: _sideBySide
              ? SideBySideDiffView(diff: diffReply.diff)
              : DiffPage(
                  diff: diffReply.diff,
                  staged: _selectedStaged,
                  scrollController: _diffScrollController,
                  onStageHunk: (_, hunkIndex) {
                    final RepoSessionController notifier = ref.read(
                      repoSessionProvider(widget.identity).notifier,
                    );
                    if (_selectedStaged) {
                      notifier.unstageHunk(_selectedPath!, hunkIndex);
                    } else {
                      notifier.stageHunk(_selectedPath!, hunkIndex);
                    }
                  },
                  onStageLines: (_, hunkIndex, lineIndices) {
                    final RepoSessionController notifier = ref.read(
                      repoSessionProvider(widget.identity).notifier,
                    );
                    if (_selectedStaged) {
                      notifier.unstageLines(
                        _selectedPath!,
                        hunkIndex,
                        lineIndices,
                      );
                    } else {
                      notifier.stageLines(
                        _selectedPath!,
                        hunkIndex,
                        lineIndices,
                      );
                    }
                  },
                ),
        ),
      ],
    );
  }

  /// Builds the commit message box.
  Widget _buildCommitBox(
    BuildContext context, {
    required WorkingCopyStatus status,
  }) {
    final bool canCommit =
        status.staged.isNotEmpty && _summaryController.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(GbmSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: CommitMessageBox(
              summaryController: _summaryController,
              descriptionController: _descriptionController,
              onSummaryChanged: (text) {
                ref
                    .read(workingCopyDraftProvider(widget.identity).notifier)
                    .updateSummary(text);
              },
              onDescriptionChanged: (text) {
                ref
                    .read(workingCopyDraftProvider(widget.identity).notifier)
                    .updateDescription(text);
              },
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          Row(
            children: <Widget>[
              GbmButton(
                label: 'Commit',
                kind: GbmButtonKind.primary,
                onPressed: canCommit ? () => _onCommit() : null,
              ),
              const SizedBox(width: GbmSpacing.space2),
              GbmButton(
                label: 'Amend',
                kind: GbmButtonKind.secondary,
                onPressed: canCommit ? () => _onAmend() : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Commits changes with the current message.
  void _onCommit() {
    final message = _summaryController.text.trim();
    final description = _descriptionController.text.trim();
    final fullMessage = description.isEmpty
        ? message
        : '$message\n\n$description';

    wc.commitChanges(ref, widget.identity, fullMessage);

    // Reset draft immediately (success confirmation arrives async)
    _summaryController.clear();
    _descriptionController.clear();
    ref.read(workingCopyDraftProvider(widget.identity).notifier).reset();
  }

  /// Amends the last commit with the current message.
  void _onAmend() {
    final message = _summaryController.text.trim();
    final description = _descriptionController.text.trim();
    final fullMessage = description.isEmpty
        ? message
        : '$message\n\n$description';

    wc.commitChanges(ref, widget.identity, fullMessage, amend: true);

    // Reset draft immediately (success confirmation arrives async)
    _summaryController.clear();
    _descriptionController.clear();
    ref.read(workingCopyDraftProvider(widget.identity).notifier).reset();
  }

  /// Opens the context menu for a file.
  void _openContextMenu(
    BuildContext context, {
    required WorkingCopyEntry entry,
    required bool fromStaged,
    required Offset position,
    required String repoId,
  }) {
    // Delegate to ChangedFileRow's context menu logic.
    // For now, we replicate the basic menu since we're not using ChangedFileRow directly.
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return SimpleDialog(
          title: const Text('File options'),
          children: <Widget>[
            if (!fromStaged)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _discardFile(entry);
                },
                child: const Text('Discard changes'),
              ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.push(
                  RoutePaths.blameDialogFor(repoId, path: entry.path),
                );
              },
              child: const Text('Blame…'),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.push(
                  RoutePaths.fileHistoryDialogFor(repoId, path: entry.path),
                );
              },
              child: const Text('File History…'),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.push(
                  RoutePaths.lineHistoryDialogFor(repoId, path: entry.path),
                );
              },
              child: const Text('Line History…'),
            ),
          ],
        );
      },
    );
  }

  /// Discards changes to a file.
  void _discardFile(WorkingCopyEntry entry) {
    ref.read(repoSessionProvider(widget.identity).notifier).restorePaths(
      <String>[entry.path],
    );
  }
}
