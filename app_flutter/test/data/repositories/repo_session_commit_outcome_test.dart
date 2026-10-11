// The three counters the commit box waits on (prepared-commit-message
// Slice D): a commit's own outcome, a refs publish, and a commit-meta reply.
// Each is a count rather than a value so a waiter can tell "something new
// arrived since I asked" from "the same thing is still there".
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

GbmEvent _workingCopyFinished({required bool succeeded, String? kind}) =>
    GbmEvent(
      GbmEventType.workingCopyOperationFinished,
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'succeeded': succeeded,
          'error': succeeded
              ? null
              : <String, dynamic>{
                  'code': 1,
                  'codeName': 'ProcessFailed',
                  'message': 'hook rejected',
                  'detail': '',
                  'argv': <String>['git', 'commit'],
                  'exitCode': 1,
                },
          'choices': <dynamic>[],
          'summary': 'Commit',
          'kind': ?kind,
        }),
      ),
    );

Map<String, dynamic> _signature() => <String, dynamic>{
  'name': 'A',
  'email': 'a@example.com',
  'when': 0,
  'tzOffsetMinutes': 0,
};

GbmEvent _commitMetaReady(List<String> oids) => GbmEvent(
  GbmEventType.commitMetaReady,
  utf8.encode(
    jsonEncode(<Map<String, dynamic>>[
      for (final String oid in oids)
        <String, dynamic>{
          'oid': oid,
          'tree': 't' * 40,
          'parents': <String>['p' * 40],
          'author': _signature(),
          'committer': _signature(),
          'subject': 's',
          'body': '',
          'signed': false,
        },
    ]),
  ),
);

FakeRepoSessionController _controller() {
  final FakeRepoSessionController c = FakeRepoSessionController(
    _identity,
    const RepoSessionState(),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('commit outcome', () {
    test('a successful commit bumps the count and records success', () {
      final FakeRepoSessionController c = _controller();
      c.debugHandleEvent(_workingCopyFinished(succeeded: true, kind: 'commit'));
      expect(c.state.commitOutcomeSeq, 1);
      expect(c.state.lastCommitSucceeded, isTrue);
    });

    test('a failed commit bumps the count, records failure, and carries '
        'the error in the same publish', () {
      final FakeRepoSessionController c = _controller();
      final List<RepoSessionState> seen = <RepoSessionState>[];
      c.addListener(seen.add, fireImmediately: false);

      c.debugHandleEvent(
        _workingCopyFinished(succeeded: false, kind: 'commit'),
      );

      expect(c.state.commitOutcomeSeq, 1);
      expect(c.state.lastCommitSucceeded, isFalse);
      // A waiter reading the count must never see it move ahead of the
      // error, or "failed" would first look like "no error yet".
      final RepoSessionState first = seen.firstWhere(
        (RepoSessionState s) => s.commitOutcomeSeq == 1,
      );
      expect(first.lastError?.message, 'hook rejected');
    });

    test('an outcome with another kind, or none, is not a commit', () {
      final FakeRepoSessionController c = _controller();
      c.debugHandleEvent(_workingCopyFinished(succeeded: true));
      c.debugHandleEvent(_workingCopyFinished(succeeded: true, kind: 'fetch'));
      c.debugHandleEvent(_workingCopyFinished(succeeded: false));
      expect(c.state.commitOutcomeSeq, 0);
    });

    test('each commit counts once', () {
      final FakeRepoSessionController c = _controller();
      c.debugHandleEvent(
        _workingCopyFinished(succeeded: false, kind: 'commit'),
      );
      c.debugHandleEvent(_workingCopyFinished(succeeded: true, kind: 'commit'));
      expect(c.state.commitOutcomeSeq, 2);
      expect(c.state.lastCommitSucceeded, isTrue);
    });
  });

  test('every refs publish bumps refsEpoch, even an identical one', () {
    final FakeRepoSessionController c = _controller();
    expect(c.state.refsEpoch, 0);
    c.publishRefs(RefSnapshot.empty);
    c.publishRefs(RefSnapshot.empty);
    expect(c.state.refsEpoch, 2);
  });

  group('commit-meta replies', () {
    test('an empty reply still counts', () {
      final FakeRepoSessionController c = _controller();
      c.debugHandleEvent(_commitMetaReady(const <String>[]));
      expect(c.state.commitMetaReplySeq, 1);
      expect(c.state.commitMetaCache, isEmpty);
    });

    test('a reply counts once and lands in the cache in the same publish', () {
      final FakeRepoSessionController c = _controller();
      final List<RepoSessionState> seen = <RepoSessionState>[];
      c.addListener(seen.add, fireImmediately: false);
      final String oid = 'c' * 40;

      c.debugHandleEvent(_commitMetaReady(<String>[oid]));

      expect(c.state.commitMetaReplySeq, 1);
      expect(
        seen
            .firstWhere((RepoSessionState s) => s.commitMetaReplySeq == 1)
            .commitMetaCache
            .containsKey(oid),
        isTrue,
      );
    });
  });
}
