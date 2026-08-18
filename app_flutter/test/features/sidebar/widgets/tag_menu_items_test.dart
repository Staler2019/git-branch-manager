// Pure-Dart unit tests for tagMenuItems() -- no widget pump needed.
// Verifies the item list matches gbm_context_menus.dart's 05-D (Tag) spec
// exactly and that "Push tag" goes through the nullable-callback gate for
// the no-single-remote case (see the function's own doc comment for why
// there's no "default remote" to fall back to, unlike a repository-level
// push).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/context_menus/gbm_context_menus.dart';
import 'package:gbm_flutter/features/sidebar/widgets/tag_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

void main() {
  group('tagMenuItems', () {
    test('labels and order match gbmContextMenuGroups 05-D exactly', () {
      final List<GbmMenuItem> items = tagMenuItems(
        tagName: 'v1.0.0',
        onCheckoutDetached: () {},
        onPush: () {},
        onCompare: () {},
        onDelete: () {},
      );

      final List<String> actualLabels = items
          .where((GbmMenuItem item) => !item.separator)
          .map((GbmMenuItem item) => item.label)
          .toList();
      final List<String> specLabels =
          gbmContextMenuGroups[GbmContextMenuTarget.tag]!.items
              .map((GbmContextMenuItemSpec spec) => spec.label)
              .toList();

      expect(actualLabels, specLabels);
    });

    test('Delete tag… is last, is danger, and is preceded by a separator', () {
      final List<GbmMenuItem> items = tagMenuItems(
        tagName: 'v1.0.0',
        onCheckoutDetached: () {},
        onPush: () {},
        onCompare: () {},
        onDelete: () {},
      );

      expect(items.last.label, 'Delete tag…');
      expect(items.last.danger, isTrue);
      expect(items[items.length - 2].separator, isTrue);
    });

    test('onPush: null renders Push tag disabled, other items unaffected', () {
      final List<GbmMenuItem> items = tagMenuItems(
        tagName: 'v1.0.0',
        onCheckoutDetached: () {},
        onPush: null,
        onCompare: () {},
        onDelete: () {},
      );

      final Map<String, GbmMenuItem> byLabel = <String, GbmMenuItem>{
        for (final GbmMenuItem item in items)
          if (!item.separator) item.label: item,
      };

      expect(byLabel['Push tag']!.onTap, isNull);
      expect(byLabel['Checkout tag (detached)']!.onTap, isNotNull);
      expect(byLabel['Compare with…']!.onTap, isNotNull);
      expect(byLabel['Copy tag name']!.onTap, isNotNull);
      expect(byLabel['Delete tag…']!.onTap, isNotNull);
    });

    test('onCheckoutDetached: null renders Checkout tag (detached) disabled, '
        'matching a conflict-active gate', () {
      final List<GbmMenuItem> items = tagMenuItems(
        tagName: 'v1.0.0',
        onCheckoutDetached: null,
        onPush: () {},
        onCompare: () {},
        onDelete: () {},
      );

      final Map<String, GbmMenuItem> byLabel = <String, GbmMenuItem>{
        for (final GbmMenuItem item in items)
          if (!item.separator) item.label: item,
      };

      expect(byLabel['Checkout tag (detached)']!.onTap, isNull);
      expect(byLabel['Push tag']!.onTap, isNotNull);
    });

    test('Copy tag name copies the tag\'s own name to the clipboard', () async {
      final List<Object?> clipboardCalls = <Object?>[];
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardCalls.add(call.arguments);
            }
            return null;
          });
      addTearDown(
        () => TestWidgetsFlutterBinding.ensureInitialized()
            .defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final List<GbmMenuItem> items = tagMenuItems(
        tagName: 'release-2.0',
        onCheckoutDetached: () {},
        onPush: () {},
        onCompare: () {},
        onDelete: () {},
      );
      items.firstWhere((GbmMenuItem i) => i.label == 'Copy tag name').onTap!();

      expect(clipboardCalls, hasLength(1));
      expect((clipboardCalls.single as Map)['text'], 'release-2.0');
    });

    test('each callback reaches its matching item, not a neighbor', () {
      bool checkedOut = false;
      bool deleted = false;

      final List<GbmMenuItem> items = tagMenuItems(
        tagName: 'v1.0.0',
        onCheckoutDetached: () => checkedOut = true,
        onPush: () {},
        onCompare: () {},
        onDelete: () => deleted = true,
      );

      items
          .firstWhere((GbmMenuItem i) => i.label == 'Checkout tag (detached)')
          .onTap!();
      expect(checkedOut, isTrue);
      expect(deleted, isFalse);

      items.firstWhere((GbmMenuItem i) => i.label == 'Delete tag…').onTap!();
      expect(deleted, isTrue);
    });
  });
}
