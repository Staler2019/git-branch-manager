import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../actions/gbm_selection_gesture.dart';

/// Keyboard half of spec page 13's `MULTIKEYS`, scoped to the branch tree.
///
/// Deliberately **not** wrapped around the whole sidebar: the filter
/// `TextField` sits above this subtree, and a `Shortcuts` closer to a
/// focused editor than `DefaultTextEditingShortcuts` would take Ctrl/Cmd+A
/// away from "select all text". Same shape and same reasoning as
/// `commit_graph_view.dart`'s `_SelectionShortcuts`, including the
/// Shortcuts/Actions-above-Focus ordering: a key event dispatches to the
/// primary focus and then walks its *ancestors*, so a `Shortcuts` nested
/// inside the focused node would never see anything.
class BranchSelectionShortcuts extends StatelessWidget {
  const BranchSelectionShortcuts({
    super.key,
    required this.focusNode,
    required this.onSelectAll,
    required this.onCollapse,
    required this.onExtend,
    required this.child,
  });

  final FocusNode focusNode;
  final VoidCallback onSelectAll;
  final VoidCallback onCollapse;
  final ValueChanged<int> onExtend;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
            const GbmExtendSelectionIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
            const GbmExtendSelectionIntent(1),
        // Both modifiers registered rather than branching on platform: an
        // unheld modifier simply never matches.
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            const GbmSelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            const GbmSelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          GbmExtendSelectionIntent: CallbackAction<GbmExtendSelectionIntent>(
            onInvoke: (GbmExtendSelectionIntent intent) {
              onExtend(intent.delta);
              return null;
            },
          ),
          GbmSelectAllIntent: CallbackAction<GbmSelectAllIntent>(
            onInvoke: (GbmSelectAllIntent intent) {
              onSelectAll();
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (DismissIntent intent) {
              onCollapse();
              return null;
            },
          ),
        },
        child: Focus(focusNode: focusNode, child: child),
      ),
    );
  }
}
