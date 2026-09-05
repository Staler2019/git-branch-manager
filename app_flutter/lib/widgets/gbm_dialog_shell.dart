import 'package:flutter/material.dart';

import '../actions/gbm_action_id.dart';
import '../actions/gbm_shortcuts.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';
import 'gbm_button.dart';
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
///
/// **G6** matches the shell to worktree-dialogs-spec.html's Shell/Title bar
/// rows: `surfacePanelRaised` fill (not `surfaceOverlay`, a genuinely
/// different colour, not a rounding), a 1px `borderDefault` around the
/// whole shell, and a `borderSubtle` line under the title bar. The title
/// text is [GbmTypography.dialogTitleText] (13, spec's literal number, not
/// rounded to the pre-existing 13.5px `textBase`).
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
          border: Border.all(color: colors.borderDefault),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: colors.surfacePanelRaised,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Its own bottom border, per the spec's `.mkbar` title-bar row
              // -- a transparent-background Container (no `color`) so it
              // draws only the border stroke and does not repeat the "hides
              // ink splashes" hazard the outer shadow Container's own
              // comment records; nothing under it is an InkWell.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: GbmSpacing.space4,
                  vertical: GbmSpacing.space3,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: GbmTypography.dialogTitleText,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GbmSpacing.space4,
                    vertical: GbmSpacing.space3,
                  ),
                  // G7: its own border-top, per the spec's "Action row" row
                  // -- independent of the title bar's border-bottom above.
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.borderSubtle)),
                  ),
                  // GbmButtonSizeScope makes every action-row button
                  // .gbm-btn-sm by default without touching each dialog's
                  // own action list -- see that class's doc comment.
                  child: GbmButtonSizeScope(
                    size: GbmButtonSize.sm,
                    // `spacing:` is what used to be missing -- callers
                    // previously inserted their own SizedBox(width: space2)
                    // between buttons because OverflowBar's own gap
                    // defaulted to 0. It now owns that gap itself, so a
                    // caller-side SizedBox would double it; see the sweep
                    // across dialog files in this same commit.
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: GbmSpacing.space2,
                      overflowAlignment: OverflowBarAlignment.end,
                      overflowSpacing: GbmSpacing.space2,
                      children: actions,
                    ),
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
