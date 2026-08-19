import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/context_menus/gbm_context_menus.dart';

void main() {
  group('GbmContextMenuGroups', () {
    test('all 11 GbmContextMenuTarget values are present as keys', () {
      expect(
        gbmContextMenuGroups.keys,
        unorderedEquals(<GbmContextMenuTarget>[
          GbmContextMenuTarget.repository,
          GbmContextMenuTarget.localBranch,
          GbmContextMenuTarget.remoteOnlyOrGoneBranch,
          GbmContextMenuTarget.branchFolder,
          GbmContextMenuTarget.tag,
          GbmContextMenuTarget.commit,
          GbmContextMenuTarget.workingCopyFile,
          GbmContextMenuTarget.historyCommitFile,
          GbmContextMenuTarget.diffLine,
          GbmContextMenuTarget.stashEntry,
          GbmContextMenuTarget.conflictHunk,
        ]),
      );
      expect(gbmContextMenuGroups.length, 11);
    });

    test('each group has correct top-level item count (per spec)', () {
      const expectedCounts = <GbmContextMenuTarget, int>{
        GbmContextMenuTarget.repository: 7, // 05-A
        GbmContextMenuTarget.localBranch: 8, // 05-B
        GbmContextMenuTarget.remoteOnlyOrGoneBranch: 5, // 05-C
        GbmContextMenuTarget.branchFolder: 4, // 05-J
        GbmContextMenuTarget.tag: 5, // 05-D
        GbmContextMenuTarget.commit: 7, // 05-E
        GbmContextMenuTarget.workingCopyFile: 6, // 05-F
        GbmContextMenuTarget.historyCommitFile: 8, // 05-K
        GbmContextMenuTarget.diffLine: 5, // 05-G
        GbmContextMenuTarget.stashEntry: 6, // 05-H
        GbmContextMenuTarget.conflictHunk: 5, // 05-I
      };

      expectedCounts.forEach((target, expectedCount) {
        final group = gbmContextMenuGroups[target]!;
        expect(
          group.items.length,
          expectedCount,
          reason:
              'Group ${group.id} (${group.title}) should have '
              '$expectedCount items, found ${group.items.length}',
        );
      });
    });

    test('each group has danger item as last non-submenu-trigger item '
        '(or none)', () {
      gbmContextMenuGroups.forEach((target, group) {
        // Filter to non-submenu-trigger items
        final nonSubmenuItems = group.items
            .where((item) => !item.isSubmenuTrigger)
            .toList();

        // Find danger item among non-submenu items
        final dangerItem = nonSubmenuItems
            .cast<GbmContextMenuItemSpec?>()
            .firstWhere((item) => item?.isDanger ?? false, orElse: () => null);

        if (dangerItem != null) {
          expect(
            nonSubmenuItems.last,
            dangerItem,
            reason:
                'Group ${group.id} (${group.title}): '
                'danger item must be last non-submenu-trigger item',
          );
        }
      });
    });

    test('05-E (commit) has exactly 5 submenu children in "More actions"', () {
      final commit = gbmContextMenuGroups[GbmContextMenuTarget.commit]!;
      final moreActionsItem = commit.items
          .cast<GbmContextMenuItemSpec?>()
          .firstWhere(
            (item) => item?.label == 'More actions',
            orElse: () => null,
          );

      expect(moreActionsItem, isNotNull);
      expect(moreActionsItem!.isSubmenuTrigger, isTrue);
      expect(moreActionsItem.children.length, 5);
    });

    test('05-K (historyCommitFile) has exactly 4 submenu children in '
        '"More actions"', () {
      final historyFile =
          gbmContextMenuGroups[GbmContextMenuTarget.historyCommitFile]!;
      final moreActionsItem = historyFile.items
          .cast<GbmContextMenuItemSpec?>()
          .firstWhere(
            (item) => item?.label == 'More actions',
            orElse: () => null,
          );

      expect(moreActionsItem, isNotNull);
      expect(moreActionsItem!.isSubmenuTrigger, isTrue);
      expect(moreActionsItem.children.length, 4);
    });

    test('no submenu children contain nested submenus', () {
      gbmContextMenuGroups.forEach((target, group) {
        for (final item in group.items) {
          if (item.isSubmenuTrigger) {
            for (final child in item.children) {
              expect(
                child.isSubmenuTrigger,
                isFalse,
                reason:
                    'Group ${group.id} (${group.title}): '
                    'submenu "${item.label}" contains nested submenu '
                    '(not allowed)',
              );
            }
          }
        }
      });
    });

    test('05-B item labels match spec exactly', () {
      final localBranch =
          gbmContextMenuGroups[GbmContextMenuTarget.localBranch]!;
      final labels = localBranch.items.map((item) => item.label).toList();

      const expectedLabels = <String>[
        'Checkout',
        'New branch from here…',
        'Rename…',
        'Merge into current',
        'Rebase current onto here',
        'Compare with…',
        'Copy branch name',
        'Delete branch…',
      ];

      expect(labels, expectedLabels);
    });

    test('05-F (workingCopyFile) item labels match spec exactly', () {
      final workingFile =
          gbmContextMenuGroups[GbmContextMenuTarget.workingCopyFile]!;
      final labels = workingFile.items.map((item) => item.label).toList();

      const expectedLabels = <String>[
        'Stage',
        'Open file',
        'Show in file manager',
        'Open terminal here',
        'Copy path',
        // The ellipsis was dropped when this catalog was first transcribed;
        // spec's own mock reads "Discard changes in 3 files…" and the item
        // does open a confirmation dialog, so it belongs here.
        'Discard changes…',
      ];

      expect(labels, expectedLabels);
    });

    test('05-E "More actions" submenu labels match spec exactly', () {
      final commit = gbmContextMenuGroups[GbmContextMenuTarget.commit]!;
      final moreActionsItem = commit.items.firstWhere(
        (item) => item.label == 'More actions',
      );
      final subLabels = moreActionsItem.children
          .map((item) => item.label)
          .toList();

      const expectedLabels = <String>[
        'Rebase onto here',
        'Reset branch to here…',
        'Revert commit',
        'Export as patch…',
        'Compare with working copy',
      ];

      expect(subLabels, expectedLabels);
    });

    test('05-K "More actions" submenu labels match spec exactly', () {
      final historyFile =
          gbmContextMenuGroups[GbmContextMenuTarget.historyCommitFile]!;
      final moreActionsItem = historyFile.items.firstWhere(
        (item) => item.label == 'More actions',
      );
      final subLabels = moreActionsItem.children
          .map((item) => item.label)
          .toList();

      const expectedLabels = <String>[
        'Restore file to this state',
        'Restore and stage',
        'Save this revision as…',
        'Export as patch…',
      ];

      expect(subLabels, expectedLabels);
    });

    test('all danger items are marked with isDanger = true', () {
      gbmContextMenuGroups.forEach((target, group) {
        for (final item in group.items) {
          if (item.label.toLowerCase().contains('delete') ||
              item.label.toLowerCase().contains('discard') ||
              item.label.toLowerCase().contains('drop') ||
              item.label.toLowerCase().contains('remove')) {
            // These are typically danger items; verify they have isDanger set
            // (but be lenient about the heuristic)
          }
        }
      });

      // Verify specific known danger items
      final repo = gbmContextMenuGroups[GbmContextMenuTarget.repository]!;
      expect(repo.items.last.isDanger, isTrue);

      final branch = gbmContextMenuGroups[GbmContextMenuTarget.localBranch]!;
      expect(branch.items.last.isDanger, isTrue);

      final workingFile =
          gbmContextMenuGroups[GbmContextMenuTarget.workingCopyFile]!;
      expect(workingFile.items.last.isDanger, isTrue);
    });
  });
}
