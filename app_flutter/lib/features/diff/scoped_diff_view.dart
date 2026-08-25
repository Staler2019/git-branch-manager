import 'package:flutter/material.dart';

import '../../data/models/parsed_diff.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_badge.dart';
import '../../widgets/gbm_button.dart';
import 'diff_scopes.dart';
import 'selection_touch.dart';
import 'widgets/diff_line.dart';

/// One side of the Working Copy diff, drawn as spec P03's 變體 B: every run
/// of changes is a card with its own Stage/Unstage button at the end of its
/// header, and the code between the cards is dimmed context.
///
/// **The button is always there, never revealed by a selection.** The old
/// per-line checkboxes meant partial staging cost a check per line and the
/// button only existed once at least one box was ticked; the card's own
/// button acts on exactly the lines the card already draws, so the commonest
/// partial stage is one press with nothing to aim at first.
///
/// **An ordinary text selection is a one-shot scope.** Drag across some
/// lines and a temporary card appears in front of the first card the drag
/// touched, acting on exactly the changed lines under the selection; the
/// cards it supersedes keep their buttons visible but struck through and
/// inert, so what the press *would* have done stays readable. One press,
/// then it is spent (spec P03's `SCOPES`).
///
/// This widget does not scroll. Both callers put it inside their own scroll
/// view -- `2 file` mode needs two independent ones and `unified` needs one
/// shared one, and a widget that scrolled itself could not be stacked.
class ScopedDiffView extends StatefulWidget {
  const ScopedDiffView({
    super.key,
    required this.title,
    required this.file,
    required this.staged,
    required this.onStageScope,
    this.onDiscardScope,
    this.emptyLabel = 'No changes',
    this.loading = false,
    this.onTemporaryScopeChanged,
  });

  /// Column heading -- `Unstaged` or `Staged`.
  final String title;

  /// The file's diff, or null when this side has nothing for the selected
  /// file (a brand-new file has no staged side; a fully-staged one has no
  /// unstaged side).
  ///
  /// A working-copy diff describes exactly one path, because the request
  /// that produced it named one path, so a single [DiffFile] rather than a
  /// [ParsedDiff] is the honest shape: hunk indices are only meaningful
  /// relative to a known file, and `gbm_stage_lines` takes a path plus a
  /// hunk index.
  final DiffFile? file;

  final bool staged;

  /// Called with the hunk index and the lines that actually move -- never
  /// the unchanged lines the gap rule swallowed into the card.
  ///
  /// A temporary scope spanning two hunks calls this **twice**, once per
  /// hunk in file order: `gbm_stage_lines` takes one hunk index, so the
  /// split has to happen here rather than be discovered by git.
  final void Function(int hunkIndex, List<int> changedLineIndices) onStageScope;

  /// 05-G's discard. Null on the staged side and in any read-only use:
  /// discarding rewrites the work tree.
  final void Function(int hunkIndex, List<int> changedLineIndices)?
  onDiscardScope;

  final String emptyLabel;

  /// A diff request for this side is in flight. The column head still
  /// renders, so switching files does not make the heading flicker away and
  /// back; only the body below it becomes the spinner.
  final bool loading;

  /// Reports how to submit the current one-shot scope, or null when there
  /// is none, so `repositoryStageSelectedLines` can act on the same block
  /// the temporary card's button does.
  ///
  /// Always called from a post-frame callback: the caller writes it into a
  /// provider, and writing a provider from `build()` is a debug-only assert
  /// that release strips (see CLAUDE.md's Riverpod traps).
  final void Function(void Function()? submit)? onTemporaryScopeChanged;

  @override
  State<ScopedDiffView> createState() => _ScopedDiffViewState();
}

class _ScopedDiffViewState extends State<ScopedDiffView> {
  final GlobalKey<SelectionAreaState> _selectionAreaKey =
      GlobalKey<SelectionAreaState>();
  late final SelectionTouchTracker _tracker;

  @override
  void initState() {
    super.initState();
    _tracker = SelectionTouchTracker()..addListener(_onTouchChanged);
  }

