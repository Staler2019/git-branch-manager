import 'package:flutter/material.dart';

import '../actions/gbm_action_id.dart';
import '../actions/gbm_shortcuts.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';
import 'gbm_kbd_chip.dart';

/// Shared chrome for every routed dialog (see routing/dialog_route.dart):
/// title bar, scrollable body, optional action row. One shared widget
/// rather than each dialog re-implementing this, since ~30 dialogs (see
/// docs/FEATURES.md) will use it by the time the rewrite reaches parity.
///
/// **No ✕ close button** -- worktree-dialogs-spec.html's G5 draws none, and
/// dialog_escape_dismiss_test.dart pins that Escape already closes every
/// routed dialog (`dialog_route.dart`'s `barrierDismissible: true`, which
/// Flutter's own `_ModalScope` wires to `DismissIntent` for free) as the
/// affordance that stays -- clicking outside the barrier is the other one.
///
/// **`actionId` is optional and additive.** Only a call site with an
/// unambiguous [GbmActionId] (a direct menu-bar entry point, per
/// `_buildActionHandlers()`) passes one; the many dialogs reached only from
/// a context menu, a panel, or with no bound shortcut at all pass none, and
/// draw no chip -- an empty slot, never a fallback of any kind.
class GbmDialogShell extends StatelessWidget {
  const GbmDialogShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.width = 480,
    this.actionId,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final GbmActionId? actionId;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final GbmActionId? boundActionId = actionId;
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final GbmKeyboardShortcut? shortcut = boundActionId == null
        ? null
        : gbmActionShortcuts(isMacOS)[boundActionId];
    return Center(
      // The shadow lives on this outer, colorless DecoratedBox rather than
      // on the Material below -- a DecoratedBox with its own `color` sitting
      // between a Material and a descendant ListTile/InkWell hides that
      // descendant's ink splashes (Flutter's own debugCheckHasMaterial-style
      // "background color or ink splashes may be invisible" assertion,
      // which only ever fires once something in [child] actually renders a
      // ListTile -- nothing did until preferences_dialog_test.dart, the
      // first test to pump a dialog whose body uses CheckboxListTile). The
      // panel's fill color now lives directly on Material itself instead, so
      // Material is the nearest colored ancestor with nothing opaque
      // between it and any ListTile in [child].
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GbmSpacing.radiusLg),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: colors.surfaceOverlay,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GbmSpacing.space4,
                  GbmSpacing.space4,
                  GbmSpacing.space3,
                  GbmSpacing.space2,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: GbmTypography.textLg,
                          fontWeight: GbmTypography.weightSemibold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (shortcut != null) ...<Widget>[
                      const SizedBox(width: GbmSpacing.space2),
                      GbmKbdChip(label: shortcut.displayLabel),
                    ],
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GbmSpacing.space4,
                  ),
                  child: child,
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(GbmSpacing.space4),
                  // OverflowBar renders exactly like the plain end-aligned
                  // Row this replaced when actions fit (spacing: 0, so no
                  // gap beyond what callers already insert as SizedBox
                  // children) -- it only switches to a vertical column,
                  // avoiding a RenderFlex overflow, once a long enough
                  // action label no longer fits [width]. Neither of
                  // CheckoutRecoveryDialogContent/DeleteBranchRecoveryDialogContent's
                  // current labels (`recovery_choice_copy.dart`) are long
                  // enough to trip this by themselves; see
                  // gbm_dialog_shell_test.dart for the measured threshold.
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    overflowSpacing: GbmSpacing.space2,
                    children: actions,
                  ),
                )
              else
                const SizedBox(height: GbmSpacing.space4),
            ],
          ),
        ),
      ),
    );
  }
}
