import 'package:flutter/widgets.dart';

import 'gbm_action_id.dart';
import 'gbm_selection_gesture.dart';

/// Edit → Undo / Redo / Cut / Copy / Paste / Select all, for any window's
/// handler map: the workspace and the no-repository welcome screen spread the
/// same six entries.
///
/// The five clipboard/history verbs dispatch Flutter's own text-editing
/// intents, so they act on whichever field has focus (commit message, filter
/// box, conflict editor, the switcher's search box) instead of needing a
/// per-field wiring. Unfocused, `maybeInvoke` finds no action and does
/// nothing, which is the correct behaviour for "Copy" with no text selected.
///
/// Every entry is deliberately **non-null**. All three dispatch paths read
/// one map ([ACT-one-handler-map]), and a null here would grey the macOS menu
/// item out and make the keyboard path a no-op while leaving the in-window
/// menu working -- the split `workspace_intent_dispatch_parity_test.dart`
/// exists to catch.
Map<GbmActionId, VoidCallback> buildEditActionHandlers() =>
    <GbmActionId, VoidCallback>{
      GbmActionId.editUndo: () => invokeFocusedTextIntent(
        const UndoTextIntent(SelectionChangedCause.keyboard),
      ),
      GbmActionId.editRedo: () => invokeFocusedTextIntent(
        const RedoTextIntent(SelectionChangedCause.keyboard),
      ),
      GbmActionId.editCut: () => invokeFocusedTextIntent(
        const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
      ),
      GbmActionId.editCopy: () =>
          invokeFocusedTextIntent(CopySelectionTextIntent.copy),
      GbmActionId.editPaste: () => invokeFocusedTextIntent(
        const PasteTextIntent(SelectionChangedCause.keyboard),
      ),
      GbmActionId.editSelectAll: invokeFocusedSelectAll,
    };

/// Dispatches [intent] at the currently focused widget; does nothing when
/// nothing has focus.
void invokeFocusedTextIntent(Intent intent) {
  final BuildContext? focused = primaryFocus?.context;
  if (focused == null) return;
  Actions.maybeInvoke(focused, intent);
}

/// Ctrl/Cmd+A has to mean two different things depending on what has focus:
/// "select every row" over a list (spec page 13's `MULTIKEYS`) and "select all
/// text" inside an editor. Focus is the only thing that can tell them apart,
/// so this offers the list intent first and falls back to the text one when
/// nothing consumed it.
void invokeFocusedSelectAll() {
  final BuildContext? focused = primaryFocus?.context;
  if (focused == null) return;
  if (Actions.maybeInvoke(focused, const GbmSelectAllIntent()) != null) {
    return;
  }
  Actions.maybeInvoke(
    focused,
    const SelectAllTextIntent(SelectionChangedCause.keyboard),
  );
}