  @override
  void didUpdateWidget(ScopedDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new diff renumbers every line, and the tracker's keys are positions
    // -- so a selection carried across the reload would point at whatever
    // now sits at those indices. This is the plan's
    // 「staging 狀態改變（diff 重新載入）就清空」 clause: staging is what
    // produces the new diff.
    if (!identical(oldWidget.file, widget.file)) {
      _dropSelection(alsoClearHighlight: false);
    }
  }

  @override
  void dispose() {
    _tracker.removeListener(_onTouchChanged);
    _tracker.dispose();
    // Leaving a submitter behind would leave the menu item live pointing at
    // a column that is no longer on screen.
    if (_reportedScope) {
      final void Function(void Function()? submit)? report =
          widget.onTemporaryScopeChanged;
      _reportedScope = false;
      if (report != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => report(null));
      }
    }
    super.dispose();
  }

  /// What [onTemporaryScopeChanged] was last told, so a rebuild that did not
  /// change the scope's existence does not re-notify.
  bool _reportedScope = false;

  void _onTouchChanged() {
    if (mounted) setState(() {});
  }

  /// Forgets the temporary scope.
  ///
  /// [SelectionTouchTracker.clear] latches as well as empties, which is
  /// what makes it stick: the rows a shorter diff still has stay selected,
  /// and their listeners would otherwise re-report on the next frame and
  /// bring the scope back naming lines the user never framed. The latch
  /// lifts on the next pointer down in the well.
  ///
  /// [alsoClearHighlight] additionally drops the highlight, so a spent
  /// scope does not leave text looking selected with no button attached to
  /// it. **Cosmetic only, and pinned by no test** -- the logic is already
  /// settled by the latch, and a widget test cannot read a
  /// [SelectableRegion]'s selection back out. It is safe from the submit
  /// path but *not* from the diff-change path: clearing there walks the
  /// selection delegate's `selectables` while the tree restructure that
  /// prompted it is still mutating them, and the framework throws
  /// ConcurrentModificationError out of
  /// `MultiSelectableSelectionContainerDelegate.handleClearSelection`.
  void _dropSelection({required bool alsoClearHighlight}) {
    _tracker.clear();
    if (!alsoClearHighlight) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _selectionAreaKey.currentState?.selectableRegion.clearSelection();
    });
  }

  void _reportScope(Map<int, List<int>> temporary) {
    final void Function(void Function()? submit)? report =
        widget.onTemporaryScopeChanged;
    if (report == null) return;
    final bool hasScope = temporary.isNotEmpty;
    if (hasScope == _reportedScope) return;
    _reportedScope = hasScope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      report(hasScope ? () => _submitTemporary(temporary) : null);
    });
  }

  /// Spends the one-shot scope: submit, forget, and drop the highlight too
  /// -- leaving the text selected after acting on it would invite a second
  /// press that stages nothing.
  ///
  /// Dropping the selection is not redundant with the tap. Pressing the
  /// card's own button is a tap *inside* the [SelectionArea], which
  /// collapses the selection by itself; the keyboard path
  /// (`GbmActionId.repositoryStageSelectedLines`) is not, and without this
  /// the scope would still be live afterwards and stage a second time.
  void _submitTemporary(Map<int, List<int>> byHunk) {
    for (final MapEntry<int, List<int>> entry in byHunk.entries) {
      widget.onStageScope(entry.key, entry.value);
    }
    _dropSelection(alsoClearHighlight: true);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final DiffFile? diffFile = widget.file;
    final Map<int, List<DiffScope>> byHunk = diffFile == null
        ? const <int, List<DiffScope>>{}
        : splitDiffFileIntoScopes(diffFile);
    final int scopeCount = byHunk.values.fold<int>(
      0,
      (int sum, List<DiffScope> scopes) => sum + scopes.length,
    );

    final Map<int, List<int>> temporary = touchedChangedLines(
      _tracker.touched,
      <int, Set<int>>{
        for (final MapEntry<int, List<DiffScope>> entry in byHunk.entries)
          entry.key: <int>{
            for (final DiffScope scope in entry.value)
              ...scope.changedLineIndices,
          },
      },
    );
    _reportScope(temporary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ColumnHead(
          title: widget.title,
          staged: widget.staged,
          scopeCount: scopeCount,
        ),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.all(GbmSpacing.space4),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (diffFile == null)
          _placeholder(colors, widget.emptyLabel)
        else if (diffFile.binary)
          _placeholder(colors, '${diffFile.displayPath} (binary file)')
        else if (diffFile.hunks.isEmpty)
          _placeholder(colors, widget.emptyLabel)
        else
          Padding(
            padding: const EdgeInsets.all(GbmSpacing.space2),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                border: Border.all(color: colors.borderSubtle),
                borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
              ),
              padding: const EdgeInsets.all(GbmSpacing.space2),
              // One SelectionArea per side. A selection cannot cross the
              // seam between the two columns, which is deliberate: a scope
              // is per file *and* per side, so a drag spanning both would
              // have no single meaning.
              // The drag window. Reports are only the user's own between
              // these two, which is also the only window in which reading
              // them does not feed back into itself -- see
              // SelectionTouchTracker's `_latched`.
              child: Listener(
                onPointerDown: (_) => _tracker.beginGesture(),
                onPointerUp: (_) => _tracker.endGesture(),
                onPointerCancel: (_) => _tracker.endGesture(),
                child: SelectionArea(
                  key: _selectionAreaKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: _wellChildren(diffFile, byHunk, temporary),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Built imperatively rather than as one nested collection-for, because
  /// the loop carries a running scope ordinal across hunks.
  ///
  /// **The temporary card holds a fixed slot at the top and is a
  /// [SizedBox.shrink] when there is no selection**, rather than being
  /// inserted in front of the first card it supersedes. Inline insertion
  /// shifts every row below it by one, and the rows carry [GlobalKey]s, so
  /// the shift reparents their [SelectionListener]s -- which perturbs the
  /// very selection delegates whose report decided the card should exist.
  /// The observed result was a card that flapped in and out on idle frames.
  /// A constant-length children list has no such loop.
  List<Widget> _wellChildren(
    DiffFile diffFile,
    Map<int, List<DiffScope>> byHunk,
    Map<int, List<int>> temporary,
  ) {
    final int temporaryChanged = temporary.values.fold<int>(
      0,
      (int sum, List<int> lines) => sum + lines.length,
    );

    final List<Widget> children = <Widget>[
      if (temporary.isEmpty)
        const SizedBox.shrink()
      else
        _TemporaryCard(
          staged: widget.staged,
          spanned: _tracker.touched.length,
          changed: temporaryChanged,
          hunkCount: temporary.length,
          onStage: () => _submitTemporary(temporary),
        ),
    ];
    int ordinal = 1;

    for (int hunkIndex = 0; hunkIndex < diffFile.hunks.length; hunkIndex++) {
      final DiffHunk hunk = diffFile.hunks[hunkIndex];
      children.add(_HunkHeading(hunk: hunk));

      for (final DiffSegment segment in hunkSegments(
        hunk,
        byHunk[hunkIndex] ?? const <DiffScope>[],
        firstOrdinal: ordinal,
      )) {
        switch (segment) {
          case DiffGapSegment():
            children.add(
              _GapBlock(
                hunk: hunk,
                hunkIndex: hunkIndex,
                lineIndices: segment.lineIndices,
                staged: widget.staged,
                tracker: _tracker,
              ),
            );
          case DiffScopeSegment(:final DiffScope scope):
            final bool superseded = (temporary[hunkIndex] ?? const <int>[]).any(
              scope.changedLineIndices.contains,
            );
            children.add(
              _ScopeCard(
                hunk: hunk,
                scope: scope,
                ordinal: ordinal++,
                staged: widget.staged,
                hunkIndex: hunkIndex,
                tracker: _tracker,
                superseded: superseded,
                onStage: () =>
                    widget.onStageScope(hunkIndex, scope.changedLineIndices),
                onDiscard: widget.onDiscardScope == null
                    ? null
                    : () => widget.onDiscardScope!(
                        hunkIndex,
                        scope.changedLineIndices,
                      ),
              ),
            );
        }
      }
    }
    return children;
  }

  Widget _placeholder(GbmColors colors, String text) => Padding(
    padding: const EdgeInsets.all(GbmSpacing.space4),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: GbmTypography.textSm,
      ),
    ),
  );
}

/// `.variant-B-colhead`: a status dot, the side's name, and how many cards
/// are below it.
class _ColumnHead extends StatelessWidget {
  const _ColumnHead({
    required this.title,
    required this.staged,
    required this.scopeCount,
  });

  final String title;
  final bool staged;
  final int scopeCount;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space2,
        vertical: GbmSpacing.space1,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: staged ? colors.success : colors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            '$scopeCount 個 scope',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HunkHeading extends StatelessWidget {
  const _HunkHeading({required this.hunk});

  final DiffHunk hunk;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.only(
        top: GbmSpacing.space1,
        bottom: GbmSpacing.space1,
      ),
      child: Text(
        '@@ -${hunk.oldStart},${hunk.oldCount} '
        '+${hunk.newStart},${hunk.newCount} @@ ${hunk.heading}',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: GbmTypography.fontMono,
          fontSize: GbmTypography.textXs,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}

/// `.variant-B-gap`: the code a change sits in. Dimmed and marked with a
/// rule down its left so the eye can tell at a glance which lines a button
/// would move and which are only there for context.
class _GapBlock extends StatelessWidget {
  const _GapBlock({
    required this.hunk,
    required this.hunkIndex,
    required this.lineIndices,
    required this.staged,
    required this.tracker,
  });

  final DiffHunk hunk;
  final int hunkIndex;
  final List<int> lineIndices;
  final bool staged;
  final SelectionTouchTracker tracker;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.borderSubtle, width: 2)),
      ),
      child: Opacity(
        opacity: 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Context rows are tracked too, even though none of them can
            // move: the button's primary number is how many lines the drag
            // framed, and counting only the changed ones would understate
            // what the user actually selected.
            for (final int index in lineIndices)
              SelectionTouchRow(
                tracker: tracker,
                rowKey: selectionRowKey(hunkIndex, index),
                child: DiffLineView(line: hunk.lines[index], staged: staged),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.variant-B-card`: one scope, with the button that moves it.
class _ScopeCard extends StatelessWidget {
  const _ScopeCard({
    required this.hunk,
    required this.scope,
    required this.ordinal,
    required this.staged,
    required this.hunkIndex,
    required this.tracker,
    required this.superseded,
    required this.onStage,
    required this.onDiscard,
  });

  final DiffHunk hunk;
  final DiffScope scope;
  final int ordinal;
  final bool staged;
  final int hunkIndex;
  final SelectionTouchTracker tracker;

  /// A live text selection covers some of this card's changed lines, so the
  /// temporary scope has taken over. The button stays drawn -- struck
  /// through and inert -- rather than disappearing, because a control that
  /// vanishes reads as "this is no longer possible".
  final bool superseded;

  final VoidCallback onStage;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final int moving = scope.changedLineIndices.length;

    // Two containers, not one. The accent stripe down the left is a border
    // side of a different colour from the other three, and Flutter asserts
    // that a `borderRadius` may only be given on a uniformly-coloured
    // border -- so the radius, fill and shadow live on the outer box (which
    // clips the corners) and the four border sides on the inner one.
    return Container(
      key: ValueKey<String>('scope-card-$ordinal'),
      margin: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
        boxShadow: GbmEffects.shadowSm(context.gbmThemeVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.borderDefault),
            right: BorderSide(color: colors.borderDefault),
            bottom: BorderSide(color: colors.borderDefault),
            left: BorderSide(
              color: staged ? colors.success : colors.accent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _CardHead(
              ordinal: ordinal,
              scope: scope,
              staged: staged,
              label: scopeButtonLabel(
                staged: staged,
                spanned: scope.lineIndices.length,
                changed: moving,
              ),
              superseded: superseded,
              onStage: onStage,
            ),
            for (final int index in scope.lineIndices)
              SelectionTouchRow(
                tracker: tracker,
                rowKey: selectionRowKey(hunkIndex, index),
                child: DiffLineView(
                  line: hunk.lines[index],
                  staged: staged,
                  selectionCount: moving,
                  onStageLine: onStage,
                  onDiscardLine: onDiscard,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.variant-B-cardhead`: 變更 N, the +/- tally, and the button.
///
/// A [Wrap], not a [Row]. In `2 file` mode each side is half of a diff pane
/// whose own minimum is 150px, so a card can be narrower than its button's
/// label -- and a [Row] there does not shrink, it overflows: [RenderFlex]
/// lays the non-flex children out first and divides only what is left, so no
/// amount of [Flexible] on the tag rescues it. [Wrap] measures with the real
/// font and drops the button onto its own line when the one line will not
/// hold it, which is legible where a clipped button is not.
class _CardHead extends StatelessWidget {
  const _CardHead({
    required this.ordinal,
    required this.scope,
    required this.staged,
    required this.label,
    required this.superseded,
    required this.onStage,
  });

  final int ordinal;
  final DiffScope scope;
  final bool staged;
  final String label;
  final bool superseded;
  final VoidCallback onStage;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      color: colors.surfacePanelRaised,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space2,
        vertical: 3,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: GbmSpacing.space2,
        runSpacing: 4,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Flexible so a long tag ellipsises inside the run rather than
              // pushing the tally out of it.
              Flexible(
                child: Text(
                  '變更 $ordinal',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    fontWeight: FontWeight.bold,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              if (scope.addedCount > 0) ...<Widget>[
                const SizedBox(width: GbmSpacing.space2),
                Text(
                  '+${scope.addedCount}',
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textXs,
                    color: colors.diffAddText,
                  ),
                ),
              ],
              if (scope.removedCount > 0) ...<Widget>[
                const SizedBox(width: 4),
                Text(
                  '\u2212${scope.removedCount}',
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textXs,
                    color: colors.diffDelText,
                  ),
                ),
              ],
            ],
          ),
          GbmButton(
            label: label,
            // Null, not merely struck through: a disabled-looking control
            // that still fires is the same trap as GbmMenuItem's
            // `enabled: false` with a live `onTap`.
            onPressed: superseded ? null : onStage,
            lineThrough: superseded,
            size: GbmButtonSize.sm,
            kind: staged ? GbmButtonKind.secondary : GbmButtonKind.primary,
          ),
        ],
      ),
    );
  }
}

