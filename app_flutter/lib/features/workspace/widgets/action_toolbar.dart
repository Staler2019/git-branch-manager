import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/lucide_icon.dart';

/// Spec page 02's numbered item 2: the 38px toolbar row directly under the
/// menu bar. Fetch / Pull / Push as one group with Push carrying the primary
/// emphasis (「三顆同組。Push 為主要樣式。」), then a divider, then Branch /
/// Stash. The spec's own icon choices name what the last two do:
/// `git-branch-plus` is New branch, `inbox` is Stash changes.
///
/// Purely presentational, like [MenuBarRow] and [TabRow] beside it: every
/// action arrives as a plain [VoidCallback] so this widget carries no
/// Riverpod/FFI dependency and is testable without a container (see
/// action_toolbar_test.dart). `workspace_screen.dart` wires all five out of
/// the one `Map<GbmActionId, VoidCallback?>` that the keyboard, the macOS
/// system menu and the in-window menu already dispatch through -- reaching
/// past that map for a "toolbar-only" handler is the exact shape of the bug
/// `workspace_intent_dispatch_parity_test.dart` exists to catch.
///
/// A null callback *is* the disabled state -- there is deliberately no
/// separate `enabled` flag that could disagree with it. Conflict gating
/// therefore arrives for free: `isActionEnabled()` already returns false for
/// all five of these ids mid-sequencer (spec page 07's STATES table,
/// 「三顆停用，改由 banner 提供 Abort / Skip / Continue / Resolve…」), so
/// `_buildActionHandlers()` puts null in the map and these grey out without
/// this file knowing what a conflict is.
class ActionToolbar extends StatelessWidget {
  const ActionToolbar({
    super.key,
    required this.onFetch,
    required this.onPull,
    required this.onPush,
    required this.onBranch,
    required this.onStash,
  });

  /// `Repository -> Fetch`. Null disables the button.
  final VoidCallback? onFetch;

  /// `Repository -> Pull`. Spec P17 wants Alt+click to open a Pull dialog
  /// with the apply mode pre-selected; there is no pull dialog route in
  /// `route_paths.dart`, so only the plain click (「直接用 Preferences 的預設
  /// 套用方式走」) is wired -- a recorded reduction, not an oversight.
  final VoidCallback? onPull;

  /// `Repository -> Push`.
  final VoidCallback? onPush;

  /// `Branch -> New branch…`.
  final VoidCallback? onBranch;

  /// `Branch -> Stash changes…`.
  final VoidCallback? onStash;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      // The same guard MenuBarRow uses, and the one the ledger records
      // TopBar as lacking: five buttons plus a divider do not fit an
      // arbitrarily narrow window, and a RenderFlex overflow is a thrown
      // error in debug/test builds rather than a visual clip. Scrolling
      // keeps every button reachable instead.
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _ToolbarButton(
                    label: 'Fetch',
                    // Spec names `download-cloud`; Lucide renames it
                    // `cloud-download`, which is the copy already bundled.
                    iconName: 'cloud-download',
                    onPressed: onFetch,
                  ),
                  _ToolbarButton(
                    label: 'Pull',
                    iconName: 'arrow-down-to-line',
                    onPressed: onPull,
                  ),
                  _ToolbarButton(
                    label: 'Push',
                    iconName: 'arrow-up-from-line',
                    kind: GbmButtonKind.primary,
                    onPressed: onPush,
                  ),
                  Container(
                    width: 1,
                    height: 16,
                    color: colors.borderSubtle,
                    margin: const EdgeInsets.symmetric(
                      horizontal: GbmSpacing.space1,
                    ),
                  ),
                  _ToolbarButton(
                    label: 'Branch',
                    iconName: 'git-branch-plus',
                    onPressed: onBranch,
                  ),
                  _ToolbarButton(
                    label: 'Stash',
                    iconName: 'inbox',
                    onPressed: onStash,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One `.gbm-btn-sm` in the row, with the 6px gap the mockup puts between
/// them and the icon tinted to match its own kind's foreground.
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.iconName,
    required this.onPressed,
    this.kind = GbmButtonKind.secondary,
  });

  final String label;
  final String iconName;
  final VoidCallback? onPressed;
  final GbmButtonKind kind;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Color foreground = kind == GbmButtonKind.primary
        ? colors.textOnAccent
        : colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GbmButton(
        label: label,
        kind: kind,
        size: GbmButtonSize.sm,
        icon: LucideIcon(
          iconName,
          size: 12,
          color: onPressed == null
              ? foreground.withValues(alpha: 0.45)
              : foreground,
        ),
        onPressed: onPressed,
      ),
    );
  }
}
