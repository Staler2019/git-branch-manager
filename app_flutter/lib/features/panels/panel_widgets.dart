import 'package:flutter/material.dart';

import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_row.dart';

/// The two pieces every spec page 19 panel repeats: a two-line list row and
/// a labelled detail field.
///
/// P19's rule is that the twelve panels "只換欄位不換造型" — swap the fields,
/// keep the form. [GbmPanelTabShell] owns the outer form; these own the
/// inner one, so a new panel supplies strings rather than re-deriving a row
/// height or a label style. Both were extracted from `WorktreesPanel`, P19's
/// reference instance, after the second and third panels copied them
/// verbatim.

/// Spec page 19 樣板規則 4's fixed label column: 「78px 標籤 + 值」.
///
/// A literal from the spec, not a derived measurement, which is why it is a
/// named constant here rather than a number inside one widget's build.
const double kPanelDetailLabelWidth = 78;

/// P19 list column: a title over a dimmer subtitle.
///
/// The height is deliberately not [GbmSpacing.rowHeightComfortable]: that is
/// sized for one line, and two stacked lines overflow it by ~2px — caught by
/// a widget test on the reference instance rather than shipping as a clipped
/// second line.
class PanelListRow extends StatelessWidget {
  const PanelListRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.icon,
    this.badge,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Leading status glyph, normally a [LucideIcon]. P19's mockup names three
  /// for `manage-worktrees` (`folder-git-2`, `git-commit-horizontal` for a
  /// detached HEAD, a warning-coloured `alert-triangle` for a path that is
  /// gone) and names none for the other eleven panels, which is why this is
  /// optional rather than required: a panel whose rows carry no status has
  /// no glyph the spec would have it draw.
  final Widget? icon;

  /// Trailing chip, normally a [GbmBadge] — `current` / `路徑不存在` in the
  /// mockup. Pinned to the row's right edge.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      selected: selected,
      onTap: onTap,
      height: GbmSpacing.rowHeightComfortable + GbmSpacing.space3,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              icon!,
              const SizedBox(width: GbmSpacing.space2),
            ],
            // Expanded, not a bare child: the icon and badge are non-flex,
            // and RenderFlex gives them their intrinsic width first, so the
            // text block is the one that has to yield
            // ([FLU-renderflex-non-flex-first]).
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textPrimary,
                      fontWeight: GbmTypography.weightMedium,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: colors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (badge != null) ...<Widget>[
              const SizedBox(width: GbmSpacing.space2),
              badge!,
            ],
          ],
        ),
      ),
    );
  }
}

/// P19 detail column: one labelled value.
///
/// Spec page 19 樣板規則 4: 「右明細一律是 **78px 標籤 + 值** 的定義列表，
/// 值可選取複製」. The label occupies a fixed [kPanelDetailLabelWidth]
/// column and the value begins exactly at its right edge, so every field in
/// every one of the twelve panels lines its values up on one axis. It was a
/// stacked `Column` (label above value) until
/// feat/p19-panel-template-conformance, which is a different shape wearing
/// the same fields.
///
/// [SelectableText], not [Text]: a detail pane exists to be read *and*
/// copied — a remote URL or an oid is usually wanted somewhere else.
class PanelDetailField extends StatelessWidget {
  const PanelDetailField({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;

  /// Monospace for values whose characters line up or are compared by eye:
  /// paths, oids, URLs.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: GbmSpacing.space3),
      child: Row(
        // The label aligns to the value's *first* line, not to the centre of
        // a value that wrapped to several.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: kPanelDetailLabelWidth,
            child: Text(
              label,
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
          ),
          // Expanded, not a bare child: RenderFlex lays out non-flex children
          // first, so the fixed label column plus an unbounded value overflows
          // before any flex could rescue it.
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The scrolling container a P19 detail column's [PanelDetailField]s sit in.
class PanelDetailColumn extends StatelessWidget {
  const PanelDetailColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GbmSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// P19 樣板規則 4, second half: 「動作列在明細底部，danger 靠右」.
///
/// The split into [actions] and [dangerActions] is what enforces the rule:
/// this widget owns the spacer between them, so "danger is on the right" is
/// structural rather than a convention each of the twelve panels has to
/// remember to follow by ordering a flat list correctly.
///
/// It is a plain widget with no scroll behaviour of its own, so it can sit
/// at the bottom of *either* detail shape — a [PanelDetailColumn] of fields,
/// or the diff-shaped detail that five of the twelve panels use instead.
/// [GbmPanelTabShell] is what places it, for the same reason.
class PanelDetailActions extends StatelessWidget {
  const PanelDetailActions({
    super.key,
    this.actions = const <Widget>[],
    this.dangerActions = const <Widget>[],
  });

  /// Ordinary actions, laid out from the left.
  final List<Widget> actions;

  /// Destructive actions, pinned to the right end. Spec page 19 rule 2 keeps
  /// these out of the toolbar entirely; this is where they go instead.
  final List<Widget> dangerActions;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space2,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          for (final (int index, Widget action) in actions.indexed) ...<Widget>[
            if (index > 0) const SizedBox(width: GbmSpacing.space2),
            action,
          ],
          const Spacer(),
          for (final (int index, Widget action) in dangerActions.indexed) ...[
            if (index > 0) const SizedBox(width: GbmSpacing.space2),
            action,
          ],
        ],
      ),
    );
  }
}

/// The "this panel has nothing in it" state for a P19 list column. Spelling
/// it out beats an empty pane, which reads as a rendering bug.
class PanelEmptyList extends StatelessWidget {
  const PanelEmptyList({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          fontSize: GbmTypography.textSm,
          color: context.gbmColors.textTertiary,
        ),
      ),
    );
  }
}
