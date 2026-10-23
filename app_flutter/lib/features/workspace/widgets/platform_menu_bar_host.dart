import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../actions/gbm_menu_model.dart';
import '../../../actions/gbm_shortcuts.dart';

/// Puts the application menus in the macOS system menu bar, and gets out of
/// the way everywhere else.
///
/// Spec page 01: "三平台統一樣式，只有 menu bar 位置與標題列跟隨系統" -- on
/// macOS the menus belong in the system bar at the top of the screen, while
/// Windows and Linux draw their own row below the title bar. That in-window
/// row is `MenuBarRow`; this widget is the macOS half, and on other platforms
/// it is a passthrough so the two never both render.
///
/// It sends the menus to the embedder itself
/// (`WidgetsBinding.platformMenuDelegate`) rather than through a
/// [PlatformMenuBar], because the welcome screen and the workspace each
/// have one and the router mounts the next screen before it disposes the
/// last. Two `PlatformMenuBar`s alive at once fail the framework's lock
/// assertion in a debug build, and in a release build the old one's
/// `dispose()` clears the menus the new one has just sent. Here the most
/// recently mounted live host owns the menu bar; when the owner goes, the
/// next newest re-sends its own, and the last one out clears it.
///
/// For testability, [isMacOSOverride] forces platform behaviour; if null
/// (the default), [Platform.isMacOS] is used.
class PlatformMenuBarHost extends StatefulWidget {
  const PlatformMenuBarHost({
    super.key,
    required this.child,
    required this.menus,
    required this.handlers,
    this.isMacOSOverride,
  });

  /// The widget to wrap.
  final Widget child;

  /// The menu structure, normally [gbmMenus].
  final List<GbmMenuModel> menus;

  /// Click handlers per action. A null handler (or a missing key) makes the
  /// system menu item inert, which is how macOS renders a disabled item.
  final Map<GbmActionId, VoidCallback?> handlers;

  /// Override for platform detection. If null, [Platform.isMacOS] is used.
  final bool? isMacOSOverride;

  bool get _isMacOS => isMacOSOverride ?? Platform.isMacOS;

  @override
  State<PlatformMenuBarHost> createState() => _PlatformMenuBarHostState();

  /// The actions macOS supplies itself, and which must therefore not be
  /// duplicated as ordinary items. Quit is the only one: it lives in the
  /// application menu, which `PlatformMenuBar` leaves alone (the embedder
  /// replaces the menus *after* index 0, so `MainMenu.xib`'s
  /// `systemMenu="apple"` entry survives).
  ///
  /// `helpAbout` used to be here too, and that was a bug rather than a
  /// simplification: a `PlatformProvidedMenuItem(about)` opens the native
  /// macOS About panel, so the one action id rendered a different window on
  /// macOS than the `AboutDialogContent` Windows and Linux got. Spec page
  /// 01 puts every window's *contents* under Flutter on all three
  /// platforms -- only the menu bar's position follows the OS. The Apple
  /// menu keeps its own native About, which is where macOS convention puts
  /// one anyway.
  static const Set<GbmActionId> _systemProvided = <GbmActionId>{
    GbmActionId.fileExit,
  };

  /// The menu tree this host sends: one [PlatformMenu] per [menus] entry.
  /// Public so a test can read and invoke what the embedder receives.
  List<PlatformMenuItem> platformMenus() {
    final Map<GbmActionId, GbmKeyboardShortcut> shortcuts = gbmActionShortcuts(
      true,
    );

    return <PlatformMenuItem>[
      for (final GbmMenuModel menu in menus)
        PlatformMenu(
          label: menu.title,
          menus: <PlatformMenuItem>[
            for (final GbmMenuItemModel item in menu.items)
              if (!_systemProvided.contains(item.id))
                // A submenu parent with declared children (Tools >
                // Rewrite history) becomes a real nested macOS submenu.
                // The two dynamic submenu parents (viewGraphColumns,
                // viewTheme) declare no children and stay flat items, as
                // they were -- their content is built at the widget layer
                // and has no PlatformMenu equivalent.
                if (item.isSubmenuParent && item.children.isNotEmpty)
                  PlatformMenu(
                    label: item.label,
                    menus: <PlatformMenuItem>[
                      for (final GbmMenuItemModel child in item.children)
                        PlatformMenuItem(
                          label: child.label,
                          shortcut: _activatorFor(shortcuts[child.id]),
                          onSelected: handlers[child.id],
                        ),
                    ],
                  )
                else
                  PlatformMenuItem(
                    label: item.label,
                    shortcut: _activatorFor(shortcuts[item.id]),
                    onSelected: handlers[item.id],
                  ),
            // Quit is appended to the menu it belongs to, so it still
            // sits under File even though macOS owns its behaviour.
            //
            // `hasMenu` is not optional: PlatformProvidedMenuItem throws
            // when the *running* platform has no such menu, and
            // isMacOSOverride only decides whether this widget builds at
            // all -- it does not change defaultTargetPlatform. Without the
            // guard, forcing the macOS branch anywhere else (a widget
            // test, a desktop embedder reporting another platform) throws
            // while building.
            if (menu.items.any((i) => i.id == GbmActionId.fileExit) &&
                PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.quit,
                ))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.quit,
              ),
          ],
        ),
    ];
  }

  /// Translates a [GbmKeyboardShortcut] into the activator the embedder
  /// wants. Returns null for an unbound action, which simply shows no key
  /// equivalent next to the item.
  static MenuSerializableShortcut? _activatorFor(
    GbmKeyboardShortcut? shortcut,
  ) {
    if (shortcut == null) return null;
    return SingleActivator(
      shortcut.trigger,
      control: shortcut.control,
      meta: shortcut.meta,
      shift: shortcut.shift,
      alt: shortcut.alt,
    );
  }
}

class _PlatformMenuBarHostState extends State<PlatformMenuBarHost> {
  /// Live macOS hosts, oldest first; the last one owns the menu bar.
  static final List<_PlatformMenuBarHostState> _live =
      <_PlatformMenuBarHostState>[];

  bool get _owns => _live.isNotEmpty && identical(_live.last, this);

  void _send() => WidgetsBinding.instance.platformMenuDelegate.setMenus(
    widget.platformMenus(),
  );

  @override
  void initState() {
    super.initState();
    if (!widget._isMacOS) return;
    _live.add(this);
    _send();
  }

  @override
  void didUpdateWidget(PlatformMenuBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handlers are new closures every build, as PlatformMenuBar saw them.
    if (_owns) _send();
  }

  @override
  void dispose() {
    final bool owned = _owns;
    _live.remove(this);
    if (owned) {
      if (_live.isEmpty) {
        WidgetsBinding.instance.platformMenuDelegate.clearMenus();
      } else {
        _live.last._send();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
