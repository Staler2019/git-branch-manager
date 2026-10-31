import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/parsed_diff.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/code_line_metrics.dart';
import '../../../widgets/gbm_icon_button.dart';
import '../../../widgets/gbm_segmented_control.dart';
import '../../../widgets/split_pane.dart';
import '../../diff/diff_block_order.dart';
import '../../diff/diff_full_file_fill.dart';
import '../../diff/diff_list_model.dart';
import '../../diff/diff_scopes.dart';
import '../../diff/scoped_diff_view.dart';
import '../../diff/sync_scroll/sync_segments.dart';
import '../../diff/sync_scroll/sync_scroll_controller.dart';
import '../../diff/sync_scroll/sync_slot_heights.dart';
import '../../diff/sync_scroll/sync_spans.dart';
import '../../diff/widgets/diff_line.dart';
import '../../diff/temporary_scope_provider.dart';

/// Spec P03's 變體 B titlebar switch: how the two sides of one file are laid
/// out below it.
enum WorkingCopyDiffMode {
  /// Left unstaged, right staged, each scrolling on its own -- the shape the
  /// two-column board above it already teaches. The divider between them is
  /// a real [GbmSplitPane] (`wc.diffSides`), for the same reason the board's
  /// own columns are: a visible divider that refuses to move reads as
  /// broken, and every other two-pane surface in the app resizes.
  twoFile,

  /// One column, unstaged above staged. **The default**, and it used to say
  /// "for a narrow window, where two columns of monospace leave nothing
  /// readable in either" -- true as far as it went, and wrong about which
  /// windows it applies to.
  ///
  /// This pane now occupies the right-hand half of the window rather than
  /// its lower half, so splitting it again into two columns would spend the
  /// readable width on exactly the arrangement the round was asked to undo
  /// (「左右不好看檔案內容」). Narrowness is no longer the trigger: the
  /// pane is *always* the narrower of the two axes it could be split on.
  /// [twoFile] is unchanged and one click away.
  unified,
}

/// The Working Copy's diff pane: a titlebar naming the selected file and the
/// `2 file` / `unified` switch, over both sides of that file's diff.
///
/// **Both sides at once.** Before this, the pane showed whichever side the
/// user last clicked and a single `lastDiff` slot held one reply, so staging
/// part of a file left the other side stale and invisible -- the half-staged
/// state the redesign exists to make legible had nowhere to be seen.
/// The longest file the full-file view draws, in lines. Measured, not
/// chosen: on macOS (profile build) 5,000 lines open in 72-77 ms with a
/// scroll p90 of 15-16 ms per frame, inside the 100 ms / 16 ms budget,
/// and 20,000 lines take 530 ms to open and 47-57 ms per frame.
const int kFullFileViewMaxLines = 5000;

class WorkingCopyDiffPane extends StatefulWidget {
  const WorkingCopyDiffPane({
    super.key,
    required this.displayPath,
    required this.unstagedFile,
    required this.stagedFile,
    required this.unstagedLoading,
    required this.stagedLoading,
    this.unstagedTruncated = false,
    this.stagedTruncated = false,
    required this.onStageScope,
    required this.onDiscardScope,
    required this.onTemporaryScopeChanged,
    required this.softWrap,
    this.maxCodeLineChars = 200,
    this.scrollController,
    this.unstagedFullFile,
    this.stagedFullFile,
    this.fullFile = false,
    this.onToggleFullFile,
  });

  /// What the titlebar names. A staged rename is two different paths, so the
  /// caller composes `old → new` rather than this widget guessing which one
  /// to drop.
  final String displayPath;

  final DiffFile? unstagedFile;
  final DiffFile? stagedFile;

  /// Each side's full-context diff, the full-file view's fill source; null
  /// until it lands or while the view is off.
  final DiffFile? unstagedFullFile;
  final DiffFile? stagedFullFile;

  /// `AppPreferences.fullFileViewEnabled`.
  final bool fullFile;

  /// The titlebar's `Full file` button; the same toggle as View → Full file.
  final VoidCallback? onToggleFullFile;
  final bool unstagedLoading;
  final bool stagedLoading;

