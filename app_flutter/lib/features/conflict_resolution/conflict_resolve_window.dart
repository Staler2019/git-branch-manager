import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../widgets/split_pane.dart';
import 'conflict_line_order.dart';
import 'conflict_resolve_logic.dart';

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
  const ConflictResolveWindow({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ConflictResolveWindow> createState() =>
      _ConflictResolveWindowState();
}

class _ConflictResolveWindowState extends ConsumerState<ConflictResolveWindow> {
  final ConflictBatch _batch = ConflictBatch();
  String? _selectedPath;

  // Per-file editor state -- reset in _selectPath() whenever the selection
  // changes. _parsedForPath guards against applying a stale
  // lastWorkingTreeContent reply (e.g. one still in flight from the
  // previously selected file) to the newly selected one.
  String? _parsedForPath;
  ParsedConflictFile? _parsed;
  ConflictLineOrderState? _lineOrder;
  bool _showAncestor = false;
  TextEditingController? _resultController;
  bool _resultSeeded = false;

  @override
  void dispose() {
    _resultController?.dispose();
    super.dispose();
  }

  void _selectPath(String path) {
    setState(() {
      _selectedPath = path;
      _parsedForPath = null;
      _parsed = null;
      _lineOrder = null;
      _resultController?.dispose();
      _resultController = null;
      _resultSeeded = false;
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
        _parsedForPath == reply.path)
      return;
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
    });
  }

  void _resetRegion(int regionIndex) {
    if (_lineOrder == null) return;
    setState(() {
      _lineOrder = _lineOrder!.resetRegion(regionIndex);
      _resultController?.dispose();
      _resultController = null;
      _resultSeeded = false;
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

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final String repoId = Uri.encodeComponent(widget.identity.workDir);

    if (!session.isOpen) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(RoutePaths.repoList)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final List<WorkingCopyEntry> conflicted =
        session.workingCopyStatus.conflicted;
    _batch.merge(conflicted);
    _applyParsedContentIfNeeded(session);
    if (_allResolved) _ensureResultSeeded();

    return Scaffold(
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
              when state.isMerging ||
                  state.isCherryPicking ||
                  state.isReverting ||
                  state.isRebasing)
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
                                                wc?.theirsBlob.isEmpty ?? false,
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
        ],
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
          label: 'Ours',
          lines: segment.ours,
          background: null,
          onTake: () =>
              _appendLines(thisRegion, ConflictLineSource.ours, segment.ours),
          regionIndex: thisRegion,
          source: ConflictLineSource.ours,
          onApplyLines: _appendLines,
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
    final String label = state.isMerging
        ? 'Merge in progress'
        : state.isCherryPicking
        ? 'Cherry-pick in progress'
        : state.isRebasing
        ? state.rebaseTotal > 0
              ? 'Rebase in progress (${state.rebaseStep}/${state.rebaseTotal})'
              : 'Rebase in progress'
        : 'Revert in progress';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space2,
      ),
      color: colors.surfacePanelRaised,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (state.isMerging)
            GbmButton(
              label: 'Abort Merge',
              onPressed: () =>
                  ref.read(repoSessionProvider(identity).notifier).mergeAbort(),
            ),
        ],
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
  });

  final int position;
  final ConflictLineEntry entry;
  final VoidCallback onDelete;

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

    return Padding(
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

/// One `<<<<<<</=======/>>>>>>>` region: ancestor (optional)/ours/theirs
/// mini-panes with Take Ours/Take Theirs, plus a live result preview and a
/// one-click Reset once resolved -- see the class doc comment on
/// [ConflictResolveWindow] for what this deliberately does not replicate
/// from the Qt original (drag/click composition, keyboard shortcuts).
class _SidePane extends StatefulWidget {
  const _SidePane({
    required this.label,
    required this.lines,
    required this.background,
    required this.onTake,
    required this.regionIndex,
    required this.source,
    required this.onApplyLines,
  });

  final String label;
  final List<String> lines;
  final Color? background;
  final VoidCallback? onTake;
  final int regionIndex;
  final ConflictLineSource source;
  final Function(int regionIndex, ConflictLineSource source, List<String> lines)
  onApplyLines;

  @override
  State<_SidePane> createState() => _SidePaneState();
}

class _SidePaneState extends State<_SidePane> {
  bool _hovered = false;

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
                    InkWell(
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
                ],
              ),
          ],
        ),
      ),
    );
  }
}
