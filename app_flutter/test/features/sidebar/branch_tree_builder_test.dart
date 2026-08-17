import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/sidebar/branch_tree_builder.dart';

void main() {
  group('BranchTreeBuilder', () {
    final headRef = RefInfo(
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

    final flatRef = RefInfo(
      fullName: 'refs/heads/develop',
      shortName: 'develop',
      kind: RefKind.localBranch,
      target: 'def456',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: true,
      worktreePath: '',
    );

    test('builds tree with single-segment branches (no nesting)', () {
      final branches = [headRef, flatRef];
      final tree = buildBranchTree(branches, {});

      expect(tree.length, 2);
      expect(tree[0] is BranchTreeLeaf, true);
      expect(tree[1] is BranchTreeLeaf, true);
      // Sorted alphabetically: develop comes before main
      expect((tree[0] as BranchTreeLeaf).ref.shortName, 'develop');
      expect((tree[1] as BranchTreeLeaf).ref.shortName, 'main');
    });

    test('builds nested tree for slash-delimited branches', () {
      final feature1 = RefInfo(
        fullName: 'refs/heads/feature/auth',
        shortName: 'feature/auth',
        kind: RefKind.localBranch,
        target: 'f1',
        upstream: '',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: false,
        isGone: false,
        isHead: false,
        isSymbolic: true,
        worktreePath: '',
      );
      final feature2 = RefInfo(
        fullName: 'refs/heads/feature/dark-mode',
        shortName: 'feature/dark-mode',
        kind: RefKind.localBranch,
        target: 'f2',
        upstream: '',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: false,
        isGone: false,
        isHead: false,
        isSymbolic: true,
        worktreePath: '',
      );

      final branches = [feature1, feature2];
      final tree = buildBranchTree(branches, {});

      expect(tree.length, 1);
      expect(tree[0] is BranchTreeFolder, true);
      final folder = tree[0] as BranchTreeFolder;
      expect(folder.folderName, 'feature');
      expect(folder.children.length, 2);
    });

    test('preserves ref data on leaf nodes', () {
      final branches = [headRef];
      final tree = buildBranchTree(branches, {});

      expect(tree.length, 1);
      final leaf = tree[0] as BranchTreeLeaf;
      expect(leaf.ref, headRef);
      expect(leaf.ref.isHead, true);
      expect(leaf.ref.shortName, 'main');
    });

    test('handles multiple levels of nesting (e.g., a/b/c)', () {
      final deep = RefInfo(
        fullName: 'refs/heads/chore/docs/api',
        shortName: 'chore/docs/api',
        kind: RefKind.localBranch,
        target: 'd1',
        upstream: '',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: false,
        isGone: false,
        isHead: false,
        isSymbolic: true,
        worktreePath: '',
      );

      final branches = [deep];
      final tree = buildBranchTree(branches, {});

      expect(tree.length, 1);
      final choreFolderNode = tree[0] as BranchTreeFolder;
      expect(choreFolderNode.folderName, 'chore');
      expect(choreFolderNode.children.length, 1);

      final docsFolderNode = choreFolderNode.children[0] as BranchTreeFolder;
      expect(docsFolderNode.folderName, 'docs');
      expect(docsFolderNode.children.length, 1);

      final leafNode = docsFolderNode.children[0] as BranchTreeLeaf;
      expect(leafNode.ref.shortName, 'chore/docs/api');
    });

    test('expands folders listed in expandedFolders', () {
      final feature1 = RefInfo(
        fullName: 'refs/heads/feature/auth',
        shortName: 'feature/auth',
        kind: RefKind.localBranch,
        target: 'f1',
        upstream: '',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: false,
        isGone: false,
        isHead: false,
        isSymbolic: true,
        worktreePath: '',
      );

      final tree = buildBranchTree([feature1], {'feature'});
      final folder = tree[0] as BranchTreeFolder;
      expect(folder.isExpanded, true);
    });

    test('collapses folders not in expandedFolders', () {
      final feature1 = RefInfo(
        fullName: 'refs/heads/feature/auth',
        shortName: 'feature/auth',
        kind: RefKind.localBranch,
        target: 'f1',
        upstream: '',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: false,
        isGone: false,
        isHead: false,
        isSymbolic: true,
        worktreePath: '',
      );

      final tree = buildBranchTree([feature1], {});
      final folder = tree[0] as BranchTreeFolder;
      expect(folder.isExpanded, false);
    });

    test('returns immutable list', () {
      final branches = [headRef];
      final tree = buildBranchTree(branches, {});

      // Verify it's immutable by checking that it throws when trying to add
      expect(() => tree.add(tree[0]), throwsUnsupportedError);
    });
  });

  group('filterBranches', () {
    final main = RefInfo(
      fullName: 'refs/heads/main',
      shortName: 'main',
      kind: RefKind.localBranch,
      target: 'abc123',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: true,
      isSymbolic: true,
      worktreePath: '',
    );

    final featureAuth = RefInfo(
      fullName: 'refs/heads/feature/auth',
      shortName: 'feature/auth',
      kind: RefKind.localBranch,
      target: 'f1',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: true,
      worktreePath: '',
    );

    final choreDocs = RefInfo(
      fullName: 'refs/heads/chore/docs',
      shortName: 'chore/docs',
      kind: RefKind.localBranch,
      target: 'c1',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: true,
      worktreePath: '',
    );

    final branches = [main, featureAuth, choreDocs];

    test('returns all branches unchanged for an empty query', () {
      expect(filterBranches(branches, ''), branches);
    });

    test('returns all branches unchanged for a whitespace-only query', () {
      expect(filterBranches(branches, '   '), branches);
    });

    test('matches by case-insensitive substring of shortName', () {
      expect(filterBranches(branches, 'FEAT'), [featureAuth]);
    });

    test('matches a slash-delimited segment anywhere in shortName', () {
      expect(filterBranches(branches, 'docs'), [choreDocs]);
    });

    test('returns an empty list when nothing matches', () {
      expect(filterBranches(branches, 'nonexistent'), isEmpty);
    });

    test('trims surrounding whitespace before matching', () {
      expect(filterBranches(branches, '  main  '), [main]);
    });
  });

  group('remoteBranchParts', () {
    test('splits refs/remotes/<remote>/<branch> into remote and branch', () {
      expect(remoteBranchParts('refs/remotes/origin/feature/auth'), (
        'origin',
        'feature/auth',
      ));
    });

    test('splits a single-segment branch name too', () {
      expect(remoteBranchParts('refs/remotes/origin/main'), ('origin', 'main'));
    });
  });

  group('mergeLocalAndRemoteBranches', () {
    RefInfo localBranch({required String shortName, String upstream = ''}) =>
        RefInfo(
          fullName: 'refs/heads/$shortName',
          shortName: shortName,
          kind: RefKind.localBranch,
          target: 'local-$shortName',
          upstream: upstream,
          ahead: 0,
          behind: 0,
          hasTrackingInfo: upstream.isNotEmpty,
          isGone: false,
          isHead: false,
          isSymbolic: false,
          worktreePath: '',
        );

    RefInfo remoteBranch({
      required String remote,
      required String branch,
      bool isSymbolic = false,
    }) => RefInfo(
      fullName: 'refs/remotes/$remote/$branch',
      shortName: '$remote/$branch',
      kind: RefKind.remoteBranch,
      target: 'remote-$branch',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: isSymbolic,
      worktreePath: '',
    );

    test('drops a remote branch already tracked by a local branch (upstream '
        'matches the remote ref\'s fullName)', () {
      final local = localBranch(
        shortName: 'main',
        upstream: 'refs/remotes/origin/main',
      );
      final remote = remoteBranch(remote: 'origin', branch: 'main');

      final merged = mergeLocalAndRemoteBranches([local], [remote]);

      expect(merged, [local]);
    });

    test('keeps a remote branch with no local branch tracking it '
        '("remote-only"), with its shortName stripped to the branch name', () {
      final local = localBranch(shortName: 'main');
      final remote = remoteBranch(remote: 'origin', branch: 'worktrees');

      final merged = mergeLocalAndRemoteBranches([local], [remote]);

      expect(merged.length, 2);
      final RefInfo remoteOnly = merged.firstWhere(
        (r) => r.kind == RefKind.remoteBranch,
      );
      expect(remoteOnly.shortName, 'worktrees');
      expect(remoteOnly.fullName, 'refs/remotes/origin/worktrees');
    });

    test('excludes symbolic remote refs (e.g. origin/HEAD)', () {
      final remote = remoteBranch(
        remote: 'origin',
        branch: 'HEAD',
        isSymbolic: true,
      );

      final merged = mergeLocalAndRemoteBranches([], [remote]);

      expect(merged, isEmpty);
    });

    test('a local-only branch (no upstream) is unaffected by unrelated '
        'remote branches', () {
      final local = localBranch(shortName: 'lfs-prune');
      final remote = remoteBranch(remote: 'origin', branch: 'lane-overflow');

      final merged = mergeLocalAndRemoteBranches([local], [remote]);

      expect(merged.length, 2);
      expect(merged, contains(local));
    });

    test('a stripped remote-only branch groups into the same folder as a '
        'same-prefix local branch', () {
      final local = localBranch(shortName: 'bugfix/rebase-conflict');
      final remote = remoteBranch(
        remote: 'origin',
        branch: 'bugfix/lane-overflow',
      );

      final merged = mergeLocalAndRemoteBranches([local], [remote]);
      final tree = buildBranchTree(merged, {'bugfix'});

      expect(tree.length, 1);
      final folder = tree[0] as BranchTreeFolder;
      expect(folder.folderName, 'bugfix');
      expect(folder.children.length, 2);
    });
  });
}
