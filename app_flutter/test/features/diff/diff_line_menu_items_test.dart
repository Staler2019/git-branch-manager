// Unit tests for 05-G's item list as a pure function, mirroring
// `working_copy_file_menu_items_test.dart`. `diff_line_test.dart` covers the
// render site; `context_menu_parity_test.dart` checks this list against the
// spec catalog.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line_menu_items.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

List<String> _labels(List<GbmMenuItem> items) => items
    .where((GbmMenuItem i) => !i.separator)
    .map((GbmMenuItem i) => i.label)
    .toList();

GbmMenuItem _itemNamed(List<GbmMenuItem> items, String label) =>
    items.firstWhere((GbmMenuItem i) => i.label == label);

List<GbmMenuItem> _items({
  int count = 1,
  bool staged = false,
  bool canStageLines = true,
  bool canStageHunk = true,
  bool canDiscard = true,
  void Function()? onStageLines,
  void Function()? onStageHunk,
  void Function()? onCopyLines,
  void Function()? onDiscardLines,
}) {
  return diffLineMenuItems(
    count: count,
    staged: staged,
    onStageLines: canStageLines ? (onStageLines ?? () {}) : null,
    onStageHunk: canStageHunk ? (onStageHunk ?? () {}) : null,
    onCopyLines: onCopyLines ?? () {},
    onDiscardLines: canDiscard ? (onDiscardLines ?? () {}) : null,
  );
}

void main() {
  group('spec 05-G order and labels', () {
    test('an unstaged diff line gives the five spec items in spec order', () {
      expect(_labels(_items()), <String>[
        'Stage',
        'Stage hunk',
        'Unstage hunk',
        'Copy lines',
        'Discard…',
      ]);
    });

    test('a staged diff line swaps Stage for Unstage and drops Discard', () {
      // Discarding rewrites the work tree; a staged-side line has nothing
      // there to rewrite, so the caller passes onDiscardLines: null.
      expect(_labels(_items(staged: true, canDiscard: false)), <String>[
        'Unstage',
        'Stage hunk',
        'Unstage hunk',
        'Copy lines',
      ]);
    });

    test('stays within showGbmContextMenu\'s cap and danger rules', () {
      final List<GbmMenuItem> items = _items();
      expect(items.last.label, 'Discard…');
      expect(items.last.danger, isTrue);
      expect(items[items.length - 2].separator, isTrue);
      expect(() => validateGbmMenuItems(items), returnsNormally);
    });
  });

  group('both hunk directions are always rendered (spec lists both)', () {
    test('unstaged: Stage hunk is live, Unstage hunk is inert', () {
      final List<GbmMenuItem> items = _items();
      expect(_itemNamed(items, 'Stage hunk').enabled, isTrue);
      expect(_itemNamed(items, 'Stage hunk').onTap, isNotNull);
      expect(_itemNamed(items, 'Unstage hunk').enabled, isFalse);
      expect(
        _itemNamed(items, 'Unstage hunk').onTap,
        isNull,
        reason:
            'GbmMenuItem.enabled is visual only -- onTap must also be '
            'null or the disabled item still dispatches',
      );
    });

    test('staged: the two swap', () {
      final List<GbmMenuItem> items = _items(staged: true, canDiscard: false);
      expect(_itemNamed(items, 'Unstage hunk').enabled, isTrue);
      expect(_itemNamed(items, 'Unstage hunk').onTap, isNotNull);
      expect(_itemNamed(items, 'Stage hunk').enabled, isFalse);
      expect(_itemNamed(items, 'Stage hunk').onTap, isNull);
    });

    test('both are inert when the hunk callback is absent entirely', () {
      final List<GbmMenuItem> items = _items(canStageHunk: false);
      for (final String label in <String>['Stage hunk', 'Unstage hunk']) {
        expect(_itemNamed(items, label).enabled, isFalse, reason: label);
        expect(_itemNamed(items, label).onTap, isNull, reason: label);
      }
    });
  });

  group('multi-line selection carries the count (spec: "Stage 12 lines")', () {
    test('Stage and Discard pluralize', () {
      final List<String> labels = _labels(_items(count: 12));
      expect(labels.first, 'Stage 12 lines');
      expect(labels.last, 'Discard 12 lines…');
    });

    test('Unstage pluralizes too', () {
      expect(
        _labels(_items(count: 4, staged: true, canDiscard: false)).first,
        'Unstage 4 lines',
      );
    });

    test('Copy lines is plural regardless -- the spec label has no count', () {
      expect(_labels(_items(count: 12)), contains('Copy lines'));
      expect(_labels(_items()), contains('Copy lines'));
    });
  });

  group('dispatch', () {
    test('each live item invokes the callback it was given', () {
      final List<String> fired = <String>[];
      final List<GbmMenuItem> items = _items(
        onStageLines: () => fired.add('lines'),
        onStageHunk: () => fired.add('hunk'),
        onCopyLines: () => fired.add('copy'),
        onDiscardLines: () => fired.add('discard'),
      );
      for (final GbmMenuItem item in items.where(
        (GbmMenuItem i) => !i.separator,
      )) {
        item.onTap?.call();
      }
      expect(fired, <String>['lines', 'hunk', 'copy', 'discard']);
    });

    test('a context line has no line-level stage item to dispatch', () {
      final List<GbmMenuItem> items = _items(canStageLines: false);
      expect(_itemNamed(items, 'Stage').enabled, isFalse);
      expect(_itemNamed(items, 'Stage').onTap, isNull);
    });
  });
}