  /// That side's reply came back refused for being over the core's diff byte
  /// cap. Separate from the `*File` being null, which is the ordinary "this
  /// side has nothing"; `ScopedDiffView` draws its own wording for it.
  final bool unstagedTruncated;
  final bool stagedTruncated;

  /// `staged` says which side the pressed card was on, and so whether the
  /// press stages or unstages.
  final void Function(bool staged, int hunkIndex, List<int> changedLineIndices)
  onStageScope;

  /// Unstaged side only -- discarding rewrites the work tree. Routed through
  /// spec page 06's confirmation dialog by the caller.
  final void Function(int hunkIndex, List<int> changedLineIndices)
  onDiscardScope;

  /// Forwarded from the **unstaged** column only -- see
  /// [temporaryScopeSubmitProvider] for why the staged one does not
  /// register.
  final void Function(void Function()? submit) onTemporaryScopeChanged;

  /// `AppPreferences.softWrapEnabled`, passed straight through to both
  /// sides' [ScopedDiffView].
  final bool softWrap;

  /// `AppPreferences.maxCodeLineChars`: each side's code is cut at this many
  /// CJK character widths ([capCodeWidth]).
  final int maxCodeLineChars;

  /// Attached to the unstaged pane in `2 file` mode and to the single scroll
  /// view in `unified` mode.
  ///
  /// One controller cannot drive two scrollables, so the staged pane's
  /// offset is **not** preserved across a tab switch in `2 file` mode. That
  /// is a deliberate reduction: the draft carries one `diffScrollOffset`,
  /// and inventing a second persisted offset was not part of this round.
  final ScrollController? scrollController;

  @override
  State<WorkingCopyDiffPane> createState() => _WorkingCopyDiffPaneState();
}

class _WorkingCopyDiffPaneState extends State<WorkingCopyDiffPane> {
  /// `unified`, not `twoFile`. Widget state, deliberately not persisted --
  /// see [WorkingCopyDiffMode] for why this default moved.
  /// Ruling: `docs/records/2026-10-04-working-copy-layout.md`
  WorkingCopyDiffMode _mode = WorkingCopyDiffMode.unified;
  final ScrollController _stagedScroll = ScrollController();

  /// Stands in when the caller passed no [WorkingCopyDiffPane.scrollController].
  ///
  /// [ScopedDiffView] needs a real one either way: it is what the vertical
  /// `Scrollbar` tracks, and a `Scrollbar` given none falls back to the
  /// `PrimaryScrollController`, which on this pane is nothing at all.
  final ScrollController _ownedUnstagedScroll = ScrollController();

  ScrollController get _unstagedScroll =>
      widget.scrollController ?? _ownedUnstagedScroll;

  /// One memo per side, keyed on that side's `DiffFile`. Two are needed
  /// rather than one shared: the sides hold different files and a single
  /// memo would thrash between them on every rebuild, which is the one thing
  /// [CodeWidthMemo] exists to stop -- 5,000 lines cost 46ms to measure.
  /// The title bar's own scope counts (U3) go through the same
  /// [splitDiffFileIntoScopes] the cards do -- one function, two memos, so
  /// the chip cannot say a number the list disagrees with. A cache each
  /// because [DiffScopeCache] holds one entry and two files sharing one
  /// would evict each other every build.
  ///
  /// **Corrected in place.** 「one function」 was necessary and was not
  /// sufficient: the cards are split with the *other* side's changed index
  /// lines as hard barriers and this count was not, so on the reported case
  /// -- an untracked file with its middle line staged -- the chip said
  /// 「1 未暫存」 over two Stage cards. Both now go through the same
  /// [DiffBarrierMemo], which is why that memo lives in the pure layer
  /// rather than inside [ScopedDiffView] ([CULT-single-source-of-truth]).
  final DiffScopeCache _unstagedScopes = DiffScopeCache();
  final DiffScopeCache _stagedScopes = DiffScopeCache();
  final DiffBarrierMemo _barriers = DiffBarrierMemo();

  static int _countScopes(
    DiffSide side,
    DiffScopeCache cache,
    IndexBarriers barriers,
  ) => cache
      .scopesOf(side.file, staged: side.staged, barriers: barriers)
      .values
      .fold<int>(0, (int sum, List<DiffScope> scopes) => sum + scopes.length);

