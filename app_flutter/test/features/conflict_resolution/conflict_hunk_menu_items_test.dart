// Pure-Dart unit tests for conflictHunkMenuItems() -- no widget pump
// needed. Verifies the item list matches gbm_context_menus.dart's 05-I
// (Conflict hunk) spec exactly, that "Open in external merge tool" always
// renders disabled (no backing capability), and that "Discard from
// result" goes through the nullable-callback gate for a region with
// nothing in its result yet.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/context_menus/gbm_context_menus.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_hunk_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

void main() {
  group('conflictHunkMenuItems', () {
    test('labels and order match gbmContextMenuGroups 05-I exactly', () {
      final List<GbmMenuItem> items = conflictHunkMenuItems(
        onTakeThisSide: () {},
        onTakeThisLineOnly: () {},
        onTakeBoth: () {},
        onDiscardFromResult: () {},
      );

      final List<String> actualLabels = items
          .where((GbmMenuItem item) => !item.separator)
          .map((GbmMenuItem item) => item.label)
          .toList();
      final List<String> specLabels =
          gbmContextMenuGroups[GbmContextMenuTarget.conflictHunk]!.items
              .map((GbmContextMenuItemSpec spec) => spec.label)
              .toList();

      expect(actualLabels, specLabels);
    });

    test('Discard from result is last, is danger, preceded by a separator', () {
      final List<GbmMenuItem> items = conflictHunkMenuItems(
        onTakeThisSide: () {},
        onTakeThisLineOnly: () {},
        onTakeBoth: () {},
        onDiscardFromResult: () {},
      );

      expect(items.last.label, 'Discard from result');
      expect(items.last.danger, isTrue);
      expect(items[items.length - 2].separator, isTrue);
    });

    test('Open in external merge tool always renders disabled', () {
      final List<GbmMenuItem> items = conflictHunkMenuItems(
        onTakeThisSide: () {},
        onTakeThisLineOnly: () {},
        onTakeBoth: () {},
        onDiscardFromResult: () {},
      );
      final GbmMenuItem item = items.firstWhere(
        (GbmMenuItem i) => i.label == 'Open in external merge tool',
      );
      expect(item.enabled, isFalse);
      expect(item.onTap, isNull);
    });

    test('onDiscardFromResult: null renders Discard from result disabled, '
        'other items unaffected', () {
      final List<GbmMenuItem> items = conflictHunkMenuItems(
        onTakeThisSide: () {},
        onTakeThisLineOnly: () {},
        onTakeBoth: () {},
        onDiscardFromResult: null,
      );

      final Map<String, GbmMenuItem> byLabel = <String, GbmMenuItem>{
        for (final GbmMenuItem item in items)
          if (!item.separator) item.label: item,
      };

      expect(byLabel['Discard from result']!.onTap, isNull);
      expect(byLabel['Discard from result']!.enabled, isFalse);
      expect(byLabel['Take this side']!.onTap, isNotNull);
      expect(byLabel['Take this line only']!.onTap, isNotNull);
      expect(byLabel['Take both — this side first']!.onTap, isNotNull);
    });

    test('each callback reaches its matching item, not a neighbor', () {
      bool tookSide = false;
      bool tookLine = false;
      bool discarded = false;

      final List<GbmMenuItem> items = conflictHunkMenuItems(
        onTakeThisSide: () => tookSide = true,
        onTakeThisLineOnly: () => tookLine = true,
        onTakeBoth: () {},
        onDiscardFromResult: () => discarded = true,
      );

      items.firstWhere((GbmMenuItem i) => i.label == 'Take this side').onTap!();
      expect(tookSide, isTrue);
      expect(tookLine, isFalse);
      expect(discarded, isFalse);

      items
          .firstWhere((GbmMenuItem i) => i.label == 'Take this line only')
          .onTap!();
      expect(tookLine, isTrue);

      items
          .firstWhere((GbmMenuItem i) => i.label == 'Discard from result')
          .onTap!();
      expect(discarded, isTrue);
    });
  });
}
