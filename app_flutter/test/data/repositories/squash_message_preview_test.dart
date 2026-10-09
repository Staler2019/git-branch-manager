// GBM_EVENT_SQUASH_MESSAGE_READY's Dart side. The reply carries the two oids
// its text was built from; [SquashMessagePreview.isCurrentFor] is the one
// reader that compares them against the session's refs, because a preview
// built for an older HEAD or source tip lists the wrong commits -- and the
// Merge dialog would write it as a permanent commit message.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final String _head = 'a' * 40;
final String _tip = 'b' * 40;

RefInfo _ref(String name, String target, {bool remote = false}) => RefInfo(
  fullName: remote ? 'refs/remotes/$name' : 'refs/heads/$name',
  shortName: name,
  kind: remote ? RefKind.remoteBranch : RefKind.localBranch,
  target: target,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

RefSnapshot _refs({String? head, String? tip}) => RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: head ?? _head,
  ),
  refs: <RefInfo>[
    _ref('main', head ?? _head),
    _ref('feature', tip ?? _tip),
    _ref('origin/feat', tip ?? _tip, remote: true),
  ],
  refCountGuardTripped: false,
  totalRefCount: 3,
);

SquashMessagePreview _preview({String source = 'feature'}) =>
    SquashMessagePreview.fromJson(<String, dynamic>{
      'source': source,
      'headOid': _head,
      'sourceOid': _tip,
      'message': 'Squashed commit of the following:\n',
    });

void main() {
  group('SquashMessagePreview.fromJson', () {
    test('reads every field', () {
      final SquashMessagePreview p = _preview();
      expect(p.source, 'feature');
      expect(p.headOid, _head);
      expect(p.sourceOid, _tip);
      expect(p.message, 'Squashed commit of the following:\n');
      expect(p.failed, isFalse);
    });

    test('an error field marks the reply failed', () {
      final SquashMessagePreview p = SquashMessagePreview.fromJson(
        <String, dynamic>{
          'source': 'x',
          'headOid': '',
          'sourceOid': '',
          'message': '',
          'error': <String, dynamic>{'message': 'unknown revision'},
        },
      );
      expect(p.failed, isTrue);
      expect(p.message, isEmpty);
    });
  });

  group('isCurrentFor', () {
    test('holds while source, HEAD and the source tip all still match', () {
      expect(_preview().isCurrentFor('feature', _refs()), isTrue);
    });

    test('a different pick is not answered by this reply', () {
      expect(_preview().isCurrentFor('release/0.5', _refs()), isFalse);
    });

    test('a moved HEAD makes it stale', () {
      expect(
        _preview().isCurrentFor('feature', _refs(head: 'c' * 40)),
        isFalse,
      );
    });

    test('a moved source tip makes it stale, HEAD unchanged', () {
      expect(_preview().isCurrentFor('feature', _refs(tip: 'c' * 40)), isFalse);
    });

    test('a failed reply is never current, even if its oids line up', () {
      final SquashMessagePreview failed = SquashMessagePreview.fromJson(
        <String, dynamic>{
          'source': 'feature',
          'headOid': _head,
          'sourceOid': _tip,
          'message': '',
          'error': <String, dynamic>{'message': 'git log failed'},
        },
      );
      expect(failed.isCurrentFor('feature', _refs()), isFalse);
    });

    test('a remote-tracking source is looked up among remote branches', () {
      expect(
        _preview(source: 'origin/feat').isCurrentFor('origin/feat', _refs()),
        isTrue,
      );
    });
  });

  test('publishSquashMessagePreview lands in session state', () {
    final FakeRepoSessionController fake = FakeRepoSessionController(
      const RepoIdentity(workDir: '/tmp/r', gitDir: '/tmp/r/.git'),
      RepoSessionState(isOpen: true, refs: _refs()),
    );
    fake.requestSquashMessage('feature');
    fake.publishSquashMessagePreview(_preview());
    expect(fake.state.squashMessagePreview?.source, 'feature');
  });

  // Replies are posted to the front of a multi-worker pool, so two quick
  // picks can answer out of order; the earlier pick's late reply must not
  // replace the current one (verifier P4 #3).
  test('a late reply for an earlier pick is dropped', () {
    final FakeRepoSessionController fake = FakeRepoSessionController(
      const RepoIdentity(workDir: '/tmp/r', gitDir: '/tmp/r/.git'),
      RepoSessionState(isOpen: true, refs: _refs()),
    );
    fake.requestSquashMessage('older');
    fake.requestSquashMessage('feature');
    fake.publishSquashMessagePreview(_preview());
    fake.publishSquashMessagePreview(_preview(source: 'older'));

    expect(fake.state.squashMessagePreview?.source, 'feature');
  });
}
