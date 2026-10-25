import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_action_availability.dart';
import '../../actions/gbm_action_id.dart';
import '../../data/models/commit_meta.dart';
import '../../data/models/parsed_diff.dart';
import '../../data/models/prepared_message_policy.dart';
import '../../data/models/working_copy_status.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../data/repositories/file_list_view_mode_repository.dart';
import '../../data/repositories/panel_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart'
    show
        ConflictResolution,
        PreparedMessageReply,
        RepoSessionController,
        RepoSessionState,
        WorkingCopyDiffReply,
        repoSessionProvider,
        workingCopyDiffKey;
import '../../data/repositories/working_copy_draft_repository.dart';
import '../../data/repositories/working_copy_repository.dart' as wc;
import '../../data/models/app_action.dart';
import '../../data/services/app_action_runner.dart';
import '../../data/services/app_actions.dart';
import '../../data/services/desktop_launcher.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_badge.dart' show GbmBadge, GbmBadgeKind;
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_menu.dart';
import '../../widgets/split_pane.dart';
import '../diff/diff_full_file_fill.dart';
import '../diff/temporary_scope_provider.dart';
import '../conflict_resolution/original_operation_message_dialog.dart'
    show splitOriginalOperationMessage;
import '../workspace/workspace_screen.dart' show repoIdForRoute;
import 'working_copy_file_identity.dart';
import 'widgets/commit_message_box.dart';
import 'widgets/working_copy_board.dart';
import 'widgets/working_copy_diff_pane.dart';
import 'widgets/working_copy_file_menu_items.dart';
import '../../routing/dialog_route.dart';

/// Changed-file list (staged/unstaged/untracked) + diff pane + commit box.
/// The Dart analog of `WorkingCopyView` (src/app/views/pages/
/// WorkingCopyView.cpp). Route `/repo/:repoId/working-copy`.
///
/// State architecture:
/// - File selection: local Widget state (re-initializes on widget rebuild, not persisted)
/// - Commit message draft: [workingCopyDraftProvider] (survives tab switches)
/// - Diff scroll position: [workingCopyDraftProvider] (survives tab switches)
/// - Display mode (List/Tree): [fileListViewModeProvider] (global, all views)
/// - Tree-mode expanded folders: owned by [FileTreeList] itself, like every
///   other tree-mode file list
/// Wide enough for `Cancel amend` at the button font, and fixed so the
/// message box's width does not change when the mode does.
const double _kCommitButtonColumnWidth = 132;

