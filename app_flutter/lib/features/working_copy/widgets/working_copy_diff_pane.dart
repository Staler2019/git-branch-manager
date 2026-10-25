import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/parsed_diff.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/code_line_metrics.dart';
import '../../../widgets/gbm_code_hscroll.dart';
import '../../../widgets/gbm_icon_button.dart';
import '../../../widgets/gbm_segmented_control.dart';
import '../../../widgets/split_pane.dart';
import '../../diff/diff_full_file_fill.dart';
import '../../diff/diff_scopes.dart';
import '../../diff/scoped_diff_view.dart';
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
  /// [GbmCodeScrollWell] needs a real one either way: it is what the vertical
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

  @override
  void dispose() {
    _stagedScroll.dispose();
    _ownedUnstagedScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

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
          onModeChanged: (WorkingCopyDiffMode mode) =>
              setState(() => _mode = mode),
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
              children: <Widget>[_side(staged: false), _side(staged: true)],
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
              contentWidth: math.max(
                _widthOf(_widthSource(staged: false), _unstagedMemo),
                _widthOf(_widthSource(staged: true), _stagedMemo),
              ),
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

  /// One `2 file` column: its own scroll position and its own width.
  Widget _side({required bool staged}) => ScopedDiffView(
    sources: <ScopedDiffSource>[_source(staged: staged)],
    onTemporaryScopeChanged: staged ? null : widget.onTemporaryScopeChanged,
    softWrap: widget.softWrap,
    verticalController: staged ? _stagedScroll : _unstagedScroll,
    contentWidth: staged
        ? _widthOf(_widthSource(staged: true), _stagedMemo)
        : _widthOf(_widthSource(staged: false), _unstagedMemo),
    backdrop: context.gbmColors.surfaceSunken,
    fill: _fillFor(<bool>[staged]),
  );
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
