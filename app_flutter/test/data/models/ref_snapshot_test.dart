import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';

void main() {
  group('RefSnapshot', () {
    final localRef = RefInfo(
      fullName: 'refs/heads/main',
      shortName: 'main',
      kind: RefKind.localBranch,
      target: 'abc123',
      upstream: 'origin/main',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: true,
      isGone: false,
      isHead: true,
      isSymbolic: true,
      worktreePath: '',
    );

    final remoteRef = RefInfo(
      fullName: 'refs/remotes/origin/main',
      shortName: 'origin/main',
      kind: RefKind.remoteBranch,
      target: 'abc123',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: true,
      worktreePath: '',
    );

    final tagRef = RefInfo(
      fullName: 'refs/tags/v1.0.0',
      shortName: 'v1.0.0',
      kind: RefKind.tag,
      target: 'abc123',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: false,
      worktreePath: '',
    );

    test('localBranches getter filters only local branches', () {
      final snapshot = RefSnapshot(
        head: HeadInfo.fromJson({
          'kind': 0,
          'branchName': 'main',
          'fullRef': 'refs/heads/main',
          'target': 'abc123',
        }),
        refs: [localRef, remoteRef, tagRef],
        refCountGuardTripped: false,
        totalRefCount: 3,
      );

      expect(snapshot.localBranches, [localRef]);
      expect(snapshot.localBranches.length, 1);
    });

    test('remoteBranches getter filters only remote branches', () {
      final snapshot = RefSnapshot(
        head: HeadInfo.fromJson({
          'kind': 0,
          'branchName': 'main',
          'fullRef': 'refs/heads/main',
          'target': 'abc123',
        }),
        refs: [localRef, remoteRef, tagRef],
        refCountGuardTripped: false,
        totalRefCount: 3,
      );

      expect(snapshot.remoteBranches, [remoteRef]);
      expect(snapshot.remoteBranches.length, 1);
    });

    test('tags getter filters only tag refs', () {
      final snapshot = RefSnapshot(
        head: HeadInfo.fromJson({
          'kind': 0,
          'branchName': 'main',
          'fullRef': 'refs/heads/main',
          'target': 'abc123',
        }),
        refs: [localRef, remoteRef, tagRef],
        refCountGuardTripped: false,
        totalRefCount: 3,
      );

      expect(snapshot.tags, [tagRef]);
      expect(snapshot.tags.length, 1);
    });

    test('getters work correctly with empty refs list', () {
      final snapshot = RefSnapshot.empty;

      expect(snapshot.localBranches, isEmpty);
      expect(snapshot.remoteBranches, isEmpty);
      expect(snapshot.tags, isEmpty);
    });

    test('getters preserve ref data and order', () {
      final remote1 = RefInfo(
        fullName: 'refs/remotes/origin/beta',
        shortName: 'origin/beta',
        kind: RefKind.remoteBranch,
        target: 'xyz789',
        upstream: '',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: false,
        isGone: false,
        isHead: false,
        isSymbolic: true,
        worktreePath: '',
      );
      final remote2 = RefInfo(
        fullName: 'refs/remotes/origin/main',
        shortName: 'origin/main',
        kind: RefKind.remoteBranch,
        target: 'abc123',
        upstream: '',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: false,
        isGone: false,
        isHead: false,
        isSymbolic: true,
        worktreePath: '',
      );
      final snapshot = RefSnapshot(
        head: RefSnapshot.empty.head,
        refs: [localRef, remote1, remote2, tagRef],
        refCountGuardTripped: false,
        totalRefCount: 4,
      );

      expect(snapshot.remoteBranches, [remote1, remote2]);
    });
  });
}
