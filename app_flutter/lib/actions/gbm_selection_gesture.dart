import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Which of spec page 13's three mouse rows a click on a list row means.
///
/// `MULTIKEYS` names them directly:
/// - 單擊 -> [single] (只選這一項，anchor 移到這一項)
/// - Ctrl / Cmd + 單擊 -> [toggle] (切換單項，anchor 移到此項)
/// - Shift + 單擊 -> [range] (anchor 到此項的連續範圍)
enum SelectionGesture { single, toggle, range }

/// Reads the modifier state at click time and maps it to a [SelectionGesture].
///
/// [pressed] is normally `HardwareKeyboard.instance.logicalKeysPressed`;
/// it is a parameter so a widget test can drive a gesture without having to
/// hold real keys down.
///
/// The toggle modifier is Cmd on macOS and Ctrl elsewhere, matching how
/// `gbm_shortcuts.dart` picks `meta` vs `control` for every other binding.
///
/// **Shift wins when both are held.** `MULTIKEYS` does not define
/// Ctrl/Cmd+Shift+click, so rather than inventing a third behaviour (some
/// file managers make it an additive range) this collapses to the range the
/// user can see themselves selecting.
SelectionGesture selectionGestureFromKeys(
  Set<LogicalKeyboardKey> pressed, {
  required bool isMacOS,
}) {
  final Set<LogicalKeyboardKey> shiftKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };
  final Set<LogicalKeyboardKey> metaKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };
  final Set<LogicalKeyboardKey> controlKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  };

  if (pressed.any(shiftKeys.contains)) return SelectionGesture.range;
  final Set<LogicalKeyboardKey> toggleKeys = isMacOS ? metaKeys : controlKeys;
  if (pressed.any(toggleKeys.contains)) return SelectionGesture.toggle;
  return SelectionGesture.single;
}

/// [selectionGestureFromKeys] against the live keyboard and the current
/// platform -- what a row's `onTap` calls.
SelectionGesture currentSelectionGesture() => selectionGestureFromKeys(
  HardwareKeyboard.instance.logicalKeysPressed,
  isMacOS: defaultTargetPlatform == TargetPlatform.macOS,
);

/// "Select every row of the list that currently has focus."
///
/// A dedicated intent rather than Flutter's `SelectAllTextIntent` because a
/// commit list is not a text field: the same Ctrl/Cmd+A has to mean "select
/// all rows" over a list and "select all text" inside an editor, and the
/// only thing that can tell them apart is which one holds focus. The
/// workspace's `editSelectAll` handler offers this one first and falls back
/// to the text intent when no list consumed it -- see
/// `workspace_screen.dart`'s `_invokeSelectAll`.
class GbmSelectAllIntent extends Intent {
  const GbmSelectAllIntent();
}

/// `Shift + ↑ / ↓`: 以鍵盤延伸範圍 (extend the range by keyboard).
/// [delta] is -1 for up and 1 for down.
class GbmExtendSelectionIntent extends Intent {
  const GbmExtendSelectionIntent(this.delta);

  final int delta;
}

/// Plain `↑ / ↓`: moves the single selection one row in painted order.
/// [delta] is -1 for up and 1 for down.
///
/// Separate from [GbmExtendSelectionIntent] rather than a flag on it: they
/// differ in what they produce (one item versus a range) and in what they
/// may traverse -- History's uncommitted row is reachable by this one and
/// deliberately not by the range one, because a range spanning it is not
/// something git could replay.
///
/// Spec page 13's `MULTIKEYS` lists 單擊 / Ctrl-Cmd / Shift / Ctrl-Cmd+A /
/// Esc and no plain arrow row, so this is an addition rather than a
/// conformance item -- the same standing as the uncommitted row itself.
class GbmMoveSelectionIntent extends Intent {
  const GbmMoveSelectionIntent(this.delta);

  final int delta;
}
