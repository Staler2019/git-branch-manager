import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_sequencer_operation.dart';
import '../../data/models/parsed_conflict_file.dart';
import '../../data/models/repo_state.dart';
import '../../data/models/working_copy_status.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/repositories/working_copy_repository.dart' as wc;
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_menu.dart';
import '../../widgets/split_pane.dart';
import 'conflict_hunk_menu_items.dart';
import 'conflict_line_order.dart';
import 'conflict_resolve_logic.dart';
import 'original_operation_message_dialog.dart';

/// The Dart analog of `ConflictResolveWindow` + `ConflictResolvePanel`
/// (src/app/views/ConflictResolveWindow.cpp, ConflictResolvePanel.cpp).
/// Routed as `/repo/:repoId/conflicts` -- a standalone top-level route (not
/// a dialog overlay), matching the Qt version's own restartable,
/// independent window: a conflict resolution can span an app restart, so it
/// needs to be reachable directly rather than living only as ephemeral
/// dialog state.
///
/// A conflicted path with parseable `<<<<<<</=======/>>>>>>>` regions gets
/// the three-column editor (LEFT [_SidePane] "ours", MIDDLE [_ResultPane],
/// RIGHT [_SidePane] "theirs", laid out with [GbmSplitPane]): per-region
/// take-ours/take-theirs appends each line into the region's
/// [ConflictLineOrderState] with a numbered badge marking application
/// order, per-line delete, reset, and a final editable result once every
/// region has at least one line -- see gbm_parse_conflict_markers() and
/// gbm_request_working_tree_content() in gbm_capi.h. A path with no
/// parseable regions (binary, or markers the parser gave up on) falls back
/// to the plain Take Ours/Take Theirs/Mark Resolved actions on the rail
/// row, same as before this editor existed.
///
/// Deliberately reduced from the Qt original: no drag-and-drop of a region
/// onto the result pane, no click-a-line/shift-click-a-range custom
/// composition, no per-side encoding/line-ending mismatch badges, and no
/// keyboard equivalents for take-ours/take-theirs/reset/navigate -- each of
/// those is a real, separate chunk of interaction design (Qt's own doc
/// comments call them out as distinct "Design A2/A3/A5" phases) on top of
/// the core capability (resolve each region by side, or hand-edit the
/// assembled result) that this port does implement in full. The batch/
/// checkmark tracking ([ConflictBatch], ported in conflict_resolve_logic.dart)
/// is also in-memory-only for this window's lifetime, not persisted to disk
/// across a full app restart the way Qt's `ConflictBatchStore` is.
class ConflictResolveWindow extends ConsumerStatefulWidget {
  const ConflictResolveWindow({
    super.key,
    required this.identity,
    this.isMacOS,
  });

  final RepoIdentity identity;
  final bool? isMacOS;

  @override
  ConsumerState<ConflictResolveWindow> createState() =>
      _ConflictResolveWindowState();
}

class _ConflictResolveWindowState extends ConsumerState<ConflictResolveWindow> {
  final ConflictBatch _batch = ConflictBatch();
  String? _selectedPath;

  // git's own record of *which* conflict this is: the ours/theirs/ancestor
  // blob oids of the selected path's WorkingCopyEntry, captured at
  // selection time. A conflict re-occurring on the same path (Abort, then
  // a new merge/rebase/cherry-pick) produces different blobs -- checked
  // fresh against the live entry on every session update in [build], not
  // by diffing successive workingCopyStatus snapshots. Unchanged blobs
  // mean the file is simply still mid-resolution and not yet saved, so
  // in-progress local edits are left alone.
  String? _selectedConflictSignature;

  // Per-file editor state -- reset in _selectPath() whenever the selection
  // changes. _parsedForPath guards against applying a stale
  // lastWorkingTreeContent reply (e.g. one still in flight from the
  // previously selected file) to the newly selected one.
  String? _parsedForPath;
  ParsedConflictFile? _parsed;
  // The lastWorkingTreeContent reply already in RepoSessionState at the
  // moment _selectPath() fired for the current selection -- e.g. from a
  // *previous* occurrence of this same path's conflict (Abort, then a new
  // merge re-conflicts it). Session state is long-lived and outlives any
  // one selection, so without this, _applyParsedContentIfNeeded's
  // path-match check alone would re-apply that leftover reply -- same
  // path, wrong (stale) content -- before the freshly requested one lands.
  WorkingTreeContentReply? _staleReplyAtSelection;
  ConflictLineOrderState? _lineOrder;
  bool _showAncestor = false;
  TextEditingController? _resultController;
  bool _resultSeeded = false;

  // Global undo history: track which region was modified on each removal.
  // Used by Ctrl/Cmd+Z to undo the most recent removal across all regions.
  // Each entry is a regionIndex; popping from the end gives us LIFO semantics.
  final List<int> _discardHistory = <int>[];

  // Region navigation: track the currently focused region for Previous/Next buttons
  int? _focusedRegionIndex;

  // GlobalKey stores for region navigation via Previous/Next buttons
  final Map<int, GlobalKey> _leftRegionKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _resultRegionKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _rightRegionKeys = <int, GlobalKey>{};

  @override
  void dispose() {
    _resultController?.dispose();
    super.dispose();
  }

  /// Signature of the given path's conflict per git's own record (the
  /// conflicted [WorkingCopyEntry]'s blob oids), or null if `path` isn't
  /// currently conflicted at all.
  String? _conflictSignatureFor(
    List<WorkingCopyEntry> conflicted,
    String path,
  ) {
    final WorkingCopyEntry? entry = conflicted
        .cast<WorkingCopyEntry?>()
        .firstWhere((e) => e?.path == path, orElse: () => null);
    if (entry == null) return null;
    return '${entry.ancestorBlob}|${entry.oursBlob}|${entry.theirsBlob}';
  }

