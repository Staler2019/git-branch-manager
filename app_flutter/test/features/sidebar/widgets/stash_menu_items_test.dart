// Pure-Dart unit tests for stashMenuItems() -- no widget pump needed.
// Verifies the item list matches gbm_context_menus.dart's 05-H (Stash
// entry) spec exactly (labels, order, danger-last) and that the
// conflict-sensitive items (Apply/Pop/Create branch from stash…) go
// through the nullable-callback gate the same way TabRow's Merge/
// Cherry-pick/Reset do, while View diff/Compare with…/Drop stash… stay
// callable regardless.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/context_menus/gbm_context_menus.dart';
import 'package:gbm_flutter/features/sidebar/widgets/stash_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

void main() {
  group('stashMenuItems', () {
    test('labels and order match gbmContextMenuGroups 05-H exactly', () {
      final List<GbmMenuItem> items = stashMenuItems(
        onApply: () {},
        onPop: () {},
        onCreateBranch: () {},
        onViewDiff: () {},
        onCompare: () {},
        onDrop: () {},
      );

      final List<String> actualLabels = items
          .where((GbmMenuItem item) => !item.separator)
          .map((GbmMenuItem item) => item.label)
          .toList();
      final List<String> specLabels =
          gbmContextMenuGroups[GbmContextMenuTarget.stashEntry]!.items
              .map((GbmContextMenuItemSpec spec) => spec.label)
              .toList();

      expect(actualLabels, specLabels);
    });

    test('Drop stash… is last, is danger, and is preceded by a separator', () {
      final List<GbmMenuItem> items = stashMenuItems(
        onApply: () {},
        onPop: () {},
        onCreateBranch: () {},
        onViewDiff: () {},
        onCompare: () {},
        onDrop: () {},
      );

      expect(items.last.label, 'Drop stash…');
      expect(items.last.danger, isTrue);
      expect(items[items.length - 2].separator, isTrue);
    });

    test('passing null for Apply/Pop/Create branch from stash… renders them '
        'disabled, matching a conflict-active gate', () {
      final List<GbmMenuItem> items = stashMenuItems(
        onApply: null,
        onPop: null,
        onCreateBranch: null,
        onViewDiff: () {},
        onCompare: () {},
        onDrop: () {},
      );

      final Map<String, GbmMenuItem> byLabel = <String, GbmMenuItem>{
        for (final GbmMenuItem item in items)
          if (!item.separator) item.label: item,
      };

      expect(byLabel['Apply stash']!.onTap, isNull);
      expect(byLabel['Apply stash']!.enabled, isFalse);
      expect(byLabel['Pop stash']!.onTap, isNull);
      expect(byLabel['Pop stash']!.enabled, isFalse);
      expect(byLabel['Create branch from stash…']!.onTap, isNull);
      expect(byLabel['Create branch from stash…']!.enabled, isFalse);
      // Unaffected by the same gate.
      expect(byLabel['View diff']!.onTap, isNotNull);
      expect(byLabel['Compare with…']!.onTap, isNotNull);
      expect(byLabel['Drop stash…']!.onTap, isNotNull);
    });

    test('each callback reaches its matching item, not a neighbor', () {
      bool appliedCalled = false;
      bool poppedCalled = false;
      bool droppedCalled = false;

      final List<GbmMenuItem> items = stashMenuItems(
        onApply: () => appliedCalled = true,
        onPop: () => poppedCalled = true,
        onCreateBranch: () {},
        onViewDiff: () {},
        onCompare: () {},
        onDrop: () => droppedCalled = true,
      );

      items.firstWhere((GbmMenuItem i) => i.label == 'Apply stash').onTap!();
      expect(appliedCalled, isTrue);
      expect(poppedCalled, isFalse);
      expect(droppedCalled, isFalse);

      items.firstWhere((GbmMenuItem i) => i.label == 'Pop stash').onTap!();
      expect(poppedCalled, isTrue);

      items.firstWhere((GbmMenuItem i) => i.label == 'Drop stash…').onTap!();
      expect(droppedCalled, isTrue);
    });
  });
}
