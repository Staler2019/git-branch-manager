import 'package:flutter/material.dart';

import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';

/// Spec page 19 樣板規則 2's four-segment toolbar:
/// 「工具列固定四段：主要建立動作（primary）、批次維護動作（ghost）、分隔線、
/// 跳出去的動作；右端固定是 filter。破壞性動作不放工具列，只在明細區或右鍵。」
///
/// **What is fixed is the order, not the occupancy.** A read-only panel
/// (blame, line-history) has no 主要建立動作 and leaves [primary] empty; the
/// segment then draws nothing at all rather than a placeholder. Reading the
/// rule the other way is how every read-only panel ends up growing a button
/// the spec never asked for.
///
/// **No destructive action belongs in any of these segments.** Rule 2 sends
/// those to the detail action row instead — see `PanelDetailActions`. The
/// one boundary this repo draws: 破壞性 means *destroys work the user cannot
/// get back*, so `Drop` moves and `Pop` (recoverable via the reflog) stays,
/// as do the escape hatches `Abort` and `Reset`, which restore a prior state
/// rather than destroying anything.
@immutable
class PanelToolbarSpec {
  const PanelToolbarSpec({
    this.primary = const <Widget>[],
    this.maintenance = const <Widget>[],
    this.external = const <Widget>[],
    this.filter,
  });

  /// 主要建立動作 — normally one [GbmButtonKind.primary] button.
  final List<Widget> primary;

  /// 批次維護動作 — normally [GbmButtonKind.ghost] buttons.
  final List<Widget> maintenance;

  /// 跳出去的動作 — the ones that leave the panel (open a terminal, jump to
  /// a commit, compare).
  final List<Widget> external;

  /// Pinned to the toolbar's right end. Normally a `PanelFilterField`.
  final Widget? filter;
}

/// The 分隔線 between the maintenance and external segments.
///
/// Its own type rather than a bare [VerticalDivider] so a test can ask
/// whether it was drawn: it appears only when it actually separates two
/// occupied segments, because a divider with nothing on one side of it
/// separates nothing.
class PanelToolbarSeparator extends StatelessWidget {
  const PanelToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
      color: context.gbmColors.borderSubtle,
    );
  }
}

/// Lays a [PanelToolbarSpec] out in the spec's order. Used by
/// `GbmPanelTabShell`; separate so its geometry can be asserted directly.
class PanelToolbarRow extends StatelessWidget {
  const PanelToolbarRow({super.key, required this.spec});

  final PanelToolbarSpec spec;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool separates =
        spec.external.isNotEmpty &&
        (spec.primary.isNotEmpty || spec.maintenance.isNotEmpty);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          ..._spaced(<Widget>[...spec.primary, ...spec.maintenance]),
          // The separator carries its own margins, and it is drawn exactly
          // when there is something on both sides of it — which is also the
          // only case where the external segment needs a gap in front of it.
          if (separates) const PanelToolbarSeparator(),
          ..._spaced(spec.external),
          const Spacer(),
          ?spec.filter,
        ],
      ),
    );
  }

  /// Inserts the standard gap *between* widgets, never before the first one:
  /// a leading gap would push the leftmost action off the toolbar's edge,
  /// and an empty segment must contribute no width at all.
  List<Widget> _spaced(List<Widget> items) {
    return <Widget>[
      for (final (int index, Widget item) in items.indexed) ...<Widget>[
        if (index > 0) const SizedBox(width: GbmSpacing.space2),
        item,
      ],
    ];
  }
}
