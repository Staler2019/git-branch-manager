import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/features/history_graph/commit_search.dart';

CommitMeta _meta({
  required String oid,
  String subject = '',
  String body = '',
  String authorName = '',
  String authorEmail = '',
}) {
  final Signature author = Signature(
    name: authorName,
    email: authorEmail,
    when: 0,
    tzOffsetMinutes: 0,
  );
  return CommitMeta(
    oid: oid,
    tree: '',
    parents: const <String>[],
    author: author,
    committer: author,
    subject: subject,
    body: body,
    signedCommit: false,
  );
}

GraphRow _row() => const GraphRow(
  parentOffset: 0,
  edgeOffset: 0,
  commitTime: 0,
  lane: 0,
  color: 0,
  flags: 0,
);

GraphSnapshotView _graph(List<String> oids) => GraphSnapshotView(
  rows: <GraphRow>[for (final _ in oids) _row()],
  oidsHex: oids,
  parentPool: const <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
  edges: const <GraphEdge>[],
);

void main() {
  group('commitMatchesQuery', () {
    final CommitMeta meta = _meta(
      oid: 'a1b2c3d4e5',
      subject: 'Fix lane allocator overflow gutter',
      body: 'Caps allocation at 48 lanes.',
      authorName: 'J. Chen',
      authorEmail: 'j.chen@example.com',
    );

    test('an empty query matches everything', () {
      expect(
        commitMatchesQuery(query: '', oid: 'a1b2c3d4e5', meta: meta),
        isTrue,
      );
      // Even with no metadata loaded yet.
      expect(
        commitMatchesQuery(query: '', oid: 'a1b2c3d4e5', meta: null),
        isTrue,
      );
    });

    test('matches the subject case-insensitively', () {
      expect(
        commitMatchesQuery(query: 'LANE ALLOCATOR', oid: 'x', meta: meta),
        isTrue,
      );
    });

    test('matches the body, not just the subject', () {
      expect(
        commitMatchesQuery(query: '48 lanes', oid: 'x', meta: meta),
        isTrue,
      );
    });

    test('matches author name and email', () {
      expect(
        commitMatchesQuery(query: 'j. chen', oid: 'x', meta: meta),
        isTrue,
      );
      expect(
        commitMatchesQuery(query: 'example.com', oid: 'x', meta: meta),
        isTrue,
      );
    });

    test('matches a hash prefix but not a hash substring', () {
      expect(
        commitMatchesQuery(query: 'a1b2', oid: 'a1b2c3d4e5', meta: meta),
        isTrue,
        reason: 'an abbreviated oid is meaningful as a prefix',
      );
      expect(
        commitMatchesQuery(query: 'b2c3', oid: 'a1b2c3d4e5', meta: null),
        isFalse,
        reason:
            'substring-matching hex would make short queries match almost '
            'every commit',
      );
    });

    test('a row with no metadata can still match on its hash', () {
      expect(
        commitMatchesQuery(query: 'a1b2', oid: 'a1b2c3d4e5', meta: null),
        isTrue,
      );
      expect(
        commitMatchesQuery(query: 'gutter', oid: 'a1b2c3d4e5', meta: null),
        isFalse,
        reason: 'the subject is unknown until commitMetaReady answers',
      );
    });

    test('a non-matching query matches nothing', () {
      expect(
        commitMatchesQuery(query: 'zzzz', oid: 'a1b2c3d4e5', meta: meta),
        isFalse,
      );
    });
  });

  group('matchingRowIndices', () {
    final GraphSnapshotView graph = _graph(<String>['aaa1', 'bbb2', 'ccc3']);
    final Map<String, CommitMeta> cache = <String, CommitMeta>{
      'aaa1': _meta(oid: 'aaa1', subject: 'Add lane allocator'),
      'bbb2': _meta(oid: 'bbb2', subject: 'Unrelated change'),
      'ccc3': _meta(oid: 'ccc3', subject: 'Fix lane overflow'),
    };

    test('an empty query returns every row in order', () {
      expect(
        matchingRowIndices(query: '', graph: graph, metaCache: cache),
        <int>[0, 1, 2],
      );
    });

    test('returns indices into the unfiltered snapshot, not a dense range', () {
      expect(
        matchingRowIndices(query: 'lane', graph: graph, metaCache: cache),
        <int>[0, 2],
        reason:
            'callers need the original row index for selection and edge '
            'lookups',
      );
    });

    test('returns empty when nothing matches', () {
      expect(
        matchingRowIndices(query: 'nothing', graph: graph, metaCache: cache),
        isEmpty,
      );
    });

    test('an empty graph yields no matches', () {
      expect(
        matchingRowIndices(
          query: 'lane',
          graph: _graph(const <String>[]),
          metaCache: const <String, CommitMeta>{},
        ),
        isEmpty,
      );
    });
  });
}
