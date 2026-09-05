import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/parsed_diff.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_badge.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_dashed.dart';
import '../../widgets/gbm_outlined_pill.dart';
import '../../widgets/gbm_code_hscroll.dart';
import '../../widgets/gbm_row.dart';
import 'diff_scopes.dart';
import 'diff_truncation.dart';
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
/// One diff, and everything that decides what its cards say and do.
///
/// A [ScopedDiffView] takes a *list* of these because `unified` mode draws
/// the unstaged and staged diffs as one list, and direction is a property of
/// each card rather than of the view around it. `2 file` mode passes a
/// one-element list, which is the same shape it always had.
class ScopedDiffSource {
  const ScopedDiffSource({
    required this.title,
    required this.file,
    required this.staged,
    required this.onStageScope,
    this.onDiscardScope,
    this.emptyLabel = 'No changes',
    this.loading = false,
    this.truncated = false,
  });

  /// Column heading -- `Unstaged` or `Staged`. Drawn only when the view is
  /// showing column heads at all; a merged list replaces them with one count
  /// in the pane's own title bar (U3).
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

  /// Which direction this diff's cards act in. Never mixed within one
  /// source, and never inferred from position in the list.
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

  /// A diff request for this side is in flight.
  final bool loading;

  /// The core refused this side's diff for being over its byte cap, so
  /// [file] is null for a reason that is not "nothing changed" -- see
  /// [kDiffTooLargeLabel]. Kept separate from [emptyLabel] rather than folded
  /// into it by the caller, because the caller would then have to decide the
  /// wording and the two sides could drift apart.
  final bool truncated;

  /// True when this source has rows to draw. A binary file and a refused one
  /// both have "no content" without being empty, which is why the three
  /// states are separate fields rather than one nullable [file].
  bool get hasContent =>
      file != null && !file!.binary && file!.hunks.isNotEmpty;
}

class ScopedDiffView extends StatefulWidget {
  const ScopedDiffView({
    super.key,
    required this.sources,
    this.showColumnHeads = true,
    this.onTemporaryScopeChanged,
    required this.softWrap,
  });

  /// The diffs to draw, in painted order. One element is `2 file` mode's
  /// column; two is `unified`'s merged list.
  final List<ScopedDiffSource> sources;

  /// Whether each source draws its own `.variant-B-colhead`. False for a
  /// merged list, where a head would be labelling a column that is not
  /// there (U3) -- and a head labelling nothing is worse than no head.
  final bool showColumnHeads;

  /// Reports how to submit the current one-shot scope, or null when there
  /// is none, so `repositoryStageSelectedLines` can act on the same block
  /// the temporary card's button does.
  ///
  /// Always called from a post-frame callback: the caller writes it into a
  /// provider, and writing a provider from `build()` is a debug-only assert
  /// that release strips (see CLAUDE.md's Riverpod traps).
  final void Function(void Function()? submit)? onTemporaryScopeChanged;

  /// `AppPreferences.softWrapEnabled`, threaded in rather than watched here:
  /// this widget holds no other Riverpod dependency, and every one of its
  /// tests pumps it with plain values.
  final bool softWrap;

  @override
  State<ScopedDiffView> createState() => _ScopedDiffViewState();
}

/// One drawable block, decorated with which source and hunk it came from and
/// where it sits on the index side -- everything the merged list needs to
/// order it and then draw it.
typedef _Block = ({
  int sourceIndex,
  int hunkIndex,
  DiffSegment segment,
  IndexPosition position,
});

class _ScopedDiffViewState extends State<ScopedDiffView> {
  final GlobalKey<SelectionAreaState> _selectionAreaKey =
      GlobalKey<SelectionAreaState>();

  late final SelectionTouchTracker _tracker;

  /// Splitting a file into scopes is the one expensive thing this build
  /// does, and `_tracker`'s listener rebuilds on every frame of a selection
  /// drag. Each cache's key is its source's file identity -- the same signal
  /// [didUpdateWidget] already treats as "a new diff".
  ///
  /// One cache per source rather than one shared: [DiffScopeCache] holds a
  /// single entry, so two sources sharing one would evict each other on every
  /// build and the memo would never hit.
  final List<DiffScopeCache> _scopeCaches = <DiffScopeCache>[];

  DiffScopeCache _cacheFor(int sourceIndex) {
    while (_scopeCaches.length <= sourceIndex) {
      _scopeCaches.add(DiffScopeCache());
    }
    return _scopeCaches[sourceIndex];
  }

  /// The index lines the *other* sources change, per source index.
  ///
  /// A merged list draws two diffs of the same file at once, and the gap
  /// rule must not fold one source's scope across a line the other one
  /// draws as a change of its own -- see [changedIndexLines]. That is the
  /// whole of the reported defect: an untracked file with its middle line
  /// staged gave the unstaged side `+ + . + +`, whose single unchanged line
  /// *is* the staged change, so two regions became one card.
  ///
  /// **Key: the sources' [DiffFile] identities, element by element.** The
  /// barrier sets are a pure function of those files, and walking every line
  /// of every hunk to rebuild them is the same order as the split
  /// [DiffScopeCache] exists to avoid -- so recomputing per frame would undo
  /// that memo during a selection drag. Identity is the honest key for the
  /// reason that cache already gives: these are immutable DTOs parsed fresh
  /// out of each `workingCopyDiffReady` payload.
  ///
  /// **Invalidated by**: a different `DiffFile` instance arriving in any
  /// source. There is nothing to unsubscribe from.
  ///
  /// **Symptom if invalidation were missed**: the cards of one side would be
  /// split at the *previous* diff's boundaries -- so after staging one more
  /// line, a card would keep a seam where nothing is any more, or lose one
  /// where something now is.
  List<Set<int>> _barrierMemo = const <Set<int>>[];
  List<DiffFile?> _barrierMemoKey = const <DiffFile?>[];

