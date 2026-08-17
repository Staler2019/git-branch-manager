// RepoSessionState.commitMetaCache accumulates across every
// GBM_EVENT_COMMIT_META_READY reply for the life of a session (see its doc
// comment in repo_session_repository.dart) -- unlike operationLog, it had no
// cap at all, so a long session scrolling a very large repo's history would
// grow it without bound. This mirrors operationLog's _kMaxOperationLogEntries
// pattern: merge, then drop the oldest entries (insertion order) once over
// the cap.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

CommitMeta _meta(String oid) => CommitMeta(
  oid: oid,
  tree: 'tree-$oid',
  parents: const <String>[],
  author: Signature(
    name: 'Author',
    email: 'a@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: Signature(
    name: 'Author',
    email: 'a@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: 'subject $oid',
  body: '',
  signedCommit: false,
);

void main() {
  group('RepoSessionState.withCommitMeta', () {
    test('merges new metas into an empty cache, keyed by oid', () {
      const state = RepoSessionState(isOpen: true);
      final RepoSessionState next = state.withCommitMeta(<CommitMeta>[
        _meta('a'),
        _meta('b'),
      ]);
      expect(next.commitMetaCache.keys, <String>{'a', 'b'});
      expect(next.commitMetaCache['a']!.subject, 'subject a');
    });

    test('accumulates across multiple calls rather than replacing', () {
      const state = RepoSessionState(isOpen: true);
      final RepoSessionState afterFirst = state.withCommitMeta(<CommitMeta>[
        _meta('a'),
      ]);
      final RepoSessionState afterSecond = afterFirst.withCommitMeta(
        <CommitMeta>[_meta('b')],
      );
      expect(afterSecond.commitMetaCache.keys, <String>{'a', 'b'});
    });

    test('does not evict anything while under the cap', () {
      const state = RepoSessionState(isOpen: true);
      final RepoSessionState next = state.withCommitMeta(<CommitMeta>[
        for (int i = 0; i < 100; i++) _meta('oid-$i'),
      ]);
      expect(next.commitMetaCache.length, 100);
    });

    test('evicts the oldest entries (by insertion order) once the merged '
        'cache exceeds the cap, keeping the cache bounded', () {
      const state = RepoSessionState(isOpen: true);
      // Insert one over whatever the real cap is (comfortably above any
      // reasonable bound) across many small batches, the way a real
      // scrolling session would accumulate it in pages, not one giant
      // batch.
      RepoSessionState next = state;
      const int totalInserted = 5001;
      for (int i = 0; i < totalInserted; i++) {
        next = next.withCommitMeta(<CommitMeta>[_meta('oid-$i')]);
      }

      expect(
        next.commitMetaCache.length,
        lessThan(totalInserted),
        reason: 'the cache must be bounded, not grow without limit',
      );
      expect(
        next.commitMetaCache.containsKey('oid-0'),
        isFalse,
        reason: 'the oldest entry must be evicted once over the cap',
      );
      expect(
        next.commitMetaCache.containsKey('oid-${totalInserted - 1}'),
        isTrue,
        reason: 'the newest entry must always survive eviction',
      );
    });
  });
}
