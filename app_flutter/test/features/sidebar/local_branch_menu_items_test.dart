// The 05-B gating rules the catalog itself does not describe: which items
// spec page 07 disables mid-conflict, and the two reasons an item can be
// kept-but-disabled. Catalog parity is asserted in
// context_menu_parity_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/sidebar/widgets/local_branch_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

List<GbmMenuItem> _items({
  bool isCurrent = false,
  bool conflictActive = false,
}) => localBranchMenuItems(
  branchName: 'feature/x',
  isCurrent: isCurrent,
  conflictActive: conflictActive,
  onCheckout: () {},
  onNewBranchFromHere: () {},
  onRename: () {},
  onMerge: () {},
  onRebaseOntoHere: () {},
  onCompare: () {},
  onDelete: () {},
);

GbmMenuItem _find(List<GbmMenuItem> items, String label) =>
    items.firstWhere((GbmMenuItem i) => i.label == label);

void main() {
  test('a clean, non-current branch has everything enabled', () {
    for (final GbmMenuItem item in _items()) {
      if (item.separator) continue;
      expect(item.enabled, isTrue, reason: item.label);
    }
  });

  test('spec page 07: every ref-moving item is disabled mid-conflict, '
      'including the three that were ungated before this extraction', () {
    final List<GbmMenuItem> items = _items(conflictActive: true);
    for (final String label in <String>[
      'Checkout',
      'New branch from here…',
      'Rename…',
      'Merge into current',
      'Rebase current onto here',
      'Delete branch…',
    ]) {
      final GbmMenuItem item = _find(items, label);
      expect(item.enabled, isFalse, reason: label);
      expect(
        item.onTap,
        isNull,
        reason: '$label: enabled alone is only a visual signal',
      );
      expect(item.tooltip, kBranchConflictTooltip, reason: label);
    }
  });

  test('the read-only items stay live mid-conflict', () {
    final List<GbmMenuItem> items = _items(conflictActive: true);
    expect(_find(items, 'Compare with…').enabled, isTrue);
    expect(_find(items, 'Copy branch name').enabled, isTrue);
  });

  test('the current branch cannot be checked out, and says why', () {
    final GbmMenuItem checkout = _find(_items(isCurrent: true), 'Checkout');
    expect(checkout.enabled, isFalse);
    expect(checkout.onTap, isNull);
    expect(checkout.tooltip, kAlreadyOnBranchTooltip);
  });

  test('an item with no callback is still rendered, just disabled', () {
    final List<GbmMenuItem> items = localBranchMenuItems(
      branchName: 'feature/x',
      isCurrent: false,
      conflictActive: false,
    );
    expect(
      items.where((GbmMenuItem i) => !i.separator).length,
      8,
      reason: 'all 8 catalog items render regardless of wiring',
    );
    expect(_find(items, 'Rebase current onto here').enabled, isFalse);
    // Copy branch name has a built-in clipboard action, so it needs no
    // caller and is always live.
    expect(_find(items, 'Copy branch name').enabled, isTrue);
  });

  test('Delete branch… is the last item and is styled danger', () {
    final List<GbmMenuItem> items = _items();
    final GbmMenuItem last = items.lastWhere((GbmMenuItem i) => !i.separator);
    expect(last.label, 'Delete branch…');
    expect(last.danger, isTrue);
    expect(
      items[items.length - 2].separator,
      isTrue,
      reason: 'a danger item must be preceded by a separator',
    );
  });
}
