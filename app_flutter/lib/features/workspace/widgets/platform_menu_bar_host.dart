import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../actions/gbm_menu_model.dart';

/// Placeholder for a macOS [PlatformMenuBar] integration (future milestone).
///
/// Currently returns [child] unwrapped on all platforms. On macOS, this would
/// build a real [PlatformMenuBar] from [menus], using system-provided menu
/// items (via [PlatformProvidedMenuItemType].quit and .about) for those roles.
/// On other platforms, this is a no-op passthrough.
///
/// The [handlers] map provides click handlers for menu items. Currently unused
/// since [PlatformMenuBar] support is deferred; this parameter is kept for
/// future implementation compatibility.
///
/// For testability, [isMacOSOverride] can be passed to force platform behavior;
/// if null (the default), [Platform.isMacOS] is used.
class PlatformMenuBarHost extends StatelessWidget {
  const PlatformMenuBarHost({
    super.key,
    required this.child,
    required this.menus,
    required this.handlers,
    this.isMacOSOverride,
  });

  /// The widget to wrap.
  final Widget child;

  /// The menu structure built from [gbmMenus] (currently unused).
  final List<GbmMenuModel> menus;

  /// Map of [GbmActionId] to click handler callbacks (currently unused).
  final Map<GbmActionId, VoidCallback?> handlers;

  /// Override for platform detection. If null, [Platform.isMacOS] is used.
  /// Used for testing.
  final bool? isMacOSOverride;

  @override
  Widget build(BuildContext context) {
    // TODO(desktop): Implement PlatformMenuBar integration
    // This is a placeholder that returns child unwrapped. On macOS, this
    // should build a real PlatformMenuBar with system-provided quit/about items.
    return child;
  }
}
