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
    // Nothing to memo: the unfiltered answer computes nothing at all. The
    // counters below therefore describe the filtered branch only.
    return UnfilteredRowIndices(graph.rows.length);
  }

  final _MatchMemoEntry? cached = _matchMemo[graph];
  if (cached != null &&
      identical(cached.metaCache, metaCache) &&
      cached.query == query) {
    MatchMemoStats.hits++;
    return cached.result;
  }

  MatchMemoStats.misses++;
  final List<int> matches = <int>[];
  for (int i = 0; i < graph.rows.length; i++) {
    final String oid = i < graph.oidsHex.length ? graph.oidsHex[i] : '';
    if (commitMatchesQuery(query: query, oid: oid, meta: metaCache[oid])) {
      matches.add(i);
    }
  }
  // Unmodifiable because the list is now shared between callers and across
  // frames -- `CommitGraphView` reads it from both `_visibleOids` (scroll
  // tick) and `build()`. No caller mutates it today; this makes that a
  // property of the type rather than of the current call sites.
  final List<int> result = List<int>.unmodifiable(matches);
  _matchMemo[graph] = _MatchMemoEntry(metaCache, query, result);
  return result;
}

/// One memoised answer: the inputs it was computed from, and the result.
class _MatchMemoEntry {
  const _MatchMemoEntry(this.metaCache, this.query, this.result);

  final Map<String, CommitMeta> metaCache;
  final String query;
  final List<int> result;
}

/// Memo for [matchingRowIndices]' filtered branch.
///
/// ## Why
///
/// Scanning every row costs, in debug JIT with a `Stopwatch`: 35.2us at 703
/// commits, 489.7us at 10k, **5.03ms at 100k**. `CommitGraphView` calls it
/// from two independent places -- `_visibleOids` on every scroll tick and
/// `build()` on every rebuild -- so at 100k a filtered frame could spend
/// most of a 16.7ms budget rescanning for an answer it already had.
///
/// ## Cache contract
///
/// - **Key**: the [GraphSnapshotView] instance (via this [Expando]), plus
///   the [Map] instance of the metadata cache and the query string held in
///   the entry. All three are needed and each rules out a different wrong
///   answer: a new snapshot has different rows, a new metadata cache can
///   make rows match that did not match before, and a new query is a
///   different question entirely. Instance identity is honest for the first
///   two because both are immutable and rebuilt wholesale -- a snapshot by
///   `readGraphSnapshot()`, the metadata cache by
///   `RepoSessionState.withCommitMeta()`, which spreads into a **new** map
///   rather than mutating the old one. The query is compared by value
///   because it is a string.
///   `GraphSnapshotView.empty` is `const` and therefore canonicalised, so
///   every empty snapshot shares one slot; harmless, since the entry still
///   has to match on cache instance and query, and an empty snapshot has no
///   rows to return either way.
/// - **Invalidation**: none to write, because each key component changes
///   identity exactly when its meaning changes. That is also why the hit
///   rate is **partial while metadata is streaming**: every
///   `commitMetaReady` reply produces a new map and so a deliberate miss.
///   Scrolling back over rows whose metadata already arrived hits every
///   time. A single slot per snapshot is enough for both call sites, which
///   ask the same question one dispatch apart.
/// - **Symptom if this were wrong**: the filter would answer from stale
///   inputs -- typing would not change the list, or metadata would stream
///   in and the commits it makes match would never appear. Not a slowdown;
///   a visibly wrong list. `commit_search_memo_test.dart` counts hits and
///   misses, because a memo that recomputed every time would return exactly
///   the same correct answers.
final Expando<_MatchMemoEntry> _matchMemo = Expando<_MatchMemoEntry>(
  'matchingRowIndices',
);

/// Hit/miss counters for [matchingRowIndices]' memo, for tests only.
///
/// A cache that recomputed on every call would still answer correctly, so
/// asserting on the result proves nothing about whether the memo works.
/// These are what `commit_search_memo_test.dart` asserts on instead. They
/// are never reset -- read them as deltas around the call under test, the
/// same way `GraphSpanIndex.debugBuildCount` is read.
abstract final class MatchMemoStats {
  static int hits = 0;
  static int misses = 0;
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
/// The non-empty-query branch is the more expensive one -- 35.2us/call at
/// 703, 489.7us at 10k, **5.03ms at 100k** (same conditions) -- and is
/// **not** removable the way this branch is: the match set is a genuine
/// function of the metadata cache. It is memoised instead; see
/// [MatchMemoStats] and the `_matchMemo` contract below for why that memo
/// hits only partially while metadata is still streaming.
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