  void _selectPath(String path) {
    final RepoSessionState currentSession = ref.read(
      repoSessionProvider(widget.identity),
    );
    final WorkingTreeContentReply? staleReply =
        currentSession.lastWorkingTreeContent;
    final String? signature = _conflictSignatureFor(
      currentSession.workingCopyStatus.conflicted,
      path,
    );
    setState(() {
      _selectedPath = path;
      _selectedConflictSignature = signature;
      _parsedForPath = null;
      _parsed = null;
      _lineOrder = null;
      _staleReplyAtSelection = staleReply;
      _resultController?.dispose();
      _resultController = null;
      _resultSeeded = false;
      _discardHistory.clear();
      _focusedRegionIndex = null;
      _leftRegionKeys.clear();
      _resultRegionKeys.clear();
      _rightRegionKeys.clear();
    });
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .requestWorkingTreeContent(path);
    wc.requestWorkingCopyDiff(ref, widget.identity, path);
  }

  void _applyParsedContentIfNeeded(RepoSessionState session) {
    final WorkingTreeContentReply? reply = session.lastWorkingTreeContent;
    if (reply == null ||
        reply.path != _selectedPath ||
        identical(reply, _staleReplyAtSelection) ||
        _parsedForPath == reply.path) {
      return;
    }
    if (!reply.editable) {
      setState(() => _parsedForPath = reply.path);
      return;
    }
    final ParsedConflictFile parsed = ref
        .read(repoSessionProvider(widget.identity).notifier)
        .parseConflictMarkers(reply.content);
    setState(() {
      _parsedForPath = reply.path;
      _parsed = parsed;
      _lineOrder = ConflictLineOrderState.initial(parsed.regionCount);
    });
  }

  bool get _allResolved {
    if (_lineOrder == null) return false;
    for (int i = 0; i < _lineOrder!.regionCount; i++) {
      final region = _lineOrder!.regions[i];
      if (region.orderedLines.isEmpty && !region.manuallyEdited) {
        return false;
      }
    }
    return true;
  }

  void _appendLines(
    int regionIndex,
    ConflictLineSource source,
    List<String> lines,
  ) {
    if (_lineOrder == null) return;
    setState(() {
      ConflictLineOrderState updated = _lineOrder!;
      for (final line in lines) {
        updated = updated.appendLine(regionIndex, source, line);
      }
      _lineOrder = updated;
      _resultController?.dispose();
      _resultController = null;
      _resultSeeded = false;
    });
  }

  void _removeLine(int regionIndex, int linePosition) {
    if (_lineOrder == null) return;
    setState(() {
      _lineOrder = _lineOrder!.removeAt(regionIndex, linePosition);
      _resultController?.dispose();
      _resultController = null;
      _resultSeeded = false;
      _discardHistory.add(regionIndex);
    });
  }

  void _resetRegion(int regionIndex) {
    if (_lineOrder == null) return;
    setState(() {
      _lineOrder = _lineOrder!.resetRegion(regionIndex);
      _resultController?.dispose();
      _resultController = null;
      _resultSeeded = false;
      _discardHistory.removeWhere((r) => r == regionIndex);
    });
  }

  void _ensureResultSeeded() {
    if (_resultSeeded || _parsed == null || _lineOrder == null) return;
    final StringBuffer buffer = StringBuffer();
    int regionIndex = 0;
    for (final segment in _parsed!.segments) {
      if (segment.kind == ConflictSegmentKind.text) {
        buffer.write(segment.lines.join());
      } else {
        buffer.write(_lineOrder!.assembledResult(regionIndex));
        regionIndex++;
      }
    }
    _resultController = TextEditingController(text: buffer.toString());
    _resultSeeded = true;
  }

  void _save() {
    final String? path = _selectedPath;
    final TextEditingController? controller = _resultController;
    if (path == null || controller == null) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .resolveConflict(
          path,
          ConflictResolution.writeResolved,
          resolvedContent: controller.text,
        );
  }

  void _undoLastDiscard() {
    if (_lineOrder == null || _discardHistory.isEmpty) return;
    final int regionIndex = _discardHistory.removeLast();
    setState(() {
      try {
        _lineOrder = _lineOrder!.undoLastRemoval(regionIndex);
        _resultController?.dispose();
        _resultController = null;
        _resultSeeded = false;
      } on StateError {
        // If the region's undo stack is empty (e.g., if it was reset after
        // the discard), ignore the error and just remove the history entry.
        // This should not happen in normal usage, but we guard defensively.
      }
    });
  }

  /// Applies the ours hunk of the currently-focused region (or the first
  /// unresolved if nothing focused yet).
  void _handleTakeOursHunk() {
    final int? target = _focusedRegionIndex ?? _nextRegionIndex(1);
    if (target == null) return;
    final ConflictSegment? segment = _regionSegmentAt(target);
    if (segment == null) return;
    _appendLines(target, ConflictLineSource.ours, segment.ours);
    setState(() => _focusedRegionIndex = target);
  }

  /// Applies the theirs hunk of the currently-focused region (or the first
  /// unresolved if nothing focused yet).
  void _handleTakeTheirsHunk() {
    final int? target = _focusedRegionIndex ?? _nextRegionIndex(1);
    if (target == null) return;
    final ConflictSegment? segment = _regionSegmentAt(target);
    if (segment == null) return;
    _appendLines(target, ConflictLineSource.theirs, segment.theirs);
    setState(() => _focusedRegionIndex = target);
  }

  /// Moves focus to the next conflict region.
  void _handleNextConflict() {
    final int? nextIndex = _nextRegionIndex(1);
    if (nextIndex != null) {
      setState(() => _focusedRegionIndex = nextIndex);
      _scrollToRegion(nextIndex);
    }
  }

  /// Returns a GlobalKey for a region, creating it if needed.
  GlobalKey _regionKey(Map<int, GlobalKey> store, int index) =>
      store.putIfAbsent(index, GlobalKey.new);

