import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// worktree-dialogs-spec.html G8's `ro` field: a `surface-sunken` box with
/// `text-secondary` text and no border, optionally preceded by a label in
/// the P6 field-label style (spec's G3 -- 11px, `text-secondary`, sentence
/// case, no bold/letter-spacing; see `add_worktree_dialog.dart`'s 「分支」
/// label for the same style's first use). [label] is optional because not
/// every `ro` row has one -- `checkout_dialog.dart`'s 「目前」line *is* its
/// own content ("目前 main · 有5 項未提交變更"), while
/// `restore_file_dialog.dart`'s 「檔案」/「還原成」rows put the label above a
/// separate value.
class GbmDialogReadOnlyField extends StatelessWidget {
  const GbmDialogReadOnlyField({super.key, this.label, required this.child});

  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label!,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space3,
            vertical: GbmSpacing.space2,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// worktree-dialogs-spec.html G8's `warn` field: `surface-sunken` + 1px
/// `border-subtle` + a 2px `--warning` left border, r6, pad 8/9 (rounded to
/// the existing `space2`(8) on every side -- 9 has no matching token, the
/// same rounding this round already made for G6/G7's own spec-vs-token
/// gaps). Lifted from `lock_worktree_dialog.dart`'s existing inline
/// Container, which lacked only the warning-coloured left rail.
///
/// The fill and the left rail are two separate `Container`s inside a `Row`,
/// not one `BoxDecoration` with a 3-side `border-subtle` + differently
/// coloured left side -- Flutter's `Border.paint` asserts "A borderRadius
/// can only be given on borders with uniform colors" and throws at paint
/// time for exactly that combination. The outer `Container` carries the
/// uniform `border-subtle` ring and the r6 radius (both legal together);
/// `clipBehavior: Clip.antiAlias` rounds its Row children's corners to
/// match, the same way a CSS `overflow: hidden` would.
class GbmDialogWarnField extends StatelessWidget {
  const GbmDialogWarnField({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(width: 2, color: colors.warning),
          Expanded(
            child: Container(
              color: colors.surfaceSunken,
              padding: const EdgeInsets.all(GbmSpacing.space2),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