  /// U3's two numbers, split exactly the way the merged list is.
  ///
  /// Only `unified` draws them, so the barriers are unconditional here: in
  /// `2 file` the two column heads still say it and this record is never
  /// built at all.
  ({int unstaged, int staged}) _scopeCounts() {
    final List<DiffSide> sides = <DiffSide>[
      (file: widget.unstagedFile, staged: false),
      (file: widget.stagedFile, staged: true),
    ];
    final List<IndexBarriers> barriers = _barriers.barriersFor(sides);
    return (
      unstaged: _countScopes(sides[0], _unstagedScopes, barriers[0]),
      staged: _countScopes(sides[1], _stagedScopes, barriers[1]),
    );
  }

  final CodeWidthMemo _unstagedMemo = CodeWidthMemo();
  final CodeWidthMemo _stagedMemo = CodeWidthMemo();

  double _widthOf(DiffFile? file, CodeWidthMemo memo) =>
      diffFileContentWidth(file, softWrap: widget.softWrap, memo: memo);

  final CjkCharWidthMemo _cjkMemo = CjkCharWidthMemo();

  /// A side's (or `unified`'s) natural width, capped. Null with soft wrap
  /// on, where nothing scrolls sideways and nothing is cut.
  CappedCodeWidth? _capped(double natural) => widget.softWrap
      ? null
      : capCodeWidth(
          naturalWidth: natural,
          maxChars: widget.maxCodeLineChars,
          charWidth: _cjkMemo.widthOf(kDiffCodeTextStyle),
          gutterWidth: kDiffGutterWidth + kDiffLinePaddingX,
        );

  /// What a side is measured for width from: its full diff while that side
  /// is filled, since the fill rows widen it; its -U3 diff otherwise.
  DiffFile? _widthSource({required bool staged}) {
    final DiffFile? full = staged
        ? widget.stagedFullFile
        : widget.unstagedFullFile;
    return widget.fullFile && full != null
        ? full
        : (staged ? widget.stagedFile : widget.unstagedFile);
  }

  /// Whether either side's full diff is longer than
  /// [kFullFileViewMaxLines].
  bool _overCap() =>
      <DiffFile?>[widget.unstagedFullFile, widget.stagedFullFile].any(
        (DiffFile? f) =>
            f != null && diffFileLineCount(f) > kFullFileViewMaxLines,
      );

  /// The fill rows for a view showing [sides] (`false` unstaged, `true`
  /// staged), or null for excerpt mode: the full-file view is off, a full
  /// diff has not landed or disagrees with its -U3 one
  /// ([fullFileFillRows]), or the file is longer than
  /// [kFullFileViewMaxLines].
  ///
  /// Not cached: the pane rebuilds when its inputs change, not per scroll
  /// frame, and [fullFileFillRows] is O(lines) -- 3 ms at 5,000.
  List<DiffFillRow>? _fillFor(List<bool> sides) {
    if (!widget.fullFile) return null;
    final List<DiffFillSource> sources = <DiffFillSource>[
      for (final bool staged in sides)
        (
          excerpt: staged ? widget.stagedFile : widget.unstagedFile,
          full: staged ? widget.stagedFullFile : widget.unstagedFullFile,
          staged: staged,
        ),
    ];
    if (_overCap()) return null;
    return fullFileFillRows(sources);
  }

  /// `2 file`'s shared segments and slot heights (plan: Slice S), and what
  /// they were built from. Rebuilt only when a diff, the fill or the wrap
  /// changes: a new [SyncSlotHeights] forgets every measured height, so a
  /// rebuild per pane build would leave the spacers on estimates.
  ({List<List<int>> segmentOf, SyncSlotHeights heights})? _sync;
  List<Object?> _syncKey = const <Object?>[];

  /// Scope splits for the sync layout. A cache each, apart from the title
  /// bar's: those split with the other side's barriers, these as a lone
  /// `2 file` column does, which is what its view draws.
  final List<DiffScopeCache> _columnScopes = <DiffScopeCache>[
    DiffScopeCache(),
    DiffScopeCache(),
  ];

