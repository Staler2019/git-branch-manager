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
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

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
    );
  }
}

/// P19 detail column: one labelled value.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
              fontFamily: mono ? 'monospace' : null,
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
