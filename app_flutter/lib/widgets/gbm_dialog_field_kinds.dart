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
          // textSecondary, per the spec's own citation for `ro` -- a Text
          // child that needs a different colour (e.g. a path drawn in
          // textPrimary) still wins by setting its own `style:`, since
          // Text merges its explicit style over this ambient default.
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
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
///
/// The `Row` is wrapped in `IntrinsicHeight`, not bare. Every real call
/// site sits inside a `Column` (a dialog body), and `RenderFlex` hands its
/// non-flex children *unbounded* max-height along the main axis regardless
/// of whether the Column itself is height-bounded -- that is how a Column
/// can overflow at all. `CrossAxisAlignment.stretch` demands a *bounded*
/// cross-axis constraint to stretch into, so an un-wrapped Row threw
/// "BoxConstraints forces an infinite height" the moment this widget was
/// mounted inside an actual dialog rather than the isolated `Center` the
/// widget's own first-draft test used ([TEST-fixture-cannot-disagree]
/// shape 4 -- a fixture that supplies bounded constraints by construction
/// cannot see a widget that only works under bounded constraints).
/// `IntrinsicHeight` measures the Row's children's own intrinsic height
/// first and hands the Row a tight, finite constraint derived from that --
/// the standard fix for "stretch two unequal-height children to match"
/// with no ambient bound to stretch into.
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
      child: IntrinsicHeight(
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
      ),
    );
  }
}