/// `.variant-B-temp`: the one-shot scope a text selection makes.
///
/// Dashed in the demo and accent-bordered here, and carrying a 一次性 pill,
/// because it is not a thing that persists -- one press spends it. It
/// sits at the top of the column, always in the same place, so it cannot
/// shift the rows whose selection produced it (see [_wellChildren]).
class _TemporaryCard extends StatelessWidget {
  const _TemporaryCard({
    required this.staged,
    required this.spanned,
    required this.changed,
    required this.hunkCount,
    required this.onStage,
  });

  final bool staged;

  /// Every row the drag covered, context included -- what the user framed.
  final int spanned;

  /// How many of those actually move.
  final int changed;

  /// How many hunks the selection spans, and so how many `stageLines` calls
  /// one press makes.
  final int hunkCount;

  final VoidCallback onStage;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      key: const ValueKey<String>('temporary-scope-card'),
      margin: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
      decoration: BoxDecoration(
        color: colors.accentSubtle,
        border: Border.all(color: colors.accent),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space2,
        vertical: 3,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: GbmSpacing.space2,
        runSpacing: 4,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const GbmBadge(label: '一次性'),
              const SizedBox(width: GbmSpacing.space2),
              Flexible(
                child: Text(
                  hunkCount > 1 ? '選取範圍 · 跨 $hunkCount 個 hunk' : '選取範圍',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          GbmButton(
            label: scopeButtonLabel(
              staged: staged,
              spanned: spanned,
              changed: changed,
            ),
            onPressed: onStage,
            size: GbmButtonSize.sm,
            kind: staged ? GbmButtonKind.secondary : GbmButtonKind.primary,
          ),
        ],
      ),
    );
  }
}
