import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/parsed_diff.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_badge.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_row.dart';
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

  /// Splitting the file into scopes is the one expensive thing this build
  /// does, and `_tracker`'s listener rebuilds on every frame of a selection
  /// drag. The cache's key is `widget.file`'s identity -- the same signal
  /// [didUpdateWidget] already treats as "a new diff".
  final DiffScopeCache _scopeCache = DiffScopeCache();

  /// Focus for the well, so `SCOPES` row 7's 「Shift + ↑ ↓」 half reaches
  /// [CallbackShortcuts] after a plain click.
  ///
  /// A drag already leaves [SelectionArea]'s own node focused and the key
  /// event bubbles through this widget's shortcuts either way, so this node
  /// exists for the case that has no drag at all: a user who clicks once and
  /// then works by keyboard. Requested on pointer down, because tapping does
  /// not grant focus by itself (CLAUDE.md's sidebar case).
  final FocusNode _wellFocus = FocusNode(debugLabel: 'gbm-diff-well');

  /// The two ends of the keyboard range, as row keys.
  ///
  /// A range, not a grow-only set: `Shift + ↑` after four `Shift + ↓`s has to
  /// walk the *focus* end back toward the anchor, which is the whole
  /// difference between extending a selection and accumulating one. Both are
  /// null until something seeds them -- a drag ending, a hunk heading click,
  /// or the first arrow press.
  String? _anchorRow;
  String? _focusRow;

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
    _wellFocus.dispose();
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
    if (!mounted) return;
    // Not while the pointer is down. **This is a rebuild-cost measure, not
    // the correctness one** -- `build`'s `settledTouched` gate is what
    // guarantees nothing derived from the touched set is drawn mid-drag, and
    // it has to be, because it is the only one that also covers a rebuild
    // this widget did not originate. What this line saves is a rebuild of
    // the whole column on every frame of a drag across twenty rows, for
    // output that would be identical anyway. Verified by mutation: removing
    // this line alone breaks nothing.
    if (_tracker.isDragging) return;
    setState(() {});
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
    // The range ends with the selection it describes. Leaving the two row
    // keys behind would let the next arrow press extend a range whose rows
    // may not even exist in the diff that replaced this one -- the same
    // stale-positional-key defect `clear()`'s own doc names.
    _anchorRow = null;
    _focusRow = null;
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
    // The highlight goes **before** the dispatch, synchronously, and that
    // order is the fix for a real crash the device tier found. Staging
    // replaces the diff; a `clearSelection()` deferred to after the dispatch
    // therefore lands while the tree restructure it caused is still mutating
    // the delegate's `selectables`, and the framework throws
    // ConcurrentModificationError out of `handleClearSelection`. This is the
    // same hazard [_dropSelection] documents on the diff-change path -- what
    // was not noticed is that the submit path *is* a diff-change path, one
    // dispatch later. Nothing below the widget tier could see it: the fakes
    // never actually restage, so the diff never changes and the clear always
    // found a settled tree.
    //
    // Clearing here is not redundant with the tap. Pressing a card's own
    // button is a tap inside the [SelectionArea], which collapses the
    // selection by itself; the keyboard path
    // (`GbmActionId.repositoryStageSelectedLines`) is not, and neither are
    // the two inputs that select no text at all.
    _selectionAreaKey.currentState?.selectableRegion.clearSelection();
    for (final MapEntry<int, List<int>> entry in byHunk.entries) {
      widget.onStageScope(entry.key, entry.value);
    }
    _dropSelection(alsoClearHighlight: false);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final DiffFile? diffFile = widget.file;
    final Map<int, List<DiffScope>> byHunk = _scopeCache.scopesOf(diffFile);
    final int scopeCount = byHunk.values.fold<int>(
      0,
      (int sum, List<DiffScope> scopes) => sum + scopes.length,
    );

    // One read of the touched set, gated once: everything derived from it --
    // the one-shot block, the row tint, the submitter published to
    // `repositoryStageSelectedLines` -- has to agree about whether the drag
    // has settled, and two reads could not.
    final Set<String> settledTouched = _tracker.isDragging
        ? const <String>{}
        : _tracker.touched;
    final Map<int, List<int>> temporary = touchedChangedLines(
      settledTouched,
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
              //
              // `Ctrl/Cmd+Shift+Enter` is bound **here**, not in
              // `gbm_shortcuts.dart`. The spec contradicts itself about this
              // key: P16's REVISIONS assigns Stage selected lines
              // `Ctrl/Cmd+Alt+S` while P03-5 and `SCOPES` row 7 both say
              // `Ctrl/Cmd+Shift+Enter`. #75 settled it by keeping *both*
              // readings -- the global binding is the revision's, and this
              // one lives inside the diff's own focus scope, which is what
              // the earlier pages describe. Scoped rather than global for
              // the same reason `Ctrl/Cmd+A` is (CLAUDE.md): a binding
              // closer to a focused editor than `DefaultTextEditingShortcuts`
              // would steal that editor's own Enter.
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  for (final bool meta in const <bool>[false, true])
                    SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                      control: !meta,
                      meta: meta,
                    ): () {
                      // **Unpinned by any test, deliberately.** A written
                      // one was deleted rather than kept: with no selection
                      // nothing inside the diff holds focus, so the key
                      // never reaches this callback at all and the
                      // assertion passed with the guard removed *and* with
                      // the callback replaced by an unconditional stage --
                      // a fixture that cannot disagree with the code. What
                      // the guard actually prevents is the *second* press
                      // after one has already spent the scope: an empty
                      // submit whose only effect is a redundant
                      // `clearSelection()`, which is the call that throws
                      // ConcurrentModificationError when the tree is
                      // mid-restructure. That is the same
                      // read-the-selection-back limitation recorded on
                      // `_dropSelection`.
                      if (temporary.isEmpty) return;
                      _submitTemporary(temporary);
                    },
                  // `SCOPES` row 7's other half: 「diff 區按住拖過多行，或
                  // Shift + ↑ ↓」. Bound here rather than globally for the
                  // same reason Ctrl/Cmd+Shift+Enter is -- a bare arrow key
                  // belongs to whatever has focus, and this only claims it
                  // while focus is inside the diff.
                  //
                  // Flutter does not supply this for free. SelectableRegion
                  // has keyboard selection intents, but with the tracker's
                  // latch removed entirely a Shift+ArrowDown after a drag
                  // still left the scope's count unchanged, so the region
                  // was not extending anything here to begin with.
                  const SingleActivator(
                    LogicalKeyboardKey.arrowDown,
                    shift: true,
                  ): () =>
                      _extendByRow(diffFile, 1),
                  const SingleActivator(
                    LogicalKeyboardKey.arrowUp,
                    shift: true,
                  ): () =>
                      _extendByRow(diffFile, -1),
                },
                child: Focus(
                  focusNode: _wellFocus,
                  child: Listener(
                    onPointerDown: (_) {
                      // Tapping does not grant focus by itself, and without
                      // focus the arrow bindings above are unreachable for a
                      // user who never drags.
                      //
                      // **Only when nothing here holds it already.**
                      // [SelectableRegion] clears its selection when it
                      // loses focus (`_handleFocusChanged`, non-web), and it
                      // requests focus for itself as a drag begins -- so an
                      // unconditional request from this ancestor is a live
                      // way to wipe the selection out from under the gesture
                      // that is making it. `hasFocus` is true for an
                      // ancestor of the primary focus, so this node being
                      // 「already focused」 covers the case where the region
                      // below it is the one actually holding it, and the key
                      // events reach [CallbackShortcuts] either way.
                      if (!_wellFocus.hasFocus) _wellFocus.requestFocus();
                      _tracker.beginGesture();
                    },
                    onPointerUp: (_) {
                      _tracker.endGesture();
                      _adoptRangeFromTouched(diffFile);
                    },
                    onPointerCancel: (_) => _tracker.endGesture(),
                    child: SelectionArea(
                      key: _selectionAreaKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: _wellChildren(
                          diffFile,
                          byHunk,
                          temporary,
                          settledTouched,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Every row of [diffFile], in the order they are painted.
  ///
  /// Painted order, not model order, because `SCOPES` row 7's range is a
  /// range over what the user can see -- and it is the *only* order in which
  /// 「跨 hunk 但不能跨檔」 has a meaning: the last row of one hunk is
  /// adjacent to the first row of the next.
  List<String> _rowsInRenderOrder(DiffFile diffFile) => <String>[
    for (int h = 0; h < diffFile.hunks.length; h++)
      for (int i = 0; i < diffFile.hunks[h].lines.length; i++)
        selectionRowKey(h, i),
  ];

  /// `SCOPES` row 7's second input: 「Shift + ↑ ↓」.
  ///
  /// [delta] is +1 for ↓ and -1 for ↑, and it moves the *focus* end of the
  /// range by one painted row -- context rows included, exactly as a drag
  /// counts them, so the two inputs the row lists as alternatives produce
  /// the same set for the same span.
  ///
  /// **The seed is the first (or last) *changed* row, not the first row.**
  /// Stepping from row zero would spend the first few presses on context
  /// that stages nothing and shows no card at all, so the opening press
  /// would read as "the key does nothing".
  void _extendByRow(DiffFile diffFile, int delta) {
    final List<String> rows = _rowsInRenderOrder(diffFile);
    if (rows.isEmpty) return;

    int anchorIndex = _anchorRow == null ? -1 : rows.indexOf(_anchorRow!);
    int focusIndex = _focusRow == null ? -1 : rows.indexOf(_focusRow!);

    if (anchorIndex < 0 || focusIndex < 0) {
      final Set<String> changed = <String>{
        for (final MapEntry<int, List<DiffScope>> entry
            in _scopeCache.scopesOf(diffFile).entries)
          for (final DiffScope scope in entry.value)
            for (final int line in scope.changedLineIndices)
              selectionRowKey(entry.key, line),
      };
      final Iterable<String> ordered = delta >= 0 ? rows : rows.reversed;
      final String? seed = ordered.where(changed.contains).firstOrNull;
      // Nothing can move in this diff, so there is no range to open.
      if (seed == null) return;
      anchorIndex = focusIndex = rows.indexOf(seed);
    } else {
      focusIndex = (focusIndex + delta).clamp(0, rows.length - 1);
    }

    _anchorRow = rows[anchorIndex];
    _focusRow = rows[focusIndex];
    final int lo = anchorIndex < focusIndex ? anchorIndex : focusIndex;
    final int hi = anchorIndex < focusIndex ? focusIndex : anchorIndex;
    _tracker.setTouched(rows.sublist(lo, hi + 1).toSet());
  }

  /// Adopts whatever a finished drag framed as the keyboard range, so the
  /// two inputs `SCOPES` row 7 lists share one range instead of each owning
  /// its own. Without this, a `Shift + ↓` after a drag would re-seed and
  /// collapse the drag back to a single row.
  void _adoptRangeFromTouched(DiffFile? diffFile) {
    if (diffFile == null) return;
    final Set<String> touched = _tracker.touched;
    if (touched.isEmpty) return;
    final List<String> rows = _rowsInRenderOrder(
      diffFile,
    ).where(touched.contains).toList();
    if (rows.isEmpty) return;
    _anchorRow = rows.first;
    _focusRow = rows.last;
  }

  /// `SCOPES` row 6: selects every row of [hunkIndex] as the one-shot scope,
  /// so one press moves 「該段所有變更行」.
  ///
  /// Every row, context included, for the same reason [_GapBlock] tracks
  /// context rows during a drag: the button's primary number is how many
  /// lines the user framed, and a hunk click frames the whole hunk.
  /// `touchedChangedLines` drops the context again before anything is sent
  /// to git, so this cannot ask git to stage an unchanged line.
  ///
  /// Deferred to after the frame because the click's own pointer-down has
  /// already called [SelectionTouchTracker.beginGesture] (which clears and
  /// unlatches) and its pointer-up [SelectionTouchTracker.endGesture]; doing
  /// this inline would race the row delegates that are still settling from
  /// the tap's own collapse of the text selection.
  void _selectHunk(DiffFile diffFile, int hunkIndex) {
    final Set<String> rows = <String>{
      for (int i = 0; i < diffFile.hunks[hunkIndex].lines.length; i++)
        selectionRowKey(hunkIndex, i),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tracker.setTouched(rows);
      // So a following Shift + ↑ ↓ grows or shrinks the hunk rather than
      // re-seeding somewhere else.
      _anchorRow = selectionRowKey(hunkIndex, 0);
      _focusRow = selectionRowKey(
        hunkIndex,
        diffFile.hunks[hunkIndex].lines.length - 1,
      );
    });
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
    Set<String> settledTouched,
  ) {
    final int temporaryChanged = temporary.values.fold<int>(
      0,
      (int sum, List<int> lines) => sum + lines.length,
    );
    final String temporaryLabel = scopeButtonLabel(
      staged: widget.staged,
      spanned: settledTouched.length,
      changed: temporaryChanged,
    );
    // The head goes on the first card the selection reaches, and only that
    // one: it is one scope and one press, however many cards it spans. The
    // rows it reaches in later cards still carry the dashed body and the
    // touched tint, so the extent stays visible without a second button
    // claiming to be a second action.
    bool temporaryHeadPlaced = false;

    final List<Widget> children = <Widget>[];
    int ordinal = 1;

    for (int hunkIndex = 0; hunkIndex < diffFile.hunks.length; hunkIndex++) {
      final DiffHunk hunk = diffFile.hunks[hunkIndex];
      children.add(
        _HunkHeading(hunk: hunk, onTap: () => _selectHunk(diffFile, hunkIndex)),
      );

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
                touched: settledTouched,
              ),
            );
          case DiffScopeSegment(:final DiffScope scope):
            final bool superseded = (temporary[hunkIndex] ?? const <int>[]).any(
              scope.changedLineIndices.contains,
            );
            final Set<int> temporaryLines = superseded
                ? (temporary[hunkIndex] ?? const <int>[]).toSet()
                : const <int>{};
            final bool showTemporaryHead = superseded && !temporaryHeadPlaced;
            if (showTemporaryHead) temporaryHeadPlaced = true;
            children.add(
              _ScopeCard(
                hunk: hunk,
                scope: scope,
                ordinal: ordinal++,
                staged: widget.staged,
                hunkIndex: hunkIndex,
                tracker: _tracker,
                touched: settledTouched,
                temporaryLines: temporaryLines,
                showTemporaryHead: showTemporaryHead,
                temporaryLabel: temporaryLabel,
                temporaryHunkCount: temporary.length,
                onSubmitTemporary: () => _submitTemporary(temporary),
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

/// The `@@ -a,b +c,d @@` line, and spec `SCOPES` row 6's own input:
/// 「點 hunk 標頭列（@@ …）」, 「該段所有變更行一起處理」.
///
/// Clicking it *selects* the hunk rather than staging it. That is what the
/// row says -- 處理 comes after the selection, and the row's own note sends
/// staging to the right-click menu ([diffLineMenuItems]'s Stage hunk, which
/// already existed). In 變體 B's vocabulary a selection is the one-shot
/// card, so the click raises exactly the card a drag over the whole hunk
/// would, and one press then moves every change in it -- which the per-scope
/// cards alone cannot do in a hunk that holds more than one.
///
/// A [GbmRow] rather than a hand-rolled [InkWell]: it is row-shaped and
/// clickable, and a hand-rolled one inherits `ThemeData.hoverColor` (~4%,
/// invisible on a real display) -- the defect the sidebar and the tree-mode
/// folder rows both shipped with.
class _HunkHeading extends StatelessWidget {
  const _HunkHeading({required this.hunk, required this.onTap});

  final DiffHunk hunk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      onTap: onTap,
      // The heading used to be a bare Text with 4px of padding above and
      // below; keeping that height stops the click target from re-spacing
      // every diff in the app.
      height: 22,
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.centerLeft,
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
    required this.touched,
  });

  final DiffHunk hunk;
  final int hunkIndex;
  final List<int> lineIndices;
  final bool staged;
  final SelectionTouchTracker tracker;

  /// Row keys currently in the one-shot scope. Passed down rather than read
  /// off [tracker] here so both row builders and the card head agree with
  /// the very same set the button was computed from -- a second read could
  /// be a frame behind it.
  final Set<String> touched;

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
                child: DiffLineView(
                  // C1 placeholder: this surface keeps its
                  // current always-wrap behaviour until C2 wires the
                  // preference through. Not a default on the parameter --
                  // an explicit value here is what makes the gap visible.
                  softWrap: true,
                  line: hunk.lines[index],
                  staged: staged,
                  touched: touched.contains(selectionRowKey(hunkIndex, index)),
                ),
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
    required this.touched,
    required this.temporaryLines,
    required this.showTemporaryHead,
    required this.temporaryLabel,
    required this.temporaryHunkCount,
    required this.onSubmitTemporary,
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

  /// Row keys currently in the one-shot scope -- see [_GapBlock.touched].
  final Set<String> touched;

  /// Which of this card's own line indices the one-shot scope covers.
  ///
  /// The demo nests `.variant-B-temp` **inside** `.variant-B-card`, wrapping
  /// the selected rows where they already are, so the card has to know which
  /// of its rows those are rather than being told only that it is
  /// superseded.
  final Set<int> temporaryLines;

  /// This is the first card in render order that the selection reaches, so
  /// it carries the one-shot head and its button. One scope, one press,
  /// however many cards it spans.
  final bool showTemporaryHead;

  final String temporaryLabel;
  final int temporaryHunkCount;
  final VoidCallback onSubmitTemporary;

  /// A live text selection covers some of this card's changed lines, so the
  /// temporary scope has taken over. The button stays drawn -- struck
  /// through and inert -- rather than disappearing, because a control that
  /// vanishes reads as "this is no longer possible". The card itself goes
  /// muted (`.variant-B-card-muted`): grey left edge, no shadow, sunken
  /// head.
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
        boxShadow: superseded
            ? null
            : GbmEffects.shadowSm(context.gbmThemeVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.borderDefault),
            right: BorderSide(color: colors.borderDefault),
            bottom: BorderSide(color: colors.borderDefault),
            left: BorderSide(
              // `.variant-B-card-muted` drops the accent for a neutral edge
              // while the one-shot scope holds the action.
              color: superseded
                  ? colors.borderStrong
                  : (staged ? colors.success : colors.accent),
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
            ..._body(context),
          ],
        ),
      ),
    );
  }

  /// The card's rows, with any run of them the one-shot scope covers wrapped
  /// in a [_TemporaryBlock] **in place**.
  ///
  /// Grouped into runs rather than assuming one contiguous block: the range
  /// a drag or `Shift + ↑ ↓` produces is contiguous over *painted* rows, and
  /// a card's `lineIndices` are contiguous too, so in practice there is one
  /// run -- but a gap here would silently draw two rows' worth of dashes
  /// around rows that are not selected, and grouping costs one comparison
  /// per row.
  List<Widget> _body(BuildContext context) {
    final List<Widget> out = <Widget>[];
    final List<int> indices = scope.lineIndices;
    bool headPlaced = !showTemporaryHead;

    int i = 0;
    while (i < indices.length) {
      final bool inTemporary = temporaryLines.contains(indices[i]);
      final int start = i;
      while (i < indices.length &&
          temporaryLines.contains(indices[i]) == inTemporary) {
        i++;
      }
      final List<Widget> rows = <Widget>[
        for (final int index in indices.sublist(start, i)) _row(index),
      ];
      if (!inTemporary) {
        out.addAll(rows);
        continue;
      }
      out.add(
        _TemporaryBlock(
          showHead: !headPlaced,
          staged: staged,
          label: temporaryLabel,
          hunkCount: temporaryHunkCount,
          onStage: onSubmitTemporary,
          children: rows,
        ),
      );
      headPlaced = true;
    }
    return out;
  }

  Widget _row(int index) => SelectionTouchRow(
    tracker: tracker,
    rowKey: selectionRowKey(hunkIndex, index),
    child: DiffLineView(
      // C1 placeholder: this surface keeps its
      // current always-wrap behaviour until C2 wires the
      // preference through. Not a default on the parameter --
      // an explicit value here is what makes the gap visible.
      softWrap: true,
      line: hunk.lines[index],
      staged: staged,
      selectionCount: scope.changedLineIndices.length,
      onStageLine: onStage,
      onDiscardLine: onDiscard,
      touched: touched.contains(selectionRowKey(hunkIndex, index)),
    ),
  );
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
              // Pills, not bare mono text: the two columns' file rows draw
              // this same fact as a [GbmBadge]
              // (`working_copy_board.dart`'s `_lineCountBadges`), and both
              // are on screen at once, so one fact drawn two ways read as
              // two facts.
              //
              // The glyph deliberately stays U+2212 rather than the file
              // rows' ASCII `-`. That split is by surface, not by accident:
              // the file lists share one glyph with `changed_files_panel`,
              // and the diff surfaces share the other with
              // `panel_file_diff_detail`. Unifying the *shape* was the
              // ruling; unifying the glyph would drag a third surface along
              // with it.
              //
              // A zero draws nothing, same rule and same reason as the file
              // rows: zero means not measured, and a `+0` pill would claim a
              // measurement that never happened.
              if (scope.addedCount > 0) ...<Widget>[
                const SizedBox(width: GbmSpacing.space2),
                GbmBadge(
                  label: '+${scope.addedCount}',
                  kind: GbmBadgeKind.added,
                ),
              ],
              if (scope.removedCount > 0) ...<Widget>[
                const SizedBox(width: GbmSpacing.space1),
                GbmBadge(
                  label: '\u2212${scope.removedCount}',
                  kind: GbmBadgeKind.removed,
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

/// `.variant-B-temp`: the one-shot scope a text selection makes, drawn
/// **inside** the scope card and wrapping the selected rows where they
/// already are.
///
/// Dashed accent border and an accent-subtle head, as in the demo, because
/// it is not a thing that persists -- one press spends it.
///
/// **It used to be an extra row pinned to the top of the column**, which was
/// an implementation convenience rather than the design: a fixed slot cannot
/// reparent the keyed rows below it, and inserting among them was recorded
/// as a hazard (the rows carry [SelectionListener]s whose reports decide
/// whether this block should exist at all, so perturbing them is a feedback
/// loop). What makes the nested form safe is the very thing that hazard note
/// pointed at: those keys are [GlobalKey]s, so Flutter *moves* the one
/// element into its new parent instead of unmounting and rebuilding it, and
/// the registration survives the move. The tracker's `keyFor` doc has said
/// so all along -- 「a row moves between subtrees as the diff changes ... a
/// global key makes Flutter reparent the one element instead」.
class _TemporaryBlock extends StatelessWidget {
  const _TemporaryBlock({
    required this.showHead,
    required this.staged,
    required this.label,
    required this.hunkCount,
    required this.onStage,
    required this.children,
  });

  /// This block carries the head and the button. False for the second and
  /// later cards a selection spanning more than one reaches: the dashed body
  /// still shows how far it got, but one scope gets one button.
  final bool showHead;

  final bool staged;

  /// Already composed by the caller, because the counts are the *whole*
  /// selection's and not this block's -- one press moves all of it.
  final String label;

  /// How many hunks the selection spans, and so how many `stageLines` calls
  /// one press makes.
  final int hunkCount;

  final VoidCallback onStage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      key: showHead ? const ValueKey<String>('temporary-scope-card') : null,
      margin: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
      decoration: BoxDecoration(
        border: Border.all(color: colors.accent),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showHead)
            Container(
              color: colors.accentSubtle,
              padding: const EdgeInsets.symmetric(
                horizontal: GbmSpacing.space2,
                vertical: 3,
              ),
              // A Wrap for the same reason [_CardHead] is one: in `2 file`
              // mode this sits inside a card inside half a diff pane, and a
              // Row there does not shrink, it overflows.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: GbmSpacing.space2,
                runSpacing: 4,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          hunkCount > 1 ? '臨時選取 · 跨 $hunkCount 個 hunk' : '臨時選取',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: GbmTypography.textXs,
                            fontWeight: FontWeight.bold,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: GbmSpacing.space2),
                      const GbmBadge(label: '一次性'),
                    ],
                  ),
                  GbmButton(
                    label: label,
                    onPressed: onStage,
                    size: GbmButtonSize.sm,
                    kind: staged
                        ? GbmButtonKind.secondary
                        : GbmButtonKind.primary,
                  ),
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}
