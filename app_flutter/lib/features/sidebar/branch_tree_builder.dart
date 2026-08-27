import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'branch_filter.dart';
import 'branch_selection_rules.dart';

/// Base class for a node in the branch tree (folder or leaf).
sealed class BranchTreeNode {
  const BranchTreeNode();
}

/// A folder node containing zero or more child nodes.
final class BranchTreeFolder extends BranchTreeNode {
  const BranchTreeFolder({
    required this.folderName,
    required this.folderPath,
    required this.children,
    required this.isExpanded,
  });

  /// Display name of the folder (e.g., 'feature' from 'feature/auth').
  ///
  /// A single segment, so it is **not** unique in the tree: two different
  /// parents may each have a `sub`. Use [folderPath] to identify a folder.
  final String folderName;

  /// Full path from the root (e.g. 'feature/sub'), which is what
  /// `buildBranchTree`'s `expandedFolders` set is keyed by.
  ///
  /// This exists because `sidebar_panel.dart` keyed its expand/collapse
  /// state on [folderName] while the builder keyed [isExpanded] on the
  /// path -- the two agree only at depth one, so a nested folder's chevron
  /// and its children could disagree, and toggling one `sub` toggled every
  /// `sub`. Anything touching the expanded set must use this field.
  final String folderPath;

  /// Child nodes (folders or leaves).
  final List<BranchTreeNode> children;

  /// Whether this folder is currently expanded in the UI.
  final bool isExpanded;
}

/// A leaf node representing an actual branch ref.
final class BranchTreeLeaf extends BranchTreeNode {
  const BranchTreeLeaf({required this.ref, this.label});

  /// The underlying branch reference.
  final RefInfo ref;

  /// What the row should *print*, when that differs from the ref's own name.
  ///
  /// P02 item 12: 「名稱中的斜線自動摺成資料夾」. A branch sitting inside a
  /// folder shows only the segment below it -- the spec's BRANCH_TREE mock
  /// lists `graph-lanes` under `feature`, not `feature/graph-lanes`, because
  /// the folder row above already prints the prefix.
  ///
  /// Null for a root-level leaf, which has no folder to carry its prefix.
  /// Only rendering uses this: filtering (P02-14 treats `/` as a separator
  /// and matches the whole path), sorting, selection keys and the a11y label
  /// all stay on [ref]'s full slash-separated name.
  final String? label;

  /// [label] when the leaf sits under a folder, the ref's own name otherwise.
  String get displayLabel => label ?? ref.shortName;
}

/// Builds a hierarchical tree from a flat list of branch refs, grouping by
/// common path prefixes (e.g., 'feature/auth' and 'feature/dark-mode' both
/// group under a 'feature' folder).
///
/// Each path segment separated by '/' becomes a folder level. Single-segment
/// names (no '/') appear as leaf nodes at the root.
///
/// [expandedFolders] is a set of folder path strings (e.g., 'feature',
/// 'feature/sub') that should be expanded; folders not in this set are
/// collapsed by default.
///
/// [expandAll] opens every folder regardless of [expandedFolders], for spec
/// P02-14's 「有輸入時資料夾全展開，清空後回到原本收合狀態」. It is a
/// parameter rather than something the caller achieves by adding folder
/// names to [expandedFolders], precisely so that clearing the query restores
/// the user's own collapse state -- both halves of it. A caller that wrote
/// into the set and undid it afterwards would have to remember which folders
/// were already open, and would collapse them if it forgot.
///
/// Returns an immutable list of root-level nodes, ordered by branch name.
List<BranchTreeNode> buildBranchTree(
  List<RefInfo> branches,
  Set<String> expandedFolders, {
  bool expandAll = false,
}) {
  if (branches.isEmpty) {
    return const <BranchTreeNode>[];
  }

  // Map from folder path (e.g. 'feature', 'feature/sub') to its children
  final Map<String, _FolderNode> folderIndex = {};

  // Root-level nodes (both folders and direct leaves)
  final Map<String, BranchTreeNode> rootNodes = {};

  for (final ref in branches) {
    final parts = ref.shortName.split('/');

    if (parts.length == 1) {
      // No nesting -- direct leaf at root
      rootNodes[ref.shortName] = BranchTreeLeaf(ref: ref);
    } else {
      // Build or navigate the tree for all but the last segment
      String currentPath = '';
      for (int i = 0; i < parts.length - 1; i++) {
        final segment = parts[i];
        final previousPath = currentPath;
        currentPath = currentPath.isEmpty ? segment : '$currentPath/$segment';

        if (!folderIndex.containsKey(currentPath)) {
          final folder = _FolderNode(
            folderName: segment,
            folderPath: currentPath,
            isExpanded: expandAll || expandedFolders.contains(currentPath),
          );
          folderIndex[currentPath] = folder;

          // Add to parent (or root)
          if (previousPath.isEmpty) {
            rootNodes[currentPath] = folder;
          } else {
            folderIndex[previousPath]!.children.add(folder);
          }
        }
      }

      // Add the leaf to its immediate parent folder
      final leaf = BranchTreeLeaf(ref: ref, label: parts.last);
      folderIndex[currentPath]!.children.add(leaf);
    }
  }

  // Convert _FolderNode to BranchTreeFolder and sort
  final List<BranchTreeNode> result = rootNodes.values.map((node) {
    if (node is _FolderNode) {
      return _folderNodeToTree(node);
    }
    return node;
  }).toList();

  // Sort by folder/branch name (folders before leaves, each group sorted)
  result.sort(_compareTreeNodes);

  return result.toList(growable: false);
}

