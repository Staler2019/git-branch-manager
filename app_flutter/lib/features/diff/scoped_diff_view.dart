import 'package:flutter/material.dart';

import '../../data/models/parsed_diff.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import 'diff_scopes.dart';
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
/// This widget does not scroll. Both callers put it inside their own scroll
/// view -- `2 file` mode needs two independent ones and `unified` needs one
/// shared one, and a widget that scrolled itself could not be stacked.
class ScopedDiffView extends StatelessWidget {
  const ScopedDiffView({
    super.key,
    required this.title,
    required this.file,
    required this.staged,
    required this.onStageScope,
    this.onDiscardScope,
    this.emptyLabel = 'No changes',
    this.loading = false,
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

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final DiffFile? diffFile = file;
    final Map<int, List<DiffScope>> byHunk = diffFile == null
        ? const <int, List<DiffScope>>{}
        : splitDiffFileIntoScopes(diffFile);
    final int scopeCount = byHunk.values.fold<int>(
      0,
      (int sum, List<DiffScope> scopes) => sum + scopes.length,
    );

    // Cards are numbered per file, not per hunk, so 變更 N is unique in the
    // column and a user can say "the third one" without naming a hunk.
    int ordinal = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ColumnHead(title: title, staged: staged, scopeCount: scopeCount),
        if (loading)
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
          _placeholder(colors, emptyLabel)
        else if (diffFile.binary)
          _placeholder(colors, '${diffFile.displayPath} (binary file)')
        else if (diffFile.hunks.isEmpty)
          _placeholder(colors, emptyLabel)
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (
                    int hunkIndex = 0;
                    hunkIndex < diffFile.hunks.length;
                    hunkIndex++
                  ) ...<Widget>[
                    _HunkHeading(hunk: diffFile.hunks[hunkIndex]),
                    for (final DiffSegment segment in hunkSegments(
                      diffFile.hunks[hunkIndex],
                      byHunk[hunkIndex] ?? const <DiffScope>[],
                      firstOrdinal: ordinal,
                    ))
                      switch (segment) {
                        DiffGapSegment() => _GapBlock(
                          hunk: diffFile.hunks[hunkIndex],
                          lineIndices: segment.lineIndices,
                          staged: staged,
                        ),
                        DiffScopeSegment(:final DiffScope scope) => _ScopeCard(
                          hunk: diffFile.hunks[hunkIndex],
                          scope: scope,
                          // Read before the loop below bumps it, so the card
                          // and the numbering agree.
                          ordinal: ordinal++,
                          staged: staged,
                          onStage: () =>
                              onStageScope(hunkIndex, scope.changedLineIndices),
                          onDiscard: onDiscardScope == null
                              ? null
                              : () => onDiscardScope!(
                                  hunkIndex,
                                  scope.changedLineIndices,
                                ),
                        ),
                      },
                  ],
                ],
              ),
            ),
          ),
      ],
    );
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
    required this.lineIndices,
    required this.staged,
  });

  final DiffHunk hunk;
  final List<int> lineIndices;
  final bool staged;

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
            for (final int index in lineIndices)
              DiffLineView(line: hunk.lines[index], staged: staged),
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
    required this.onStage,
    required this.onDiscard,
  });

  final DiffHunk hunk;
  final DiffScope scope;
  final int ordinal;
  final bool staged;
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
              onStage: onStage,
            ),
            for (final int index in scope.lineIndices)
              DiffLineView(
                line: hunk.lines[index],
                staged: staged,
                selectionCount: moving,
                onStageLine: onStage,
                onDiscardLine: onDiscard,
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
    required this.onStage,
  });

  final int ordinal;
  final DiffScope scope;
  final bool staged;
  final String label;
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
            onPressed: onStage,
            size: GbmButtonSize.sm,
            kind: staged ? GbmButtonKind.secondary : GbmButtonKind.primary,
          ),
        ],
      ),
    );
  }
}
