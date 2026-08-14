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
}
