// Pure-Dart unit tests for branchFolderMenuItems() -- no widget pump
// needed. Verifies the item list matches gbm_context_menus.dart's 05-J
// (Branch folder) spec, with the documented divergence for the toggle
// item's state-dependent label (see the function's own doc comment), and
// that "Fetch branches in folder" always renders disabled (no capi
// backing).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/context_menus/gbm_context_menus.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_folder_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

void main() {
  group('branchFolderMenuItems', () {
    final List<String> specLabels =
        gbmContextMenuGroups[GbmContextMenuTarget.branchFolder]!.items
            .map((GbmContextMenuItemSpec spec) => spec.label)
            .toList();

    test('item count and order match gbmContextMenuGroups 05-J, aside from '
        'the documented toggle-label split', () {
      final List<GbmMenuItem> items = branchFolderMenuItems(
        isExpanded: false,
        onToggleExpand: () {},
        onCopyPrefix: () {},
        onDeleteMerged: () {},
      );
      final List<String> actualLabels = items
          .where((GbmMenuItem item) => !item.separator)
          .map((GbmMenuItem item) => item.label)
          .toList();

      expect(actualLabels, hasLength(specLabels.length));
      // Item 0 is the documented split -- checked separately below.
      expect(actualLabels.sublist(1), specLabels.sublist(1));
    });

    test('collapsed (isExpanded: false) shows "Expand all"', () {
      final List<GbmMenuItem> items = branchFolderMenuItems(
        isExpanded: false,
        onToggleExpand: () {},
        onCopyPrefix: () {},
        onDeleteMerged: () {},
      );
      expect(items.first.label, 'Expand all');
    });

    test('expanded (isExpanded: true) shows "Collapse all"', () {
      final List<GbmMenuItem> items = branchFolderMenuItems(
        isExpanded: true,
        onToggleExpand: () {},
        onCopyPrefix: () {},
        onDeleteMerged: () {},
      );
      expect(items.first.label, 'Collapse all');
    });

    test(
      'Delete merged branches… is last, is danger, preceded by a separator',
      () {
        final List<GbmMenuItem> items = branchFolderMenuItems(
          isExpanded: false,
          onToggleExpand: () {},
          onCopyPrefix: () {},
          onDeleteMerged: () {},
        );

        expect(items.last.label, 'Delete merged branches…');
        expect(items.last.danger, isTrue);
        expect(items[items.length - 2].separator, isTrue);
      },
    );

    test('Fetch branches in folder always renders disabled', () {
      final List<GbmMenuItem> items = branchFolderMenuItems(
        isExpanded: false,
        onToggleExpand: () {},
        onCopyPrefix: () {},
        onDeleteMerged: () {},
      );
      final GbmMenuItem fetchItem = items.firstWhere(
        (GbmMenuItem i) => i.label == 'Fetch branches in folder',
      );
      expect(fetchItem.enabled, isFalse);
      expect(fetchItem.onTap, isNull);
    });

    test('each callback reaches its matching item, not a neighbor', () {
      bool toggled = false;
      bool copied = false;
      bool deleted = false;

      final List<GbmMenuItem> items = branchFolderMenuItems(
        isExpanded: false,
        onToggleExpand: () => toggled = true,
        onCopyPrefix: () => copied = true,
        onDeleteMerged: () => deleted = true,
      );

      items.firstWhere((GbmMenuItem i) => i.label == 'Expand all').onTap!();
      expect(toggled, isTrue);
      expect(copied, isFalse);
      expect(deleted, isFalse);

      items
          .firstWhere((GbmMenuItem i) => i.label == 'Copy folder prefix')
          .onTap!();
      expect(copied, isTrue);

      items
          .firstWhere((GbmMenuItem i) => i.label == 'Delete merged branches…')
          .onTap!();
      expect(deleted, isTrue);
    });
  });
}