  ({List<List<int>> segmentOf, SyncSlotHeights heights}) _syncLayout(
    List<List<DiffFillRow>?> fills,
  ) {
    final List<Object?> key = <Object?>[
      widget.unstagedFile,
      widget.stagedFile,
      widget.fullFile ? widget.unstagedFullFile : null,
      widget.fullFile ? widget.stagedFullFile : null,
      fills[0] == null,
      fills[1] == null,
      widget.softWrap,
    ];
    final current = _sync;
    if (current != null &&
        key.length == _syncKey.length &&
        <int>[for (int i = 0; i < key.length; i++) i].every(
          (int i) => identical(key[i], _syncKey[i]) || key[i] == _syncKey[i],
        )) {
      return current;
    }
    _syncKey = key;
    current?.heights.dispose();

    // The blocks each column's view will draw: one source, so no barriers
    // ([DiffBarrierMemo] gives a lone side [IndexBarriers.none]) -- the same
    // function the view calls, with the same inputs.
    final List<ScopedDiffSource> sources = <ScopedDiffSource>[
      _source(staged: false),
      _source(staged: true),
    ];
    final List<List<DiffBlock>> blocks = <List<DiffBlock>>[];
    final List<DiffSide> sides = <DiffSide>[];
    for (int c = 0; c < 2; c++) {
      final DiffSide side = (file: sources[c].file, staged: sources[c].staged);
      sides.add(side);
      blocks.add(
        sources[c].hasContent
            ? orderedDiffBlocks(
                <DiffSide>[side],
                <Map<int, List<DiffScope>>>[
                  _columnScopes[c].scopesOf(side.file, staged: side.staged),
                ],
                fill: fills[c],
              )
            : const <DiffBlock>[],
      );
    }
    final SyncSegments segments = partitionSyncSegments<IndexPosition>(
      <List<SyncSpan<IndexPosition>?>>[
        for (int c = 0; c < 2; c++)
          syncUnitSpans(blocks[c], <DiffSide>[sides[c]]),
      ],
      compareIndexPositions,
    );
    // Each column's own height per segment, estimated the way its view's
    // model estimates its items, until the view measures them.
    final List<List<double>> estimate = <List<double>>[
      for (int c = 0; c < 2; c++)
        () {
          final DiffListModel model = DiffListModel.fromBlocks(
            blocks[c],
            sides: <DiffSide>[sides[c]],
            headings: fills[c] == null,
            metrics: kDiffListEstimate,
            leadingExtents: const <double>[kDiffLeadingEstimate],
            sync: (
              segmentOfUnit: segments.segmentOf[c],
              segmentCount: segments.count,
              spacerExtentOf: (_) => 0,
            ),
          );
          final List<double> run = List<double>.filled(segments.count, 0);
          for (int i = 0; i < model.items.length; i++) {
            run[model.segmentOfItem(i)] += model.extentOf(i);
          }
          return run;
        }(),
    ];
    return _sync = (
      segmentOf: segments.segmentOf,
      heights: SyncSlotHeights.forSegments(
        columns: 2,
        segments: segments.count,
        estimate: (int c, int k) => estimate[c][k],
      ),
    );
  }

  /// `2 file`'s two columns scrolled as one (S4); built with the first
  /// `2 file` build and dropped on leaving it, so re-entering mirrors the
  /// unstaged column's offset afresh.
  SyncScrollController? _syncScroll;
  ScrollController? _syncScrollUnstaged;

  SyncScrollController _syncScrollFor(SyncSlotHeights heights) {
    if (!identical(_syncScrollUnstaged, _unstagedScroll)) _dropSyncScroll();
    _syncScrollUnstaged = _unstagedScroll;
    final SyncScrollController scroll = _syncScroll ??= SyncScrollController(
      <ScrollController>[_unstagedScroll, _stagedScroll],
    );
    return scroll..heights = heights;
  }

  void _dropSyncScroll() {
    _syncScroll?.dispose();
    _syncScroll = null;
  }

  /// `2 file`'s sideways offset, one for both columns (S5a): each column's
  /// own [GbmCodeHScroll] scroller, mirrored like the vertical one.
  final List<ScrollController> _sidewaysScroll = <ScrollController>[
    ScrollController(),
    ScrollController(),
  ];
  late final SyncScrollController _sidewaysSync = SyncScrollController(
    _sidewaysScroll,
  );

