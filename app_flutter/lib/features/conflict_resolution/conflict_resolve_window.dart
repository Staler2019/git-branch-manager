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
/// the rich per-region editor (see [_RegionEditor]): ours/theirs/ancestor
/// panes per region, take-ours/take-theirs/reset, and a final editable
/// result once every region has a choice -- see gbm_parse_conflict_markers()
/// and gbm_request_working_tree_content() in gbm_capi.h. A path with no
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
  List<ConflictRegionChoice> _resolutions = <ConflictRegionChoice>[];
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
      _resolutions = <ConflictRegionChoice>[];
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
      _resolutions = List<ConflictRegionChoice>.filled(
        parsed.regionCount,
        ConflictRegionChoice.unresolved,
      );
    });
  }

  bool get _allResolved =>
      _resolutions.isNotEmpty &&
      _resolutions.every((r) => r != ConflictRegionChoice.unresolved);

  void _setRegionChoice(int regionIndex, ConflictRegionChoice choice) {
    setState(() {
      final List<ConflictRegionChoice> updated = List<ConflictRegionChoice>.of(
        _resolutions,
      );
      updated[regionIndex] = choice;
      _resolutions = updated;
      if (!_allResolved) {
        _resultController?.dispose();
        _resultController = null;
        _resultSeeded = false;
      }
    });
  }

  void _resetRegion(int regionIndex) =>
      _setRegionChoice(regionIndex, ConflictRegionChoice.unresolved);

  void _ensureResultSeeded() {
    if (_resultSeeded || _parsed == null) return;
    final String? assembled = assembleConflictResolution(
      _parsed!,
      _resolutions,
    );
    if (assembled == null) return;
    _resultController = TextEditingController(text: assembled);
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
                  state.isReverting)
            _SequencerBanner(identity: widget.identity, state: state),
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
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 280,
                        child: Column(
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
                      ),
                      VerticalDivider(width: 1, color: colors.borderSubtle),
                      Expanded(
                        child: _selectedPath == null
                            ? Center(
                                child: Text(
                                  'Select a file',
                                  style: TextStyle(color: colors.textTertiary),
                                ),
                              )
                            : _buildEditor(context),
                      ),
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
    if (parsed == null || parsed.regionCount == 0) {
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
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
            children: _buildSegmentBlocks(parsed),
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

  /// Walks `parsed.segments` once, pairing each region with its fixed index
  /// into `_resolutions` -- a plain imperative loop rather than a
  /// declarative `for` inside the widget list, so that index is captured
  /// once per region rather than mutated from inside a callback.
  List<Widget> _buildSegmentBlocks(ParsedConflictFile parsed) {
    final List<Widget> blocks = <Widget>[];
    int regionIndex = 0;
    for (final ConflictSegment segment in parsed.segments) {
      if (segment.kind == ConflictSegmentKind.text) {
        blocks.add(_ContextBlock(text: segment.lines.join()));
        continue;
      }
      final int thisRegion = regionIndex++;
      blocks.add(
        _RegionEditor(
          index: thisRegion,
          total: parsed.regionCount,
          segment: segment,
          choice: _resolutions[thisRegion],
          showAncestor: _showAncestor,
          onTakeOurs: () =>
              _setRegionChoice(thisRegion, ConflictRegionChoice.ours),
          onTakeTheirs: () =>
              _setRegionChoice(thisRegion, ConflictRegionChoice.theirs),
          onReset: () => _resetRegion(thisRegion),
        ),
      );
    }
    return blocks;
  }
}

class _SequencerBanner extends ConsumerWidget {
  const _SequencerBanner({required this.identity, required this.state});

  final RepoIdentity identity;
  final RepoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final String label = state.isMerging
        ? 'Merge in progress'
        : state.isCherryPicking
        ? 'Cherry-pick in progress'
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

/// One `<<<<<<</=======/>>>>>>>` region: ancestor (optional)/ours/theirs
/// mini-panes with Take Ours/Take Theirs, plus a live result preview and a
/// one-click Reset once resolved -- see the class doc comment on
/// [ConflictResolveWindow] for what this deliberately does not replicate
/// from the Qt original (drag/click composition, keyboard shortcuts).
class _RegionEditor extends StatelessWidget {
  const _RegionEditor({
    required this.index,
    required this.total,
    required this.segment,
    required this.choice,
    required this.showAncestor,
    required this.onTakeOurs,
    required this.onTakeTheirs,
    required this.onReset,
  });

  final int index;
  final int total;
  final ConflictSegment segment;
  final ConflictRegionChoice choice;
  final bool showAncestor;
  final VoidCallback onTakeOurs;
  final VoidCallback onTakeTheirs;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool resolved = choice != ConflictRegionChoice.unresolved;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
      decoration: BoxDecoration(
        border: Border.all(
          color: resolved
              ? colors.borderSubtle
              : colors.danger.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      ),
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
                  'Region ${index + 1} of $total',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    fontWeight: GbmTypography.weightSemibold,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                Text(
                  resolved
                      ? (choice == ConflictRegionChoice.ours
                            ? 'Using ours'
                            : 'Using theirs')
                      : 'Unresolved',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: resolved ? colors.diffAddText : colors.danger,
                  ),
                ),
                const Spacer(),
                if (resolved)
                  TextButton(
                    onPressed: onReset,
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
          if (showAncestor && segment.hasBase)
            _SidePane(
              label: 'Ancestor',
              lines: segment.base,
              background: colors.surfaceSunken,
              onTake: null,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _SidePane(
                  label: 'Ours',
                  lines: segment.ours,
                  background: choice == ConflictRegionChoice.ours
                      ? colors.diffAddBg
                      : null,
                  onTake: onTakeOurs,
                ),
              ),
              VerticalDivider(width: 1, color: colors.borderSubtle),
              Expanded(
                child: _SidePane(
                  label: 'Theirs',
                  lines: segment.theirs,
                  background: choice == ConflictRegionChoice.theirs
                      ? colors.diffAddBg
                      : null,
                  onTake: onTakeTheirs,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidePane extends StatelessWidget {
  const _SidePane({
    required this.label,
    required this.lines,
    required this.background,
    required this.onTake,
  });

  final String label;
  final List<String> lines;
  final Color? background;
  final VoidCallback? onTake;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      color: background,
      padding: const EdgeInsets.all(GbmSpacing.space1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  fontWeight: GbmTypography.weightMedium,
                  color: colors.textTertiary,
                ),
              ),
              if (onTake != null) ...<Widget>[
                const Spacer(),
                TextButton(
                  onPressed: onTake,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 20),
                    padding: EdgeInsets.zero,
                    foregroundColor: colors.accent,
                  ),
                  child: Text(
                    'Take $label',
                    style: const TextStyle(fontSize: GbmTypography.textXs),
                  ),
                ),
              ],
            ],
          ),
          Text(
            lines.isEmpty ? '(nothing)' : lines.join(),
            style: TextStyle(
              fontFamily: GbmTypography.fontMono,
              fontSize: GbmTypography.textSm,
              color: lines.isEmpty ? colors.textTertiary : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
