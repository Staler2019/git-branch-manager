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
/// BRANCHES is deliberately **not** built from this: it sits directly under
/// the repository button rather than after a preceding section, carries the
/// pending-cleanup badge and two icon buttons, and takes a larger top inset
/// for both reasons.
class SidebarSectionLabel extends StatelessWidget {
  const SidebarSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GbmSpacing.space3,
        GbmSpacing.space2,
        GbmSpacing.space1,
        GbmSpacing.space1,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: GbmTypography.textXs,
          fontWeight: GbmTypography.weightSemibold,
          color: colors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
