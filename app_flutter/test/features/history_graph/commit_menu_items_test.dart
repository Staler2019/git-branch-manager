// MULTIACTS' gating rules for the 05-E commit menu: which items stay live
// for a multi-selection, which are kept-but-disabled with a reason, and how
// the labels report the count. Catalog parity itself is asserted in
// context_menu_parity_test.dart; this file covers the states that catalog
// does not describe.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

List<GbmMenuItem> _items({
  int count = 1,
  bool contiguous = true,
  bool conflictActive = false,
}) => commitMenuItems(
  count: count,
  contiguous: contiguous,
  conflictActive: conflictActive,
  onCopySha: () {},
  onCheckout: () {},
  onMerge: () {},
  onCherryPick: () {},
  onCreateBranchHere: () {},
  onCompare: () {},
  onRebaseOntoHere: () {},
  onResetBranchHere: () {},
  onRevert: () {},
  onExportAsPatch: () {},
  onCompareWithWorkingCopy: () {},
);

GbmMenuItem _find(List<GbmMenuItem> items, String startsWith) {
  for (final GbmMenuItem item in items) {
    if (item.label.startsWith(startsWith)) return item;
    for (final GbmMenuItem child in item.children) {
      if (child.label.startsWith(startsWith)) return child;
    }
  }
  fail('no item starting with "$startsWith"');
}

void main() {
  group('single selection', () {
    test('everything with a callback is enabled', () {
      for (final GbmMenuItem item in _items()) {
        if (item.isSubmenuTrigger) {
          for (final GbmMenuItem child in item.children) {
            expect(child.enabled, isTrue, reason: child.label);
          }
          continue;
        }
        expect(item.enabled, isTrue, reason: item.label);
      }
    });

    test('an action with no callback is disabled rather than hidden', () {
      // Spec page 13: 「保留但 disabled…不隱藏 — 隱藏會讓人以為功能不存在」.
      final List<GbmMenuItem> items = commitMenuItems(
        count: 1,
        contiguous: true,
        conflictActive: false,
        onCopySha: () {},
      );
      expect(items.length, 7, reason: 'all 7 top-level items still render');
      final GbmMenuItem checkout = _find(items, 'Checkout');
      expect(checkout.enabled, isFalse);
      expect(checkout.onTap, isNull, reason: 'enabled alone is only visual');
    });
  });

  group('multi-selection labels carry the count', () {
    test('cherry-pick, revert, copy and export are pluralised', () {
      final List<GbmMenuItem> items = _items(count: 3);
      expect(_find(items, 'Cherry-pick').label, 'Cherry-pick 3 commits');
      expect(_find(items, 'Copy').label, 'Copy 3 SHAs');
      expect(_find(items, 'Revert').label, 'Revert 3 commits');
      expect(_find(items, 'Export').label, 'Export 3 patches…');
    });

    test('single-target items keep their singular label', () {
      final List<GbmMenuItem> items = _items(count: 3);
      expect(_find(items, 'Checkout').label, 'Checkout this commit');
      expect(_find(items, 'Merge').label, 'Merge into current');
    });
  });

  group('MULTIACTS: single-target actions are disabled with a reason', () {
    test('checkout / merge / create branch / reset / rebase / compare-with-'
        'working-copy all explain themselves', () {
      final List<GbmMenuItem> items = _items(count: 3);
      for (final String label in <String>[
        'Checkout',
        'Merge',
        'Create branch',
        'Reset branch',
        'Rebase onto',
        'Compare with working copy',
      ]) {
        final GbmMenuItem item = _find(items, label);
        expect(item.enabled, isFalse, reason: label);
        expect(item.onTap, isNull, reason: label);
        expect(item.tooltip, kSingleCommitOnlyTooltip, reason: label);
      }
    });

    test('copy SHA and export stay live -- MULTIACTS lists both as '
        'multi-capable', () {
      final List<GbmMenuItem> items = _items(count: 3);
      expect(_find(items, 'Copy').enabled, isTrue);
      expect(_find(items, 'Export').enabled, isTrue);
    });
  });

  group('MULTIACTS: contiguity gates cherry-pick and revert', () {
    test('a contiguous multi-selection leaves both live', () {
      final List<GbmMenuItem> items = _items(count: 3);
      expect(_find(items, 'Cherry-pick').enabled, isTrue);
      expect(_find(items, 'Revert').enabled, isTrue);
    });

    test('a gappy multi-selection disables both with the reason', () {
      final List<GbmMenuItem> items = _items(count: 3, contiguous: false);
      for (final String label in <String>['Cherry-pick', 'Revert']) {
        final GbmMenuItem item = _find(items, label);
        expect(item.enabled, isFalse, reason: label);
        expect(item.onTap, isNull, reason: label);
        expect(item.tooltip, kContiguousOnlyTooltip, reason: label);
      }
    });

    test('contiguity is irrelevant to a single selection', () {
      final List<GbmMenuItem> items = _items(contiguous: false);
      expect(_find(items, 'Cherry-pick').enabled, isTrue);
      expect(_find(items, 'Revert').enabled, isTrue);
    });
  });

  group('Compare takes one or two commits', () {
    test('one or two are fine', () {
      expect(_find(_items(), 'Compare with…').enabled, isTrue);
      expect(_find(_items(count: 2), 'Compare with…').enabled, isTrue);
    });

    test('three or more is disabled -- a comparison has two ends', () {
      final GbmMenuItem compare = _find(_items(count: 3), 'Compare with…');
      expect(compare.enabled, isFalse);
      expect(compare.tooltip, kTwoCommitsAtMostTooltip);
    });
  });

  group('spec page 07: mid-conflict', () {
    test('every HEAD-moving item is disabled and says why', () {
      final List<GbmMenuItem> items = _items(conflictActive: true);
      for (final String label in <String>[
        'Checkout',
        'Merge',
        'Cherry-pick',
        'Create branch',
        'Rebase onto',
        'Reset branch',
        'Revert',
      ]) {
        final GbmMenuItem item = _find(items, label);
        expect(item.enabled, isFalse, reason: label);
        expect(item.tooltip, kConflictActiveTooltip, reason: label);
      }
    });

    test('read-only items stay live -- a conflict does not make reading '
        'history unsafe', () {
      final List<GbmMenuItem> items = _items(conflictActive: true);
      expect(_find(items, 'Compare with…').enabled, isTrue);
      expect(_find(items, 'Copy').enabled, isTrue);
      expect(_find(items, 'Export').enabled, isTrue);
    });
  });
}