  List<Set<int>> _barriersBySource() {
    final List<DiffFile?> files = <DiffFile?>[
      for (final ScopedDiffSource source in widget.sources) source.file,
    ];
    if (files.length == _barrierMemoKey.length) {
      bool same = true;
      for (int i = 0; i < files.length; i++) {
        if (!identical(files[i], _barrierMemoKey[i])) {
          same = false;
          break;
        }
      }
      if (same) return _barrierMemo;
    }

    final List<Set<int>> barriers = <Set<int>>[];
    for (int i = 0; i < widget.sources.length; i++) {
      final Set<int> other = <int>{};
      for (int j = 0; j < widget.sources.length; j++) {
        if (j == i) continue;
        other.addAll(
          changedIndexLines(
            widget.sources[j].file,
            staged: widget.sources[j].staged,
          ),
        );
      }
      // `const` so a single-source view hands the cache the *same* empty set
      // on every build -- a fresh `<int>{}` would miss on identity and
      // re-split every frame, which is exactly what the memo above is for.
      barriers.add(other.isEmpty ? const <int>{} : other);
    }

    _barrierMemoKey = files;
    _barrierMemo = barriers;
    return barriers;
  }

  /// The scopes of every source, by source index.
  List<Map<int, List<DiffScope>>> _scopesBySource() {
    final List<Set<int>> barriers = _barriersBySource();
    return <Map<int, List<DiffScope>>>[
      for (int i = 0; i < widget.sources.length; i++)
        _cacheFor(i).scopesOf(
          widget.sources[i].file,
          staged: widget.sources[i].staged,
          barrierIndexLines: barriers[i],
        ),
    ];
  }

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
    if (_diffsChanged(oldWidget.sources, widget.sources)) {
      _dropSelection(alsoClearHighlight: false);
    }
  }

  /// True when any source's diff was replaced, or the list changed length.
  /// Identity, not equality: a new [DiffFile] instance is a new diff even
  /// when it happens to hold the same lines, and that is what renumbers the
  /// positional row keys.
  static bool _diffsChanged(
    List<ScopedDiffSource> before,
    List<ScopedDiffSource> after,
  ) {
    if (before.length != after.length) return true;
    for (int i = 0; i < before.length; i++) {
      if (!identical(before[i].file, after[i].file)) return true;
    }
    return false;
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

  void _reportScope(TemporaryScope? temporary) {
    final void Function(void Function()? submit)? report =
        widget.onTemporaryScopeChanged;
    if (report == null) return;
    final bool hasScope = temporary != null;
    if (hasScope == _reportedScope) return;
    _reportedScope = hasScope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      report(hasScope ? () => _submitTemporary(temporary) : null);
      // `temporary` is promoted non-null by `hasScope` above.
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
  void _submitTemporary(TemporaryScope scope) {
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
    // One source, decided by [resolveTemporaryScope]: git has no action that
    // stages and unstages at once, so a scope that spanned both directions
    // would have no single dispatch (U5).
    if (scope.sourceIndex >= widget.sources.length) return;
    final ScopedDiffSource source = widget.sources[scope.sourceIndex];
    for (final MapEntry<int, List<int>> entry in scope.byHunk.entries) {
      source.onStageScope(entry.key, entry.value);
    }
    _dropSelection(alsoClearHighlight: false);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<ScopedDiffSource> sources = widget.sources;
    final List<Map<int, List<DiffScope>>> scopesBySource = _scopesBySource();
    // Once per frame, for both readers. `_orderedBlocks` runs `hunkSegments`
    // over every hunk of every source, which is not cached the way the scope
    // split is -- and this runs on every frame of a drag.
    final List<_Block> blocks = _orderedBlocks(scopesBySource);

    // One read of the touched set, gated once: everything derived from it --
    // the one-shot block, the row tint, the submitter published to
    // `repositoryStageSelectedLines` -- has to agree about whether the drag
    // has settled, and two reads could not.
    final Set<String> settledTouched = _tracker.isDragging
        ? const <String>{}
        : _tracker.touched;
    final List<Map<int, Set<int>>> changedBySource = <Map<int, Set<int>>>[
      for (final Map<int, List<DiffScope>> byHunk in scopesBySource)
        <int, Set<int>>{
          for (final MapEntry<int, List<DiffScope>> entry in byHunk.entries)
            entry.key: <int>{
              for (final DiffScope scope in entry.value)
                ...scope.changedLineIndices,
            },
        },
    ];
    final TemporaryScope? temporary = resolveTemporaryScope(
      rowsInRenderOrder: _rowsFrom(blocks),
      touched: settledTouched,
      changedBySource: changedBySource,
    );
    _reportScope(temporary);

    final bool anyContent = sources.any(
      (ScopedDiffSource source) => source.hasContent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.showColumnHeads)
          for (int i = 0; i < sources.length; i++)
            _ColumnHead(
              title: sources[i].title,
              staged: sources[i].staged,
              scopeCount: scopesBySource[i].values.fold<int>(
                0,
                (int sum, List<DiffScope> scopes) => sum + scopes.length,
              ),
            ),
        // A source that is in flight or refused says so **even when another
        // source has rows**, and it says so in its own right rather than by
        // suppressing the list. Losing that message is a real regression the
        // merge introduced and two existing tests caught: with the staged
        // side drawing cards, the unstaged side's 「Diff too large」 simply
        // vanished, which is exactly the 「no message at all」
        // [CPP-parse-refuses-over-cap] forbids.
        //
        // Unreachable with one source -- a single source cannot both have
        // content and be the one with the notice -- so `2 file` mode is
        // provably untouched by this (U6).
        if (anyContent)
          for (final ScopedDiffSource source in sources)
            if (_noticeFor(source) case final Widget notice) notice,
        if (!anyContent)
          _emptyBody(colors)
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
              // One SelectionArea for the whole view. In `2 file` mode that
              // is one per side, because each side is its own view and a
              // selection cannot cross the seam between two columns. In
              // `unified` it spans both directions deliberately: the drag is
              // allowed to run across the boundary, and
              // [resolveTemporaryScope] is what decides which single
              // direction it acts in (U5) -- a rule the user can see in the
              // button's own label, rather than a wall they hit mid-drag.
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
                      if (temporary == null) return;
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
                      _extendByRow(1),
                  const SingleActivator(
                    LogicalKeyboardKey.arrowUp,
                    shift: true,
                  ): () =>
                      _extendByRow(-1),
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
                      _adoptRangeFromTouched();
                    },
                    onPointerCancel: (_) => _tracker.endGesture(),
                    child: SelectionArea(
                      key: _selectionAreaKey,
                      // The scroll well is the *pane's*, not this
                      // widget's: `unified` mode scrolls both sides on one
                      // vertical position, and a well per side cannot
                      // express that. Rows still find it -- GbmPinnedGutter
                      // reads GbmCodeHScrollScope out of the context, so it
                      // does not care who built it. What has to stay true
                      // here is that the SelectionArea remains outside
                      // everything the drag meets.
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: _wellChildren(
                          blocks,
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

  /// What to draw when no source has a single row to show.
  ///
  /// The precedence is the same chain the single-source version had, read
  /// across every source instead of one: in flight beats refused, refused
  /// beats binary, and only then does the caller's own wording apply. It is
  /// reached only when *nothing* has content, so a merged list with cards on
  /// one side and nothing on the other draws no placeholder at all -- the
  /// pane's own count already says the other side is empty, and a
  /// 「Nothing staged」 line in the middle of a list of unstaged cards would
  /// read as a section that failed to load.
  /// The 「in flight」/「refused」/「binary」 line for one source, drawn beside
  /// the merged list rather than in place of it, or null when the source has
  /// nothing to announce.
  ///
  /// Named with the source's own title, because with the column heads gone
  /// (U3) nothing else on screen would say *which* direction was refused --
  /// and a bare 「Diff too large to display」 over a list of staged cards
  /// reads as a claim about the list.
  Widget? _noticeFor(ScopedDiffSource source) {
    if (source.hasContent) return null;
    if (source.loading) {
      return _Notice(
        title: source.title,
        staged: source.staged,
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (source.truncated) {
      return _Notice(
        title: source.title,
        staged: source.staged,
        message: kDiffTooLargeLabel,
      );
    }
    final DiffFile? file = source.file;
    if (file != null && file.binary) {
      return _Notice(
        title: source.title,
        staged: source.staged,
        message: '${file.displayPath} (binary file)',
      );
    }
    // Plain 「nothing on this side」 is deliberately silent here: the pane's
    // own 「N 未暫存 · M 已暫存」 already says it, and a placeholder line in
    // the middle of the other side's cards would read as a section that
    // failed to load rather than one that is simply empty.
    return null;
  }

  Widget _emptyBody(GbmColors colors) {
    final List<ScopedDiffSource> sources = widget.sources;
    if (sources.isEmpty) return _placeholder(colors, 'No changes');
    if (sources.any((ScopedDiffSource s) => s.loading)) {
      return const Padding(
        padding: EdgeInsets.all(GbmSpacing.space4),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Before the empty arm: a refused diff also has no file, and falling
    // through to `emptyLabel` would say "Nothing unstaged" about a file the
    // row's own +N badge says has changes.
    if (sources.any((ScopedDiffSource s) => s.truncated)) {
      return _placeholder(colors, kDiffTooLargeLabel);
    }
    final ScopedDiffSource? binary = sources
        .where((ScopedDiffSource s) => s.file?.binary ?? false)
        .firstOrNull;
    if (binary != null) {
      return _placeholder(colors, '${binary.file!.displayPath} (binary file)');
    }
    return _placeholder(colors, sources.first.emptyLabel);
  }

  /// Every row of every source, in the order they are painted.
  ///
  /// Painted order, not model order, because `SCOPES` row 7's range is a
  /// range over what the user can see -- and it is the *only* order in which
  /// 「跨 hunk 但不能跨檔」 has a meaning: the last row of one hunk is
  /// adjacent to the first row of the next.
  ///
  /// In a merged list this order is also what settles a drag's direction:
  /// [resolveTemporaryScope] takes the first *changed* row it finds here, so
  /// "which card did the selection reach first" is answered by the same list
  /// the rows were laid out from ([CULT-single-source-of-truth]).
  ///
  /// **That sentence was written before it was true.** This walked the
  /// sources in order for one round while [_wellChildren] painted them
  /// sorted, so the two disagreed exactly when the regions interleaved.
  /// Both now read [_orderedBlocks]; the derivation below is deliberately
  /// the only body here, so there is nothing left to drift.
  List<String> _rowsInRenderOrder() =>
      _rowsFrom(_orderedBlocks(_scopesBySource()));

  /// The row keys of [blocks], in the order they are painted.
  ///
  /// Separate from [_rowsInRenderOrder] only so `build` can hand over blocks
  /// it has already ordered; the keyboard handlers have no frame to share
  /// with and order their own.
  static List<String> _rowsFrom(List<_Block> blocks) => <String>[
    for (final _Block block in blocks)
      for (final int lineIndex in block.segment.lineIndices)
        selectionRowKey(block.sourceIndex, block.hunkIndex, lineIndex),
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
  void _extendByRow(int delta) {
    final List<String> rows = _rowsInRenderOrder();
    if (rows.isEmpty) return;

    int anchorIndex = _anchorRow == null ? -1 : rows.indexOf(_anchorRow!);
    int focusIndex = _focusRow == null ? -1 : rows.indexOf(_focusRow!);

    if (anchorIndex < 0 || focusIndex < 0) {
      final List<Map<int, List<DiffScope>>> scopesBySource = _scopesBySource();
      final Set<String> changed = <String>{
        for (
          int sourceIndex = 0;
          sourceIndex < scopesBySource.length;
          sourceIndex++
        )
          for (final MapEntry<int, List<DiffScope>> entry
              in scopesBySource[sourceIndex].entries)
            for (final DiffScope scope in entry.value)
              for (final int line in scope.changedLineIndices)
                selectionRowKey(sourceIndex, entry.key, line),
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
  void _adoptRangeFromTouched() {
    final Set<String> touched = _tracker.touched;
    if (touched.isEmpty) return;
    final List<String> rows = _rowsInRenderOrder()
        .where(touched.contains)
        .toList();
    if (rows.isEmpty) return;
    _anchorRow = rows.first;
    _focusRow = rows.last;
  }

  /// `SCOPES` row 6: selects every row of one hunk as the one-shot scope, so
  /// one press moves 「該段所有變更行」.
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
  void _selectHunk(int sourceIndex, DiffFile diffFile, int hunkIndex) {
    final Set<String> rows = <String>{
      for (int i = 0; i < diffFile.hunks[hunkIndex].lines.length; i++)
        selectionRowKey(sourceIndex, hunkIndex, i),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tracker.setTouched(rows);
      // So a following Shift + ↑ ↓ grows or shrinks the hunk rather than
      // re-seeding somewhere else.
      _anchorRow = selectionRowKey(sourceIndex, hunkIndex, 0);
      _focusRow = selectionRowKey(
        sourceIndex,
        hunkIndex,
        diffFile.hunks[hunkIndex].lines.length - 1,
      );
    });
  }

  /// Every drawable block of every source, in the order they are painted.
  ///
  /// The one place that order is decided, because two things read it: the
  /// widgets themselves, and [_rowsInRenderOrder], which is what
  /// [resolveTemporaryScope] and `Shift + ↑ ↓` walk. They were two
  /// traversals for one round -- a source-major one here and a sorted one in
  /// [_wellChildren] -- and they disagreed the moment the regions
  /// interleaved, which is exactly the case the sort exists for: a drag
  /// reaching a staged card painted above an unstaged one resolved to
  /// unstaged, against U5, and a Shift-range spanned rows in an order
  /// nothing on screen was in ([SPEC-range-follows-paint-order]).
  List<_Block> _orderedBlocks(List<Map<int, List<DiffScope>>> scopesBySource) {
    // Every drawable block of every source, decorated with where it sits on
    // the index -- the ruler the two diffs share ([indexPositionOf]).
    final List<_Block> blocks = <_Block>[];
    final List<Set<int>> barriers = _barriersBySource();

    for (
      int sourceIndex = 0;
      sourceIndex < widget.sources.length;
      sourceIndex++
    ) {
      final ScopedDiffSource source = widget.sources[sourceIndex];
      final DiffFile? diffFile = source.file;
      if (diffFile == null || !source.hasContent) continue;
      final Map<int, List<DiffScope>> byHunk = scopesBySource[sourceIndex];
      for (int hunkIndex = 0; hunkIndex < diffFile.hunks.length; hunkIndex++) {
        final DiffHunk hunk = diffFile.hunks[hunkIndex];
        for (final DiffSegment segment in hunkSegments(
          hunk,
          byHunk[hunkIndex] ?? const <DiffScope>[],
          // 使用者裁定 B: a context row whose index line the *other* source
          // draws as a change of its own is dropped here rather than drawn
          // twice. Empty for a single source, so `2 file` mode is untouched.
          hiddenLines: barrierLineIndices(
            hunk,
            staged: source.staged,
            indexLines: barriers[sourceIndex],
          ),
        )) {
          blocks.add((
            sourceIndex: sourceIndex,
            hunkIndex: hunkIndex,
            segment: segment,
            // The empty case is unreachable by construction -- a gap
            // segment is only emitted for a non-empty run and a scope
            // always has at least one changed line -- so it only has to be
            // a total order, not a meaningful position.
            position: segment.lineIndices.isEmpty
                ? (
                    line: source.staged ? hunk.newStart : hunk.oldStart,
                    offset: 0,
                  )
                : indexPositionOf(
                    hunk,
                    segment.lineIndices.first,
                    staged: source.staged,
                  ),
          ));
        }
      }
    }

    // U1: 「我要對齊的不是行號，是 git 判斷出的區域變更」. Ordering
    // *regions* asserts only that one region precedes another in the file,
    // which is true in the index coordinates both diffs already carry. It is
    // not the hard line alignment 變體 B's own note forbids -- that would
    // claim two rows from two different diffs are the same line.
    //
    // Sorted, never merged: 「unstage, stage 必定是不同 scope」, so two
    // regions at the same position stay two cards with two buttons.
    //
    // Decorated with the original index because [List.sort] is not stable
    // and the tie-break has to be deterministic: at equal positions the
    // unstaged side comes first, which is the reading order the two-column
    // layout taught. Skipped entirely for a single source, so `2 file` mode
    // provably cannot be reordered by this (U6).
    if (widget.sources.length > 1) {
      final List<int> order = <int>[for (int i = 0; i < blocks.length; i++) i];
      order.sort((int a, int b) {
        final int byPosition = compareIndexPositions(
          blocks[a].position,
          blocks[b].position,
        );
        if (byPosition != 0) return byPosition;
        final int bySource = blocks[a].sourceIndex.compareTo(
          blocks[b].sourceIndex,
        );
        if (bySource != 0) return bySource;
        return a.compareTo(b);
      });
      final List<_Block> sorted = <_Block>[
        for (final int i in order) blocks[i],
      ];
      blocks
        ..clear()
        ..addAll(sorted);
    }

    return blocks;
  }

  /// Built imperatively rather than as one nested collection-for, because
  /// the loop carries a running scope ordinal across hunks -- and now across
  /// sources, so a merged list numbers its cards 1..N once rather than
  /// restarting at each direction.
  ///
  /// **There is no temporary card here at all.** This list emits exactly
  /// three kinds of child -- [_HunkHeading], [_GapBlock], [_ScopeCard] --
  /// and a one-shot selection is rendered *inside* the cards it covers:
  /// [_ScopeCard] wraps the covered run of its own rows in a
  /// [_TemporaryBlock] in place, and the head plus its button go on the
  /// first card the selection reaches (`showTemporaryHead` below). That is
  /// the style demo's own structure -- `.variant-B-temp` is nested inside
  /// `.variant-B-card`, which goes `.variant-B-card-muted` with its button
  /// `.variant-B-btn-off` ([SPEC-demo-dom-is-the-spec]).
  ///
  /// **Corrected in place**: this comment used to say the temporary card
  /// 「holds a fixed slot at the top and is a [SizedBox.shrink] when there
  /// is no selection」, and justified it by the reparenting hazard -- an
  /// inline insertion shifts every row below it, and the rows carry
  /// [SelectionListener]s whose reports are what decided the card should
  /// exist. Both halves outlived what they described. The slot shipped,
  /// the user pointed at it, and it was replaced by the nested form; the
  /// hazard is answered by the rows' own [GlobalKey]s, which make Flutter
  /// *move* an element into its new parent rather than rebuild it. A
  /// recorded hazard is a reason to solve the problem, not a licence to
  /// change the design ([FLU-selectionarea-gives-a-string]).
  List<Widget> _wellChildren(
    List<_Block> blocks,
    TemporaryScope? temporary,
    Set<String> settledTouched,
  ) {
    // The one-shot scope belongs to exactly one source, so every card in
    // every *other* source draws as an ordinary card -- not struck through,
    // not tinted. That is U5 made visible: the excluded cards keep their own
    // buttons and stay pressable.
    final Map<int, List<int>> temporaryByHunk =
        temporary?.byHunk ?? const <int, List<int>>{};
    final int temporaryChanged = temporaryByHunk.values.fold<int>(
      0,
      (int sum, List<int> lines) => sum + lines.length,
    );
    // How many rows the drag framed *within the winning source*: the label's
    // primary number is 匡選行數, and counting rows the scope excluded would
    // promise to move lines the button will not touch.
    final int temporarySpanned = temporary == null
        ? 0
        : settledTouched
              .where(
                (String row) => row.startsWith('${temporary.sourceIndex}:'),
              )
              .length;
    final String temporaryLabel = temporary == null
        ? ''
        : scopeButtonLabel(
            staged: widget.sources[temporary.sourceIndex].staged,
            spanned: temporarySpanned,
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
    // A heading whenever the list moves to a different hunk *or* a different
    // source. In a merged list that is more headings than either side alone
    // would draw, and each earns its place: `@@ -a,b +c,d @@` is the only
    // thing on screen that says which diff's coordinates the rows below it
    // are in (U4).
    int? lastSourceIndex;
    int? lastHunkIndex;

    for (final _Block block in blocks) {
      final ScopedDiffSource source = widget.sources[block.sourceIndex];
      final DiffFile diffFile = source.file!;
      final DiffHunk hunk = diffFile.hunks[block.hunkIndex];
      final bool isTemporarySource =
          temporary != null && temporary.sourceIndex == block.sourceIndex;

      if (block.sourceIndex != lastSourceIndex ||
          block.hunkIndex != lastHunkIndex) {
        lastSourceIndex = block.sourceIndex;
        lastHunkIndex = block.hunkIndex;
        children.add(
          _HunkHeading(
            hunk: hunk,
            hunkIndex: block.hunkIndex,
            onTap: () =>
                _selectHunk(block.sourceIndex, diffFile, block.hunkIndex),
          ),
        );
      }

      switch (block.segment) {
        case DiffGapSegment():
          children.add(
            _GapBlock(
              sourceIndex: block.sourceIndex,
              hunk: hunk,
              hunkIndex: block.hunkIndex,
              lineIndices: block.segment.lineIndices,
              staged: source.staged,
              tracker: _tracker,
              touched: settledTouched,
              softWrap: widget.softWrap,
            ),
          );
        case DiffScopeSegment(:final DiffScope scope):
          final bool superseded =
              isTemporarySource &&
              (temporaryByHunk[block.hunkIndex] ?? const <int>[]).any(
                scope.changedLineIndices.contains,
              );
          final Set<int> temporaryLines = superseded
              ? (temporaryByHunk[block.hunkIndex] ?? const <int>[]).toSet()
              : const <int>{};
          final bool showTemporaryHead = superseded && !temporaryHeadPlaced;
          if (showTemporaryHead) temporaryHeadPlaced = true;
          children.add(
            _ScopeCard(
              sourceIndex: block.sourceIndex,
              hunk: hunk,
              scope: scope,
              ordinal: ordinal++,
              staged: source.staged,
              // U2: in a merged list the card is the only thing that can say
              // which direction it acts in, so the dot the column head used
              // to carry moves onto the card head. With the heads still
              // drawn it would be the same fact twice, inches apart.
              showDirectionDot: !widget.showColumnHeads,
              hunkIndex: block.hunkIndex,
              tracker: _tracker,
              touched: settledTouched,
              softWrap: widget.softWrap,
              temporaryLines: temporaryLines,
              showTemporaryHead: showTemporaryHead,
              temporaryLabel: temporaryLabel,
              temporaryHunkCount: temporaryByHunk.length,
              onSubmitTemporary: temporary == null
                  ? _noTemporaryScope
                  : () => _submitTemporary(temporary),
              superseded: superseded,
              onStage: () => source.onStageScope(
                block.hunkIndex,
                scope.changedLineIndices,
              ),
              onDiscard: source.onDiscardScope == null
                  ? null
                  : () => source.onDiscardScope!(
                      block.hunkIndex,
                      scope.changedLineIndices,
                    ),
            ),
          );
      }
    }
    return children;
  }

  /// Stands in for the submit callback on a card that has no one-shot scope
  /// over it. Never reachable: [_ScopeCard] only draws the temporary head
  /// (the one thing that calls it) when `showTemporaryHead` is true, and
  /// that requires a scope to exist. A no-op rather than a nullable
  /// parameter, so the card's own contract stays "there is always something
  /// to call" and no call site has to null-check what it just gated on.
  static void _noTemporaryScope() {}

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

/// One direction's 「in flight」 or 「refused」 line in a merged list.
///
/// Carries the same 8px dot and the same title the column head would have,
/// because that is the only thing that says which of the two diffs the line
/// is about once the heads are gone.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.staged,
    this.message,
    this.child,
  });

  final String title;
  final bool staged;
  final String? message;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space2,
        vertical: GbmSpacing.space2,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: staged ? colors.success : colors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          Text(
            title,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              fontWeight: FontWeight.bold,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          ?child,
          // Its own Text, not interpolated into the title, so a finder for
          // the message alone still matches -- the wording is what the
          // existing tests pin, and it is shared with `2 file` mode.
          if (message != null)
            Flexible(
              child: Text(
                message!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: GbmTypography.textSm,
                ),
              ),
            ),
        ],
      ),
    );
  }
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
          // `.variant-B-dot { width: 8px; height: 8px }`. It shipped at 6.
          Container(
            key: const ValueKey<String>('column-head-dot'),
            width: 8,
            height: 8,
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
          // `.variant-B-chip`: a ringed pill on raised ground, not the bare
          // tertiary text this shipped as. The title beside it deliberately
          // keeps textXs/bold/secondary rather than the design's
          // text-sm/semibold/primary -- every other pane header in this app
          // uses the former, and matching the design on this one header
          // would make it the odd one out among its neighbours.
          // Flexible, because RenderFlex lays its non-flex children out
          // first and divides only what is left -- so the Expanded title
          // beside it cannot rescue an overflow the chip causes. It did:
          // the chip is wider than the bare text it replaced (a ring plus
          // 8px of padding each side) and the head overflowed by 11px at
          // `splitterWcDiffSides.minExtent`. The pill's own text already
          // ellipsises, so shrinking is a truncation rather than a clip.
          Flexible(
            child: GbmOutlinedPill(
              label: '$scopeCount 個 scope',
              color: colors.textTertiary,
              borderColor: colors.borderSubtle,
              background: colors.surfacePanelRaised,
              verticalPadding: 1,
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
  const _HunkHeading({
    required this.hunk,
    required this.hunkIndex,
    required this.onTap,
  });

  final DiffHunk hunk;
  final int hunkIndex;
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
      child: Row(
        children: <Widget>[
          Flexible(
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
          // 變體 B follows the heading with a 1px rule filling the rest of
          // the row. Without it the `@@ …` line reads as one more line of
          // code in the same mono face rather than as a divider.
          const SizedBox(width: GbmSpacing.space2),
          Expanded(
            child: Container(
              key: ValueKey<String>('hunk-heading-rule-$hunkIndex'),
              height: 1,
              color: colors.borderSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.variant-B-gap`: the code a change sits in. Dimmed and marked with a
/// rule down its left so the eye can tell at a glance which lines a button
/// would move and which are only there for context.
class _GapBlock extends StatelessWidget {
  const _GapBlock({
    required this.sourceIndex,
    required this.hunk,
    required this.hunkIndex,
    required this.lineIndices,
    required this.staged,
    required this.tracker,
    required this.touched,
    required this.softWrap,
  });

  final bool softWrap;

  /// Which of the view's sources these rows came from -- the first component
  /// of every row key, so two sources' identically-numbered rows stay
  /// distinct ([selectionRowKey]).
  final int sourceIndex;
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
    // `.variant-B-gap { padding-left: 2px;
    //                   border-left: 1px dashed var(--border-default) }`.
    //
    // It shipped as a 2px solid `border-subtle` rule *plus* `Opacity(0.6)`
    // over the rows -- marking context twice, once with a rule and again by
    // fading the code. 變體 B fades nothing anywhere (the word `opacity`
    // appears in its stylesheet only under `.variant-A-*` and
    // `.variant-C-*`), and the dashed rule is what carries the distinction.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      // IntrinsicHeight because the rule beside the rows is a vertical
      // GbmDashedLine, which needs a bounded height to draw into, and a
      // `Column` hands its non-flex children `maxHeight: infinity` whatever
      // its own bound is -- [FLU-column-nonflex-unbounded-height] /
      // [FLU-row-stretch-needs-intrinsic-height], hit again here.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            GbmDashedLine(color: colors.borderDefault, axis: Axis.vertical),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Context rows are tracked too, even though none of them
                  // can move: the button's primary number is how many lines
                  // the drag framed, and counting only the changed ones
                  // would understate what the user actually selected.
                  for (final int index in lineIndices)
                    SelectionTouchRow(
                      tracker: tracker,
                      rowKey: selectionRowKey(sourceIndex, hunkIndex, index),
                      child: DiffLineView(
                        softWrap: softWrap,
                        line: hunk.lines[index],
                        staged: staged,
                        touched: touched.contains(
                          selectionRowKey(sourceIndex, hunkIndex, index),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.variant-B-card`: one scope, with the button that moves it.
class _ScopeCard extends StatefulWidget {
  const _ScopeCard({
    required this.sourceIndex,
    required this.showDirectionDot,
    required this.hunk,
    required this.scope,
    required this.ordinal,
    required this.staged,
    required this.hunkIndex,
    required this.tracker,
    required this.touched,
    required this.softWrap,
    required this.temporaryLines,
    required this.showTemporaryHead,
    required this.temporaryLabel,
    required this.temporaryHunkCount,
    required this.onSubmitTemporary,
    required this.superseded,
    required this.onStage,
    required this.onDiscard,
  });

  /// Which of the view's sources this card came from -- see
  /// [_GapBlock.sourceIndex].
  final int sourceIndex;

  /// Whether the head carries the direction dot the column head used to
  /// (U2). True exactly when there is no column head above to carry it.
  final bool showDirectionDot;
  final DiffHunk hunk;
  final DiffScope scope;
  final int ordinal;
  final bool staged;
  final int hunkIndex;
  final SelectionTouchTracker tracker;

  /// Row keys currently in the one-shot scope -- see [_GapBlock.touched].
  final Set<String> touched;

  /// See [ScopedDiffView.softWrap].
  final bool softWrap;

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
  State<_ScopeCard> createState() => _ScopeCardState();
}

class _ScopeCardState extends State<_ScopeCard> {
  /// `.variant-B-card:hover`. A MouseRegion rather than a GbmRow because a
  /// card is not row-shaped -- it is a block with a head, a body and a
  /// button of its own, and GbmRow's tint would paint over all three.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final int moving = widget.scope.changedLineIndices.length;

    // Two containers, not one. The accent stripe down the left is a border
    // side of a different colour from the other three, and Flutter asserts
    // that a `borderRadius` may only be given on a uniformly-coloured
    // border -- so the radius, fill and shadow live on the outer box (which
    // clips the corners) and the four border sides on the inner one.
    // `.variant-B-card:hover { border-color: var(--border-strong);
    //                          border-left-color: var(--accent-hover);
    //                          box-shadow: var(--shadow-md) }`
    //
    // A superseded card is deliberately left out: its button is struck
    // through and inert, and a card that lifts under the pointer while
    // nothing on it can be pressed is the affordance lying.
    final bool lifted = _hovered && !widget.superseded;
    final Color ring = lifted ? colors.borderStrong : colors.borderDefault;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        key: ValueKey<String>('scope-card-${widget.ordinal}'),
        // `.variant-B-card { margin: var(--space-2) 0 }`. It shipped at
        // space1, which read as one block of code with hairlines in it rather
        // than as separate cards.
        margin: const EdgeInsets.symmetric(vertical: GbmSpacing.space2),
        decoration: BoxDecoration(
          color: colors.surfacePanel,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
          boxShadow: widget.superseded
              ? null
              : (lifted
                    ? GbmEffects.shadowMd(context.gbmThemeVariant)
                    : GbmEffects.shadowSm(context.gbmThemeVariant)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: ring),
              right: BorderSide(color: ring),
              bottom: BorderSide(color: ring),
              left: BorderSide(
                // `.variant-B-card-muted` drops the accent for a neutral edge
                // while the one-shot scope holds the action.
                color: widget.superseded
                    ? colors.borderStrong
                    : (widget.staged
                          ? colors.success
                          : (lifted ? colors.accentHover : colors.accent)),
                width: 3,
              ),
            ),
          ),
          // A card's rows sit on surfacePanel while the well behind them is
          // surfaceSunken, and a pinned gutter paints its own backdrop so the
          // code can pass under it -- with the well's colour it would show as a
          // seam down the left of every card.
          child: GbmPinnedGutterBackdrop(
            color: colors.surfacePanel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _CardHead(
                  ordinal: widget.ordinal,
                  scope: widget.scope,
                  staged: widget.staged,
                  showDirectionDot: widget.showDirectionDot,
                  label: scopeButtonLabel(
                    staged: widget.staged,
                    spanned: widget.scope.lineIndices.length,
                    changed: moving,
                  ),
                  superseded: widget.superseded,
                  onStage: widget.onStage,
                ),
                ..._body(context),
              ],
            ),
          ),
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
    final List<int> indices = widget.scope.lineIndices;
    bool headPlaced = !widget.showTemporaryHead;

    int i = 0;
    while (i < indices.length) {
      final bool inTemporary = widget.temporaryLines.contains(indices[i]);
      final int start = i;
      while (i < indices.length &&
          widget.temporaryLines.contains(indices[i]) == inTemporary) {
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
          staged: widget.staged,
          label: widget.temporaryLabel,
          hunkCount: widget.temporaryHunkCount,
          onStage: widget.onSubmitTemporary,
          children: rows,
        ),
      );
      headPlaced = true;
    }
    return out;
  }

  Widget _row(int index) => SelectionTouchRow(
    tracker: widget.tracker,
    rowKey: selectionRowKey(widget.sourceIndex, widget.hunkIndex, index),
    child: DiffLineView(
      softWrap: widget.softWrap,
      line: widget.hunk.lines[index],
      staged: widget.staged,
      selectionCount: widget.scope.changedLineIndices.length,
      onStageLine: widget.onStage,
      onDiscardLine: widget.onDiscard,
      touched: widget.touched.contains(
        selectionRowKey(widget.sourceIndex, widget.hunkIndex, index),
      ),
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
    required this.showDirectionDot,
    required this.label,
    required this.superseded,
    required this.onStage,
  });

  /// See [_ScopeCard.showDirectionDot].
  final bool showDirectionDot;

  final int ordinal;
  final DiffScope scope;
  final bool staged;
  final String label;
  final bool superseded;
  final VoidCallback onStage;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    // `.variant-B-cardhead { background: var(--surface-panel-raised);
    //                         border-bottom: 1px solid var(--border-default) }`,
    // and `.variant-B-card-muted`'s head goes `--surface-sunken`.
    //
    // The rule is what makes the head read as a head; without it the tag and
    // the button float over the code. **The design's `height: 30px` is
    // deliberately not adopted** -- this is a `Wrap`, and in a narrow pane it
    // has to be free to take a second line, which a fixed height would clip.
    // That matters more now that the pane is a right-hand column.
    return Container(
      decoration: BoxDecoration(
        color: superseded ? colors.surfaceSunken : colors.surfacePanelRaised,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
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
              // The same 8px `.variant-B-dot` the column head drew, in the
              // same two colours, moved down one level (U2). It is the only
              // thing in a merged list that names the direction *before* the
              // eye reaches the button at the other end of the row, and the
              // colour is the one the left edge of this very card already
              // carries -- so the two agree by construction rather than by
              // two call sites remembering the same rule.
              if (showDirectionDot) ...<Widget>[
                Container(
                  key: const ValueKey<String>('card-head-dot'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: staged ? colors.success : colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
              ],
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
            // `.variant-B-btn-unstage`: secondary's ground and label with a
            // `border-strong` ring rather than `border-default`. Two of the
            // three tokens were already right and had been since the scope
            // cards were written; the ring is the one that differed, and it
            // is what lets a merged list's two directions tell each other
            // apart before the eye reaches the verb (U8).
            borderColor: staged ? colors.borderStrong : null,
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

    // `.variant-B-temp { border: 1px dashed var(--accent) }` and
    // `.variant-B-temphead { border-bottom: 1px dashed var(--accent) }`.
    //
    // Dashed is the distinction, not decoration: it is what separates this
    // block -- which disappears the moment it is spent -- from the
    // solid-edged cards that persist. Both were solid before and differed
    // only in colour, which is a weaker signal than the label 一次性 beside
    // it is making. Flutter has no dashed `BorderSide`, hence
    // [GbmDashedBorder] / [GbmDashedLine].
    return GbmDashedBorder(
      key: showHead ? const ValueKey<String>('temporary-scope-card') : null,
      color: colors.accent,
      radius: GbmSpacing.radiusSm,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
        ),
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
                            hunkCount > 1
                                ? '臨時選取 · 跨 $hunkCount 個 hunk'
                                : '臨時選取',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: GbmTypography.textXs,
                              fontWeight: FontWeight.bold,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: GbmSpacing.space2),
                        // `.variant-B-once`: outlined and lettered in
                        // --warning over a transparent ground. It shipped as
                        // a GbmBadge at its default neutral kind, which is
                        // the same shape as the +N/-N tallies in the card
                        // head a few pixels above -- and this is the one
                        // thing on screen that says 「這個按下去就沒了」.
                        GbmOutlinedPill(
                          label: '一次性',
                          color: colors.warning,
                          fontWeight: GbmTypography.weightSemibold,
                        ),
                      ],
                    ),
                    GbmButton(
                      label: label,
                      onPressed: onStage,
                      size: GbmButtonSize.sm,
                      kind: staged
                          ? GbmButtonKind.secondary
                          : GbmButtonKind.primary,
                      // Same control, same treatment: this block acts in the
                      // same direction as the card it sits in.
                      borderColor: staged ? colors.borderStrong : null,
                    ),
                  ],
                ),
              ),
            if (showHead) GbmDashedLine(color: colors.accent),
            ...children,
          ],
        ),
      ),
    );
  }
}