  @override
  void dispose() {
    _dropSyncScroll();
    _sidewaysSync.dispose();
    for (final ScrollController c in _sidewaysScroll) {
      c.dispose();
    }
    _sync?.heights.dispose();
    _stagedScroll.dispose();
    _ownedUnstagedScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    // One width for `unified`'s single view, the wider of the two sides.
    final CappedCodeWidth? unifiedCap = _mode == WorkingCopyDiffMode.unified
        ? _capped(
            math.max(
              _widthOf(_widthSource(staged: false), _unstagedMemo),
              _widthOf(_widthSource(staged: true), _stagedMemo),
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TitleBar(
          displayPath: widget.displayPath,
          mode: _mode,
          // U3's replacement for the two column heads, and only where they
          // were removed: in `2 file` the heads still say it, and saying it
          // twice would be [UX-rubric] dimension D's redundancy.
          scopeCounts: _mode == WorkingCopyDiffMode.unified
              ? _scopeCounts()
              : null,
          onModeChanged: (WorkingCopyDiffMode mode) => setState(() {
            if (mode != WorkingCopyDiffMode.twoFile) _dropSyncScroll();
            _mode = mode;
          }),
          fullFile: widget.fullFile,
          tooLarge: widget.fullFile && _overCap(),
          onToggleFullFile: widget.onToggleFullFile,
        ),
        Expanded(
          child: switch (_mode) {
            WorkingCopyDiffMode.twoFile => GbmSplitPane(
              axis: Axis.horizontal,
              spec: GbmLayout.splitterWcDiffSides,
              storageId: 'wc.diffSides',
              children: () {
                final List<List<DiffFillRow>?> fills = <List<DiffFillRow>?>[
                  _fillFor(const <bool>[false]),
                  _fillFor(const <bool>[true]),
                ];
                final sync = _syncLayout(fills);
                final SyncScrollController scroll = _syncScrollFor(
                  sync.heights,
                );
                // One width for both, the wider side's, so the two scroll
                // the same distance sideways.
                final CappedCodeWidth? cap = _capped(
                  math.max(
                    _widthOf(_widthSource(staged: false), _unstagedMemo),
                    _widthOf(_widthSource(staged: true), _stagedMemo),
                  ),
                );
                return <Widget>[
                  for (int c = 0; c < 2; c++)
                    _side(
                      staged: c == 1,
                      fill: fills[c],
                      cap: cap,
                      sync: (
                        column: c,
                        segmentOfUnit: sync.segmentOf[c],
                        heights: sync.heights,
                        scroll: scroll,
                        horizontal: _sidewaysScroll[c],
                        sideways: _sidewaysSync,
                      ),
                    ),
                ];
              }(),
            ),
            // **One view holding both directions**, not two stacked.
            // 「應該是單一 view 檢視 stage/unstage scope and button，而非
            // 還是拆成上下檢視」 -- two views one above the other is what
            // shipped, and it was two columns rotated rather than a merged
            // list. The cards carry their own direction now (U2), the
            // ordering is by index region (U1), and the column heads are
            // gone because there is no column left for them to label (U3).
            //
            // One scroll position over both halves, because this mode's
            // whole point is that they scroll as one column -- and therefore
            // one width, the wider of the two, or the narrower side's rows
            // would stop short of the shared scroll extent.
            WorkingCopyDiffMode.unified => ScopedDiffView(
              sources: <ScopedDiffSource>[
                _source(staged: false),
                _source(staged: true),
              ],
              showColumnHeads: false,
              onTemporaryScopeChanged: widget.onTemporaryScopeChanged,
              softWrap: widget.softWrap,
              verticalController: _unstagedScroll,
              contentWidth: unifiedCap?.totalWidth ?? 0,
              codeClipWidth: unifiedCap?.clipWidth,
              backdrop: colors.surfaceSunken,
              fill: _fillFor(const <bool>[false, true]),
            ),
          },
        ),
      ],
    );
  }

