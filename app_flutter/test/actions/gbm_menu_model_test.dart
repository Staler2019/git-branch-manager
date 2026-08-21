import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_menu_model.dart';

/// Every item in every menu, including declared submenu children.
///
/// This must recurse: spec page 14's `Tools > Rewrite history` holds three
/// real action ids in [GbmMenuItemModel.children], and a flat walk over
/// `menu.items` would report them as missing from the menu bar entirely --
/// which is the opposite of the truth.
List<GbmMenuItemModel> _allItems() {
  final List<GbmMenuItemModel> items = <GbmMenuItemModel>[];
  void visit(GbmMenuItemModel item) {
    items.add(item);
    item.children.forEach(visit);
  }

  for (final GbmMenuModel menu in gbmMenus) {
    menu.items.forEach(visit);
  }
  return items;
}

void main() {
  group('gbmMenus', () {
    test('every GbmActionId appears exactly once across all menus', () {
      final List<GbmActionId> idList = _allItems()
          .map((GbmMenuItemModel item) => item.id)
          .toList();
      final Set<GbmActionId> idSet = idList.toSet();

      expect(
        idSet.length,
        idList.length,
        reason: 'Each GbmActionId should appear exactly once',
      );
      expect(
        idSet,
        GbmActionId.values.toSet(),
        reason: 'Every GbmActionId value must be present',
      );
    });

    test('has exactly 8 menus with correct titles in order', () {
      // Tools is spec page 14's new eighth menu, placed per its rule 1:
      // "放在 Remote 之後、Help 之前".
      expect(gbmMenus.length, 8);
      expect(gbmMenus.map((GbmMenuModel m) => m.title).toList(), <String>[
        'File',
        'Edit',
        'View',
        'Repository',
        'Branch',
        'Remote',
        'Tools',
        'Help',
      ]);
    });

    test('Tools menu matches spec page 14 TOOLSMENU verbatim', () {
      final GbmMenuModel tools = gbmMenus.firstWhere(
        (GbmMenuModel m) => m.title == 'Tools',
      );
      expect(
        tools.items.map((GbmMenuItemModel i) => i.label).toList(),
        <String>[
          'Stashes…',
          'Worktrees…',
          'Remotes…',
          'Submodules…',
          'Large files (LFS)…',
          'Patches…',
          'Reflog…',
          'Rewrite history',
        ],
      );

      // Rule 2: "破壞性或多步驟的三項（Interactive rebase、Bisect、Clean
      // untracked files）收進 Rewrite history 第二層，不與唯讀面板同層".
      final GbmMenuItemModel rewrite = tools.items.last;
      expect(rewrite.isSubmenuParent, isTrue);
      expect(
        rewrite.children.map((GbmMenuItemModel i) => i.label).toList(),
        <String>['Interactive rebase…', 'Bisect…', 'Clean untracked files…'],
      );
    });

    test('the three submenu parents are the only ones', () {
      final Iterable<GbmMenuItemModel> parents = _allItems().where(
        (GbmMenuItemModel item) => item.isSubmenuParent,
      );
      expect(
        parents.map((GbmMenuItemModel item) => item.id).toSet(),
        <GbmActionId>{
          // Dynamic children, built at the widget layer.
          GbmActionId.viewGraphColumns,
          GbmActionId.viewTheme,
          // Static children, declared in the model.
          GbmActionId.toolsRewriteHistory,
        },
      );
    });

    test('only branchDeleteBranch and Clean untracked files are danger', () {
      final Iterable<GbmMenuItemModel> danger = _allItems().where(
        (GbmMenuItemModel item) => item.isDanger,
      );
      expect(
        danger.map((GbmMenuItemModel item) => item.id).toSet(),
        <GbmActionId>{
          GbmActionId.branchDeleteBranch,
          GbmActionId.toolsCleanUntrackedFiles,
        },
      );
    });
  });
}
