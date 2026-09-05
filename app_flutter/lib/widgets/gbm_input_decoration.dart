import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// `.gbm-input` (docs/design/tokens-reference.md:111): radius 6, padding
/// 0/12 horizontal. Height 30 is **not** produced by this decoration --
/// wrap the `TextField` itself in `SizedBox(height: GbmSpacing.inputHeight,
/// child: TextField(decoration: gbmInputDecoration(...)))`, the same idiom
/// [GbmButton] uses for its own fixed h24/h30. Tuning `contentPadding`
/// against font metrics to land on an exact pixel height would drift
/// between the test font and the app's real one
/// ([TEST-canvas-is-800x600]), where a `SizedBox` does not.
///
/// Every dialog before this helper built its own bare
/// `InputDecoration(isDense: true, border: OutlineInputBorder())` inline --
/// Material's default radius (4) and no focus treatment at all. This is the
/// one shared definition; a new dialog reaches for it instead of writing a
/// fifth copy.
///
/// Deliberately has **no** `labelText` parameter. Material's floating label
/// needs room above the input line that a fixed 30px `SizedBox` does not
/// have -- measured: with `labelText` set, the label paints from y=14.9
/// while the `SizedBox` itself starts at y=20, so the label renders outside
/// its own box and overlaps the value text's first ~6px. A dialog field's
/// label is the P6 external `Text` above the box (`add_worktree_dialog.dart`'s
/// '位置'/'分支'/'來源', spec's `fld__label` -- see the spec's own "Proposed"
/// markup at worktree-dialogs-spec.html:613/618, which draws exactly this
/// shape for '新分支名稱'/'目標路徑'), never `InputDecoration.labelText`.
InputDecoration gbmInputDecoration({
  required GbmColors colors,
  String? hintText,
  String? errorText,
  String? suffixText,
  Widget? prefixIcon,
}) {
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
  );
  return InputDecoration(
    hintText: hintText,
    errorText: errorText,
    suffixText: suffixText,
    prefixIcon: prefixIcon,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
    border: border,
    enabledBorder: border,
    // The spec's `focus` field kind (G8): an accent-coloured outline on
    // focus, which nothing in the app drew before this -- every TextField
    // relied on Material's own default focus ring instead.
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.accent, width: 1.5),
    ),
  );
}

/// Sibling for the three `maxLines > 1` fields (merge/create-tag/
/// cherry-pick's commit-message-shaped boxes): same padding/radius/focus
/// treatment, but no fixed-height contract -- a multiline box has to grow
/// with its content, which [gbmInputDecoration]'s `SizedBox`-wrapping
/// convention would clip. No `labelText` here either, for the reason
/// documented on [gbmInputDecoration] -- none of its three callers used it.
InputDecoration gbmMultilineInputDecoration({
  required GbmColors colors,
  String? hintText,
}) {
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
  );
  return InputDecoration(
    hintText: hintText,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: GbmSpacing.space3,
      vertical: GbmSpacing.space2,
    ),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.accent, width: 1.5),
    ),
  );
}
