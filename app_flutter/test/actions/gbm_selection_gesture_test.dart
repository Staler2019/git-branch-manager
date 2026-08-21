// Spec page 13 MULTIKEYS' three mouse rows, as read off the modifier state.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_selection_gesture.dart';

void main() {
  group('selectionGestureFromKeys', () {
    test('no modifier is a plain single selection', () {
      expect(
        selectionGestureFromKeys(const <LogicalKeyboardKey>{}, isMacOS: true),
        SelectionGesture.single,
      );
    });

    test('shift is a range on either platform', () {
      for (final bool isMacOS in <bool>[true, false]) {
        expect(
          selectionGestureFromKeys(<LogicalKeyboardKey>{
            LogicalKeyboardKey.shiftLeft,
          }, isMacOS: isMacOS),
          SelectionGesture.range,
        );
      }
    });

    test('the toggle modifier is Cmd on macOS and Ctrl elsewhere', () {
      expect(
        selectionGestureFromKeys(<LogicalKeyboardKey>{
          LogicalKeyboardKey.metaLeft,
        }, isMacOS: true),
        SelectionGesture.toggle,
      );
      expect(
        selectionGestureFromKeys(<LogicalKeyboardKey>{
          LogicalKeyboardKey.controlLeft,
        }, isMacOS: false),
        SelectionGesture.toggle,
      );
    });

    test('the wrong platform modifier does not toggle', () {
      // Ctrl-click on macOS is the OS's own secondary-click; treating it as
      // a toggle would fight the context menu that same gesture opens.
      expect(
        selectionGestureFromKeys(<LogicalKeyboardKey>{
          LogicalKeyboardKey.controlLeft,
        }, isMacOS: true),
        SelectionGesture.single,
      );
      expect(
        selectionGestureFromKeys(<LogicalKeyboardKey>{
          LogicalKeyboardKey.metaLeft,
        }, isMacOS: false),
        SelectionGesture.single,
      );
    });

    test('shift wins over the toggle modifier (MULTIKEYS leaves the '
        'combination undefined; pinned here rather than invented per '
        'call site)', () {
      expect(
        selectionGestureFromKeys(<LogicalKeyboardKey>{
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.metaLeft,
        }, isMacOS: true),
        SelectionGesture.range,
      );
    });

    test('right-hand modifier keys count too', () {
      expect(
        selectionGestureFromKeys(<LogicalKeyboardKey>{
          LogicalKeyboardKey.shiftRight,
        }, isMacOS: true),
        SelectionGesture.range,
      );
      expect(
        selectionGestureFromKeys(<LogicalKeyboardKey>{
          LogicalKeyboardKey.metaRight,
        }, isMacOS: true),
        SelectionGesture.toggle,
      );
    });
  });
}