/// Remote branches indexed by branch name -- the part after `<remote>/` --
/// so that asking "what is this local branch's remote counterpart?" is O(1)
/// per row instead of a scan.
///
/// Built once per render pass and thrown away; it holds no state and is never
/// put into [RepoSessionState]. That last part is deliberate: a freshly built
/// `Map` has no value equality, so threading one through `WorkspaceScreen`'s
/// watched record would make the record unequal on every publish and restore
/// the menu-bar rebuild storm (CLAUDE.md, "History 捲動卡頓").
///
/// A name carried by **two** remotes is left out of the index entirely rather
/// than resolved to whichever came first -- see [counterpartOf].
class RemoteBranchIndex {
  const RemoteBranchIndex._(this._unambiguousByBranchName);

  factory RemoteBranchIndex.from(List<RefInfo> remoteBranches) {
    final Map<String, String> byName = <String, String>{};
    final Set<String> ambiguous = <String>{};
    for (final RefInfo remote in remoteBranches) {
      // origin/HEAD is not a branch to show, check out or claim.
      if (remote.isSymbolic) continue;
      final String branchName = remoteBranchParts(remote.fullName).$2;
      if (byName.containsKey(branchName)) {
        ambiguous.add(branchName);
        continue;
      }
      byName[branchName] = remote.fullName;
    }
    for (final String name in ambiguous) {
      byName.remove(name);
    }
    return RemoteBranchIndex._(byName);
  }

  /// Branch name -> that branch's one remote ref, ambiguous names removed.
  final Map<String, String> _unambiguousByBranchName;

  /// The full name of [local]'s counterpart, or the empty string when it has
  /// none.
  ///
  /// Two rules, in order:
  ///
  /// 1. **An explicit upstream wins.** [RefInfo.upstream] is git's
  ///    `%(upstream)` -- the tracked ref's *full* name
  ///    (`refs/remotes/origin/main`, confirmed against real `git for-each-ref`
  ///    output, not `%(upstream:short)`). It is returned whether or not that
  ///    ref is still present, because a tracked upstream that has vanished is
  ///    exactly the gone case callers need to see.
  /// 2. **Otherwise, an unambiguous same-named remote ref.** `git push origin
  ///    HEAD` (no `-u`) and most PR flows write no `branch.NAME.merge` config
  ///    at all, so `%(upstream)` comes back blank while the remote-tracking
  ///    ref exists all the same. With nothing but the name linking the two,
  ///    matching on the tracking *config* alone let that remote ref through as
  ///    a second row for a branch that already had one.
  ///
  /// Ambiguity claims nothing. With both `origin/main` and `upstream/main`
  /// present, nothing says which one an untracked local `main` means, and
  /// guessing would hide a real branch.
  String counterpartOf(RefInfo local) {
    if (local.upstream.isNotEmpty) {
      return local.upstream;
    }
    return _unambiguousByBranchName[local.shortName] ?? '';
  }
}