  /// Computes the next or previous region index to focus on.
  /// Prefers unresolved regions, wraps around, and cycles through all if all are resolved.
  int? _nextRegionIndex(int direction) {
    if (_lineOrder == null) return null;
    final int regionCount = _lineOrder!.regionCount;
    if (regionCount == 0) return null;

    bool isUnresolved(int i) {
      final region = _lineOrder!.regions[i];
      return region.orderedLines.isEmpty && !region.manuallyEdited;
    }

    final List<int> unresolvedIndices = <int>[
      for (int i = 0; i < regionCount; i++)
        if (isUnresolved(i)) i,
    ];

    final List<int> pool = unresolvedIndices.isNotEmpty
        ? unresolvedIndices
        : List<int>.generate(regionCount, (i) => i);

    final int? current = _focusedRegionIndex;
    if (current == null) return pool.first;

    if (direction > 0) {
      return pool.firstWhere((i) => i > current, orElse: () => pool.first);
    }

    final List<int> before = pool.where((i) => i < current).toList();
    return before.isNotEmpty ? before.last : pool.last;
  }

  /// Scrolls all three region columns to a given region index.
  void _scrollToRegion(int index) {
    for (final store in [
      _leftRegionKeys,
      _resultRegionKeys,
      _rightRegionKeys,
    ]) {
      final BuildContext? ctx = store[index]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          alignment: 0.1,
        );
      }
    }
  }

  /// Returns the ConflictSegment for a given region index.
  /// Returns null if _parsed is null or the region index is out of bounds.
  ConflictSegment? _regionSegmentAt(int regionIndex) {
    if (_parsed == null) return null;
    int regionIndexCounter = 0;
    for (final segment in _parsed!.segments) {
      if (segment.kind != ConflictSegmentKind.region) continue;
      if (regionIndexCounter == regionIndex) return segment;
      regionIndexCounter++;
    }
    return null;
  }

  /// Dispatches abort based on the operation type (merge/cherry-pick/rebase).
  void _handleAbort(RepoSessionState session) {
    final notifier = ref.read(repoSessionProvider(widget.identity).notifier);

    switch (activeSequencerOperation(session.repoState)) {
      case SequencerOperationKind.merge:
        notifier.mergeAbort();
      case SequencerOperationKind.cherryPick:
        notifier.cherryPickAbort();
      case SequencerOperationKind.rebase:
        // Covers both rebaseApply and rebaseMerge.
        notifier.abortRebase();
      case SequencerOperationKind.revert:
      case null:
        // Revert has no abort and null means nothing is in progress to
        // abort -- both unreachable through the UI (_ConflictActionBar
        // disables Abort for revert). Exhaustive switch over the implicit
        // "anything else -> abortRebase" this replaced.
        break;
    }
  }

  /// Continue no longer fires the sequencer step directly -- it first
  /// fetches git's own proposed commit message (MERGE_MSG/
  /// rebase-merge/message) so the MSGS-table step can pre-fill an editable
  /// dialog with it. The actual cherry-pick/rebase continue call happens in
  /// [_showOriginalOperationMessageDialog] once the user confirms (or is
  /// skipped entirely if they cancel).
  void _handleContinue() {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .requestOriginalOperationMessage();
  }

  /// Fired by the `originalOperationMessage` null -> non-null [ref.listen]
  /// transition in [build] -- same "not something the user chose to open"
  /// auto-dialog pattern as WorkspaceScreen's credentialPrompt/
  /// checkoutChoices listeners. Dispatches the edited message to
  /// cherry-pick or rebase continue based on which operation is active;
  /// cancelling the dialog leaves the sequencer untouched.
  void _showOriginalOperationMessageDialog(String initialMessage) {
    final notifier = ref.read(repoSessionProvider(widget.identity).notifier);
    final RepoSessionState session = ref.read(
      repoSessionProvider(widget.identity),
    );
    final SequencerOperationKind? kind = activeSequencerOperation(
      session.repoState,
    );
    final bool isCherryPick = kind == SequencerOperationKind.cherryPick;
    promptOriginalOperationMessage(
      context,
      title: isCherryPick ? 'Cherry-pick message' : 'Rebase message',
      initialMessage: initialMessage,
    ).then((message) {
      if (message == null) return;
      switch (kind) {
        case SequencerOperationKind.cherryPick:
          notifier.cherryPickContinueWithMessage(message);
        case SequencerOperationKind.rebase:
          notifier.continueRebaseWithMessage(message);
        case SequencerOperationKind.merge:
        case SequencerOperationKind.revert:
        case null:
          // Continue is only reachable for cherry-pick/rebase
          // (canContinue is false for merge/revert/no-op); unreachable
          // through the UI.
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final String repoId = Uri.encodeComponent(widget.identity.workDir);

    // Auto-shows the MSGS-table dialog once requestOriginalOperationMessage()'s
    // reply lands -- see _handleContinue()'s doc comment.
    ref.listen(
      repoSessionProvider(
        widget.identity,
      ).select((s) => s.originalOperationMessage),
      (previous, next) {
        if (next != null && previous == null) {
          _showOriginalOperationMessageDialog(next);
        }
      },
    );

    // Detects the *currently selected* file's conflict being a genuinely
    // new occurrence per git's own record -- e.g. Abort, then a new merge/
    // rebase/cherry-pick conflicts the same path again with different
    // content. Judged fresh against the live conflicted entry's blob oids
    // on every session update (not by diffing this snapshot against the
    // last one): if the oids no longer match what was loaded at selection
    // time, git considers this a different conflict than what's on screen,
    // so re-select to refetch/reparse. Unchanged oids mean the file is
    // simply still mid-resolution and not yet saved -- in-progress local
    // edits are left alone. Nothing else re-triggers _selectPath() while
    // the selection itself doesn't change.
    ref.listen(
      repoSessionProvider(
        widget.identity,
      ).select((s) => s.workingCopyStatus.conflicted),
      (_, next) {
        final String? path = _selectedPath;
        if (path == null) return;
        final String? signature = _conflictSignatureFor(next, path);
        if (signature != null && signature != _selectedConflictSignature) {
          _selectPath(path);
        }
      },
    );

    if (!session.isOpen) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(RoutePaths.welcome)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final List<WorkingCopyEntry> conflicted =
        session.workingCopyStatus.conflicted;
    _batch.merge(conflicted);
    _applyParsedContentIfNeeded(session);
    if (_allResolved) _ensureResultSeeded();

    return _ConflictResolveWindowShortcuts(
      isMacOS: widget.isMacOS ?? Platform.isMacOS,
      onUndoDiscard: _undoLastDiscard,
      onTakeOursHunk: _handleTakeOursHunk,
      onTakeTheirsHunk: _handleTakeTheirsHunk,
      onNextConflict: _handleNextConflict,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => context.go(RoutePaths.workingCopyFor(repoId)),
          ),
          title: const Text('Resolve Conflicts'),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (session.repoState case final state?
                when activeSequencerOperation(state) != null)
              SequencerBanner(identity: widget.identity, state: state),
            if (session.lastError case final error?)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(GbmSpacing.space2),
                color: colors.diffDelBg,
                child: Text(
                  error.message,
                  style: TextStyle(
                    color: colors.diffDelText,
                    fontSize: GbmTypography.textSm,
                  ),
                ),
              ),
            Expanded(
              child: _batch.entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'No conflicts remaining.',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                          const SizedBox(height: GbmSpacing.space3),
                          GbmButton(
                            label: 'Go to Working Copy',
                            kind: GbmButtonKind.primary,
                            onPressed: () =>
                                context.go(RoutePaths.workingCopyFor(repoId)),
                          ),
                        ],
                      ),
                    )
                  : GbmSplitPane(
                      axis: Axis.horizontal,
                      spec: GbmLayout.splitterCwFiles,
                      storageId: 'cw.files',
                      children: <Widget>[
                        // Left rail: file list
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: GbmSpacing.space3,
                                vertical: GbmSpacing.space1,
                              ),
                              child: Text(
                                '${_batch.resolvedCount} of ${_batch.entries.length} resolved',
                                style: TextStyle(
                                  fontSize: GbmTypography.textXs,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                children: <Widget>[
                                  for (final entry in _batch.entries)
                                    _ConflictRailRow(
                                      entry: entry,
                                      selected: entry.path == _selectedPath,
                                      onTap: () => _selectPath(entry.path),
                                      onTakeOurs: () {
                                        final WorkingCopyEntry? wc = conflicted
                                            .cast<WorkingCopyEntry?>()
                                            .firstWhere(
                                              (e) => e?.path == entry.path,
                                              orElse: () => null,
                                            );
                                        ref
                                            .read(
                                              repoSessionProvider(
                                                widget.identity,
                                              ).notifier,
                                            )
                                            .resolveConflict(
                                              entry.path,
                                              ConflictResolution.takeOurs,
                                              oursBlobMissing:
                                                  wc?.oursBlob.isEmpty ?? false,
                                            );
                                      },
                                      onTakeTheirs: () {
                                        final WorkingCopyEntry? wc = conflicted
                                            .cast<WorkingCopyEntry?>()
                                            .firstWhere(
                                              (e) => e?.path == entry.path,
                                              orElse: () => null,
                                            );
                                        ref
                                            .read(
                                              repoSessionProvider(
                                                widget.identity,
                                              ).notifier,
                                            )
                                            .resolveConflict(
                                              entry.path,
                                              ConflictResolution.takeTheirs,
                                              theirsBlobMissing:
                                                  wc?.theirsBlob.isEmpty ??
                                                  false,
                                            );
                                      },
                                      onMarkResolved: () => ref
                                          .read(
                                            repoSessionProvider(
                                              widget.identity,
                                            ).notifier,
                                          )
                                          .resolveConflict(
                                            entry.path,
                                            ConflictResolution.markResolved,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Right: editor with three-pane layout
                        _selectedPath == null
                            ? Center(
                                child: Text(
                                  'Select a file',
                                  style: TextStyle(color: colors.textTertiary),
                                ),
                              )
                            : _buildEditor(context),
                      ],
                    ),
            ),
            // Bottom action bar
            _ConflictActionBar(
              identity: widget.identity,
              selectedPath: _selectedPath,
              lineOrder: _lineOrder,
              focusedRegionIndex: _focusedRegionIndex,
              onMarkResolved: _selectedPath != null
                  ? () => ref
                        .read(repoSessionProvider(widget.identity).notifier)
                        .resolveConflict(
                          _selectedPath!,
                          ConflictResolution.markResolved,
                        )
                  : null,
              onPrevious: () {
                final nextIndex = _nextRegionIndex(-1);
                if (nextIndex != null) {
                  setState(() => _focusedRegionIndex = nextIndex);
                  _scrollToRegion(nextIndex);
                }
              },
              onNext: _handleNextConflict,
              hasSequencerOperation:
                  activeSequencerOperation(session.repoState) != null,
              isRevert:
                  activeSequencerOperation(session.repoState) ==
                  SequencerOperationKind.revert,
              canContinue:
                  activeSequencerOperation(session.repoState)?.canContinue ??
                  false,
              onAbort: () => _handleAbort(session),
              onContinue: _handleContinue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final ParsedConflictFile? parsed = _parsed;

    if (_parsedForPath != _selectedPath) {
      return const Center(child: CircularProgressIndicator());
    }
    if (parsed == null || parsed.regionCount == 0 || _lineOrder == null) {
      // Not editable (binary/non-UTF8), or no parseable regions -- fall
      // back to the rail row's whole-file Take Ours/Take Theirs/Mark
      // Resolved actions; nothing more to show here.
      return Center(
        child: Text(
          'This file has no per-region conflict markers to resolve here.\nUse Take Ours / Take Theirs / Mark Resolved on the left.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textTertiary),
        ),
      );
    }

    final bool anyHasBase = parsed.regions.any((r) => r.hasBase);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(GbmSpacing.space2),
          child: Row(
            children: <Widget>[
              Text(
                '${parsed.regionCount} region${parsed.regionCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              if (anyHasBase)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Checkbox(
                      value: _showAncestor,
                      onChanged: (value) =>
                          setState(() => _showAncestor = value ?? false),
                      visualDensity: VisualDensity.compact,
                    ),
                    Text(
                      'Show ancestor',
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: GbmSplitPane(
            axis: Axis.horizontal,
            spec: GbmLayout.splitterCwPanes,
            storageId: 'cw.panes',
            children: <Widget>[
              // LEFT: Ours column
              ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: GbmSpacing.space2,
                ),
                children: _buildOursSideBlocks(parsed),
              ),
              // MIDDLE: Result column with badges
              ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: GbmSpacing.space2,
                ),
                children: _buildResultBlocks(parsed),
              ),
              // RIGHT: Theirs column
              ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: GbmSpacing.space2,
                ),
                children: _buildTheirsSideBlocks(parsed),
              ),
            ],
          ),
        ),
        if (_allResolved && _resultController != null)
          Container(
            padding: const EdgeInsets.all(GbmSpacing.space2),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Result (editable)',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: GbmSpacing.space1),
                TextField(
                  controller: _resultController,
                  maxLines: 8,
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textSm,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: GbmSpacing.space2),
                Align(
                  alignment: Alignment.centerRight,
                  child: GbmButton(
                    label: 'Save',
                    kind: GbmButtonKind.primary,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Builds the LEFT column showing ours side with Take Ours buttons per region
  List<Widget> _buildOursSideBlocks(ParsedConflictFile parsed) {
    final List<Widget> blocks = <Widget>[];
    int regionIndex = 0;
    for (final ConflictSegment segment in parsed.segments) {
      if (segment.kind == ConflictSegmentKind.text) {
        blocks.add(_ContextBlock(text: segment.lines.join()));
        continue;
      }
      final int thisRegion = regionIndex++;
      blocks.add(
        _SidePane(
          key: _regionKey(_leftRegionKeys, thisRegion),
          label: 'Ours',
          lines: segment.ours,
          background: null,
          onTake: () =>
              _appendLines(thisRegion, ConflictLineSource.ours, segment.ours),
          regionIndex: thisRegion,
          source: ConflictLineSource.ours,
          onApplyLines: _appendLines,
          otherSource: ConflictLineSource.theirs,
          otherSideLines: segment.theirs,
          onReset: () => _resetRegion(thisRegion),
          hasResult:
              _lineOrder?.getOrderedLines(thisRegion).isNotEmpty ?? false,
        ),
      );
    }
    return blocks;
  }

  /// Builds the MIDDLE column showing assembled result with numbered badges and delete buttons
  List<Widget> _buildResultBlocks(ParsedConflictFile parsed) {
    if (_lineOrder == null) return [];
    final List<Widget> blocks = <Widget>[];
    int regionIndex = 0;
    for (final ConflictSegment segment in parsed.segments) {
      if (segment.kind == ConflictSegmentKind.text) {
        blocks.add(_ContextBlock(text: segment.lines.join()));
        continue;
      }
      final int thisRegion = regionIndex++;
      final List<ConflictLineEntry> orderedLines = _lineOrder!.getOrderedLines(
        thisRegion,
      );

      blocks.add(
        _ResultPane(
          key: _regionKey(_resultRegionKeys, thisRegion),
          index: thisRegion,
          total: parsed.regionCount,
          orderedLines: orderedLines,
          onDelete: (position) => _removeLine(thisRegion, position),
          onReset: () => _resetRegion(thisRegion),
          onAcceptDrop: _appendLines,
        ),
      );
    }
    return blocks;
  }

  /// Builds the RIGHT column showing theirs side with Take Theirs buttons per region
  List<Widget> _buildTheirsSideBlocks(ParsedConflictFile parsed) {
    final List<Widget> blocks = <Widget>[];
    int regionIndex = 0;
    for (final ConflictSegment segment in parsed.segments) {
      if (segment.kind == ConflictSegmentKind.text) {
        blocks.add(_ContextBlock(text: segment.lines.join()));
        continue;
      }
      final int thisRegion = regionIndex++;
      blocks.add(
        _SidePane(
          key: _regionKey(_rightRegionKeys, thisRegion),
          label: 'Theirs',
          lines: segment.theirs,
          background: null,
          onTake: () => _appendLines(
            thisRegion,
            ConflictLineSource.theirs,
            segment.theirs,
          ),
          regionIndex: thisRegion,
          source: ConflictLineSource.theirs,
          onApplyLines: _appendLines,
          otherSource: ConflictLineSource.ours,
          otherSideLines: segment.ours,
          onReset: () => _resetRegion(thisRegion),
          hasResult:
              _lineOrder?.getOrderedLines(thisRegion).isNotEmpty ?? false,
        ),
      );
    }
    return blocks;
  }
}

/// Presentational -- no Riverpod dependency beyond `ref.read` inside the
/// Abort callback, so it can be widget-tested directly (see
/// sequencer_banner_test.dart), matching [ConflictBanner]'s split.
class SequencerBanner extends ConsumerWidget {
  const SequencerBanner({
    super.key,
    required this.identity,
    required this.state,
  });

  final RepoIdentity identity;
  final RepoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    // The null case (activeSequencerOperation returns null) is unreachable:
    // this widget is only built when the build() call site's `when
    // activeSequencerOperation(state) != null` guard already passed. Falls
    // back to the revert wording anyway, matching this ladder's own
    // previous unconditional-else behavior.
    final String label = switch (activeSequencerOperation(state)) {
      SequencerOperationKind.merge => 'Merge in progress',
      SequencerOperationKind.cherryPick => 'Cherry-pick in progress',
      SequencerOperationKind.rebase =>
        state.rebaseTotal > 0
            ? 'Rebase in progress (${state.rebaseStep}/${state.rebaseTotal})'
            : 'Rebase in progress',
      SequencerOperationKind.revert || null => 'Revert in progress',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space2,
      ),
      color: colors.surfacePanelRaised,
      child: Text(
        label,
        style: TextStyle(
          fontSize: GbmTypography.textSm,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

/// Presentational action bar with Previous, Next, Mark Resolved, Abort, Continue buttons.
/// Takes all state and callbacks as plain parameters so it can be tested directly.
class _ConflictActionBar extends StatelessWidget {
  const _ConflictActionBar({
    required this.identity,
    required this.selectedPath,
    required this.lineOrder,
    required this.focusedRegionIndex,
    required this.onMarkResolved,
    required this.onPrevious,
    required this.onNext,
    required this.hasSequencerOperation,
    required this.isRevert,
    required this.canContinue,
    required this.onAbort,
    required this.onContinue,
  });

  final RepoIdentity identity;
  final String? selectedPath;
  final ConflictLineOrderState? lineOrder;
  final int? focusedRegionIndex;
  final VoidCallback? onMarkResolved;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool hasSequencerOperation;
  final bool isRevert;
  final bool canContinue;
  final VoidCallback onAbort;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool hasMultipleRegions =
        lineOrder != null && lineOrder!.regionCount > 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space2,
      ),
      color: colors.surfacePanelRaised,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Previous button
            GbmButton(
              label: 'Previous',
              onPressed: hasMultipleRegions ? onPrevious : null,
            ),
            const SizedBox(width: GbmSpacing.space1),
            // Next button
            GbmButton(
              label: 'Next',
              onPressed: hasMultipleRegions ? onNext : null,
            ),
            const SizedBox(width: GbmSpacing.space2),
            // Mark Resolved button
            GbmButton(label: 'Mark Resolved', onPressed: onMarkResolved),
            const SizedBox(width: GbmSpacing.space4),
            // Abort button
            if (hasSequencerOperation) ...<Widget>[
              Tooltip(
                message: isRevert
                    ? 'Revert has no abort (use Resolve manual actions)'
                    : '',
                child: GbmButton(
                  label: 'Abort',
                  onPressed: isRevert ? null : onAbort,
                ),
              ),
              const SizedBox(width: GbmSpacing.space1),
              // Continue button
              Tooltip(
                message: canContinue
                    ? ''
                    : 'Continue not available for merge/revert yet -- use Mark Resolved on each file instead',
                child: GbmButton(
                  label: 'Continue',
                  onPressed: canContinue ? onContinue : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConflictRailRow extends StatelessWidget {
  const _ConflictRailRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onTakeOurs,
    required this.onTakeTheirs,
    required this.onMarkResolved,
  });

  final ConflictBatchEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTakeOurs;
  final VoidCallback onTakeTheirs;
  final VoidCallback onMarkResolved;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool resolved = entry.state == ConflictFileState.resolved;
    return Material(
      color: selected ? colors.surfaceSelected : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space3,
            vertical: GbmSpacing.space2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    resolved ? Icons.check_circle : Icons.error_outline,
                    size: 14,
                    color: resolved ? colors.diffAddText : colors.danger,
                  ),
                  const SizedBox(width: GbmSpacing.space1),
                  Expanded(
                    child: Text(
                      entry.path,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textPrimary,
                        fontWeight: GbmTypography.weightMedium,
                        decoration: resolved
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (!resolved) ...<Widget>[
                const SizedBox(height: GbmSpacing.space1),
                Wrap(
                  spacing: GbmSpacing.space1,
                  children: <Widget>[
                    _MiniButton(label: 'Take Ours', onPressed: onTakeOurs),
                    _MiniButton(label: 'Take Theirs', onPressed: onTakeTheirs),
                    _MiniButton(
                      label: 'Mark Resolved',
                      onPressed: onMarkResolved,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        minimumSize: const Size(0, 24),
        foregroundColor: colors.textSecondary,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: GbmTypography.textXs),
      ),
    );
  }
}

class _ResultPane extends StatefulWidget {
  const _ResultPane({
    super.key,
    required this.index,
    required this.total,
    required this.orderedLines,
    required this.onDelete,
    required this.onReset,
    required this.onAcceptDrop,
  });

  final int index;
  final int total;
  final List<ConflictLineEntry> orderedLines;
  final Function(int) onDelete;
  final VoidCallback onReset;
  final Function(int regionIndex, ConflictLineSource source, List<String> lines)
  onAcceptDrop;

  @override
  State<_ResultPane> createState() => _ResultPaneState();
}

class _ResultPaneState extends State<_ResultPane> {
  bool _dragOver = false;
  late final GlobalKey _paneKey;

  @override
  void initState() {
    super.initState();
    _paneKey = GlobalKey();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool resolved = widget.orderedLines.isNotEmpty;

    return DragTarget<_ConflictHunkDragData>(
      onWillAcceptWithDetails: (details) {
        // Only accept drops for this region
        return details.data.regionIndex == widget.index;
      },
      onLeave: (_) {
        setState(() => _dragOver = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _dragOver = false);
        widget.onAcceptDrop(
          details.data.regionIndex,
          details.data.source,
          details.data.lines,
        );
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          key: _paneKey,
          margin: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
          decoration: BoxDecoration(
            border: Border.all(
              color: _dragOver
                  ? colors.accent
                  : (resolved
                        ? colors.borderSubtle
                        : colors.danger.withValues(alpha: 0.5)),
            ),
            borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          ),
          child: MouseRegion(
            onEnter: (_) {
              if (candidateData.isNotEmpty) {
                setState(() => _dragOver = true);
              }
            },
            onExit: (_) {
              setState(() => _dragOver = false);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  color: colors.surfaceSunken,
                  padding: const EdgeInsets.symmetric(
                    horizontal: GbmSpacing.space2,
                    vertical: 2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        'Region ${widget.index + 1} of ${widget.total}',
                        style: TextStyle(
                          fontSize: GbmTypography.textXs,
                          fontWeight: GbmTypography.weightSemibold,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: GbmSpacing.space2),
                      Text(
                        resolved ? 'Resolved' : 'Unresolved',
                        style: TextStyle(
                          fontSize: GbmTypography.textXs,
                          color: resolved ? colors.diffAddText : colors.danger,
                        ),
                      ),
                      const Spacer(),
                      if (resolved)
                        TextButton(
                          onPressed: widget.onReset,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 24),
                            foregroundColor: colors.textSecondary,
                          ),
                          child: const Text(
                            'Reset',
                            style: TextStyle(fontSize: GbmTypography.textXs),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(GbmSpacing.space1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Result',
                        style: TextStyle(
                          fontSize: GbmTypography.textXs,
                          fontWeight: GbmTypography.weightMedium,
                          color: colors.textTertiary,
                        ),
                      ),
                      if (widget.orderedLines.isEmpty)
                        Text(
                          '(nothing)',
                          style: TextStyle(
                            fontFamily: GbmTypography.fontMono,
                            fontSize: GbmTypography.textSm,
                            color: colors.textTertiary,
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            for (int i = 0; i < widget.orderedLines.length; i++)
                              _ResultLine(
                                position: i,
                                entry: widget.orderedLines[i],
                                onDelete: () => widget.onDelete(i),
                                onOutOfBoundsDrag: () => widget.onDelete(i),
                                regionIndex: widget.index,
                                paneKey: _paneKey,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    required this.position,
    required this.entry,
    required this.onDelete,
    required this.onOutOfBoundsDrag,
    required this.regionIndex,
    required this.paneKey,
  });

  final int position;
  final ConflictLineEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onOutOfBoundsDrag;
  final int regionIndex;
  final GlobalKey paneKey;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    // Use circled digit Unicode characters for badges
    final List<String> circledDigits = [
      '①',
      '②',
      '③',
      '④',
      '⑤',
      '⑥',
      '⑦',
      '⑧',
      '⑨',
      '⑩',
      '⑪',
      '⑫',
      '⑬',
      '⑭',
      '⑮',
      '⑯',
      '⑰',
      '⑱',
      '⑲',
      '⑳',
    ];
    final String badgeText = position < circledDigits.length
        ? circledDigits[position]
        : '${position + 1}';

    return Draggable<_ResultLineDragData>(
      data: _ResultLineDragData(
        regionIndex: regionIndex,
        linePosition: position,
      ),
      affinity: Axis.horizontal,
      onDragEnd: (details) {
        // Check if the drag endpoint is outside the pane bounds.
        // If so, trigger deletion. Otherwise, it's a no-op.
        final RenderBox? paneBox =
            paneKey.currentContext?.findRenderObject() as RenderBox?;
        if (paneBox != null) {
          final Offset globalPos = details.offset;
          final Offset localPos = paneBox.globalToLocal(globalPos);
          final Size paneSize = paneBox.size;
          final bool isOutOfBounds =
              localPos.dx < 0 ||
              localPos.dx > paneSize.width ||
              localPos.dy < 0 ||
              localPos.dy > paneSize.height;
          if (isOutOfBounds) {
            onOutOfBoundsDrag();
          }
        }
      },
      feedback: Material(
        color: Colors.transparent,
        child: Text(
          badgeText,
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            color: colors.accent,
            fontWeight: GbmTypography.weightMedium,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 20,
              child: Center(
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.accent,
                    fontWeight: GbmTypography.weightMedium,
                  ),
                ),
              ),
            ),
            const SizedBox(width: GbmSpacing.space1),
            Expanded(
              child: Text(
                entry.lineContent,
                style: TextStyle(
                  fontFamily: GbmTypography.fontMono,
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: colors.textSecondary),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Delete line',
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextBlock extends StatelessWidget {
  const _ContextBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    if (text.trim().isEmpty) return const SizedBox(height: GbmSpacing.space1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: GbmTypography.fontMono,
          fontSize: GbmTypography.textSm,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}

/// Intent for undoing the last discard in the conflict resolve window.
/// This is local to the window and not tied to app-wide undo.
class _UndoDiscardIntent extends Intent {
  const _UndoDiscardIntent();
}

/// Intent for applying the ours hunk to the focused conflict region.
class _TakeOursHunkIntent extends Intent {
  const _TakeOursHunkIntent();
}

/// Intent for applying the theirs hunk to the focused conflict region.
class _TakeTheirsHunkIntent extends Intent {
  const _TakeTheirsHunkIntent();
}

/// Intent for moving focus to the next conflict region.
class _NextConflictIntent extends Intent {
  const _NextConflictIntent();
}

/// Keyboard shortcuts + actions wrapper for the conflict resolve window.
/// Handles Ctrl/Cmd+Z to undo the last discard, and Alt+Left/Right/Down for
/// taking hunks and navigating regions. This is window-local and not tied
/// to the app-wide edit undo or menu action systems.
class _ConflictResolveWindowShortcuts extends StatelessWidget {
  const _ConflictResolveWindowShortcuts({
    required this.child,
    required this.isMacOS,
    required this.onUndoDiscard,
    required this.onTakeOursHunk,
    required this.onTakeTheirsHunk,
    required this.onNextConflict,
  });

  final Widget child;
  final bool isMacOS;
  final VoidCallback onUndoDiscard;
  final VoidCallback onTakeOursHunk;
  final VoidCallback onTakeTheirsHunk;
  final VoidCallback onNextConflict;

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: !isMacOS,
        meta: isMacOS,
      ): const _UndoDiscardIntent(),
      SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
          const _TakeOursHunkIntent(),
      SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
          const _TakeTheirsHunkIntent(),
      SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
          const _NextConflictIntent(),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoDiscardIntent: CallbackAction<_UndoDiscardIntent>(
            onInvoke: (_) => onUndoDiscard(),
          ),
          _TakeOursHunkIntent: CallbackAction<_TakeOursHunkIntent>(
            onInvoke: (_) => onTakeOursHunk(),
          ),
          _TakeTheirsHunkIntent: CallbackAction<_TakeTheirsHunkIntent>(
            onInvoke: (_) => onTakeTheirsHunk(),
          ),
          _NextConflictIntent: CallbackAction<_NextConflictIntent>(
            onInvoke: (_) => onNextConflict(),
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

/// Drag data for a whole-hunk drag-and-drop operation.
class _ConflictHunkDragData {
  _ConflictHunkDragData({
    required this.regionIndex,
    required this.source,
    required this.lines,
  });

  final int regionIndex;
  final ConflictLineSource source;
  final List<String> lines;
}

/// Drag data for a result line drag-and-drop operation.
class _ResultLineDragData {
  _ResultLineDragData({required this.regionIndex, required this.linePosition});

  final int regionIndex;
  final int linePosition;
}

/// One `<<<<<<</=======/>>>>>>>` region: ancestor (optional)/ours/theirs
/// mini-panes with Take Ours/Take Theirs, plus a live result preview and a
/// one-click Reset once resolved -- see the class doc comment on
/// [ConflictResolveWindow] for what this deliberately does not replicate
/// from the Qt original (drag/click composition, keyboard shortcuts).
class _SidePane extends StatefulWidget {
  const _SidePane({
    super.key,
    required this.label,
    required this.lines,
    required this.background,
    required this.onTake,
    required this.regionIndex,
    required this.source,
    required this.onApplyLines,
    required this.otherSource,
    required this.otherSideLines,
    required this.onReset,
    required this.hasResult,
  });

  final String label;
  final List<String> lines;
  final Color? background;
  final VoidCallback? onTake;
  final int regionIndex;
  final ConflictLineSource source;
  final Function(int regionIndex, ConflictLineSource source, List<String> lines)
  onApplyLines;

  /// 05-I "Take both — this side first" needs the other side's lines to
  /// append after this side's own -- this pane otherwise only knows about
  /// [lines], its own side.
  final ConflictLineSource otherSource;
  final List<String> otherSideLines;

  /// 05-I "Discard from result" -- the same whole-region reset
  /// `_ResultPane`'s own "Reset" button calls, exposed here too so a
  /// right-click on either side pane can reach it without navigating to
  /// the result pane first.
  final VoidCallback onReset;

  /// Gates "Discard from result": true once this region has at least one
  /// line in its result, mirroring `_ResultPane`'s own `if (resolved)`
  /// guard on rendering its Reset button at all.
  final bool hasResult;

  @override
  State<_SidePane> createState() => _SidePaneState();
}

class _SidePaneState extends State<_SidePane> {
  bool _hovered = false;

  void _openHunkContextMenu(TapDownDetails details, String line) {
    showGbmContextMenu(
      context,
      details.globalPosition,
      conflictHunkMenuItems(
        onTakeThisSide: () => widget.onApplyLines(
          widget.regionIndex,
          widget.source,
          widget.lines,
        ),
        onTakeThisLineOnly: () => widget.onApplyLines(
          widget.regionIndex,
          widget.source,
          <String>[line],
        ),
        onTakeBoth: () {
          widget.onApplyLines(widget.regionIndex, widget.source, widget.lines);
          widget.onApplyLines(
            widget.regionIndex,
            widget.otherSource,
            widget.otherSideLines,
          );
        },
        onDiscardFromResult: widget.hasResult ? widget.onReset : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool isOurs = widget.label == 'Ours';
    final arrowIcon = isOurs ? Icons.arrow_forward : Icons.arrow_back;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        color: widget.background,
        padding: const EdgeInsets.all(GbmSpacing.space1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    fontWeight: GbmTypography.weightMedium,
                    color: colors.textTertiary,
                  ),
                ),
                if (widget.onTake != null) ...<Widget>[
                  const Spacer(),
                  Draggable<_ConflictHunkDragData>(
                    data: _ConflictHunkDragData(
                      regionIndex: widget.regionIndex,
                      source: widget.source,
                      lines: widget.lines,
                    ),
                    affinity: Axis.horizontal,
                    feedback: Material(
                      color: Colors.transparent,
                      child: Text(
                        'Take ${widget.lines.length} ${widget.lines.length == 1 ? 'line' : 'lines'}',
                        style: TextStyle(
                          fontSize: GbmTypography.textXs,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: TextButton.icon(
                        onPressed: widget.onTake,
                        icon: Icon(arrowIcon, size: 16),
                        label: Text(
                          'Take ${widget.label}',
                          style: const TextStyle(
                            fontSize: GbmTypography.textXs,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 20),
                          padding: EdgeInsets.zero,
                          foregroundColor: colors.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (widget.lines.isEmpty)
              Text(
                '(nothing)',
                style: TextStyle(
                  fontFamily: GbmTypography.fontMono,
                  fontSize: GbmTypography.textSm,
                  color: colors.textTertiary,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final line in widget.lines)
                    GestureDetector(
                      onSecondaryTapDown: (TapDownDetails details) =>
                          _openHunkContextMenu(details, line),
                      child: InkWell(
                        onTap: () => widget.onApplyLines(
                          widget.regionIndex,
                          widget.source,
                          [line],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: GbmSpacing.space1,
                          ),
                          child: Text(
                            line,
                            style: TextStyle(
                              fontFamily: GbmTypography.fontMono,
                              fontSize: GbmTypography.textSm,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
