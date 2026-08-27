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

    // The user's own repository: branches pushed with `git push origin HEAD`
    // (no `-u`), so `branch.<name>.merge` is empty and `%(upstream)` is blank,
    // while `refs/remotes/origin/<name>` exists all the same. Matching only on
    // the tracking *config* let that remote ref through, and then:
    //
    //   root-level name   rootNodes['main'] = local, then overwritten by
    //                     remote -- the local row vanished, taking Checkout,
    //                     Merge and Delete branch with it
    //   nested name       two leaves under the same folder, one git-branch
    //                     and one cloud, for a single branch
    //
    // After a fetch the prune preview marked that remote ref gone-pending, so
    // the surviving row turned cloud-off + gone. That is the whole of the
    // reported 「剛進來是灰雲、fetch 後變黃雲斜線」.
    test('drops a same-named remote branch even when the local branch never '
        'set an upstream', () {
      final local = localBranch(shortName: 'main');
      final remote = remoteBranch(remote: 'origin', branch: 'main');

      final merged = mergeLocalAndRemoteBranches([local], [remote]);

      expect(merged, [local]);
    });

    test('a nested same-named pair does not become two leaves', () {
      // The root-level case collapses in a Map (silently); the nested case
      // appends to a List (visibly). Both have to be covered because they
      // fail in different directions.
      final local = localBranch(shortName: 'feat/p03-working-copy-redesign');
      final remote = remoteBranch(
        remote: 'origin',
        branch: 'feat/p03-working-copy-redesign',
      );

      final merged = mergeLocalAndRemoteBranches([local], [remote]);
      final tree = buildBranchTree(merged, {'feat'});

      expect(merged, [local]);
      final folder = tree.single as BranchTreeFolder;
      expect(folder.children.length, 1);
      expect(
        (folder.children.single as BranchTreeLeaf).ref.kind,
        RefKind.localBranch,
      );
    });

    // remoteCounterpartOf is tested directly, not only through the merge.
    // The merge drops a same-named remote row either way -- once by claiming
    // it and once by the one-row-per-name rule below it -- so a merge
    // assertion cannot tell the two mechanisms apart, and the name rule
    // survived a mutation that deleted it outright. C5 and C7 read this
    // function for its *answer* (which remote ref, so gone-ness and the
    // ahead/behind badge can be looked up), not for the merge's side effect.
    test('a same-named remote ref is the counterpart of a local branch that '
        'never set an upstream', () {
      final local = localBranch(shortName: 'main');
      final origin = remoteBranch(remote: 'origin', branch: 'main');

      expect(remoteCounterpartOf(local, [origin]), 'refs/remotes/origin/main');
    });

    test('a local branch with no same-named remote ref has no counterpart', () {
      final local = localBranch(shortName: 'lfs-prune');
      final origin = remoteBranch(remote: 'origin', branch: 'lane-overflow');

      expect(remoteCounterpartOf(local, [origin]), '');
    });

    test('an upstream that no longer exists is still the counterpart', () {
      // The whole gone case: git kept the tracking config, the ref is gone.
      // Returning '' here would make a gone branch indistinguishable from a
      // never-pushed one, which is exactly what C5 has to tell apart.
      final local = localBranch(
        shortName: 'main',
        upstream: 'refs/remotes/origin/main',
      );

      expect(remoteCounterpartOf(local, []), 'refs/remotes/origin/main');
    });

    test('a symbolic remote ref is never a counterpart', () {
      final local = localBranch(shortName: 'HEAD');
      final origin = remoteBranch(
        remote: 'origin',
        branch: 'HEAD',
        isSymbolic: true,
      );

      expect(remoteCounterpartOf(local, [origin]), '');
    });

    test('drops a remote branch tracked under a different name', () {
      // Pins the claim itself rather than the name dedup: the two rows share
      // no name, so only `claimed` can drop this one.
      final local = localBranch(
        shortName: 'feature/x',
        upstream: 'refs/remotes/origin/renamed-x',
      );
      final remote = remoteBranch(remote: 'origin', branch: 'renamed-x');

      final merged = mergeLocalAndRemoteBranches([local], [remote]);

      expect(merged, [local]);
    });

    test(
      'an explicit upstream wins over a same-named ref on another remote',
      () {
        // Tracking is a statement the user made; the name match is a guess.
        // Only the tracked ref is the counterpart, so origin/main survives as
        // a remote-only row of its own.
        final local = localBranch(
          shortName: 'main',
          upstream: 'refs/remotes/upstream/main',
        );
        final origin = remoteBranch(remote: 'origin', branch: 'main');
        final up = remoteBranch(remote: 'upstream', branch: 'main');

        expect(
          remoteCounterpartOf(local, [origin, up]),
          'refs/remotes/upstream/main',
        );
      },
    );

    test('a name match on two remotes at once claims neither', () {
      // origin/main and upstream/main are two different refs and nothing
      // says which one an untracked local `main` means. Guessing would drop
      // a real branch, so the name rule only fires when it is unambiguous.
      final local = localBranch(shortName: 'main');
      final origin = remoteBranch(remote: 'origin', branch: 'main');
      final up = remoteBranch(remote: 'upstream', branch: 'main');

      expect(remoteCounterpartOf(local, [origin, up]), '');
    });

    test('the local row still survives a two-remote name collision', () {
      // Nothing is claimed, so both remote rows reach the shortName rewrite
      // and all three rows end up called `main`. The local one is the row
      // that can be checked out, merged and deleted, so it is the one that
      // must not be the casualty.
      final local = localBranch(shortName: 'main');
      final origin = remoteBranch(remote: 'origin', branch: 'main');
      final up = remoteBranch(remote: 'upstream', branch: 'main');

      final merged = mergeLocalAndRemoteBranches([local], [origin, up]);

      expect(merged.where((r) => r.shortName == 'main').length, 1);
      expect(merged.single.kind, RefKind.localBranch);
    });

    test('two remote-only refs sharing a branch name collapse to one row', () {
      // Same collision with no local branch to prefer. First wins, so the
      // outcome is at least deterministic rather than last-write-wins.
      final origin = remoteBranch(remote: 'origin', branch: 'shared');
      final up = remoteBranch(remote: 'upstream', branch: 'shared');

      final merged = mergeLocalAndRemoteBranches([], [origin, up]);

      expect(merged.length, 1);
      expect(merged.single.fullName, 'refs/remotes/origin/shared');
    });

    test(
      'a remote ref whose branch name only prefixes a local one is kept',
      () {
        // `main` must not claim `main-2`: the rule is equality, not prefix.
        final local = localBranch(shortName: 'main');
        final remote = remoteBranch(remote: 'origin', branch: 'main-2');

        final merged = mergeLocalAndRemoteBranches([local], [remote]);

        expect(merged.length, 2);
      },
    );

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

  // How the sidebar answers 「where am I」 now that no pin does: the panel
  // seeds its expanded-folder set with the ancestors of HEAD, so the row is
  // already on screen. These must be `folderPath`s (`a/b`), not folder
  // *names* (`b`) -- `buildBranchTree` keys `expandedFolders` on the path,
  // and two different parents may each own a `sub`.
  group('ancestorFolderPaths', () {
    test('a one-level branch yields its single folder', () {
      expect(ancestorFolderPaths('feature/zeta'), <String>{'feature'});
    });

    test('a nested branch yields every level, as full paths', () {
      expect(ancestorFolderPaths('a/b/c'), <String>{'a', 'a/b'});
    });

    test('a root-level branch has no ancestors', () {
      expect(ancestorFolderPaths('main'), isEmpty);
    });

    test('an empty name (detached HEAD) has no ancestors', () {
      expect(ancestorFolderPaths(''), isEmpty);
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