/// [RemoteBranchIndex.counterpartOf] for a caller with one branch to resolve
/// (the current branch, a selected row) rather than a list to walk.
///
/// O(remoteBranches) because it builds the index to answer once. A caller
/// resolving *every* row must build a [RemoteBranchIndex] instead and reuse
/// it -- calling this per row is quadratic, which measured 14ms per merge at
/// 500 local + 500 remote branches against 0.1ms for the indexed form.
String remoteCounterpartOf(RefInfo local, List<RefInfo> remoteBranches) =>
    RemoteBranchIndex.from(remoteBranches).counterpartOf(local);

/// Merges [localBranches] with the subset of [remoteBranches] that no local
/// branch claims ("remote-only", Flutter Desktop Spec's `BRANCH_STATES`
/// "Remote only（未 checkout）") into one flat list ready for
/// [buildBranchTree] -- spec page 02 items 4/12: "Local 與 remote 不再分兩
/// 段，同一條分支只出現一次".
///
/// Claiming is [RemoteBranchIndex.counterpartOf]'s two rules. A claimed
/// remote ref is dropped: the local leaf already represents it. An unclaimed
/// one is kept with its `shortName` rewritten to drop the leading `<remote>/`
/// segment (recover it with [remoteBranchParts] on `fullName`) so it groups
/// into the same folder a same-named local branch would, since
/// [buildBranchTree] groups by `shortName.split('/')`. Symbolic remote refs
/// (`origin/HEAD`) are excluded -- not a real branch to show or check out.
///
/// **This function is the one place that enforces 「同一條分支只出現一次」**,
/// and it holds after claiming too: two remotes can carry the same branch
/// name, in which case neither is claimed (the name is ambiguous) and both
/// would still arrive at the same rewritten `shortName`. Whoever is first
/// under that name wins, and [localBranches] come first, so the row that can
/// be checked out, merged and deleted is never the casualty. That is a real
/// reduction -- a second remote's copy of a branch name is not drawn -- and it
/// is deterministic rather than the order-dependent overwrite it replaced.
/// [buildBranchTree] does no such de-duplication of its own: root-level names
/// go into a `Map` (silently last-write-wins) and nested ones into a `List`
/// (visibly duplicated), so a caller handing it duplicates gets one of those
/// two failures.
List<RefInfo> mergeLocalAndRemoteBranches(
  List<RefInfo> localBranches,
  List<RefInfo> remoteBranches,
) {
  final RemoteBranchIndex index = RemoteBranchIndex.from(remoteBranches);
  final Set<String> claimed = <String>{};
  final Set<String> takenNames = <String>{};
  for (final RefInfo local in localBranches) {
    final String counterpart = index.counterpartOf(local);
    if (counterpart.isNotEmpty) {
      claimed.add(counterpart);
    }
    takenNames.add(local.shortName);
  }

  final List<RefInfo> remoteOnly = <RefInfo>[];
  for (final RefInfo r in remoteBranches) {
    if (r.isSymbolic || claimed.contains(r.fullName)) continue;
    final String branchName = remoteBranchParts(r.fullName).$2;
    // `Set.add` returns false when the name is already spoken for.
    if (!takenNames.add(branchName)) continue;
    remoteOnly.add(
      RefInfo(
        fullName: r.fullName,
        shortName: branchName,
        kind: r.kind,
        target: r.target,
        upstream: r.upstream,
        ahead: r.ahead,
        behind: r.behind,
        hasTrackingInfo: r.hasTrackingInfo,
        isGone: r.isGone,
        isHead: r.isHead,
        isSymbolic: r.isSymbolic,
        worktreePath: r.worktreePath,
      ),
    );
  }

  return <RefInfo>[...localBranches, ...remoteOnly];
}

/// Filters [branches] to those whose [RefInfo.shortName] matches [query]
/// under [matchesBranchFilter] (Cmd/Ctrl+Shift+E "Filter branches", see
/// gbm_action_id.dart's `editFilterBranches`). Matching is flat against the
/// full slash-delimited name (e.g. 'docs' matches 'chore/docs'), independent
/// of [buildBranchTree]'s folder grouping -- callers building a filtered
/// tree should pass the filtered list into [buildBranchTree] afterward.
///
/// This used to inline a bare `contains`, which failed spec P02-14's own
/// worked example; the rule now lives in `branch_filter.dart` because tags
/// and stashes are filtered by the same box and must share it.
///
/// A blank (empty or whitespace-only) [query] returns [branches] unchanged.
List<RefInfo> filterBranches(List<RefInfo> branches, String query) {
  if (query.trim().isEmpty) {
    return branches;
  }
  return branches
      .where((ref) => matchesBranchFilter(ref.shortName, query))
      .toList(growable: false);
}