class WorkingCopyView extends ConsumerStatefulWidget {
  const WorkingCopyView({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<WorkingCopyView> createState() => _WorkingCopyViewState();
}

class _WorkingCopyViewState extends ConsumerState<WorkingCopyView> {
  String? _selectedPath;

  /// The oid whose message has already been pulled into the box for
  /// amending, so a rebuild does not overwrite the user's edits with HEAD's
  /// original text every time the cache is touched.
  String? _amendPrefilledFor;

  late TextEditingController _summaryController;
  late TextEditingController _descriptionController;
  late ScrollController _diffScrollController;

  /// A [_reconcilePreparedMessage] pass is already scheduled for the end of
  /// this frame.
  bool _preparedPassScheduled = false;

  /// The first pass after mounting re-asks an unanswered parent check: its
  /// reply may have arrived, and been evicted, while this view was gone.
  bool _firstPreparedPass = true;

  @override
  void initState() {
    super.initState();
    // A merge can already be pending when the view mounts (app startup,
    // ruling ⑪), and a listener never fires for the value already there.
    _schedulePreparedPass();
    final draft = ref.read(workingCopyDraftProvider(widget.identity));
    _summaryController = TextEditingController(text: draft.summary)
      ..addListener(_onSummaryChanged);
    _descriptionController = TextEditingController(text: draft.description);
    _diffScrollController = ScrollController(
      initialScrollOffset: draft.diffScrollOffset,
    )..addListener(_onDiffScroll);
  }

  /// Switching worktree keeps this State: go_router keys the page by route,
  /// not by `repoId`. Everything [initState] seeded from the old identity's
  /// draft is re-seeded from the new one's, or one repository's commit
  /// message sits in -- and is then saved into -- the other's box.
  ///
  /// The controllers are re-seeded after this frame, not here:
  /// [CommitMessageBox] writes every controller change into the draft
  /// provider, and a provider write during build throws.
  @override
  void didUpdateWidget(WorkingCopyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity == widget.identity) return;
    _selectedPath = null;
    _amendPrefilledFor = null;
    _firstPreparedPass = true;
    final RepoIdentity identity = widget.identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.identity != identity) return;
      final draft = ref.read(workingCopyDraftProvider(identity));
      _summaryController.text = draft.summary;
      _descriptionController.text = draft.description;
      if (_diffScrollController.hasClients) {
        _diffScrollController.jumpTo(draft.diffScrollOffset);
      }
    });
    _schedulePreparedPass();
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

  /// Triggers a rebuild on every keystroke in the summary field, mirroring
  /// [_onDiffScroll]'s listener pattern. Without this, [_buildCommitBox]'s
  /// `canCommit` (which reads `_summaryController.text.trim()` directly,
  /// not a watched provider) only recomputes on some *unrelated* rebuild --
  /// e.g. staging a file -- not when the summary text itself changes, so
  /// the Commit/Amend buttons stay stale until something else happens to
  /// force a rebuild (code-review-2026-08.md H2). No state to update here;
  /// `onSummaryChanged` (wired separately, below) already persists the text
  /// into [workingCopyDraftProvider] -- this listener exists purely to make
  /// `canCommit` re-evaluate.
  void _onSummaryChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(repoSessionProvider(widget.identity));
    final WorkingCopyStatus status = ref.watch(
      wc.repoWorkingCopyStatusProvider(widget.identity),
    );
    final Map<String, WorkingCopyDiffReply> diffs = ref.watch(
      wc.repoWorkingCopyDiffsProvider(widget.identity),
    );
    final Map<String, WorkingCopyDiffReply> fullDiffs = ref.watch(
      wc.repoWorkingCopyFullDiffsProvider(widget.identity),
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
      WorkingCopyStatus next,
    ) {
      _requestBothSides(next);
    });
    // Switched on with a file already selected: its full diffs are wanted
    // now, not on the next click or status change.
    ref.listen<bool>(
      appPreferencesProvider.select((p) => p.fullFileViewEnabled),
      (bool? previous, bool next) {
        if (next && previous != true) {
          _requestBothSides(
            ref.read(wc.repoWorkingCopyStatusProvider(widget.identity)),
          );
        }
      },
    );

    _watchAmendPrefill(session);
    _watchPreparedMessage();
    _syncBoxFromDraft();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Conflicted section (only if there are conflicted files)
        if (status.conflicted.isNotEmpty)
          _buildConflictedSection(context, status: status, session: session),
        // File board (left) + diff pane (right)
        Expanded(
          flex: 5,
          child: GbmSplitPane(
            // Horizontal, and it used to be vertical -- 「file line view 在
            // 右側」. The complaint this answers is that the diff's readable
            // width was being spent on two file columns; stacking those on
            // the left and giving the diff the rest of the window is the
            // whole change. Page 09's SPLITTERS row for `wc.diff` says
            // `dir: '水平'`, so this is a ruled deviation, not a fix.
            axis: Axis.horizontal,
            // Pane 0 (the board) is the fixed-width one and sits at the
            // leading edge, which is `fixedPaneEnd`'s default -- so a wider
            // window gives every new pixel to the diff.
            spec: GbmLayout.splitterWcFiles,
            storageId: 'wc.files',
            children: <Widget>[
              // File board (staged/unstaged columns)
              _buildFileBoard(
                context,
                status: status,
                unstagedAndUntracked: unstagedAndUntracked,
                viewMode: viewMode,
              ),
              // Diff pane
              _buildDiffPane(
                context,
                status: status,
                diffs: diffs,
                fullDiffs: fullDiffs,
              ),
            ],
          ),
        ),
        // Commit message box (bottom)
        Container(
          height: 200,
          decoration: BoxDecoration(
            // P3's mock: the commit area is surface-panel-raised (ruling ⑮).
            color: colors.surfacePanelRaised,
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: _buildCommitBox(context, status: status, session: session),
        ),
      ],
    );
  }

  /// Builds the conflicted files section (pinned at the top).
  /// Only rendered when there are conflicted files.
  Widget _buildConflictedSection(
    BuildContext context, {
    required WorkingCopyStatus status,
    required RepoSessionState session,
  }) {
    final GbmColors colors = context.gbmColors;
    final conflicted = status.conflicted;
    final String repoId = repoIdForRoute(widget.identity);

    // This section sits as a bare child of the outer Column in build(),
    // which gives it unbounded height -- the Expanded ListView below needs
    // a bounded (not necessarily tight) max height from somewhere to
    // resolve its flex, or RenderFlex throws during layout instead of the
    // conflicted-file list ever painting. Capped at a fixed height rather
    // than shrink-wrapped so an unusually large conflict count scrolls
    // internally instead of pushing the file board/commit box off-screen.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header
            Container(
              height: GbmSpacing.rowHeightCompact,
              color: colors.surfacePanelRaised,
              padding: const EdgeInsets.symmetric(
                horizontal: GbmSpacing.space2,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'CONFLICTED',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  GbmBadge(
                    label: '${conflicted.length}',
                    kind: GbmBadgeKind.removed,
                  ),
                ],
              ),
            ),
            // Conflicted files list
            Expanded(
              child: ListView.builder(
                itemCount: conflicted.length,
                itemBuilder: (context, index) {
                  final entry = conflicted[index];
                  return _buildConflictedFileRow(
                    context,
                    entry: entry,
                    repoId: repoId,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a single conflicted file row.
  Widget _buildConflictedFileRow(
    BuildContext context, {
    required WorkingCopyEntry entry,
    required String repoId,
  }) => _ConflictedFileRow(
    entry: entry,
    onOpenConflicts: () => context.go(RoutePaths.conflictsFor(repoId)),
    notifier: ref.read(repoSessionProvider(widget.identity).notifier),
  );

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
      lineCountsUnavailable: status.lineCountsUnavailable,
      // `fromStaged` says which column was clicked, which no longer selects
      // anything: the pane below draws both sides of the file at once, so
      // there is no "side I am looking at" left to record. The board still
      // reports it because its own row context menu (05-F) needs to know
      // whether the row it was opened on can be staged or unstaged.
      onFileActivated: (String path, bool fromStaged) {
        setState(() => _selectedPath = path);
        _requestBothSides(status);
      },
      onStageRequested: (paths) {
        wc.stageFiles(ref, widget.identity, paths);
      },
      onUnstageRequested: (paths) {
        wc.unstageFiles(ref, widget.identity, paths);
      },
      rowWrapper: (context, entry, fromStaged, selectedPaths, child) {
        return GestureDetector(
          onSecondaryTapDown: (details) {
            _openContextMenu(
              context,
              entry: entry,
              fromStaged: fromStaged,
              selectedPaths: selectedPaths,
              position: details.globalPosition,
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
    required Map<String, WorkingCopyDiffReply> diffs,
    required Map<String, WorkingCopyDiffReply> fullDiffs,
  }) {
    final GbmColors colors = context.gbmColors;
    final StateController<void Function()?> scopeSubmit = ref.read(
      temporaryScopeSubmitProvider.notifier,
    );

    if (_selectedPath == null) {
      return Center(
        child: Text(
          'Select a file',
          style: TextStyle(color: colors.textTertiary),
        ),
      );
    }

    final ({String? unstaged, String? staged}) sides = _selectedSides(status);
    final WorkingCopyDiffReply? unstagedReply = sides.unstaged == null
        ? null
        : diffs[workingCopyDiffKey(sides.unstaged!, staged: false)];
    final WorkingCopyDiffReply? stagedReply = sides.staged == null
        ? null
        : diffs[workingCopyDiffKey(sides.staged!, staged: true)];
    final bool fullFile = ref.watch(
      appPreferencesProvider.select((p) => p.fullFileViewEnabled),
    );
    final DiffFile? unstagedFull = !fullFile || sides.unstaged == null
        ? null
        : _fileOf(
            fullDiffs[workingCopyDiffKey(sides.unstaged!, staged: false)],
          );
    final DiffFile? stagedFull = !fullFile || sides.staged == null
        ? null
        : _fileOf(fullDiffs[workingCopyDiffKey(sides.staged!, staged: true)]);
    _refetchIfDisagreeing(
      sides.unstaged,
      _fileOf(unstagedReply),
      unstagedFull,
      staged: false,
    );
    _refetchIfDisagreeing(
      sides.staged,
      _fileOf(stagedReply),
      stagedFull,
      staged: true,
    );

    return WorkingCopyDiffPane(
      unstagedFullFile: unstagedFull,
      stagedFullFile: stagedFull,
      fullFile: fullFile,
      onToggleFullFile: () =>
          ref.read(appPreferencesProvider.notifier).toggleFullFileView(),
      // Read here rather than inside ScopedDiffView: this is the nearest
      // container that already holds a Riverpod dependency, and keeping the
      // diff widgets on plain values is what lets their tests pump them
      // without a ProviderScope.
      softWrap: ref.watch(appPreferencesProvider).softWrapEnabled,
      // Two paths when a rename is half-staged: the work tree still calls it
      // the old name while the index already calls it the new one, and
      // showing only one of them would make the pane look like it is
      // describing a file the board is not selecting.
      displayPath: _displayPath(sides),
      unstagedFile: _fileOf(unstagedReply),
      stagedFile: _fileOf(stagedReply),
      // Pending means the side exists but its reply has not landed. A side
      // that does not exist at all is not loading; it is empty, and
      // ScopedDiffView says so.
      unstagedLoading: sides.unstaged != null && unstagedReply == null,
      stagedLoading: sides.staged != null && stagedReply == null,
      // Refused for size, which is not the same as having nothing to show --
      // the pane says so rather than drawing `emptyLabel` over it.
      unstagedTruncated: unstagedReply?.diff.truncated ?? false,
      stagedTruncated: stagedReply?.diff.truncated ?? false,
      scrollController: _diffScrollController,
      onStageScope: (bool staged, int hunkIndex, List<int> lineIndices) {
        final String? path = staged ? sides.staged : sides.unstaged;
        if (path == null) return;
        final RepoSessionController notifier = ref.read(
          repoSessionProvider(widget.identity).notifier,
        );
        if (staged) {
          notifier.unstageLines(path, hunkIndex, lineIndices);
        } else {
          notifier.stageLines(path, hunkIndex, lineIndices);
        }
      },
      onDiscardScope: (int hunkIndex, List<int> lineIndices) =>
          _discardLines(hunkIndex, lineIndices),
      // Already inside a post-frame callback when it arrives (see
      // ScopedDiffView.onTemporaryScopeChanged), so this is not a provider
      // write from build(). The notifier is taken now, not in the callback:
      // ScopedDiffView.dispose() reports `null` a frame later, and when this
      // whole view leaves in the same frame `ref` is already unusable by
      // then. The provider is app-scoped, so the notifier outlives the view.
      onTemporaryScopeChanged: (void Function()? submit) {
        scopeSubmit.state = submit;
      },
    );
  }

  /// What the diff titlebar names for the current selection.
  String _displayPath(({String? unstaged, String? staged}) sides) {
    final String? unstaged = sides.unstaged;
    final String? staged = sides.staged;
    if (unstaged != null && staged != null && unstaged != staged) {
      return '$unstaged \u2192 $staged';
    }
    return unstaged ?? staged ?? _selectedPath ?? '';
  }

  /// A working-copy diff describes exactly one path, because the request
  /// that produced it named one path -- so the reply's single file is the
  /// whole of it.
  ///
  /// **An empty `files` is not one condition.** It used to be read as "git
  /// reported no change on that side", and that reading is what made an
  /// untracked file draw `Nothing unstaged` next to a row badge saying `+12`:
  /// `git diff` cannot see a path that is in neither the index nor HEAD, so
  /// it reported nothing and the pane believed it. The core answers untracked
  /// paths itself now (`DiffService::workingTreeDiff`), and the other case an
  /// empty `files` can mean -- a diff refused for its size -- is carried by
  /// `truncated` and read separately above. What is left here really is "no
  /// change on that side".
  /// Asks for both of one side's diffs again when they disagree on which
  /// lines changed, so the full-file view can fill; the pane stays in
  /// excerpt mode meanwhile. After the frame, because a provider write from
  /// `build` is forbidden; the controller asks at most once per
  /// fingerprint, so a rebuild that sees the same pair asks nothing more.
  void _refetchIfDisagreeing(
    String? path,
    DiffFile? excerpt,
    DiffFile? full, {
    required bool staged,
  }) {
    if (path == null || excerpt == null || full == null) return;
    if (fullDiffAgreesWith(excerpt, full)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      wc.refetchDisagreeingWorkingCopyDiffs(
        ref,
        widget.identity,
        path,
        staged: staged,
      );
    });
  }

  DiffFile? _fileOf(WorkingCopyDiffReply? reply) =>
      reply == null || reply.diff.files.isEmpty ? null : reply.diff.files.first;

  /// The path each column uses for the selected file, which is **not**
  /// always the same string: a staged rename is `new` on the staged side
  /// while the work tree still talks about `old`. Both are resolved through
  /// [logicalFileKey], the one definition of "the same file" the board's
  /// selection also uses.
  ({String? unstaged, String? staged}) _selectedSides(
    WorkingCopyStatus status,
  ) {
    final String? path = _selectedPath;
    if (path == null) return (unstaged: null, staged: null);

    String? keyOf(List<WorkingCopyEntry> side) {
      for (final WorkingCopyEntry entry in side) {
        if (entry.path == path) return logicalFileKey(entry);
      }
      return null;
    }

    final String key =
        keyOf(status.entries) ?? logicalFileKey(_syntheticEntry(path));

    String? pathIn(List<WorkingCopyEntry> side) {
      for (final WorkingCopyEntry entry in side) {
        if (logicalFileKey(entry) == key) return entry.path;
      }
      return null;
    }

    return (
      unstaged: pathIn(status.entriesWithUnstagedSide),
      staged: pathIn(status.staged),
    );
  }

  /// Fires one diff request per side of the selected file.
  ///
  /// Both, not just the side that was clicked: spec page 03 shows the
  /// unstaged and the staged diff of one file at the same time, and each
  /// side has to be asked for under its own path. A single request is why
  /// the pane used to go stale on whichever side the user was not looking
  /// at when a line was staged.
  ///
  /// With the full-file view on, each side's full-context diff is asked for
  /// beside it, under the same path: the view fills between the -U3 cards
  /// from it, and the two are compared against each other, so they must be
  /// asked for together.
  void _requestBothSides(WorkingCopyStatus status) {
    final ({String? unstaged, String? staged}) sides = _selectedSides(status);
    final bool full = ref.read(appPreferencesProvider).fullFileViewEnabled;
    if (sides.unstaged case final String path) {
      wc.requestWorkingCopyDiff(ref, widget.identity, path, staged: false);
      if (full) {
        wc.requestWorkingCopyFullDiff(
          ref,
          widget.identity,
          path,
          staged: false,
        );
      }
    }
    if (sides.staged case final String path) {
      wc.requestWorkingCopyDiff(ref, widget.identity, path, staged: true);
      if (full) {
        wc.requestWorkingCopyFullDiff(ref, widget.identity, path, staged: true);
      }
    }
  }

  /// A stand-in for a path that is no longer in the status at all (the file
  /// was staged away between the click and this rebuild). It keys to the
  /// path itself, so both lookups above simply come back null.
  WorkingCopyEntry _syntheticEntry(String path) => WorkingCopyEntry(
    path: path,
    oldPath: '',
    untracked: false,
    staged: false,
    indexStatus: FileChangeKind.modified,
    hasUnstagedChange: false,
    worktreeStatus: FileChangeKind.modified,
    unstagedAdded: 0,
    unstagedRemoved: 0,
    stagedAdded: 0,
    stagedRemoved: 0,
    conflict: ConflictKind.none,
    ancestorBlob: '',
    oursBlob: '',
    theirsBlob: '',
    similarity: 0,
    isSubmodule: false,
    isConflicted: false,
  );

  /// Builds the commit message box.
  Widget _buildCommitBox(
    BuildContext context, {
    required WorkingCopyStatus status,
    required RepoSessionState session,
  }) {
    // A merge concludes with nothing staged when every conflict took ours
    // (ruling ⑤⑭, which overrides P3 item 8 for this case); git commits it.
    final bool canCommit =
        (status.staged.isNotEmpty || (session.repoState?.isMerging ?? false)) &&
        _summaryController.text.trim().isNotEmpty &&
        isActionEnabled(GbmActionId.repositoryCommit, session);

    final WorkingCopyDraft draft = ref.watch(
      workingCopyDraftProvider(widget.identity),
    );

    return Padding(
      padding: const EdgeInsets.all(GbmSpacing.space3),
      // Buttons in a fixed-width column at the right of the fields, which is
      // where spec P03's mockup draws them. The width is explicit and the
      // fields are Expanded rather than the other way round: RenderFlex lays
      // its non-flex children out first and divides only what is left, so a
      // button column that sized itself to its labels would decide how much
      // of the row the message box gets.
      child: Row(
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
          const SizedBox(width: GbmSpacing.space2),
          SizedBox(
            width: _kCommitButtonColumnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (draft.amending) ...<Widget>[
                  GbmButton(
                    label: 'Amend',
                    kind: GbmButtonKind.primary,
                    onPressed: canCommit ? () => _onSubmit(amend: true) : null,
                  ),
                  const SizedBox(height: GbmSpacing.space2),
                  GbmButton(
                    label: 'Cancel amend',
                    kind: GbmButtonKind.ghost,
                    onPressed: _onCancelAmend,
                  ),
                ] else ...<Widget>[
                  GbmButton(
                    label: 'Commit',
                    kind: GbmButtonKind.primary,
                    onPressed: canCommit ? () => _onSubmit(amend: false) : null,
                  ),
                  // Enters the mode; it does not amend. The box has to show
                  // what is about to be rewritten before there is anything
                  // to press Amend on. No ellipsis: no dialog follows
                  // ([UX-ellipsis-promises-a-dialog], ruling ⑮). Not drawn
                  // at all during a merge, where git refuses to amend (④).
                  if (!(session.repoState?.isMerging ?? false)) ...<Widget>[
                    const SizedBox(height: GbmSpacing.space2),
                    GbmButton(
                      label: 'Amend',
                      kind: GbmButtonKind.secondary,
                      onPressed:
                          isActionEnabled(
                            GbmActionId.repositoryAmendLastCommit,
                            session,
                          )
                          ? () => wc.beginAmendMode(ref, widget.identity)
                          : null,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pulls HEAD's message into the box once it arrives, exactly once per oid.
  void _watchAmendPrefill(RepoSessionState session) {
    final WorkingCopyDraft draft = ref.watch(
      workingCopyDraftProvider(widget.identity),
    );
    if (!draft.amending) {
      _amendPrefilledFor = null;
      return;
    }
    final String head = session.refs.head.target;
    if (head.isEmpty || _amendPrefilledFor == head) return;
    final CommitMeta? meta = session.commitMetaCache[head];
    if (meta == null) return;

    _amendPrefilledFor = head;
    // Post-frame: this runs from build(), and both the controllers and the
    // draft provider are written here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _summaryController.text = meta.subject;
      _descriptionController.text = meta.body;
      ref
          .read(workingCopyDraftProvider(widget.identity).notifier)
          .applyAmendedMessage(summary: meta.subject, description: meta.body);
    });
  }

  /// Keeps the two text fields showing what the draft holds, whoever changed
  /// it -- the prepared-message episode, a cancelled amend, a reset. Typing
  /// writes the draft from the field, so the two are already equal then and
  /// nothing is written back (the cursor stays put). Without this, a draft
  /// changed off-screen leaves the box showing text Commit would not send.
  void _syncBoxFromDraft() {
    ref.listen<WorkingCopyDraft>(workingCopyDraftProvider(widget.identity), (
      _,
      WorkingCopyDraft next,
    ) {
      if (_summaryController.text != next.summary) {
        _summaryController.text = next.summary;
      }
      if (_descriptionController.text != next.description) {
        _descriptionController.text = next.description;
      }
    });
  }

  /// Re-runs the prepared-message episode whenever anything it reads
  /// changes: RepoState and its pending flag, the reply, HEAD, or the
  /// overwrite switch.
  void _watchPreparedMessage() {
    ref.listen<(bool, PreparedMessageReply?, String, bool, int, bool, int)>(
      repoSessionProvider(widget.identity).select(
        (s) => (
          s.repoState?.preparedMessagePending ?? false,
          s.preparedMessage,
          // HEAD and RepoState arriving at all are inputs too: nothing
          // that records an episode is decided before either.
          s.refs.head.target,
          s.repoState == null,
          // Slice D R2's waits: refs read for the head check (an Abort
          // changes nothing else in them), an error while waiting, and a
          // commit-meta reply -- empty ones included.
          s.refsCoverRequest,
          s.lastError != null,
          s.commitMetaReplySeq,
        ),
      ),
      (_, _) => _schedulePreparedPass(),
    );
    ref.listen<bool>(
      appPreferencesProvider.select((p) => p.overwriteWithPreparedMessage),
      (_, _) => _schedulePreparedPass(),
    );
  }

  /// Post-frame, because a pass writes the draft provider and may request
  /// from the session -- neither may happen while a listener of either is
  /// being notified. [FLU-postframe-no-frame]: the callback only runs if a
  /// frame is coming, so ask for one.
  void _schedulePreparedPass() {
    if (_preparedPassScheduled) return;
    _preparedPassScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preparedPassScheduled = false;
      if (mounted) _reconcilePreparedMessage();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _reconcilePreparedMessage() {
    final RepoSessionState session = ref.read(
      repoSessionProvider(widget.identity),
    );
    final PreparedMessageReply? reply = session.preparedMessage;
    final String message = reply?.message.trimRight() ?? '';
    final PreparedReplyStatus status = reply == null
        ? PreparedReplyStatus.none
        : (reply.failed || message.isEmpty)
        ? PreparedReplyStatus.failed
        : PreparedReplyStatus.message;
    final ({String summary, String description}) split =
        splitOriginalOperationMessage(message);

    final bool mounting = _firstPreparedPass;
    _firstPreparedPass = false;
    final PreparedMessageAction action = ref
        .read(workingCopyDraftProvider(widget.identity).notifier)
        .reconcilePreparedMessage(
          pending: session.repoState?.preparedMessagePending ?? false,
          reply: status,
          summary: split.summary,
          description: split.description,
          raw: status == PreparedReplyStatus.message ? message : '',
          head: session.refs.head.target,
          repoStateKnown: session.repoState != null,
          overwrite: ref
              .read(appPreferencesProvider)
              .overwriteWithPreparedMessage,
          refsCoverRequest: session.refsCoverRequest,
          requestRefresh: ref
              .read(repoSessionProvider(widget.identity).notifier)
              .refreshHistory,
          commitMetaReplySeq: session.commitMetaReplySeq,
          commitMetaRequestSeq: ref
              .read(repoSessionProvider(widget.identity).notifier)
              .commitMetaRequestSeq,
          parentsOf: (String oid) => session.commitMetaCache[oid]?.parents,
          lastErrorPresent: session.lastError != null,
          mounting: mounting,
        );
    // The box follows the draft through [_syncBoxFromDraft]; all that is
    // left here is asking core for the message.
    switch (action) {
      case PreparedMessageAction.startAndRequest:
      case PreparedMessageAction.cancelAmendAndStart:
      case PreparedMessageAction.revalidate:
        ref
            .read(repoSessionProvider(widget.identity).notifier)
            .requestPreparedMessage();
      case PreparedMessageAction.checkParent:
        ref
            .read(repoSessionProvider(widget.identity).notifier)
            .requestCommitMeta(<String>[session.refs.head.target]);
      // Sent by the draft itself, which records the request number.
      case PreparedMessageAction.checkHead:
      case PreparedMessageAction.replace:
      case PreparedMessageAction.restoreAndEnd:
      case PreparedMessageAction.nothing:
      case PreparedMessageAction.keep:
      case PreparedMessageAction.end:
      case PreparedMessageAction.keepValidated:
      case PreparedMessageAction.replaceAsNew:
      case PreparedMessageAction.clearAndEnd:
        break;
    }
  }

  void _onCancelAmend() {
    final WorkingCopyDraftController notifier = ref.read(
      workingCopyDraftProvider(widget.identity).notifier,
    );
    notifier.cancelAmend();
    final WorkingCopyDraft restored = ref.read(
      workingCopyDraftProvider(widget.identity),
    );
    _summaryController.text = restored.summary;
    _descriptionController.text = restored.description;
    _amendPrefilledFor = null;
  }

  /// Submits, through the one shared entry point the menu and the shortcut
  /// also use.
  /// Waiting for the commit to land is `WorkspaceScreen`'s job, for every
  /// path alike (`WorkingCopyDraft.pendingCommitSeq`).
  void _onSubmit({required bool amend}) {
    wc.submitCommit(ref, widget.identity, amend: amend);
  }

  /// Context menu 05-F for a working-copy file.
  ///
  /// Previously opened a Material `SimpleDialog` titled "File options" -- a
  /// modal in the middle of the screen where the spec calls for a right-click
  /// menu at the cursor, and the one place in the app that bypassed
  /// `showGbmContextMenu` and so picked up none of the design system's menu
  /// styling.
  ///
  /// Spec 05-F: "有多選時全部動作改為複數並帶數量，例如 Stage 3 files" -- when
  /// the right-clicked row is part of a multi-selection, the actions apply to
  /// the whole batch and say how many files that is.
  ///
  /// The item list itself lives in `widgets/working_copy_file_menu_items.dart`
  /// so `context_menu_parity_test.dart` can check it against the spec catalog
  /// without pumping this whole view; see that file for why Blame / File
  /// History / Line History are no longer here.
  void _openContextMenu(
    BuildContext context, {
    required WorkingCopyEntry entry,
    required bool fromStaged,
    required Set<String> selectedPaths,
    required Offset position,
  }) {
    // A right-click on a row outside the current selection acts on that row
    // alone, matching every other list in the app; right-clicking inside the
    // selection keeps the batch.
    final List<String> targets = selectedPaths.contains(entry.path)
        ? selectedPaths.toList(growable: false)
        : <String>[entry.path];
    final DesktopLauncher launcher = ref.read(desktopLauncherProvider);
    // Open file / Show in file manager act on the right-clicked row, not the
    // batch (see workingCopyFileMenuItems' doc comment), and both need an
    // absolute path -- `entry.path` is repository-relative.
    final String absolutePath = _absolutePathOf(entry.path);

    showGbmContextMenu(
      context,
      position,
      workingCopyFileMenuItems(
        count: targets.length,
        fromStaged: fromStaged,
        onStageToggle: () => fromStaged
            ? wc.unstageFiles(ref, widget.identity, targets)
            : wc.stageFiles(ref, widget.identity, targets),
        onOpenFile: () => _launch(openFileAction(launcher, absolutePath)),
        onShowInFileManager: () =>
            _launch(openInFileManagerAction(launcher, absolutePath)),
        onOpenTerminal: () =>
            _launch(openTerminalAction(launcher, widget.identity.workDir)),
        onCopyPath: () =>
            Clipboard.setData(ClipboardData(text: targets.join('\n'))),
        onDiscard: fromStaged ? null : () => _discardFiles(targets),
        // Spec page 14 routes these three to tabs, not dialogs -- they are
        // in IAMAP's "大型管理面板（12）" group. Opened per file (the flyout
        // exists precisely so the path is pre-filled), so each gets its own
        // tab keyed by subject.
        onFileHistory: () =>
            _openFilePanel(GbmPanelKind.fileHistory, entry.path),
        onBlame: () => _openFilePanel(GbmPanelKind.blame, entry.path),
        onLineHistory: () =>
            _openFilePanel(GbmPanelKind.lineHistory, entry.path),
      ),
    );
  }

  /// Opens one of the three per-file history panels as a tab about [path]
  /// (spec page 14 `IAMAP`), with the path pre-filled -- which is the whole
  /// point of putting them behind the file's own context menu.
  ///
  /// `context.go` rather than `push`: a panel sits beside History/Working
  /// Copy and replaces the shell's child instead of stacking over it.
  void _openFilePanel(GbmPanelKind kind, String path) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    assert(kind.isPerSubject, 'not a per-file history panel: $kind');
    final String tabId = ref
        .read(panelTabsProvider(widget.identity).notifier)
        .open(kind, subject: path);
    context.go(RoutePaths.panelFor(repoId, tabId));
  }

  /// Joins the repository's work dir with a repository-relative path from
  /// git. Kept deliberately dumb (no `package:path`, which this app does not
  /// depend on): git always reports `/`-separated relative paths, and
  /// [DesktopLauncher] normalizes separators for the Windows shell utilities
  /// that care.
  /// 05-F's launcher items, as a Log line (ruling R4).
  Future<void> _launch(AppAction<void> action) => ref
      .read(appActionRunnerProvider)
      .run(
        action,
        sink: ref
            .read(repoSessionProvider(widget.identity).notifier)
            .recordAppLog,
      );

  String _absolutePathOf(String repoRelativePath) {
    final String base = widget.identity.workDir;
    final String trimmed = base.endsWith('/') || base.endsWith(r'\')
        ? base.substring(0, base.length - 1)
        : base;
    return '$trimmed/$repoRelativePath';
  }

  /// Opens the discard confirmation for [paths].
  ///
  /// Previously called `restorePaths` directly, destroying uncommitted work
  /// with no confirmation at all -- spec page 06 requires a dialog that
  /// lists the files and states the change cannot be undone, so the
  /// destructive call now lives behind `DiscardChangesDialogContent`.
  void _discardFiles(List<String> paths) {
    if (paths.isEmpty) return;
    pushDialogRoute(
      context,
      RoutePaths.discardChangesDialogFor(
        Uri.encodeComponent(widget.identity.workDir),
        paths: paths,
      ),
    );
  }

  /// 05-G's "Discard N lines…" -- the same confirmation dialog as
  /// [_discardFiles], in its line mode.
  void _discardLines(int hunkIndex, List<int> lineIndices) {
    if (_selectedPath == null || lineIndices.isEmpty) return;
    pushDialogRoute(
      context,
      RoutePaths.discardLinesDialogFor(
        Uri.encodeComponent(widget.identity.workDir),
        path: _selectedPath!,
        hunkIndex: hunkIndex,
        lineIndices: lineIndices,
      ),
    );
  }
}

/// One row of the conflicted-files banner: the path, then the three
/// one-press resolutions.
///
/// **Stateful for its hover, and that is not a style choice.** This row was a
/// `Container` wrapping a bare `InkWell` whose only callback was
/// `onDoubleTap`, which put it in two of this repo's recorded traps at once:
///
/// - a hand-rolled `InkWell` inherits `ThemeData.hoverColor` (about four per
///   cent black/white), invisible on a real display --
///   [FLU-hand-rolled-inkwell-hover];
/// - that `onDoubleTap` is a `DoubleTapGestureRecognizer` on the **ancestor**
///   path of the row's own three buttons, and it holds the gesture arena open
///   until `kDoubleTapTimeout` (~300ms) --
///   [FLU-gesture-arena-taxes-double-tap]. Measured here rather than assumed:
///   with the old shape, tapping `Take Ours` and pumping a single frame
///   dispatched **nothing at all**.
///
/// `GbmRow` cannot answer both. It has no `onDoubleTap`, and an `InkWell`
/// with no callback is not `isWidgetEnabled`, so routing through it would not
/// hover either -- the row would need a single-click action it does not have,
/// and inventing one is a UX decision rather than a repair. So the hover is
/// an explicit [MouseRegion] painting the same `surfaceHover` token `GbmRow`
/// would, and the double tap moves down onto the path itself.
///
/// **The one behaviour that narrows**: a double click on the button strip no
/// longer opens the conflict window. `Expanded` gives the path everything up
/// to the first button, so the only region lost is the buttons themselves,
/// where a double click was ambiguous anyway.
class _ConflictedFileRow extends StatefulWidget {
  const _ConflictedFileRow({
    required this.entry,
    required this.onOpenConflicts,
    required this.notifier,
  });

  final WorkingCopyEntry entry;
  final VoidCallback onOpenConflicts;
  final RepoSessionController notifier;

  @override
  State<_ConflictedFileRow> createState() => _ConflictedFileRowState();
}

class _ConflictedFileRowState extends State<_ConflictedFileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final WorkingCopyEntry entry = widget.entry;
    final RepoSessionController notifier = widget.notifier;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: GbmSpacing.rowHeightCompact,
        decoration: BoxDecoration(
          color: _hovered ? colors.surfaceHover : null,
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
          child: Row(
            children: <Widget>[
              Expanded(
                // Opaque rather than the default `deferToChild`: the path is
                // one text run and the row is wider than it, so deferring
                // leaves the gap beside a short filename dead to the click.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: widget.onOpenConflicts,
                  child: Text(
                    entry.path,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              GbmButton(
                kind: GbmButtonKind.secondary,
                size: GbmButtonSize.sm,
                label: 'Take Ours',
                onPressed: () {
                  notifier.resolveConflict(
                    entry.path,
                    ConflictResolution.takeOurs,
                    oursBlobMissing: entry.oursBlob.isEmpty,
                  );
                },
              ),
              const SizedBox(width: GbmSpacing.space1),
              GbmButton(
                kind: GbmButtonKind.secondary,
                size: GbmButtonSize.sm,
                label: 'Take Theirs',
                onPressed: () {
                  notifier.resolveConflict(
                    entry.path,
                    ConflictResolution.takeTheirs,
                    theirsBlobMissing: entry.theirsBlob.isEmpty,
                  );
                },
              ),
              const SizedBox(width: GbmSpacing.space1),
              GbmButton(
                kind: GbmButtonKind.secondary,
                size: GbmButtonSize.sm,
                label: 'Mark Resolved',
                onPressed: () {
                  notifier.resolveConflict(
                    entry.path,
                    ConflictResolution.markResolved,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
