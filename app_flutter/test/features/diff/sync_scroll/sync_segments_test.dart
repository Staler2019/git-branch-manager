// Slice S1: the columns of `2 file` and conflict resolve are cut into
// segments as finely as possible without cutting any column's item in two
// (plan: Slice S, 「定義」). The fixtures write every expected segment out;
// the seeded test checks the three invariants on shapes no fixture names.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/diff_scopes.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_segments.dart';

SyncSpan<int> _s(int lo, [int? hi]) => (lo: lo, hi: hi ?? lo);

int _int(int a, int b) => a.compareTo(b);

List<List<int>> _segments(List<List<SyncSpan<int>?>> columns) =>
    partitionSyncSegments<int>(columns, _int).segmentOf;

void main() {
  group('fixtures', () {
    test('adjacent spans split, touching ones do not', () {
      expect(
        _segments(<List<SyncSpan<int>?>>[
          <SyncSpan<int>?>[_s(1, 3)],
          <SyncSpan<int>?>[_s(4, 5)],
        ]),
        <List<int>>[
          <int>[1],
          <int>[2],
        ],
      );
      expect(
        _segments(<List<SyncSpan<int>?>>[
          <SyncSpan<int>?>[_s(1, 3)],
          <SyncSpan<int>?>[_s(3, 5)],
        ]),
        <List<int>>[
          <int>[1],
          <int>[1],
        ],
      );
    });

    test('one long item takes the other column\'s items with it', () {
      final SyncSegments s = partitionSyncSegments<int>(<List<SyncSpan<int>?>>[
        <SyncSpan<int>?>[_s(1), _s(2, 6), _s(7)],
        <SyncSpan<int>?>[_s(1), _s(2), _s(3), _s(5), _s(7)],
      ], _int);
      expect(s.segmentOf, <List<int>>[
        <int>[1, 2, 3],
        <int>[1, 2, 2, 2, 3],
      ]);
      expect(s.count, 4);
    });

    test('items that start together share a segment', () {
      expect(
        _segments(<List<SyncSpan<int>?>>[
          <SyncSpan<int>?>[_s(4, 4), _s(9)],
          <SyncSpan<int>?>[_s(4, 8), _s(9)],
        ]),
        <List<int>>[
          <int>[1, 2],
          <int>[1, 2],
        ],
      );
    });

    test('an empty column has no items and takes no segment', () {
      final SyncSegments s = partitionSyncSegments<int>(<List<SyncSpan<int>?>>[
        <SyncSpan<int>?>[_s(1), _s(3)],
        <SyncSpan<int>?>[],
      ], _int);
      expect(s.segmentOf, <List<int>>[
        <int>[1, 2],
        <int>[],
      ]);
      expect(s.count, 3);
    });

    test('items with no position stay in the leading segment 0', () {
      final SyncSegments s = partitionSyncSegments<int>(<List<SyncSpan<int>?>>[
        <SyncSpan<int>?>[null, null],
        <SyncSpan<int>?>[null],
      ], _int);
      expect(s.segmentOf, <List<int>>[
        <int>[0, 0],
        <int>[0],
      ]);
      expect(s.count, 1);
    });

    test('a leading head is segment 0, the first positioned item is not', () {
      expect(
        _segments(<List<SyncSpan<int>?>>[
          <SyncSpan<int>?>[null, _s(1), _s(2)],
          <SyncSpan<int>?>[null, null, _s(2)],
        ]),
        <List<int>>[
          <int>[0, 1, 2],
          <int>[0, 0, 2],
        ],
      );
    });
  });

  test('an item with no position after one that has it joins its segment', () {
    expect(
      _segments(<List<SyncSpan<int>?>>[
        <SyncSpan<int>?>[_s(1), _s(3), null, _s(5)],
        <SyncSpan<int>?>[_s(1), _s(5)],
      ]),
      <List<int>>[
        <int>[1, 2, 2, 3],
        <int>[1, 3],
      ],
    );
  });

  group('IndexPosition (B6)', () {
    SyncSpan<IndexPosition> at(int line, int offset) =>
        (lo: (line: line, offset: offset), hi: (line: line, offset: offset));

    test('an unstaged insertion at (41,1) sits between staged (41,0) and '
        '(42,0)', () {
      expect(
        partitionSyncSegments<IndexPosition>(<List<SyncSpan<IndexPosition>?>>[
          <SyncSpan<IndexPosition>?>[at(41, 1)],
          <SyncSpan<IndexPosition>?>[at(41, 0), at(42, 0)],
        ], compareIndexPositions).segmentOf,
        <List<int>>[
          <int>[2],
          <int>[1, 3],
        ],
      );
    });

    test('a staged deletion and an unstaged insertion at the same (L,1) share '
        'a segment', () {
      expect(
        partitionSyncSegments<IndexPosition>(<List<SyncSpan<IndexPosition>?>>[
          <SyncSpan<IndexPosition>?>[at(10, 0), at(10, 1), at(11, 0)],
          <SyncSpan<IndexPosition>?>[at(10, 0), at(10, 1), at(11, 0)],
        ], compareIndexPositions).segmentOf,
        <List<int>>[
          <int>[1, 2, 3],
          <int>[1, 2, 3],
        ],
      );
    });
  });

  test('seeded: no item is cut, order holds, and no segment can be cut '
      'finer', () {
    final Random rng = Random(20261025);
    for (int round = 0; round < 500; round++) {
      final int columnCount = 2 + rng.nextInt(2);
      final List<List<SyncSpan<int>?>> columns = <List<SyncSpan<int>?>>[];
      for (int c = 0; c < columnCount; c++) {
        final List<SyncSpan<int>?> items = <SyncSpan<int>?>[
          for (int i = rng.nextInt(3); i > 0; i--) null,
        ];
        int at = 0;
        for (int i = rng.nextInt(12); i > 0; i--) {
          at += 1 + rng.nextInt(3);
          final int len = rng.nextInt(4);
          items.add(_s(at, at + len));
          at += len;
        }
        columns.add(items);
      }
      final SyncSegments s = partitionSyncSegments<int>(columns, _int);
      final String why = 'round $round: $columns -> ${s.segmentOf}';

      // Order holds: segments never go backwards down a column, and every
      // segment index is in range.
      for (final List<int> column in s.segmentOf) {
        for (int i = 0; i < column.length; i++) {
          expect(column[i], inInclusiveRange(0, s.count - 1), reason: why);
          if (i > 0) {
            expect(column[i], greaterThanOrEqualTo(column[i - 1]), reason: why);
          }
        }
      }

      // Segment 0 holds exactly the items with no position.
      for (int c = 0; c < columnCount; c++) {
        for (int i = 0; i < columns[c].length; i++) {
          expect(s.segmentOf[c][i] == 0, columns[c][i] == null, reason: why);
        }
      }

      // Each positioned segment's span, across every column.
      final List<int?> lo = List<int?>.filled(s.count, null);
      final List<int?> hi = List<int?>.filled(s.count, null);
      for (int c = 0; c < columnCount; c++) {
        for (int i = 0; i < columns[c].length; i++) {
          final SyncSpan<int>? span = columns[c][i];
          if (span == null) continue;
          final int k = s.segmentOf[c][i];
          lo[k] = lo[k] == null ? span.lo : min(lo[k]!, span.lo);
          hi[k] = hi[k] == null ? span.hi : max(hi[k]!, span.hi);
        }
      }
      for (int k = 1; k < s.count; k++) {
        expect(lo[k], isNotNull, reason: '$why: segment $k is empty');
        // No item is cut: segments do not overlap.
        if (k > 1) expect(hi[k - 1]! < lo[k]!, isTrue, reason: why);
        // As fine as possible: inside a segment, the items sorted by lo
        // overlap their running max hi, so no cut fits between them.
        final List<SyncSpan<int>> inK = <SyncSpan<int>>[
          for (int c = 0; c < columnCount; c++)
            for (int i = 0; i < columns[c].length; i++)
              if (s.segmentOf[c][i] == k) columns[c][i]!,
        ]..sort((SyncSpan<int> a, SyncSpan<int> b) => a.lo.compareTo(b.lo));
        int reach = inK.first.hi;
        for (final SyncSpan<int> span in inK.skip(1)) {
          expect(span.lo <= reach, isTrue, reason: '$why: segment $k splits');
          reach = max(reach, span.hi);
        }
      }
    }
  });
}
