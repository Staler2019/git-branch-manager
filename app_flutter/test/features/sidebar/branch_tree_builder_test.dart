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
      // `headRef` is `main` with `isHead: true` and still sorts *after*
      // `develop`: the current branch has no ordering priority at all -- see
      // docs/ledger.md, 「側邊欄目前分支不再置頂」.
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

    test('matches by word initials, not only by substring', () {
      // The seam, not the rule: `branch_filter_test.dart` owns spec
      // P02-14's matching semantics, and this asserts `filterBranches`
      // actually goes through them. It inlined a bare `contains` for a
      // long time, which is exactly the regression this catches --
      // `'feature/auth'.contains('fa')` is false.
      expect(filterBranches(branches, 'fa'), [featureAuth]);
      expect(filterBranches(branches, 'cd'), [choreDocs]);
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

  group('fetchableRefsInFolder', () {
    RefInfo localWithUpstream({
      required String shortName,
      required String upstream,
    }) => RefInfo(
      fullName: 'refs/heads/$shortName',
      shortName: shortName,
      kind: RefKind.localBranch,
      target: 'local-$shortName',
      upstream: upstream,
      ahead: 0,
      behind: 0,
      hasTrackingInfo: true,
      isGone: false,
      isHead: false,
      isSymbolic: false,
      worktreePath: '',
    );

    RefInfo localWithNoUpstream(String shortName) => RefInfo(
      fullName: 'refs/heads/$shortName',
      shortName: shortName,
      kind: RefKind.localBranch,
      target: 'local-$shortName',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: false,
      worktreePath: '',
    );

    RefInfo remoteOnly({required String remote, required String branch}) =>
        RefInfo(
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
          isSymbolic: false,
          worktreePath: '',
        );

    test('collects branch names from local branches tracking one remote', () {
      final result = fetchableRefsInFolder([
        localWithUpstream(
          shortName: 'feature/a',
          upstream: 'refs/remotes/origin/feature/a',
        ),
        localWithUpstream(
          shortName: 'feature/b',
          upstream: 'refs/remotes/origin/feature/b',
        ),
      ]);

      expect(result, isNotNull);
      expect(result!.$1, 'origin');
      expect(result.$2, <String>['feature/a', 'feature/b']);
    });

    test('also collects from remote-only leaves via their own fullName', () {
      final result = fetchableRefsInFolder([
        remoteOnly(remote: 'origin', branch: 'feature/c'),
      ]);

      expect(result, isNotNull);
      expect(result!.$1, 'origin');
      expect(result.$2, <String>['feature/c']);
    });

    test('a local branch with no upstream contributes nothing', () {
      final result = fetchableRefsInFolder([localWithNoUpstream('feature/d')]);

      expect(result, isNull);
    });

    test(
      'returns null when the folder\'s branches track more than one remote',
      () {
        final result = fetchableRefsInFolder([
          localWithUpstream(
            shortName: 'feature/a',
            upstream: 'refs/remotes/origin/feature/a',
          ),
          localWithUpstream(
            shortName: 'feature/b',
            upstream: 'refs/remotes/upstream/feature/b',
          ),
        ]);

        expect(result, isNull);
      },
    );

    test('returns null for an empty ref list', () {
      expect(fetchableRefsInFolder(const []), isNull);
    });
  });

  group('leaf labels (P02 item 12: 名稱中的斜線自動摺成資料夾)', () {
    RefInfo local(String name) => RefInfo(
      fullName: 'refs/heads/$name',
      shortName: name,
      kind: RefKind.localBranch,
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

    /// Walks to the single leaf under [path], failing loudly rather than
    /// returning null so a wrong tree shape reads as a wrong tree shape.
    BranchTreeLeaf leafAt(List<BranchTreeNode> nodes, List<String> folders) {
      List<BranchTreeNode> level = nodes;
      for (final String name in folders) {
        final BranchTreeFolder folder = level
            .whereType<BranchTreeFolder>()
            .firstWhere((BranchTreeFolder f) => f.folderName == name);
        level = folder.children;
      }
      return level.whereType<BranchTreeLeaf>().single;
    }

    test('a branch inside a folder shows only its last segment', () {
      // The spec's own BRANCH_TREE mock lists `graph-lanes` under a
      // `feature` folder, not `feature/graph-lanes`.
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[local('feature/graph-lanes')],
        <String>{},
        expandAll: true,
      );

      expect(leafAt(tree, <String>['feature']).displayLabel, 'graph-lanes');
    });

    test('a root-level branch keeps its whole name', () {
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[local('main')],
        <String>{},
        expandAll: true,
      );

      expect(tree.whereType<BranchTreeLeaf>().single.displayLabel, 'main');
    });

    test('a nested branch shows only the segment below its own folder', () {
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[local('feature/auth/ui')],
        <String>{},
        expandAll: true,
      );

      expect(leafAt(tree, <String>['feature', 'auth']).displayLabel, 'ui');
    });

    test('the full name stays on the ref, for filtering and semantics', () {
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[local('feature/graph-lanes')],
        <String>{},
        expandAll: true,
      );

      // Only the *rendered* label is shortened. Everything that compares --
      // the filter (P02-14 「斜線視為分隔」), selection keys, the a11y label --
      // still works off the full slash-separated name.
      expect(
        leafAt(tree, <String>['feature']).ref.shortName,
        'feature/graph-lanes',
      );
    });
  });

  // The current branch is sorted like any other leaf. This is a
  // **user-ratified deviation** from BRANCH_STATES' 「永遠置頂於所屬資料夾
  // 內」 and P02-14 rule 7 -- see docs/ledger.md. Every fixture below keeps
  // HEAD alphabetically last among its siblings, so a reinstated pin fails
  // them rather than passing by coincidence.
  group('current branch has no sort priority', () {
    RefInfo branch(String name, {bool isHead = false}) => RefInfo(
      fullName: 'refs/heads/$name',
      shortName: name,
      kind: RefKind.localBranch,
      target: 'a' * 40,
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: isHead,
      isSymbolic: isHead,
      worktreePath: '',
    );

    /// The names of one level's children, folders included, in the order the
    /// sidebar paints them.
    List<String> namesAt(List<BranchTreeNode> nodes, List<String> folders) {
      List<BranchTreeNode> level = nodes;
      for (final String name in folders) {
        level = level
            .whereType<BranchTreeFolder>()
            .firstWhere((BranchTreeFolder f) => f.folderName == name)
            .children;
      }
      return level
          .map(
            (BranchTreeNode n) => switch (n) {
              BranchTreeFolder(:final folderName) => folderName,
              BranchTreeLeaf(:final ref) => ref.shortName,
              _ => throw StateError('unexpected node $n'),
            },
          )
          .toList();
    }

    test('a current branch inside a folder sorts alphabetically', () {
      // The falsifying case: `zeta` is alphabetically last of the three, and
      // that is exactly where it must land. A pin puts it first.
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[
          branch('feature/alpha'),
          branch('feature/beta'),
          branch('feature/zeta', isHead: true),
        ],
        <String>{},
        expandAll: true,
      );

      expect(namesAt(tree, <String>['feature']), <String>[
        'feature/alpha',
        'feature/beta',
        'feature/zeta',
      ]);
    });

    test('CONTROL: it stays inside its own folder', () {
      // Nothing hoists the current branch out of its folder any more, and
      // nothing ever should -- the row is reached by expanding to it.
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[branch('chore/docs'), branch('feature/zeta', isHead: true)],
        <String>{},
        expandAll: true,
      );

      expect(namesAt(tree, const <String>[]), <String>['chore', 'feature']);
      expect(namesAt(tree, <String>['feature']), <String>['feature/zeta']);
    });

    test('a root-level current branch still sorts after sibling folders', () {
      // The folders-before-leaves rule is structure, not priority, so it is
      // the half that stays: `main` is HEAD and still renders below
      // `feature`. BRANCH_TREE's mock draws it the other way round.
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[branch('feature/alpha'), branch('main', isHead: true)],
        <String>{},
        expandAll: true,
      );

      expect(namesAt(tree, const <String>[]), <String>['feature', 'main']);
    });

    test('CONTROL: with no current branch, folders still lead', () {
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[branch('feature/alpha'), branch('main')],
        <String>{},
        expandAll: true,
      );

      expect(namesAt(tree, const <String>[]), <String>['feature', 'main']);
    });

    test('the current branch takes its alphabetical place among siblings', () {
      final List<BranchTreeNode> tree = buildBranchTree(
        <RefInfo>[
          branch('feature/gamma'),
          branch('feature/alpha'),
          branch('feature/head', isHead: true),
          branch('feature/beta'),
        ],
        <String>{},
        expandAll: true,
      );

      expect(namesAt(tree, <String>['feature']), <String>[
        'feature/alpha',
        'feature/beta',
        'feature/gamma',
        'feature/head',
      ]);
    });
  });
}
