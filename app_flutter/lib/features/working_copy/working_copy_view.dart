import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_action_availability.dart';
import '../../actions/gbm_action_id.dart';
import '../../data/models/commit_meta.dart';
import '../../data/models/git_error.dart';
import '../../data/models/parsed_diff.dart';
import '../../data/models/working_copy_status.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../data/repositories/file_list_view_mode_repository.dart';
import '../../data/repositories/panel_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart'
    show
        ConflictResolution,
        RepoSessionController,
        RepoSessionState,
        WorkingCopyDiffReply,
        repoSessionProvider,
        workingCopyDiffKey;
import '../../data/repositories/working_copy_draft_repository.dart';
import '../../data/repositories/working_copy_repository.dart' as wc;
import '../../data/services/desktop_launcher.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_badge.dart' show GbmBadge, GbmBadgeKind;
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_menu.dart';
import '../../widgets/split_pane.dart';
import '../diff/temporary_scope_provider.dart';
import '../workspace/workspace_screen.dart' show repoIdForRoute;
import 'working_copy_file_identity.dart';
import 'widgets/commit_message_box.dart';
import 'widgets/working_copy_board.dart';
import 'widgets/working_copy_diff_pane.dart';
import 'widgets/working_copy_file_menu_items.dart';

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

  /// HEAD's oid at the moment a commit was submitted, or null when none is
  /// outstanding.
  ///
  /// The draft is cleared when HEAD moves off it, **not** when the button is
  /// pressed. Clearing on press is what the box used to do, and a commit
  /// that failed -- nothing staged, a rejecting hook, a bad identity -- took
  /// the message with it; now that the message is also on disk, that would
  /// have destroyed the saved copy too.
  String? _pendingCommitFrom;

  /// The oid whose message has already been pulled into the box for
  /// amending, so a rebuild does not overwrite the user's edits with HEAD's
  /// original text every time the cache is touched.
  String? _amendPrefilledFor;

  late TextEditingController _summaryController;
  late TextEditingController _descriptionController;
  late ScrollController _diffScrollController;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(workingCopyDraftProvider(widget.identity));
    _summaryController = TextEditingController(text: draft.summary)
      ..addListener(_onSummaryChanged);
    _descriptionController = TextEditingController(text: draft.description);
    _diffScrollController = ScrollController(
      initialScrollOffset: draft.diffScrollOffset,
    )..addListener(_onDiffScroll);
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

    _watchCommitOutcome();
    _watchAmendPrefill(session);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Conflicted section (only if there are conflicted files)
        if (status.conflicted.isNotEmpty)
          _buildConflictedSection(context, status: status, session: session),
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
              _buildDiffPane(context, status: status, diffs: diffs),
            ],
          ),
        ),
        // Commit message box (bottom)
        Container(
          height: 200,
          decoration: BoxDecoration(
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
  }) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionController notifier = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );

    return Container(
      height: GbmSpacing.rowHeightCompact,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: InkWell(
        onDoubleTap: () {
          context.go(RoutePaths.conflictsFor(repoId));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.path,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
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

    final ({String? unstaged, String? staged}) sides = _selectedSides(status);
    final WorkingCopyDiffReply? unstagedReply = sides.unstaged == null
        ? null
        : diffs[workingCopyDiffKey(sides.unstaged!, staged: false)];
    final WorkingCopyDiffReply? stagedReply = sides.staged == null
        ? null
        : diffs[workingCopyDiffKey(sides.staged!, staged: true)];

    return WorkingCopyDiffPane(
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
      // write from build().
      onTemporaryScopeChanged: (void Function()? submit) {
        ref.read(temporaryScopeSubmitProvider.notifier).state = submit;
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
  /// whole of it, and an empty `files` means git reported no change on that
  /// side rather than an error.
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
      unstaged: pathIn(<WorkingCopyEntry>[
        ...status.unstaged,
        ...status.untrackedFiles,
      ]),
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
  void _requestBothSides(WorkingCopyStatus status) {
    final ({String? unstaged, String? staged}) sides = _selectedSides(status);
    if (sides.unstaged case final String path) {
      wc.requestWorkingCopyDiff(ref, widget.identity, path, staged: false);
    }
    if (sides.staged case final String path) {
      wc.requestWorkingCopyDiff(ref, widget.identity, path, staged: true);
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
    final bool canCommit =
        status.staged.isNotEmpty &&
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
                  const SizedBox(height: GbmSpacing.space2),
                  // Enters the mode; it does not amend. The box has to show
                  // what is about to be rewritten before there is anything
                  // to press Amend on.
                  GbmButton(
                    label: 'Amend…',
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
            ),
          ),
        ],
      ),
    );
  }

  /// Clears the box once HEAD has actually moved off where it was when the
  /// commit was submitted.
  ///
  /// A commit -- amend included -- always produces a new oid, so HEAD moving
  /// is the success signal, and no capi addition is needed to get one.
  void _watchCommitOutcome() {
    ref.listen(
      repoSessionProvider(widget.identity).select((s) => s.refs.head.target),
      (String? previous, String next) {
        // No `next != _pendingCommitFrom` check: `select` only notifies when
        // the selected value actually changes, so arriving here already
        // means HEAD moved. Status refreshes republish the session
        // constantly during a commit and must not be mistaken for one.
        if (_pendingCommitFrom == null) return;
        _pendingCommitFrom = null;
        _summaryController.clear();
        _descriptionController.clear();
        ref.read(workingCopyDraftProvider(widget.identity).notifier).reset();
      },
    );
    // Any error cancels the wait. **Not attributed to the commit** -- a
    // fetch failing mid-commit cancels it too, and this repo's own rule is
    // that "the next event is mine" is never a safe attribution. The
    // reduction is deliberate and fail-safe in the direction that matters:
    // the cost of a false cancel is a message that outlives a commit that
    // did succeed, while the cost of not cancelling is clearing a message
    // the user wrote *after* a failure, when some later checkout moves HEAD.
    ref.listen<GitError?>(
      repoSessionProvider(widget.identity).select((s) => s.lastError),
      (GitError? previous, GitError? next) {
        if (next != null) _pendingCommitFrom = null;
      },
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
  void _onSubmit({required bool amend}) {
    final String from = ref
        .read(repoSessionProvider(widget.identity))
        .refs
        .head
        .target;
    if (!wc.submitCommit(ref, widget.identity, amend: amend)) return;
    _pendingCommitFrom = from;
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
        onOpenFile: () => launcher.openFile(absolutePath),
        onShowInFileManager: () => launcher.openInFileManager(absolutePath),
        onOpenTerminal: () => launcher.openTerminal(widget.identity.workDir),
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
    context.push(
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
    context.push(
      RoutePaths.discardLinesDialogFor(
        Uri.encodeComponent(widget.identity.workDir),
        path: _selectedPath!,
        hunkIndex: hunkIndex,
        lineIndices: lineIndices,
      ),
    );
  }
}
