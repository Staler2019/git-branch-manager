import 'package:flutter/material.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../actions/gbm_shortcuts.dart';

/// Intent for triggering a [GbmActionId].
class GbmActionIntent extends Intent {
  const GbmActionIntent(this.id);

  /// The action ID triggered by a keyboard shortcut or click.
  final GbmActionId id;
}

/// Converts a [GbmKeyboardShortcut] to a [SingleActivator].
extension GbmKeyboardShortcutToActivator on GbmKeyboardShortcut {
  /// Returns a [SingleActivator] suitable for [Shortcuts.shortcuts].
  SingleActivator toActivator() => SingleActivator(
    trigger,
    control: control,
    meta: meta,
    shift: shift,
    alt: alt,
  );
}

/// Wraps its child in [Shortcuts] and [Actions] to handle keyboard shortcuts
/// and [GbmActionIntent] dispatching.
///
/// This widget is deliberately factored out of [WorkspaceScreen] so it can be
/// tested independently without Riverpod/FFI session dependencies. The handlers
/// map is partial: ids absent or mapped to null are accepted but no-op (so
/// callers can pass handlers only for the actions they care about).
class WorkspaceActionShortcuts extends StatelessWidget {
  const WorkspaceActionShortcuts({
    super.key,
    required this.handlers,
    required this.isMacOS,
    required this.child,
  });

  /// Maps [GbmActionId] to handler callbacks. Absent ids or null values are
  /// accepted no-ops. Every id with a non-null handler will fire that callback
  /// when its shortcut is pressed.
  final Map<GbmActionId, VoidCallback?> handlers;

  /// Platform detection for shortcut bindings (Cmd on macOS, Ctrl elsewhere).
  final bool isMacOS;

  /// The child widget to wrap.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Map<ShortcutActivator, Intent> shortcuts =
        <ShortcutActivator, Intent>{
          for (final MapEntry<GbmActionId, GbmKeyboardShortcut> e
              in gbmActionShortcuts(isMacOS).entries)
            e.value.toActivator(): GbmActionIntent(e.key),
        };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          GbmActionIntent: CallbackAction<GbmActionIntent>(
            onInvoke: (intent) {
              handlers[intent.id]?.call();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