/// Internal representation of a folder node being built.
class _FolderNode extends BranchTreeNode {
  _FolderNode({
    required this.folderName,
    required this.folderPath,
    required this.isExpanded,
  });

  final String folderName;
  final String folderPath;
  final bool isExpanded;
  final List<BranchTreeNode> children = <BranchTreeNode>[];
}

/// Recursively converts a _FolderNode to a BranchTreeFolder.
BranchTreeFolder _folderNodeToTree(_FolderNode node) {
  final convertedChildren = node.children.map((child) {
    if (child is _FolderNode) {
      return _folderNodeToTree(child);
    }
    return child;
  }).toList();

  convertedChildren.sort(_compareTreeNodes);

  return BranchTreeFolder(
    folderName: node.folderName,
    folderPath: node.folderPath,
    children: convertedChildren.toList(growable: false),
    isExpanded: node.isExpanded,
  );
}

/// Comparison function for sorting tree nodes: folders (alphabetically), then
/// leaves (alphabetically). **The current branch has no priority here.**
///
/// That is a *user-ratified deviation* from `BRANCH_STATES`' 目前分支 row
/// (「永遠置頂於所屬資料夾內」) and from `BRANCH_TREE`'s mock, which draws
/// `main` (`current: true`, `depth: 0`) above the folders at its own depth.
/// The user asked for a plain alphabetical tree: a pin makes the first row of
/// every level jump around depending on where HEAD happens to be, and it is
/// the sort order the whole sidebar is read through. Finding the current
/// branch is `sidebar_panel.dart`'s job instead -- it seeds the expanded set
/// with [ancestorFolderPaths] so the row is already on screen. Do not
/// reinstate the pin; see docs/ledger.md.
///
/// Folders-before-leaves stays, because it is tree *structure* rather than
/// branch priority -- the same distinction the user drew.
int _compareTreeNodes(BranchTreeNode a, BranchTreeNode b) {
  final aIsFolder = a is BranchTreeFolder;
  final bIsFolder = b is BranchTreeFolder;

  if (aIsFolder && !bIsFolder) return -1;
  if (!aIsFolder && bIsFolder) return 1;

  final aName = switch (a) {
    BranchTreeFolder(:final folderName) => folderName,
    BranchTreeLeaf(:final ref) => ref.shortName,
    _FolderNode(:final folderName) => folderName,
  };

  final bName = switch (b) {
    BranchTreeFolder(:final folderName) => folderName,
    BranchTreeLeaf(:final ref) => ref.shortName,
    _FolderNode(:final folderName) => folderName,
  };

  return aName.compareTo(bName);
}

/// The first selectable leaf in render order, skipping remote-only rows --
/// `BranchTreeItem` draws those with `selected: false`, so selecting one
/// would look like the key did nothing.
///
/// Every leaf in the tree is a genuine match now, so the first one *is* the
/// first result. This used to take a `skip` for the current branch, which
/// P02-14 rule 7 forced onto the screen whether or not it matched; that
/// exemption is gone (see `sidebar_panel.dart`), and with it the only caller
/// that ever passed the parameter.
String? firstLeafName(List<BranchTreeNode> nodes) {
  for (final BranchTreeNode node in nodes) {
    if (node is BranchTreeLeaf) {
      if (node.ref.kind != RefKind.remoteBranch) {
        return node.ref.shortName;
      }
    } else if (node is BranchTreeFolder) {
      final String? nested = firstLeafName(node.children);
      if (nested != null) return nested;
    }
  }
  return null;
}

