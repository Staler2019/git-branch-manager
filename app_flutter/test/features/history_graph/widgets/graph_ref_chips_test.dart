import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_ref_chips.dart';

RefInfo _local(
  String name,
  String target, {
  String upstream = '',
  bool isHead = false,
}) {
  return RefInfo(
    fullName: 'refs/heads/$name',
    shortName: name,
    kind: RefKind.localBranch,
    target: target,
    upstream: upstream,
    ahead: 0,
    behind: 0,
    hasTrackingInfo: upstream.isNotEmpty,
    isGone: false,
    isHead: isHead,
    isSymbolic: false,
    worktreePath: '',
  );
}

RefInfo _remote(String remoteQualifiedName, String target) {
  return RefInfo(
    fullName: 'refs/remotes/$remoteQualifiedName',
    shortName: remoteQualifiedName,
    kind: RefKind.remoteBranch,
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
}

RefInfo _tag(String name, String target) {
  return RefInfo(
    fullName: 'refs/tags/$name',
    shortName: name,
    kind: RefKind.tag,
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
}

RefSnapshot _snapshot(List<RefInfo> refs) => RefSnapshot(
  head: RefSnapshot.empty.head,
  refs: refs,
  refCountGuardTripped: false,
  totalRefCount: refs.length,
);

void main() {
  group('refChipsForCommit', () {
    test('returns an empty list when no ref points to the commit', () {
      const refs = RefSnapshot.empty;

      expect(refChipsForCommit(refs, 'deadbeef'), isEmpty);
    });

    test('returns the single ref pointing to the commit', () {
      final refs = _snapshot(<RefInfo>[_local('main', 'abc123')]);

      final result = refChipsForCommit(refs, 'abc123');

      expect(result, hasLength(1));
      expect(result.single.label, 'main');
      expect(result.single.showCloudIcon, isFalse);
      expect(result.single.isDashed, isFalse);
    });

    test('returns every unrelated ref pointing to the same commit as-is', () {
      final refs = _snapshot(<RefInfo>[
        _local('main', 'abc123'),
        _tag('v1.0', 'abc123'),
        _local('other', 'def456'),
      ]);

      final result = refChipsForCommit(refs, 'abc123');

      expect(result, hasLength(2));
      expect(result.map((c) => c.label), containsAll(<String>['main', 'v1.0']));
      expect(result.map((c) => c.label), isNot(contains('other')));
    });

    test('a local branch synced with its upstream merges into one chip with '
        'a cloud icon, suppressing the separate remote chip -- spec page 02: '
        '"local 與 origin 在同一個 commit 時只出一個 chip"', () {
      final refs = _snapshot(<RefInfo>[
        _local('main', 'abc123', upstream: 'refs/remotes/origin/main'),
        _remote('origin/main', 'abc123'),
      ]);

      final result = refChipsForCommit(refs, 'abc123');

      expect(result, hasLength(1));
      expect(result.single.label, 'main');
      expect(result.single.kind, RefKind.localBranch);
      expect(result.single.showCloudIcon, isTrue);
      expect(result.single.isDashed, isFalse);
    });

    test('a diverged upstream keeps its own dashed chip on the commit it '
        'actually points at, and the local branch chip on its own row shows '
        'no cloud icon -- spec page 02: "虛線外框＝只有在分歧時才會出現"', () {
      final refs = _snapshot(<RefInfo>[
        _local('main', 'abc123', upstream: 'refs/remotes/origin/main'),
        _remote('origin/main', 'def456'), // diverged: different commit
      ]);

      final localRow = refChipsForCommit(refs, 'abc123');
      expect(localRow, hasLength(1));
      expect(localRow.single.label, 'main');
      expect(localRow.single.showCloudIcon, isFalse);
      expect(localRow.single.isDashed, isFalse);

      final remoteRow = refChipsForCommit(refs, 'def456');
      expect(remoteRow, hasLength(1));
      expect(remoteRow.single.label, 'origin/main');
      expect(remoteRow.single.kind, RefKind.remoteBranch);
      expect(remoteRow.single.isDashed, isTrue);
      expect(remoteRow.single.showCloudIcon, isFalse);
    });

    test(
      'a remote branch with no local branch tracking it (remote-only) '
      'renders as a plain chip, neither cloud nor dashed -- that is the '
      "sidebar's distinct \"Remote only\" state, not this divergence rule",
      () {
        final refs = _snapshot(<RefInfo>[_remote('origin/feature', 'abc123')]);

        final result = refChipsForCommit(refs, 'abc123');

        expect(result, hasLength(1));
        expect(result.single.label, 'origin/feature');
        expect(result.single.isDashed, isFalse);
        expect(result.single.showCloudIcon, isFalse);
      },
    );

    test('a local-only branch (no upstream) renders as a plain chip', () {
      final refs = _snapshot(<RefInfo>[_local('scratch', 'abc123')]);

      final result = refChipsForCommit(refs, 'abc123');

      expect(result, hasLength(1));
      expect(result.single.label, 'scratch');
      expect(result.single.showCloudIcon, isFalse);
      expect(result.single.isDashed, isFalse);
    });

    test('isCurrent carries through from RefInfo.isHead', () {
      final refs = _snapshot(<RefInfo>[_local('main', 'abc123', isHead: true)]);

      final result = refChipsForCommit(refs, 'abc123');

      expect(result.single.isCurrent, isTrue);
    });
  });
}
