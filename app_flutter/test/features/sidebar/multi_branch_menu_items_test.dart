// Spec page 13's MULTIBRANCHMENU. The catalog in gbm_context_menus.dart
// covers spec page *05* only, so there is no parity test to lean on here --
// these assertions are the acceptance baseline for this menu.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/sidebar/widgets/local_branch_menu_items.dart';
import 'package:gbm_flutter/features/sidebar/widgets/multi_branch_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

List<GbmMenuItem> _items({
  int count = 3,
  bool conflictActive = false,
  bool fetchable = true,
  bool pushable = true,
  bool comparable = false,
}) => multiBranchMenuItems(
  count: count,
  conflictActive: conflictActive,
  onCopyNames: () {},
  onFetch: fetchable ? () {} : null,
  onPush: pushable ? () {} : null,
  fetchBlockedReason: fetchable ? null : 'no upstream',
  pushBlockedReason: pushable ? null : 'no remote',
  onCompare: comparable ? () {} : null,
  onDelete: () {},
);

GbmMenuItem _find(List<GbmMenuItem> items, String label) =>
    items.firstWhere((GbmMenuItem i) => i.label == label);

void main() {
  test('the item list matches MULTIBRANCHMENU, counted labels included', () {
    expect(
      _items()
          .where((GbmMenuItem i) => !i.separator)
          .map((GbmMenuItem i) => i.label)
          .toList(),
      <String>[
        'Fetch 3 branches',
        'Push 3 branches',
        'Checkout',
        'Rename…',
        'Set upstream…',
        'Compare',
        'Copy branch names',
        'Delete 3 branches…',
      ],
    );
  });

  test('the menu is a valid GbmMenu (8-item cap, danger last)', () {
    expect(() => validateGbmMenuItems(_items()), returnsNormally);
  });

  test('the three 單項 items are kept, disabled and explained -- never '
      'hidden, per spec page 13', () {
    final List<GbmMenuItem> items = _items();
    for (final String label in <String>[
      'Checkout',
      'Rename…',
      'Set upstream…',
    ]) {
      final GbmMenuItem item = _find(items, label);
      expect(item.enabled, isFalse, reason: label);
      expect(
        item.onTap,
        isNull,
        reason: '$label: enabled alone is only a visual signal',
      );
      expect(item.tooltip, kSingleBranchOnlyTooltip, reason: label);
    }
  });

  test('Compare needs exactly two branches', () {
    expect(_find(_items(count: 2, comparable: true), 'Compare').enabled, true);
    final GbmMenuItem three = _find(_items(), 'Compare');
    expect(three.enabled, isFalse);
    expect(three.onTap, isNull);
    expect(three.tooltip, 'Compare takes exactly two branches');
  });

  test('spec page 07: Push and Delete are off mid-conflict, Fetch and Copy '
      'stay live', () {
    final List<GbmMenuItem> items = _items(conflictActive: true);
    for (final String label in <String>[
      'Push 3 branches',
      'Delete 3 branches…',
    ]) {
      final GbmMenuItem item = _find(items, label);
      expect(item.enabled, isFalse, reason: label);
      expect(item.onTap, isNull, reason: label);
      expect(item.tooltip, kBranchConflictTooltip, reason: label);
    }
    expect(_find(items, 'Fetch 3 branches').enabled, isTrue);
    expect(_find(items, 'Copy branch names').enabled, isTrue);
  });

  test(
    'an unavailable Fetch/Push says why rather than going silently grey',
    () {
      final List<GbmMenuItem> items = _items(fetchable: false, pushable: false);
      expect(_find(items, 'Fetch 3 branches').tooltip, 'no upstream');
      expect(_find(items, 'Push 3 branches').tooltip, 'no remote');
    },
  );

  test('mid-conflict, the conflict reason wins over the caller\'s Push '
      'reason -- the sequencer is the blocker the user has to clear first', () {
    final List<GbmMenuItem> items = _items(
      conflictActive: true,
      pushable: false,
    );
    expect(_find(items, 'Push 3 branches').tooltip, kBranchConflictTooltip);
  });
}
