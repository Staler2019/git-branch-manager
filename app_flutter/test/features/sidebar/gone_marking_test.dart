import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/sidebar/branch_tree_builder.dart';
import 'package:gbm_flutter/features/sidebar/gone_marking.dart';

RefInfo _local(String shortName, {String upstream = '', bool isGone = false}) =>
    RefInfo(
      fullName: 'refs/heads/$shortName',
      shortName: shortName,
      kind: RefKind.localBranch,
      target: 'a' * 40,
      upstream: upstream,
      ahead: 0,
      behind: 0,
      // Deliberately NOT derived from `upstream`: git's %(upstream:track) is
      // an empty string for a branch exactly in sync with its upstream, so
      // hasTrackingInfo is false there while %(upstream) is fully populated.
      // A fixture that computes one from the other cannot falsify code that
      // makes the same wrong derivation (the Tier 0c trap).
      hasTrackingInfo: false,
      isGone: isGone,
      isHead: false,
      isSymbolic: false,
      worktreePath: '',
    );

RefInfo _remoteOnly(String fullName) => RefInfo(
  fullName: fullName,
  // mergeLocalAndRemoteBranches strips the `<remote>/` prefix off a
  // remote-only leaf's shortName, so shortName is NOT the ref name.
  shortName: fullName.split('/').skip(3).join('/'),
  kind: RefKind.remoteBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

/// A resolver over a repository with no remote-tracking refs at all, so
/// `counterpartOf` can only answer from a branch's own tracking config. That
/// is precisely the pre-C5 behaviour, which is what the tests below this
/// point were written against and must keep asserting.
final String Function(RefInfo) _noRemotes = RemoteBranchIndex.from(
  const <RefInfo>[],
).counterpartOf;

void main() {
  group('isEffectivelyGone', () {
    const Set<String> pending = <String>{'refs/remotes/origin/vanished'};

    test('git already saying gone is enough on its own', () {
      // Post-prune, %(upstream:track) reports [gone] and the pending set is
      // empty -- the existing path must keep working untouched.
      expect(
        isEffectivelyGone(
          _local('feature', upstream: 'refs/remotes/origin/x', isGone: true),
          const <String>{},
          remoteCounterpart: 'refs/remotes/origin/x',
        ),
        isTrue,
      );
    });

    test('a local branch whose upstream is pending-gone', () {
      expect(
        isEffectivelyGone(
          _local('feature', upstream: 'refs/remotes/origin/vanished'),
          pending,
          remoteCounterpart: 'refs/remotes/origin/vanished',
        ),
        isTrue,
      );
    });

    test('a local branch tracking a live upstream is not gone', () {
      expect(
        isEffectivelyGone(
          _local('feature', upstream: 'refs/remotes/origin/alive'),
          pending,
          remoteCounterpart: 'refs/remotes/origin/alive',
        ),
        isFalse,
      );
    });

    test('a local branch with no upstream is never gone', () {
      // The empty string must not accidentally match anything, and a branch
      // that never had an upstream has not lost one.
      expect(
        isEffectivelyGone(_local('local-only'), pending, remoteCounterpart: ''),
        isFalse,
      );
      expect(
        isEffectivelyGone(_local('local-only'), const <String>{
          '',
        }, remoteCounterpart: ''),
        isFalse,
      );
    });

    test('a remote-only row is matched on its full ref name', () {
      // Not on shortName: mergeLocalAndRemoteBranches strips the remote
      // prefix, so a remote-only `origin/vanished` arrives with
      // shortName == 'vanished'.
      expect(
        isEffectivelyGone(
          _remoteOnly('refs/remotes/origin/vanished'),
          pending,
          remoteCounterpart: '',
        ),
        isTrue,
      );
    });

    test('a remote-only row for a live branch is not gone', () {
      expect(
        isEffectivelyGone(
          _remoteOnly('refs/remotes/origin/alive'),
          pending,
          remoteCounterpart: '',
        ),
        isFalse,
      );
    });

    test('a nested branch name is matched whole', () {
      expect(
        isEffectivelyGone(
          _local('a', upstream: 'refs/remotes/origin/feature/deep/name'),
          const <String>{'refs/remotes/origin/feature/deep/name'},
          remoteCounterpart: 'refs/remotes/origin/feature/deep/name',
        ),
        isTrue,
      );
    });

    // C5. A branch pushed with `git push origin HEAD` has no tracking config
    // at all, so `upstream` is empty and the old `if (ref.upstream.isEmpty)
    // return false` let it through unmarked -- while the same-named remote
    // ref it really does have sat in the pending set. After C4 that remote
    // row is claimed and no longer drawn, so if this row does not carry the
    // mark, nothing does.
    test('a local branch with no upstream is gone when its same-named remote '
        'ref is', () {
      expect(
        isEffectivelyGone(
          _local('feature'),
          pending,
          remoteCounterpart: 'refs/remotes/origin/vanished',
        ),
        isTrue,
      );
    });

    test('a branch that was never pushed at all is still not gone', () {
      // The user's own report: 「branches have not been pushed ... this
      // should not mark as gone」. No tracking config *and* no same-named
      // remote ref means there is no counterpart to have lost.
      expect(
        isEffectivelyGone(
          _local('never-pushed'),
          pending,
          remoteCounterpart: '',
        ),
        isFalse,
      );
    });

    test('the counterpart is what is matched, not the ref\'s own upstream', () {
      // Guards the direction of the fix: passing a counterpart that is NOT
      // in the pending set must win over an upstream that is. Nothing in
      // production resolves them differently -- counterpartOf returns
      // `upstream` verbatim when it is set -- but a future caller that
      // resolves through some other rule must not be silently overridden.
      expect(
        isEffectivelyGone(
          _local('feature', upstream: 'refs/remotes/origin/vanished'),
          pending,
          remoteCounterpart: 'refs/remotes/origin/alive',
        ),
        isFalse,
      );
    });

    test('an empty pending set changes nothing', () {
      expect(
        isEffectivelyGone(
          _local('feature', upstream: 'refs/remotes/origin/vanished'),
          const <String>{},
          remoteCounterpart: 'refs/remotes/origin/vanished',
        ),
        isFalse,
      );
    });
  });

  group('gonePendingCount', () {
    test('counts rows the pending set actually marks', () {
      final List<RefInfo> branches = <RefInfo>[
        _local('a', upstream: 'refs/remotes/origin/a'),
        _local('b', upstream: 'refs/remotes/origin/b'),
        _remoteOnly('refs/remotes/origin/c'),
      ];

      expect(
        gonePendingCount(branches, const <String>{
          'refs/remotes/origin/b',
          'refs/remotes/origin/c',
        }, _noRemotes),
        2,
      );
    });

    test('is zero when the set names refs the snapshot no longer has', () {
      // The ghost case: the user pruned in a terminal, or removed the whole
      // remote. The refs are gone from the snapshot but gonePendingByRemote
      // still lists them, so counting the set's size would claim "3 pending"
      // over a tree with nothing marked.
      expect(
        gonePendingCount(
          <RefInfo>[_local('a', upstream: 'refs/remotes/origin/a')],
          const <String>{'refs/remotes/origin/deleted'},
          _noRemotes,
        ),
        0,
      );
    });

    test('does not count a row git already reports as gone', () {
      // Stage 3 already happened for that row: its remote-tracking ref is
      // deleted, so there is nothing left for Prune to clean up.
      expect(
        gonePendingCount(
          <RefInfo>[
            _local('a', upstream: 'refs/remotes/origin/a', isGone: true),
          ],
          const <String>{},
          _noRemotes,
        ),
        0,
      );
    });

    test('counts a row only once', () {
      // A local branch and the remote ref it tracks cannot both appear --
      // mergeLocalAndRemoteBranches drops the matched remote row -- but the
      // count must not depend on that holding.
      final List<RefInfo> branches = <RefInfo>[
        _local('a', upstream: 'refs/remotes/origin/a'),
      ];
      expect(
        gonePendingCount(branches, const <String>{
          'refs/remotes/origin/a',
        }, _noRemotes),
        1,
      );
    });

    test('counts an untracked branch whose same-named remote ref is gone', () {
      // The count feeds spec P02's 「待清理數量」 badge. Resolving through
      // the index rather than through `upstream` is what keeps the badge and
      // the row markings from disagreeing.
      final RemoteBranchIndex index = RemoteBranchIndex.from(<RefInfo>[
        _remoteOnly('refs/remotes/origin/pushed-without-u'),
      ]);

      expect(
        gonePendingCount(
          <RefInfo>[_local('pushed-without-u')],
          const <String>{'refs/remotes/origin/pushed-without-u'},
          index.counterpartOf,
        ),
        1,
      );
    });

    test('is zero for an empty tree', () {
      expect(
        gonePendingCount(const <RefInfo>[], const <String>{
          'refs/remotes/origin/a',
        }, _noRemotes),
        0,
      );
    });
  });
}
