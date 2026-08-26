import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/commit_meta.dart';
import '../../data/models/graph_snapshot.dart';
import '../../data/repositories/repo_identity.dart';

/// The live query behind Edit → Find in history (Ctrl/Cmd+F).
///
/// Spec page 02 item 3: "就地過濾 commit 清單，支援 message / author / hash
/// 前綴" -- an in-place filter of the list already on screen, not a separate
/// results view.
///
/// Per-repository, so switching repository does not carry a stale filter
/// across, and transient (not persisted): a filter the user left behind days
/// ago silently hiding most of the history on next launch would read as data
/// loss.
///
/// **Known limitation.** Message and author matching can only see commits
/// whose [CommitMeta] has been fetched, which today is driven by what has
/// scrolled into view (`requestCommitMeta`). Hash-prefix matching is exact
/// over the whole snapshot, since oids come from the graph buffer itself.
/// Making message search exhaustive needs a core-side search entry point
/// rather than a wider prefetch -- streaming metadata for every commit of a
/// 200k-commit history to filter it in Dart would defeat the point of the
/// packed snapshot. Until then the match count rendered next to the field is
/// "matches among loaded commits", not "matches in the repository".
final StateProviderFamily<String, RepoIdentity> commitSearchQueryProvider =
    StateProvider.family<String, RepoIdentity>((ref, identity) => '');

/// The search field's focus node, shared between the field that owns it
/// (`CommitGraphView`) and the Ctrl/Cmd+F handler that focuses it
/// (`WorkspaceScreen`).
///
/// A provider rather than a constructor parameter, unlike
/// `SidebarPanel.filterFocusNode`: the sidebar is built by `WorkspaceScreen`
/// itself, but `HistoryPage` arrives as a `ShellRoute` child, so there is no
/// constructor call between the two to thread a node through.
final ProviderFamily<FocusNode, RepoIdentity> historySearchFocusNodeProvider =
    Provider.family<FocusNode, RepoIdentity>((ref, identity) {
      final FocusNode node = FocusNode(debugLabel: 'historySearch');
      ref.onDispose(node.dispose);
      return node;
    });

/// Whether [query] matches the commit at [oid].
///
/// The three fields the spec names, in the order it names them:
/// - **message**: case-insensitive substring of the subject *and* body, so a
///   query can find a commit by something written below the summary line.
/// - **author**: case-insensitive substring of the author's name or email.
/// - **hash prefix**: `startsWith`, not `contains` -- an abbreviated OID is
///   meaningful only as a prefix, and substring-matching hex would make
///   almost any short query match almost every commit.
///
/// [meta] is null until `commitMetaReady` has answered for this oid (rows
/// are fetched lazily as they scroll into view). An unresolved row can still
/// match on its hash, which is known from the graph snapshot alone.
bool commitMatchesQuery({
  required String query,
  required String oid,
  required CommitMeta? meta,
}) {
  if (query.isEmpty) return true;
  final String needle = query.toLowerCase();

  if (oid.toLowerCase().startsWith(needle)) return true;
  if (meta == null) return false;

  if (meta.subject.toLowerCase().contains(needle)) return true;
  if (meta.body.toLowerCase().contains(needle)) return true;
  if (meta.author.name.toLowerCase().contains(needle)) return true;
  if (meta.author.email.toLowerCase().contains(needle)) return true;
  return false;
}

/// The row indices of [graph] matching [query], in history order.
///
/// Indices into the *unfiltered* snapshot are returned rather than a
/// filtered copy of the rows, so callers keep the original row index needed
/// for selection and for `GraphSnapshotView`'s edge lookups.
List<int> matchingRowIndices({
  required String query,
  required GraphSnapshotView graph,
  required Map<String, CommitMeta> metaCache,
}) {
  if (query.isEmpty) {
    return UnfilteredRowIndices(graph.rows.length);
  }
  final List<int> matches = <int>[];
  for (int i = 0; i < graph.rows.length; i++) {
    final String oid = i < graph.oidsHex.length ? graph.oidsHex[i] : '';
    if (commitMatchesQuery(query: query, oid: oid, meta: metaCache[oid])) {
      matches.add(i);
    }
  }
  return matches;
}

/// `[0, 1, ..., length - 1]` without allocating it.
///
/// This is the unfiltered answer from [matchingRowIndices], which is the
/// History list's commonest state by far. It used to be built with
/// `List<int>.generate(graph.rows.length, (i) => i)` -- an N-element
/// allocation whose i-th element is i, produced on **every scroll tick**
/// (`CommitGraphView._onScroll` -> `_requestVisibleMeta` -> `_visibleOids`)
/// and again in every `build()`. Measured in debug JIT with a `Stopwatch`,
/// both paths warmed 20k iterations first (an unwarmed run reports the
/// index getting *cheaper* as N grows, which is JIT warm-up, not a result):
/// 4.0us/call at 703 commits, 41.2us at 10k, **669.9us at 100k**.
///
/// Removed rather than cached, per this repo's own preference for deleting
/// a recomputation over memoising it: with nothing filtered, a position in
/// the rendered list *is* the snapshot row index, so there is nothing to
/// compute and correspondingly no invalidation to get wrong.
///
/// **The non-empty-query branch above was deliberately left alone**, and is
/// the more expensive one: 35.2us/call at 703, 489.7us at 10k, **5.03ms at
/// 100k** (same conditions). It is not removable the way this branch is --
/// the match set is a genuine function of the metadata cache -- and the memo
/// that would cover it has to key on that cache's identity, which gets a new
/// one on **every metadata reply**, i.e. exactly the scroll-streaming path
/// it would need to serve. Deciding whether a roughly-half-hit-rate cache
/// earns its invalidation contract is the user's call, not the
/// implementer's; the number is recorded here and in docs/ledger.md so that
/// call is made from a measurement.
///
/// Read-only on purpose. Every element is derived from its own index, so a
/// write has nowhere to go; mutating members throw [UnsupportedError]
/// rather than silently dropping the value.
class UnfilteredRowIndices extends ListBase<int> {
  UnfilteredRowIndices(this.length);

  @override
  final int length;

  @override
  set length(int newLength) => throw UnsupportedError(
    'UnfilteredRowIndices is a fixed-length view of 0..length-1',
  );

  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return index;
  }

  @override
  void operator []=(int index, int value) => throw UnsupportedError(
    'UnfilteredRowIndices is read-only: element i is always i',
  );
}
