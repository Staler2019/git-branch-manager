import 'package:flutter/foundation.dart';

/// One list's multi-selection, as spec page 13's `MULTIKEYS` table defines
/// it: an ordered set of chosen items plus a single **anchor** — the item a
/// subsequent Shift-click measures its range from.
///
/// Spec's framing is that single-selection is the degenerate case, not a
/// separate mode: 「單選是多選的特例：所有清單一律維持一組 selection + 一個
/// anchor」 (every list keeps one selection and one anchor; a single
/// selection is just the case where that set has one member). So the same
/// type backs History's commit list and the sidebar's branch tree, each
/// holding its own instance — spec keeps selections from bleeding across
/// lists (「選取狀態跨 scope 不混用」), which is why this is a plain value
/// type rather than one shared global.
///
/// Immutable: every transition returns a new instance (docs/ARCHITECTURE.md
/// invariant 2), so a Riverpod notifier can publish it directly and widget
/// rebuilds stay driven by identity rather than in-place mutation.
///
/// [items] keeps **insertion order**, not list order. That matters for the
/// anchor rules below and for actions that report what they are about to do
/// in the order the user picked. Anything that needs positional order (a
/// range, a contiguity check, a compare's older/newer sides) resolves it
/// against the underlying list, not against this order — see
/// [isContiguousIn] and [orderedBy].
@immutable
class ListSelection<T> {
  const ListSelection({this.items = const <Never>[], this.anchor});

  /// The empty selection: nothing chosen, no anchor.
  static ListSelection<T> empty<T>() => ListSelection<T>();

  /// Chosen items, in the order they were added.
  final List<T> items;

  /// The item a Shift-click measures its range from, and the one that keeps
  /// driving any single-target UI (History's commit detail panel reads it).
  /// Null exactly when [items] is empty.
  final T? anchor;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get length => items.length;
  bool get isMultiple => items.length > 1;

  bool contains(T item) => items.contains(item);

  /// `單擊`: select only this item and move the anchor here.
  ListSelection<T> single(T item) =>
      ListSelection<T>(items: <T>[item], anchor: item);

  /// `Ctrl / Cmd + 單擊`: toggle one item, moving the anchor to it.
  ///
  /// Deselecting the anchor itself is the one case `MULTIKEYS` does not
  /// spell out. Resolved here rather than ad hoc at a call site: the anchor
  /// falls back to the most recently added of whatever remains, so the next
  /// Shift-click still measures from something the user actually chose, and
  /// goes null only when the selection empties out.
  ListSelection<T> toggle(T item) {
    if (!items.contains(item)) {
      return ListSelection<T>(items: <T>[...items, item], anchor: item);
    }
    final List<T> remaining = <T>[
      for (final T existing in items)
        if (existing != item) existing,
    ];
    if (remaining.isEmpty) return ListSelection<T>();
    return ListSelection<T>(
      items: remaining,
      // Removing a non-anchor item leaves the anchor where it was; removing
      // the anchor promotes the newest survivor.
      anchor: item == anchor ? remaining.last : anchor,
    );
  }

  /// `Shift + 單擊` / `Shift + ↑ / ↓`: replace the selection with every item
  /// between the anchor and [item] inclusive, taken from [all] (the list's
  /// own order — the caller passes the *unfiltered* order where one exists).
  ///
  /// The anchor deliberately does **not** move: that is what makes a second
  /// Shift-click grow or shrink the same range instead of starting a new
  /// one. With no anchor yet, or with either end missing from [all], this
  /// degrades to a plain single selection rather than guessing a range.
  ListSelection<T> range(T item, List<T> all) {
    final T? from = anchor;
    if (from == null) return single(item);
    final int start = all.indexOf(from);
    final int end = all.indexOf(item);
    if (start < 0 || end < 0) return single(item);
    final int lo = start <= end ? start : end;
    final int hi = start <= end ? end : start;
    return ListSelection<T>(
      items: <T>[for (int i = lo; i <= hi; i++) all[i]],
      anchor: from,
    );
  }

  /// `Ctrl / Cmd + A`: select the whole current list. The anchor stays put
  /// when it is still present, so a following Shift-click still has the
  /// user's own reference point; otherwise it falls to the first item.
  ListSelection<T> selectAll(List<T> all) {
    if (all.isEmpty) return ListSelection<T>();
    final T? from = anchor;
    return ListSelection<T>(
      items: List<T>.of(all),
      anchor: from != null && all.contains(from) ? from : all.first,
    );
  }

  /// `Esc`: 「縮回單選（保留 anchor 項）」 — collapse back to just the
  /// anchor rather than clearing outright, so Esc undoes the *extension*
  /// without also throwing away where the user was.
  ListSelection<T> collapseToAnchor() {
    final T? from = anchor;
    if (from == null) return ListSelection<T>();
    return ListSelection<T>(items: <T>[from], anchor: from);
  }

  /// True when the selected items occupy an unbroken run of [all].
  ///
  /// Spec gates cherry-pick / revert on this: 「commit 多選只在連續範圍時開放
  /// cherry-pick / revert / squash；不連續時這三項 disabled」. An empty
  /// selection is not contiguous — there is nothing to act on — while a
  /// single item trivially is. An item missing from [all] (e.g. selected
  /// before a filter changed what the list holds) makes the answer false
  /// rather than throwing: the honest reading of "can these be replayed as
  /// one run" is no.
  bool isContiguousIn(List<T> all) {
    if (items.isEmpty) return false;
    final List<int> indices = <int>[];
    for (final T item in items) {
      final int index = all.indexOf(item);
      if (index < 0) return false;
      indices.add(index);
    }
    indices.sort();
    for (int i = 1; i < indices.length; i++) {
      if (indices[i] != indices[i - 1] + 1) return false;
    }
    return true;
  }

  /// The selection in [all]'s own order rather than insertion order — what
  /// anything positional needs: which of two commits is the older side of a
  /// compare, which order a cherry-pick replays in. Items absent from [all]
  /// are dropped, mirroring [isContiguousIn]'s treatment of them.
  List<T> orderedBy(List<T> all) => <T>[
    for (final T candidate in all)
      if (items.contains(candidate)) candidate,
  ];

  @override
  bool operator ==(Object other) =>
      other is ListSelection<T> &&
      other.anchor == anchor &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(anchor, Object.hashAll(items));

  @override
  String toString() => 'ListSelection(items: $items, anchor: $anchor)';
}
