// Counting tests for `matchingRowIndices`' memo.
//
// A broken cache still answers correctly -- it just recomputes -- so an
// assertion on the *result* cannot tell a working memo from a missing one.
// These tests assert on `MatchMemoStats`' hit/miss counters instead, per
// this repo's rule that every cache needs a test that counts rather than
// one that only checks the output.
//
// Counters are global to the isolate and never reset, so every assertion
// below is a **delta** against a `before` snapshot -- the same shape
// `graph_span_index_test.dart` uses for `debugBuildCount`.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_search.dart';

CommitMeta _meta({required String oid, String subject = ''}) {
  const Signature author = Signature(
    name: '',
    email: '',
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
    body: '',
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
  final GraphSnapshotView graph = _graph(<String>['aaa1', 'bbb2', 'ccc3']);
  final Map<String, CommitMeta> cache = <String, CommitMeta>{
    'aaa1': _meta(oid: 'aaa1', subject: 'Add lane allocator'),
    'bbb2': _meta(oid: 'bbb2', subject: 'Unrelated change'),
    'ccc3': _meta(oid: 'ccc3', subject: 'Fix lane overflow'),
  };

  test('the same query over the same graph and cache is computed once', () {
    final int misses = MatchMemoStats.misses;
    final int hits = MatchMemoStats.hits;

    final List<int> first = matchingRowIndices(
      query: 'lane',
      graph: graph,
      metaCache: cache,
    );
    final List<int> second = matchingRowIndices(
      query: 'lane',
      graph: graph,
      metaCache: cache,
    );

    expect(first, <int>[0, 2]);
    expect(second, <int>[0, 2], reason: 'a memo must not change the answer');
    expect(MatchMemoStats.misses - misses, 1);
    expect(
      MatchMemoStats.hits - hits,
      1,
      reason: 'the second call must be served from the memo, not rescanned',
    );
  });

  test('a different query over the same graph and cache is recomputed', () {
    matchingRowIndices(query: 'lane', graph: graph, metaCache: cache);
    final int misses = MatchMemoStats.misses;

    final List<int> other = matchingRowIndices(
      query: 'unrelated',
      graph: graph,
      metaCache: cache,
    );

    expect(other, <int>[1]);
    expect(
      MatchMemoStats.misses - misses,
      1,
      reason:
          'the query is part of the key; dropping it would serve the '
          'previous query\'s answer',
    );
  });

  test('newly arrived metadata surfaces its matching rows -- the symptom '
      'test for a key that ignored the metadata cache', () {
    // Before any metadata: only a hash prefix can match.
    final Map<String, CommitMeta> beforeMeta = const <String, CommitMeta>{};
    expect(
      matchingRowIndices(query: 'lane', graph: graph, metaCache: beforeMeta),
      isEmpty,
    );

    // `withCommitMeta` spreads into a **new** map rather than mutating, so
    // the arrival of metadata is exactly a change of map identity.
    final Map<String, CommitMeta> afterMeta = <String, CommitMeta>{
      ...beforeMeta,
      ...cache,
    };

    expect(
      matchingRowIndices(query: 'lane', graph: graph, metaCache: afterMeta),
      <int>[0, 2],
      reason:
          'a memo keyed only on (graph, query) would still answer empty '
          'here -- the user would type a filter, watch metadata stream in, '
          'and never see the matching commits appear',
    );
  });

  test('an equal-but-distinct cache instance is a miss, not a hit', () {
    matchingRowIndices(query: 'lane', graph: graph, metaCache: cache);
    final int misses = MatchMemoStats.misses;

    final Map<String, CommitMeta> copy = Map<String, CommitMeta>.of(cache);
    expect(
      matchingRowIndices(query: 'lane', graph: graph, metaCache: copy),
      <int>[0, 2],
    );

    expect(
      MatchMemoStats.misses - misses,
      1,
      reason:
          'the key is instance identity, not deep equality -- this is '
          'why the hit rate is partial while metadata is still streaming',
    );
  });

  test('a different snapshot is a miss', () {
    matchingRowIndices(query: 'lane', graph: graph, metaCache: cache);
    final int misses = MatchMemoStats.misses;

    final GraphSnapshotView other = _graph(<String>['aaa1', 'bbb2']);
    matchingRowIndices(query: 'lane', graph: other, metaCache: cache);

    expect(MatchMemoStats.misses - misses, 1);
  });

  test('an empty query never touches the memo', () {
    final int misses = MatchMemoStats.misses;
    final int hits = MatchMemoStats.hits;

    matchingRowIndices(query: '', graph: graph, metaCache: cache);
    matchingRowIndices(query: '', graph: graph, metaCache: cache);

    expect(
      <int>[MatchMemoStats.misses - misses, MatchMemoStats.hits - hits],
      <int>[0, 0],
      reason:
          'the unfiltered answer is UnfilteredRowIndices, which computes '
          'nothing and so has nothing to cache',
    );
  });

  test('a real withCommitMeta transition is a miss -- pins the producer the '
      'memo key depends on', () {
    // Every other test here builds the "new" metadata cache by hand. This
    // one goes through the real producer, because the key's honesty rests
    // entirely on `withCommitMeta` spreading into a **new** map rather than
    // mutating the old one in place. Were that ever "optimised" to mutate,
    // the memo would keep serving pre-metadata answers and no other test
    // in this file would notice -- they would all still construct their own
    // fresh maps and pass.
    // The seed map below is a plain growable literal, deliberately not
    // `const` and deliberately not built by calling `withCommitMeta`
    // itself. `RepoSessionState`'s default cache is a `const` map, which is
    // unmodifiable -- an in-place mutation would throw on it, and this test
    // would go red without any of its own assertions being what caught the
    // defect. A growable map is also what the app really holds from the
    // first metadata reply onwards, so the mutation succeeds here and the
    // three assertions below are what stand between it and the user.
    final RepoSessionState seeded = RepoSessionState(
      isOpen: true,
      commitMetaCache: <String, CommitMeta>{
        'ccc3': _meta(oid: 'ccc3', subject: 'Fix lane overflow'),
      },
    );
    expect(
      matchingRowIndices(
        query: 'lane',
        graph: graph,
        metaCache: seeded.commitMetaCache,
      ),
      <int>[2],
    );
    final int misses = MatchMemoStats.misses;

    final RepoSessionState next = seeded.withCommitMeta(<CommitMeta>[
      _meta(oid: 'aaa1', subject: 'Add lane allocator'),
    ]);

    expect(
      identical(next.commitMetaCache, seeded.commitMetaCache),
      isFalse,
      reason: 'withCommitMeta must not mutate the cache in place',
    );
    expect(
      matchingRowIndices(
        query: 'lane',
        graph: graph,
        metaCache: next.commitMetaCache,
      ),
      <int>[0, 2],
      reason:
          'in-place mutation would leave the memo serving the pre-batch '
          'answer under an unchanged key',
    );
    expect(MatchMemoStats.misses - misses, 1);
  });

  test('the shared result cannot be mutated by one caller under another', () {
    final List<int> rows = matchingRowIndices(
      query: 'lane',
      graph: graph,
      metaCache: cache,
    );
    expect(() => rows.add(99), throwsUnsupportedError);
    expect(() => rows[0] = 99, throwsUnsupportedError);
  });
}
