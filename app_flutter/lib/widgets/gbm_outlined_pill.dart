import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A `radius-full` pill with a 1px ring, drawn in whatever colour the caller
/// names.
///
/// **Not a [GbmBadge] with a border bolted on.** `GbmBadge` is the `+N`/`-N`
/// tally shape -- a filled, border-less, mono pill -- and these are two
/// different things that happen to be round: 變體 B models them as two
/// separate classes and so does this file.
///
///   .variant-B-once { padding: 0 var(--space-2);
///                     border: 1px solid var(--warning);
///                     border-radius: var(--radius-full);
///                     font-size: var(--text-xs);
///                     font-weight: var(--weight-semibold);
///                     color: var(--warning); }
///   .variant-B-chip { padding: 1px var(--space-2);
///                     background: var(--surface-panel-raised);
///                     border: 1px solid var(--border-subtle);
///                     border-radius: var(--radius-full);
///                     font-size: var(--text-xs);
///                     color: var(--text-tertiary); }
///
/// Public rather than private to `scoped_diff_view.dart`, where both callers
/// live today, for one reason that is not "it might be reused": a private
/// class is invisible to a test, and the only assertion left would be to
/// walk a `Container`'s `BoxDecoration` -- which is how a token gets pinned
/// by shape instead of by identity.
class GbmOutlinedPill extends StatelessWidget {
  const GbmOutlinedPill({
    super.key,
    required this.label,
    required this.color,
    this.borderColor,
    this.background,
    this.fontWeight,
    this.verticalPadding = 0,
  });

  /// The text, and -- unless [borderColor] says otherwise -- the ring too.
  final String label;
  final Color color;

  /// Defaults to [color], which is `.variant-B-once`'s case: one warning
  /// colour for both the letters and the outline.
  final Color? borderColor;

  /// Null is a transparent ground, which is `.variant-B-once`'s case.
  final Color? background;

  final FontWeight? fontWeight;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: GbmSpacing.space2,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor ?? color),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusFull),
      ),
      child: Text(
        label,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: GbmTypography.textXs,
          fontWeight: fontWeight,
          color: color,
        ),
      ),
    );
  }
}