  /// One direction's diff, as a [ScopedDiffSource].
  ///
  /// Every per-side value lives here rather than in the widget that draws
  /// it, which is what lets `unified` hand *both* directions to one
  /// [ScopedDiffView] without either side's callbacks having to know how
  /// many neighbours it has.
  ScopedDiffSource _source({required bool staged}) => ScopedDiffSource(
    title: staged ? 'Staged' : 'Unstaged',
    file: staged ? widget.stagedFile : widget.unstagedFile,
    staged: staged,
    loading: staged ? widget.stagedLoading : widget.unstagedLoading,
    truncated: staged ? widget.stagedTruncated : widget.unstagedTruncated,
    emptyLabel: staged ? 'Nothing staged' : 'Nothing unstaged',
    onStageScope: (int hunkIndex, List<int> lineIndices) =>
        widget.onStageScope(staged, hunkIndex, lineIndices),
    // Discard is a work-tree rewrite, so it exists on the unstaged side
    // only -- there is nothing about a staged line to throw away.
    onDiscardScope: staged ? null : widget.onDiscardScope,
  );

  /// One `2 file` column, its scroll positions synced through [sync].
  Widget _side({
    required bool staged,
    required List<DiffFillRow>? fill,
    required CappedCodeWidth? cap,
    required ScopedDiffSync sync,
  }) {
    return ScopedDiffView(
      sources: <ScopedDiffSource>[_source(staged: staged)],
      onTemporaryScopeChanged: staged ? null : widget.onTemporaryScopeChanged,
      softWrap: widget.softWrap,
      verticalController: staged ? _stagedScroll : _unstagedScroll,
      contentWidth: cap?.totalWidth ?? 0,
      codeClipWidth: cap?.clipWidth,
      backdrop: context.gbmColors.surfaceSunken,
      fill: fill,
      sync: sync,
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.displayPath,
    required this.mode,
    required this.scopeCounts,
    required this.onModeChanged,
    required this.fullFile,
    required this.tooLarge,
    required this.onToggleFullFile,
  });

  final String displayPath;

  /// Whether this file is drawn whole; [tooLarge] when the view is on but
  /// the file is over [kFullFileViewMaxLines] and drawn in excerpts.
  final bool fullFile;
  final bool tooLarge;
  final VoidCallback? onToggleFullFile;
  final WorkingCopyDiffMode mode;

  /// How many cards each direction has, or null when the two column heads
  /// are still saying it themselves (`2 file`). U3.
  final ({int unstaged, int staged})? scopeCounts;

  final ValueChanged<WorkingCopyDiffMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfacePanelRaised,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: <Widget>[
          // Flexible, not Expanded: RenderFlex lays the non-flex children
          // out first, so a path that insists on its full width would push
          // the switch off the end of the bar instead of eliding itself.
          Flexible(
            child: Text(
              displayPath,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          if (scopeCounts != null) ...<Widget>[
            const SizedBox(width: GbmSpacing.space2),
            // One line, both directions, in the same order the list draws
            // them -- 「2 未暫存 · 1 已暫存」. Not a pill per side: two pills
            // here would be the two column heads again, in a narrower place.
            Text(
              '${scopeCounts!.unstaged} 未暫存 · ${scopeCounts!.staged} 已暫存',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
          ],
          const SizedBox(width: GbmSpacing.space2),
          // Disabled with its reason rather than hidden over the cap
          // ([FLU-menu-enabled-is-visual-only]), and not pressed then: this
          // file is drawn in excerpts whatever the preference says.
          GbmIconButton(
            icon: const Icon(Icons.expand, size: 16),
            tooltip: tooLarge ? 'File too large for full view' : 'Full file',
            active: fullFile && !tooLarge,
            onPressed: tooLarge ? null : onToggleFullFile,
          ),
          const SizedBox(width: GbmSpacing.space2),
          GbmSegmentedControl<WorkingCopyDiffMode>(
            value: mode,
            onChanged: onModeChanged,
            options: const <GbmSegmentedOption<WorkingCopyDiffMode>>[
              GbmSegmentedOption<WorkingCopyDiffMode>(
                value: WorkingCopyDiffMode.twoFile,
                label: '2 file',
                icon: Icons.vertical_split,
                showLabel: true,
              ),
              GbmSegmentedOption<WorkingCopyDiffMode>(
                value: WorkingCopyDiffMode.unified,
                label: 'unified',
                icon: Icons.view_stream,
                showLabel: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
