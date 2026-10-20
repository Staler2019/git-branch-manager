// Edit's shared handlers dispatch at whatever holds focus. Select all offers
// the list intent first and falls back to the text intent only when no list
// took it -- the one ordering a focused widget cannot show by itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_edit_intents.dart';
import 'package:gbm_flutter/actions/gbm_selection_gesture.dart';

Future<FocusNode> _pumpFocused(
  WidgetTester tester, {
  required List<String> calls,
  required bool handlesListIntent,
}) async {
  final FocusNode node = FocusNode();
  addTearDown(node.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Actions(
        actions: <Type, Action<Intent>>{
          // Returns null, as both real list actions do
          // (`branch_selection_shortcuts.dart`, `commit_graph_view.dart`):
          // `maybeInvoke`'s result is the action's return value, so it cannot
          // say whether a list took the intent.
          if (handlesListIntent)
            GbmSelectAllIntent: CallbackAction<GbmSelectAllIntent>(
              onInvoke: (_) {
                calls.add('list');
                return null;
              },
            ),
          SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
            onInvoke: (_) => calls.add('text'),
          ),
        },
        child: Focus(focusNode: node, child: const SizedBox()),
      ),
    ),
  );
  node.requestFocus();
  await tester.pump();
  return node;
}

void main() {
  testWidgets('Select all goes to a focused list first, and only there', (
    tester,
  ) async {
    final List<String> calls = <String>[];
    await _pumpFocused(tester, calls: calls, handlesListIntent: true);
    invokeFocusedSelectAll();
    expect(calls, <String>['list']);
  });

  testWidgets('Select all falls back to the text intent', (tester) async {
    final List<String> calls = <String>[];
    await _pumpFocused(tester, calls: calls, handlesListIntent: false);
    invokeFocusedSelectAll();
    expect(calls, <String>['text']);
  });

  test('all six Edit entries, none null', () {
    expect(buildEditActionHandlers().keys.toSet(), <GbmActionId>{
      GbmActionId.editUndo,
      GbmActionId.editRedo,
      GbmActionId.editCut,
      GbmActionId.editCopy,
      GbmActionId.editPaste,
      GbmActionId.editSelectAll,
    });
  });
}
