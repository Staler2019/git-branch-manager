import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// The uppercase label above a sidebar section (TAGS / STASH).
///
/// One widget rather than a copy per section: the headers must look
/// identical, and P02-14 rule 5 (「沒有命中的段落整段隱藏，不留空標題」) means
/// each one appears and disappears independently, so a drift between them
/// would only ever show up in one query's worth of rows.
///
/// With [onToggle] it is also the section's collapse control (ruling
/// 2026-10-18, folder rules): a leading chevron, the whole row tappable, and
/// [count] after the label so a collapsed section still says what it holds.
/// The chevron is `BranchFolderRow`'s, so the sidebar has one collapse
/// vocabulary. Left inset, chevron gap and count style are the design spec's
/// I1–I3 (`docs/claude-design-demo/sidebar-selection-collapse-spec.html`).
///
/// BRANCHES is deliberately **not** built from this: it sits directly under
/// the repository button rather than after a preceding section, carries the
/// pending-cleanup badge and two icon buttons, and takes a larger top inset
/// for both reasons.
class SidebarSectionLabel extends StatelessWidget {
  const SidebarSectionLabel(
    this.label, {
    super.key,
    this.count,
    this.isExpanded = true,
    this.onToggle,
  });

  final String label;

  /// Rows in the section -- the filtered count while a query is in force.
  final int? count;

  /// Drawn state, which is not always the remembered one: a query forces
  /// the section open without touching what the user chose.
  final bool isExpanded;

  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final TextStyle style = TextStyle(
      fontSize: GbmTypography.textXs,
      fontWeight: GbmTypography.weightSemibold,
      color: colors.textTertiary,
      letterSpacing: 0.5,
    );
    final VoidCallback? onToggle = this.onToggle;
    final int? count = this.count;
    final Widget row = Padding(
      padding: EdgeInsets.fromLTRB(
        onToggle == null ? GbmSpacing.space3 : GbmSpacing.space2,
        GbmSpacing.space2,
        GbmSpacing.space1,
        GbmSpacing.space1,
      ),
      child: Row(
        children: <Widget>[
          if (onToggle != null) ...<Widget>[
            Icon(
              isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 18,
              color: colors.textSecondary,
            ),
            const SizedBox(width: GbmSpacing.space1),
          ],
          Text(label, style: style),
          if (count != null) ...<Widget>[
            const SizedBox(width: GbmSpacing.space1),
            Text(
              '$count',
              style: style.copyWith(fontWeight: GbmTypography.weightRegular),
            ),
          ],
        ],
      ),
    );
    if (onToggle == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: row),
    );
  }
}
