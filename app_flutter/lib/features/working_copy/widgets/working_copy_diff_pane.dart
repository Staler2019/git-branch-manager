import 'package:flutter/material.dart';

import '../../../data/models/parsed_diff.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_segmented_control.dart';
import '../../diff/scoped_diff_view.dart';

/// Spec P03's 變體 B titlebar switch: how the two sides of one file are laid
/// out below it.
enum WorkingCopyDiffMode {
  /// Left unstaged, right staged, each scrolling on its own -- the shape the
  /// two-column board above it already teaches.
  twoFile,

  /// One column, unstaged above staged. For a narrow window, where two
  /// columns of monospace leave nothing readable in either.
  unified,
}

/// The Working Copy's diff pane: a titlebar naming the selected file and the
/// `2 file` / `unified` switch, over both sides of that file's diff.
///
/// **Both sides at once.** Before this, the pane showed whichever side the
/// user last clicked and a single `lastDiff` slot held one reply, so staging
/// part of a file left the other side stale and invisible -- the half-staged
/// state the redesign exists to make legible had nowhere to be seen.
class WorkingCopyDiffPane extends StatefulWidget {
  const WorkingCopyDiffPane({
    super.key,
    required this.displayPath,
    required this.unstagedFile,
    required this.stagedFile,
    required this.unstagedLoading,
    required this.stagedLoading,
    required this.onStageScope,
    required this.onDiscardScope,
    this.scrollController,
  });

  /// What the titlebar names. A staged rename is two different paths, so the
  /// caller composes `old → new` rather than this widget guessing which one
  /// to drop.
  final String displayPath;

  final DiffFile? unstagedFile;
  final DiffFile? stagedFile;
  final bool unstagedLoading;
  final bool stagedLoading;

  /// `staged` says which side the pressed card was on, and so whether the
  /// press stages or unstages.
  final void Function(bool staged, int hunkIndex, List<int> changedLineIndices)
  onStageScope;

  /// Unstaged side only -- discarding rewrites the work tree. Routed through
  /// spec page 06's confirmation dialog by the caller.
  final void Function(int hunkIndex, List<int> changedLineIndices)
  onDiscardScope;

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
  WorkingCopyDiffMode _mode = WorkingCopyDiffMode.twoFile;
  final ScrollController _stagedScroll = ScrollController();

  @override
  void dispose() {
    _stagedScroll.dispose();
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
          onModeChanged: (WorkingCopyDiffMode mode) =>
              setState(() => _mode = mode),
        ),
        Expanded(
          child: switch (_mode) {
            WorkingCopyDiffMode.twoFile => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    controller: widget.scrollController,
                    child: _side(staged: false),
                  ),
                ),
                Container(width: 1, color: colors.borderDefault),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _stagedScroll,
                    child: _side(staged: true),
                  ),
                ),
              ],
            ),
            WorkingCopyDiffMode.unified => SingleChildScrollView(
              controller: widget.scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _side(staged: false),
                  Container(height: 1, color: colors.borderDefault),
                  _side(staged: true),
                ],
              ),
            ),
          },
        ),
      ],
    );
  }

  Widget _side({required bool staged}) => ScopedDiffView(
    title: staged ? 'Staged' : 'Unstaged',
    file: staged ? widget.stagedFile : widget.unstagedFile,
    staged: staged,
    loading: staged ? widget.stagedLoading : widget.unstagedLoading,
    emptyLabel: staged ? 'Nothing staged' : 'Nothing unstaged',
    onStageScope: (int hunkIndex, List<int> lineIndices) =>
        widget.onStageScope(staged, hunkIndex, lineIndices),
    // Discard is a work-tree rewrite, so it exists on the unstaged side
    // only -- there is nothing about a staged line to throw away.
    onDiscardScope: staged ? null : widget.onDiscardScope,
  );
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.displayPath,
    required this.mode,
    required this.onModeChanged,
  });

  final String displayPath;
  final WorkingCopyDiffMode mode;
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
