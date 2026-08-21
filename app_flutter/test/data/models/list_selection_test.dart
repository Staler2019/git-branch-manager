// Walks spec page 13's MULTIKEYS table row by row against ListSelection,
// plus the two rules MULTIACTS depends on (contiguity, positional order).
// Pure unit tests: no widgets, no Riverpod — the transitions are the thing
// under test, not any list that happens to use them.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';

const List<String> _rows = <String>['a', 'b', 'c', 'd', 'e'];

ListSelection<String> _of(List<String> items, String? anchor) =>
    ListSelection<String>(items: items, anchor: anchor);

void main() {
  group('MULTIKEYS: 單擊 — 只選這一項，anchor 移到這一項', () {
    test('replaces any prior selection and moves the anchor', () {
      final ListSelection<String> result = _of(<String>[
        'a',
        'b',
      ], 'a').single('d');
      expect(result.items, <String>['d']);
      expect(result.anchor, 'd');
    });
  });

  group('MULTIKEYS: Ctrl/Cmd + 單擊 — 切換單項，anchor 移到此項', () {
    test('adds an unselected item and moves the anchor to it', () {
      final ListSelection<String> result = _of(<String>['a'], 'a').toggle('c');
      expect(result.items, <String>['a', 'c']);
      expect(result.anchor, 'c');
    });

    test('removes an already-selected item', () {
      final ListSelection<String> result = _of(<String>[
        'a',
        'b',
        'c',
      ], 'c').toggle('b');
      expect(result.items, <String>['a', 'c']);
    });

    test('deselecting a non-anchor item leaves the anchor alone', () {
      final ListSelection<String> result = _of(<String>[
        'a',
        'b',
        'c',
      ], 'c').toggle('a');
      expect(result.anchor, 'c');
    });

    test('deselecting the anchor promotes the newest survivor '
        '(MULTIKEYS does not specify this; pinned here rather than decided '
        'ad hoc at a call site)', () {
      final ListSelection<String> result = _of(<String>[
        'a',
        'b',
        'c',
      ], 'c').toggle('c');
      expect(result.items, <String>['a', 'b']);
      expect(result.anchor, 'b');
    });

    test('deselecting the last item empties the selection and the anchor', () {
      final ListSelection<String> result = _of(<String>['a'], 'a').toggle('a');
      expect(result.isEmpty, isTrue);
      expect(result.anchor, isNull);
    });
  });

  group('MULTIKEYS: Shift + 單擊 — anchor 到此項的連續範圍', () {
    test('selects the inclusive range downward', () {
      final ListSelection<String> result = _of(<String>[
        'b',
      ], 'b').range('d', _rows);
      expect(result.items, <String>['b', 'c', 'd']);
    });

    test('selects the inclusive range upward', () {
      final ListSelection<String> result = _of(<String>[
        'd',
      ], 'd').range('b', _rows);
      expect(result.items, <String>['b', 'c', 'd']);
    });

    test('leaves the anchor put so a second Shift-click resizes the '
        'same range instead of starting a new one', () {
      final ListSelection<String> first = _of(<String>[
        'b',
      ], 'b').range('e', _rows);
      expect(first.anchor, 'b');
      final ListSelection<String> second = first.range('c', _rows);
      expect(second.items, <String>['b', 'c']);
      expect(second.anchor, 'b');
    });

    test('degrades to a single selection with no anchor yet', () {
      final ListSelection<String> result = ListSelection<String>().range(
        'c',
        _rows,
      );
      expect(result.items, <String>['c']);
      expect(result.anchor, 'c');
    });

    test('degrades to a single selection when an end is not in the list', () {
      final ListSelection<String> result = _of(<String>[
        'zz',
      ], 'zz').range('c', _rows);
      expect(result.items, <String>['c']);
    });
  });

  group('MULTIKEYS: Ctrl/Cmd + A — 全選當前清單', () {
    test('selects everything and keeps a still-present anchor', () {
      final ListSelection<String> result = _of(<String>[
        'c',
      ], 'c').selectAll(_rows);
      expect(result.items, _rows);
      expect(result.anchor, 'c');
    });

    test('falls back to the first row when the anchor is gone', () {
      final ListSelection<String> result = _of(<String>[
        'zz',
      ], 'zz').selectAll(_rows);
      expect(result.anchor, 'a');
    });

    test('an empty list yields an empty selection, not an empty anchor', () {
      final ListSelection<String> result = _of(<String>[
        'a',
      ], 'a').selectAll(const <String>[]);
      expect(result.isEmpty, isTrue);
      expect(result.anchor, isNull);
    });
  });

  group('MULTIKEYS: Esc — 縮回單選（保留 anchor 項）', () {
    test('collapses to the anchor rather than clearing', () {
      final ListSelection<String> result = _of(<String>[
        'a',
        'b',
        'c',
      ], 'b').collapseToAnchor();
      expect(result.items, <String>['b']);
      expect(result.anchor, 'b');
    });

    test('an empty selection stays empty', () {
      expect(ListSelection<String>().collapseToAnchor().isEmpty, isTrue);
    });
  });

  group('MULTIACTS: 連續範圍 gating', () {
    test('a single item is contiguous', () {
      expect(_of(<String>['c'], 'c').isContiguousIn(_rows), isTrue);
    });

    test('an unbroken run is contiguous regardless of insertion order', () {
      expect(_of(<String>['d', 'b', 'c'], 'd').isContiguousIn(_rows), isTrue);
    });

    test('a gap is not contiguous', () {
      expect(_of(<String>['a', 'c'], 'a').isContiguousIn(_rows), isFalse);
    });

    test('an empty selection is not contiguous — there is nothing to run', () {
      expect(ListSelection<String>().isContiguousIn(_rows), isFalse);
    });

    test('an item missing from the list reads as non-contiguous, not a throw '
        '(a filter can change what the list holds under a live selection)', () {
      expect(_of(<String>['a', 'zz'], 'a').isContiguousIn(_rows), isFalse);
    });
  });

  group('orderedBy', () {
    test('returns list order, not insertion order', () {
      expect(_of(<String>['d', 'a', 'c'], 'd').orderedBy(_rows), <String>[
        'a',
        'c',
        'd',
      ]);
    });

    test('drops items absent from the list', () {
      expect(_of(<String>['zz', 'b'], 'b').orderedBy(_rows), <String>['b']);
    });
  });

  group('value semantics', () {
    test('equal items and anchor compare equal', () {
      expect(_of(<String>['a', 'b'], 'a'), _of(<String>['a', 'b'], 'a'));
      expect(
        _of(<String>['a', 'b'], 'a').hashCode,
        _of(<String>['a', 'b'], 'a').hashCode,
      );
    });

    test('a different anchor is a different selection', () {
      expect(_of(<String>['a', 'b'], 'a'), isNot(_of(<String>['a', 'b'], 'b')));
    });

    test('transitions never mutate the receiver', () {
      final ListSelection<String> original = _of(<String>['a'], 'a');
      original.toggle('b');
      original.range('c', _rows);
      original.selectAll(_rows);
      expect(original.items, <String>['a']);
      expect(original.anchor, 'a');
    });
  });
}
