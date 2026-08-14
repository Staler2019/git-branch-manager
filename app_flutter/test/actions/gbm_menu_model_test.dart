import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_menu_model.dart';

void main() {
  group('gbmMenus', () {
    test('all 52 GbmActionId values appear exactly once across all menus', () {
      // Flatten all items from all menus
      final allItems = <GbmMenuItemModel>[];
      for (final menu in gbmMenus) {
        allItems.addAll(menu.items);
      }

      // Extract all IDs
      final idSet = allItems.map((item) => item.id).toSet();
      final idList = allItems.map((item) => item.id).toList();

      // Check uniqueness: Set size should equal List size
      expect(
        idSet.length,
        idList.length,
        reason: 'Each GbmActionId should appear exactly once',
      );

      // Check completeness: all 52 IDs should be in the set
      expect(
        idSet,
        GbmActionId.values.toSet(),
        reason: 'All 52 GbmActionId values must be present',
      );
    });

    test('has exactly 7 menus with correct titles in order', () {
      expect(gbmMenus.length, 7);
      expect(gbmMenus.map((m) => m.title).toList(), [
        'File',
        'Edit',
        'View',
        'Repository',
        'Branch',
        'Remote',
        'Help',
      ]);
    });

    test('only viewGraphColumns and viewTheme have isSubmenuParent=true', () {
      final allItems = <GbmMenuItemModel>[];
      for (final menu in gbmMenus) {
        allItems.addAll(menu.items);
      }

      final submenuParents = allItems.where((item) => item.isSubmenuParent);
      expect(
        submenuParents.length,
        2,
        reason: 'Exactly 2 items should be submenu parents',
      );

      final submenuParentIds = submenuParents.map((item) => item.id).toSet();
      expect(submenuParentIds, {
        GbmActionId.viewGraphColumns,
        GbmActionId.viewTheme,
      });

      // All other items should have isSubmenuParent=false
      final nonSubmenuItems = allItems.where((item) => !item.isSubmenuParent);
      expect(
        nonSubmenuItems.length,
        50,
        reason: '50 items should not be submenu parents',
      );
    });

    test('only branchDeleteBranch has isDanger=true', () {
      final allItems = <GbmMenuItemModel>[];
      for (final menu in gbmMenus) {
        allItems.addAll(menu.items);
      }

      final dangerItems = allItems.where((item) => item.isDanger);
      expect(
        dangerItems.length,
        1,
        reason: 'Exactly 1 item should be marked as danger',
      );

      final dangerItem = dangerItems.first;
      expect(dangerItem.id, GbmActionId.branchDeleteBranch);

      // All other items should have isDanger=false
      final nonDangerItems = allItems.where((item) => !item.isDanger);
      expect(
        nonDangerItems.length,
        51,
        reason: '51 items should not be marked as danger',
      );
    });
  });
}
