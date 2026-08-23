import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
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
        ),
        isTrue,
      );
    });

    test('a local branch whose upstream is pending-gone', () {
      expect(
        isEffectivelyGone(
          _local('feature', upstream: 'refs/remotes/origin/vanished'),
          pending,
        ),
        isTrue,
      );
    });

    test('a local branch tracking a live upstream is not gone', () {
      expect(
        isEffectivelyGone(
          _local('feature', upstream: 'refs/remotes/origin/alive'),
          pending,
        ),
        isFalse,
      );
    });

    test('a local branch with no upstream is never gone', () {
      // The empty string must not accidentally match anything, and a branch
      // that never had an upstream has not lost one.
      expect(isEffectivelyGone(_local('local-only'), pending), isFalse);
      expect(
        isEffectivelyGone(_local('local-only'), const <String>{''}),
        isFalse,
      );
    });

    test('a remote-only row is matched on its full ref name', () {
      // Not on shortName: mergeLocalAndRemoteBranches strips the remote
      // prefix, so a remote-only `origin/vanished` arrives with
      // shortName == 'vanished'.
      expect(
        isEffectivelyGone(_remoteOnly('refs/remotes/origin/vanished'), pending),
        isTrue,
      );
    });

    test('a remote-only row for a live branch is not gone', () {
      expect(
        isEffectivelyGone(_remoteOnly('refs/remotes/origin/alive'), pending),
        isFalse,
      );
    });

    test('a nested branch name is matched whole', () {
      expect(
        isEffectivelyGone(
          _local('a', upstream: 'refs/remotes/origin/feature/deep/name'),
          const <String>{'refs/remotes/origin/feature/deep/name'},
        ),
        isTrue,
      );
    });

    test('an empty pending set changes nothing', () {
      expect(
        isEffectivelyGone(
          _local('feature', upstream: 'refs/remotes/origin/vanished'),
          const <String>{},
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
        }),
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
        ),
        0,
      );
    });

    test('does not count a row git already reports as gone', () {
      // Stage 3 already happened for that row: its remote-tracking ref is
      // deleted, so there is nothing left for Prune to clean up.
      expect(
        gonePendingCount(<RefInfo>[
          _local('a', upstream: 'refs/remotes/origin/a', isGone: true),
        ], const <String>{}),
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
        gonePendingCount(branches, const <String>{'refs/remotes/origin/a'}),
        1,
      );
    });

    test('is zero for an empty tree', () {
      expect(
        gonePendingCount(const <RefInfo>[], const <String>{
          'refs/remotes/origin/a',
        }),
        0,
      );
    });
  });
}
