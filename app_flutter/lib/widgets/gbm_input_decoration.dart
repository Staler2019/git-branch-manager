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
///
/// It has **no `errorText` parameter either**, for the same reason one step
/// further on. Material lays the error message out as *subtext below the
/// box*, and the fixed-height wrapper bounds the box and its subtext
/// together -- so an errored field spent the height on the message and
/// painted its outline at **10px** (measured). Callers pass `hasError` to
/// recolour the outline and draw the message themselves, in an external
/// `Text` under the box; that is the spec's own `.fld__hint` shape, and it
/// is the same external-element decision the label above already made.
InputDecoration gbmInputDecoration({
  required GbmColors colors,
  String? hintText,
  bool hasError = false,
  String? suffixText,
  Widget? prefixIcon,
}) {
  OutlineInputBorder outline(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
    borderSide: BorderSide(color: color),
  );
  // A bare `OutlineInputBorder()` carries a bare `BorderSide()`, which is
  // **black, width 1** -- not the theme's border colour. Every state is
  // named explicitly because the resting state of a field is now whichever
  // one its screen leaves it in: Add Worktree's 位置 rests *disabled*.
  final Color resting = hasError ? colors.danger : colors.borderDefault;
  return InputDecoration(
    hintText: hintText,
    suffixText: suffixText,
    prefixIcon: prefixIcon,
    // spec `.box`: `background: var(--gbm-surface-panel)`. Unfilled, the box
    // showed the shell's `surface-panel-raised` straight through, so a field
    // read as flush with the dialog instead of sunken into it.
    filled: true,
    fillColor: colors.surfacePanel,
    // **Not `isDense: true`** -- and the difference is the whole of the
    // painted height. `_RenderDecoration` sizes the box it paints as
    // `min(max(contentHeight, minContainerHeight), maxContainerHeight)`,
    // and `isDense` sets `minContainerHeight` to the text's own height.
    // The `SizedBox` only supplies `maxContainerHeight`, so a dense field
    // painted its natural ~23px outline inside a 30px widget and the box
    // came out visibly shorter than the `GbmButton` beside it (measured on
    // a real macOS screenshot: 23 against the button's 30). Non-dense sets
    // that floor to `kMinInteractiveDimension` (48), so the `min` lands on
    // the wrapper's 30 exactly, for any font -- which is why this is the
    // font-independent fix and tuning `contentPadding` was not.
    //
    // It depends on the `SizedBox` above actually being there: with no
    // upper bound the same expression yields 48. Every caller wraps.
    isDense: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
    border: outline(resting),
    enabledBorder: outline(resting),
    disabledBorder: outline(resting),
    // The spec's `focus` field kind (G8): an accent-coloured outline on
    // focus, which nothing in the app drew before this -- every TextField
    // relied on Material's own default focus ring instead. spec
    // `.box--focus { border-color: var(--gbm-accent); }` changes the colour
    // and nothing else, so the width stays at 1.
    focusedBorder: outline(hasError ? colors.danger : colors.accent),
  );
}

/// The message half of an errored field, drawn *under* the box instead of
/// inside the decoration -- see [gbmInputDecoration]'s comment for why the
/// decoration cannot carry it. Shape is the spec's `.fld__hint` line
/// (11px, under the control), in `danger` rather than `text-tertiary`.
///
/// Returns [SizedBox.shrink] rather than null so a caller can drop it into
/// a `Column` unconditionally; the leading gap is inside the same widget so
/// nothing is spent when there is no message.
Widget gbmFieldError({required GbmColors colors, String? error}) {
  if (error == null || error.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: GbmSpacing.space1),
    child: Text(
      error,
      style: TextStyle(fontSize: GbmTypography.textXs, color: colors.danger),
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
  OutlineInputBorder outline(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: colors.surfacePanel,
    // Dense **here**, unlike the single-line helper: this box has no
    // fixed-height wrapper to bound it, so the non-dense floor of 48 would
    // become a real minimum rather than something the `min` clamps away.
    // Its natural content-driven height is already what a multiline box
    // wants.
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: GbmSpacing.space3,
      vertical: GbmSpacing.space2,
    ),
    border: outline(colors.borderDefault),
    enabledBorder: outline(colors.borderDefault),
    disabledBorder: outline(colors.borderDefault),
    focusedBorder: outline(colors.accent),
  );
}
