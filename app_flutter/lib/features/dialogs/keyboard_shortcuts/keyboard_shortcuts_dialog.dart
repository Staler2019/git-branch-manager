import 'package:flutter/material.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../actions/gbm_menu_model.dart';
import '../../../actions/gbm_shortcuts.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_kbd_chip.dart';

/// Help → Keyboard shortcuts (Ctrl/Cmd+/).
///
/// Spec page 04's stated intent is "每個動作的選單路徑與 shortcut" -- so each
/// row shows the menu path (`Repository → Push`) next to the key, and the
/// whole table is derived from [gbmMenus] and [gbmActionShortcuts] rather
/// than typed out.
///
/// It previously listed seven hardcoded strings ('Refresh — R', 'Stage file
/// — S', …) that matched neither the menu labels nor the bindings actually
/// registered in `WorkspaceActionShortcuts`; a hand-maintained copy of a
/// table that already exists in code can only drift.
class KeyboardShortcutsDialogContent extends StatelessWidget {
  const KeyboardShortcutsDialogContent({super.key});

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final Map<GbmActionId, GbmKeyboardShortcut> shortcuts = gbmActionShortcuts(
      isMacOS,
    );

    return GbmDialogShell(
      title: 'Keyboard Shortcuts',
      actionId: GbmActionId.helpKeyboardShortcuts,
      width: 560,
      child: SizedBox(
        height: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final GbmMenuModel menu in gbmMenus)
                ..._menuRows(context, menu, shortcuts, colors),
              const SizedBox(height: GbmSpacing.space2),
              Text(
                'Ctrl is Cmd on macOS. Items without a key are reachable from '
                'the menu bar only.',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One menu's heading plus a row per bound item. A menu with no bound
  /// items contributes nothing at all -- no orphaned heading, matching the
  /// "沒有命中的段落整段隱藏，不留空標題" rule the spec states for the sidebar
  /// filter and which reads the same way here.
  List<Widget> _menuRows(
    BuildContext context,
    GbmMenuModel menu,
    Map<GbmActionId, GbmKeyboardShortcut> shortcuts,
    GbmColors colors,
  ) {
    final List<GbmMenuItemModel> bound = <GbmMenuItemModel>[
      for (final GbmMenuItemModel item in menu.items)
        if (shortcuts.containsKey(item.id)) item,
    ];
    if (bound.isEmpty) return const <Widget>[];

    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(
          top: GbmSpacing.space3,
          bottom: GbmSpacing.space1,
        ),
        child: Text(
          menu.title,
          style: TextStyle(
            fontSize: GbmTypography.textXs,
            fontWeight: GbmTypography.weightSemibold,
            color: colors.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
      ),
      for (final GbmMenuItemModel item in bound)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${menu.title} → ${item.label}',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              GbmKbdChip(label: shortcuts[item.id]!.displayLabel),
            ],
          ),
        ),
    ];
  }
}