/// The rows a range can span, walked out of the tree in paint order:
/// minus HEAD and remote-only rows (neither is bulk-selectable), and
/// minus anything inside a collapsed folder.
///
/// Collapsed children are excluded because `BranchFolderRow`'s caller does not
/// render them at all. A range that spanned them would select branches
/// with no visible row, and a later Shift+arrow could not step onto one --
/// so all three selection entry points read the same list and cannot
/// disagree about what "the current list" means.
List<String> selectableLeafNames(List<BranchTreeNode> nodes) {
  final List<String> names = <String>[];
  void walk(List<BranchTreeNode> level) {
    for (final BranchTreeNode node in level) {
      if (node is BranchTreeLeaf) {
        if (node.ref.kind != RefKind.remoteBranch &&
            isBulkSelectable(node.ref)) {
          names.add(node.ref.shortName);
        }
      } else if (node is BranchTreeFolder && node.isExpanded) {
        walk(node.children);
      }
    }
  }

  walk(nodes);
  return names;
}

/// Spec page 13's `MULTIBRANCHMENU`, opened by right-clicking any row
/// while more than one branch is selected. Right-clicking a row that is
/// *not* in the selection collapses to it first and gets the ordinary
/// 05-B menu instead -- see [_onBranchContextMenu].

/// Every leaf ref under [nodes], at any depth.
///
/// Used by the folder-scoped actions (05-J's "Delete merged in folder" and
/// "Fetch branches in folder"), which act on a whole subtree rather than on
/// one row.
List<RefInfo> collectFolderLeafRefs(List<BranchTreeNode> nodes) {
  final List<RefInfo> refs = <RefInfo>[];
  for (final BranchTreeNode node in nodes) {
    if (node is BranchTreeLeaf) {
      refs.add(node.ref);
    } else if (node is BranchTreeFolder) {
      refs.addAll(collectFolderLeafRefs(node.children));
    }
  }
  return refs;
}

/// Every ancestor folder of [shortName], as the full paths
/// [BranchTreeFolder.folderPath] uses -- `a/b/c` yields `{a, a/b}`, not
/// `{a, b}`. `buildBranchTree` keys `expandedFolders` on the path, and two
/// different parents may each own a `sub`, so names would open the wrong ones.
///
/// This is what puts the current branch on screen without a sort pin:
/// `sidebar_panel.dart` seeds its expanded set with the ancestors of HEAD.
/// A root-level branch and a detached HEAD (`''`) both have none, so both
/// correctly expand nothing.
Set<String> ancestorFolderPaths(String shortName) {
  final List<String> parts = shortName.split('/');
  final Set<String> paths = <String>{};
  String current = '';
  for (int i = 0; i < parts.length - 1; i++) {
    current = current.isEmpty ? parts[i] : '$current/${parts[i]}';
    paths.add(current);
  }
  return paths;
}

/// Every folder path under [nodes], at any depth.
///
/// Full paths, not display names -- the panel's expanded-folder set is keyed
/// the way [buildBranchTree] reads it (see [BranchTreeFolder.folderPath]).
Set<String> collectFolderPaths(List<BranchTreeNode> nodes) {
  final Set<String> names = <String>{};
  for (final BranchTreeNode node in nodes) {
    if (node is BranchTreeFolder) {
      names.add(node.folderPath);
      names.addAll(collectFolderPaths(node.children));
    }
  }
  return names;
}

/// What 05-J's "Fetch branches in folder" needs to call
/// `RepoSessionController.fetchRemote(remoteName:, refs:)`: the single
/// remote every fetchable branch in [refs] tracks, and the branch names
/// (as they exist on that remote, no prefix) to fetch. A local branch
/// with no configured upstream contributes nothing (there is no remote
/// ref for it to fetch). Returns null when there is nothing fetchable, or
/// when the branches present track more than one distinct remote --
/// `gbm_remote_fetch()` targets exactly one remote per call, and picking
/// one over another silently would fetch less than the user asked for.
(String remote, List<String> branches)? fetchableRefsInFolder(
  List<RefInfo> refs,
) {
  final Map<String, List<String>> byRemote = <String, List<String>>{};
  for (final RefInfo ref in refs) {
    final String upstream = ref.kind == RefKind.remoteBranch
        ? ref.fullName
        : ref.upstream;
    if (upstream.isEmpty) continue;
    final (String remote, String branch) = remoteBranchParts(upstream);
    if (remote.isEmpty || branch.isEmpty) continue;
    (byRemote[remote] ??= <String>[]).add(branch);
  }
  if (byRemote.length != 1) return null;
  final MapEntry<String, List<String>> only = byRemote.entries.single;
  return (only.key, only.value);
}
