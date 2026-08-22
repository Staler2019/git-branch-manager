import 'dart:math' as math;

/// The History list's columns, as pure data.
///
/// Spec page 02 item 16 (`spec_logic.js:491`) names eight of them:
///
/// > History 標題列右側一顆按鈕開出勾選清單：Graph、Message、Refs、Author、
/// > Date、Commit hash、Committer、Changed files。Graph 與 Message 固定不可關，
/// > 其餘可開關並拖曳排序。設定存在應用層級，所有 repo 共用；欄寬各自可拖曳並記憶。
///
/// This file holds the model and the two resolvers that turn whatever is in
/// SharedPreferences into something renderable. Everything here is pure: the
/// interesting cases are all *bad stored input* -- a preferences file written
/// by an older build, hand-edited, or corrupt -- and those are far easier to
/// pin against a function taking a literal than against a notifier reachable
/// only through a real store.
///
/// Storage ids are the strings `graph_columns_selector.dart` has already
/// written to `graphColumns.visibility` on every existing install. Renaming
/// one silently orphans a user's saved settings, so they are spelled out
/// here and pinned by `graph_column_test.dart` rather than derived from the
/// enum's own name.
enum GbmGraphColumnId {
  graph('graph', 'Graph', defaultWidth: 0, minWidth: 0, maxWidth: 0),
  message('message', 'Message', defaultWidth: 0, minWidth: 0, maxWidth: 0),
  // 60 is what the row has always reserved for the chip strip. Raising it
  // to a roomier-looking 120 was measured against
  // `workspace_narrow_window_test.dart`'s 1280x720 case -- the app's own
  // default window size -- and cost the Author column on a twelve-lane
  // history, so it stays where it is and the user drags it up when they
  // want more.
  refs('refs', 'Refs', defaultWidth: 60, minWidth: 48, maxWidth: 400),
  author('author', 'Author', defaultWidth: 110, minWidth: 48, maxWidth: 320),
  date('date', 'Date', defaultWidth: 80, minWidth: 48, maxWidth: 240),
  // Spec spells these "Commit hash" and "Changed files"; the picker they
  // replace used "Hash" and "Changed Files".
  hash('hash', 'Commit hash', defaultWidth: 64, minWidth: 40, maxWidth: 200),
  committer(
    'committer',
    'Committer',
    defaultWidth: 110,
    minWidth: 48,
    maxWidth: 320,
    defaultVisible: false,
  ),
  changedFiles(
    'changedFiles',
    'Changed files',
    defaultWidth: 64,
    minWidth: 40,
    maxWidth: 160,
    defaultVisible: false,
  );

  const GbmGraphColumnId(
    this.storageId,
    this.label, {
    required this.defaultWidth,
    required this.minWidth,
    required this.maxWidth,
    this.defaultVisible = true,
  });

  /// The key this column uses inside every `graphColumns.*` map.
  final String storageId;

  /// The picker's label, in the spec's own spelling.
  final String label;

  /// Starting width in logical pixels, before any drag. Meaningless for the
  /// two non-resizable columns, which carry 0.
  final double defaultWidth;
  final double minWidth;
  final double maxWidth;

  /// Whether the column is on when the stored visibility map says nothing
  /// about it -- spec's `GRAPH_COLS` `on:` flag (`spec_logic.js:451`), where
  /// Committer and Changed files are the only two that start off.
  ///
  /// This is not cosmetic. The old picker wrote a key only when a column was
  /// *toggled*, so every existing install has a map that omits these two, and
  /// a blanket `?? true` fallback switches them on for everybody the moment
  /// they gain a render path. It also decides who pays for the Changed files
  /// column's per-commit file counts: spec starts it off precisely so that
  /// cost is opt-in.
  final bool defaultVisible;

  /// Spec's "Graph 與 Message 固定不可關".
  ///
  /// Deliberately not read from `graph_columns_repository.dart`'s
  /// `kLockedGraphColumnIds`, even though the two must always agree: this
  /// file has no imports at all, and that is what lets the repository depend
  /// on it rather than the other way round. `graph_column_test.dart` asserts
  /// the two never drift.
  bool get isLocked =>
      this == GbmGraphColumnId.graph || this == GbmGraphColumnId.message;

  /// Spec's "其餘可開關並拖曳排序" governs toggling *and* reordering with one
  /// word, so a locked column is also a pinned one.
  bool get isMovable => !isLocked;

  /// The same six columns again, and not a third independent fact: graph's
  /// width is derived from the snapshot's lane count and message is the sole
  /// flex column, so neither has a "column width" to drag or remember. Spec's
  /// "欄寬各自可拖曳並記憶" is read against the same "其餘" as the sentence
  /// before it.
  bool get isResizable => !isLocked;
}

/// The spec's own order, from `GRAPH_COLS` (`spec_logic.js:451`).
///
/// This is one list, not two: the picker enumerates the columns in this
/// order and the mockup's History row (`spec_raw.html:1303-1312`) renders
/// them in the same one.
const List<GbmGraphColumnId> kGraphColumnOrderDefault = <GbmGraphColumnId>[
  GbmGraphColumnId.graph,
  GbmGraphColumnId.message,
  GbmGraphColumnId.refs,
  GbmGraphColumnId.author,
  GbmGraphColumnId.date,
  GbmGraphColumnId.hash,
  GbmGraphColumnId.committer,
  GbmGraphColumnId.changedFiles,
];

/// The storage ids of the columns spec starts switched off.
///
/// The shipped default, in the shape `planCommitRowColumns` takes its
/// `hiddenByUser` in. Derived from [GbmGraphColumnId.defaultVisible] rather
/// than written out, so the two cannot disagree.
final Set<String> kDefaultHiddenGraphColumnIds =
    Set<String>.unmodifiable(<String>{
      for (final GbmGraphColumnId id in GbmGraphColumnId.values)
        if (!id.defaultVisible) id.storageId,
    });

/// The column with this [storageId], or null if nothing matches.
GbmGraphColumnId? graphColumnById(String storageId) {
  for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
    if (id.storageId == storageId) return id;
  }
  return null;
}

/// Turns a persisted `graphColumns.order` list into a renderable order.
///
/// Guarantees, in this order of precedence:
///
///  1. `graph` is index 0 and `message` is index 1, whatever was stored.
///  2. Every remaining column appears in the stored relative order.
///  3. Known columns the stored list never mentioned are appended in
///     [kGraphColumnOrderDefault] order -- forward compatibility, so a
///     preferences file written before a column existed does not make that
///     column unreachable.
///  4. Unrecognised and duplicate ids are dropped.
///
/// The result therefore always contains every [GbmGraphColumnId] exactly
/// once, which is what lets callers index it without a null check.
List<GbmGraphColumnId> resolveGraphColumnOrder(List<String> stored) {
  final List<GbmGraphColumnId> movable = <GbmGraphColumnId>[];
  final Set<GbmGraphColumnId> seen = <GbmGraphColumnId>{};

  for (final String raw in stored) {
    final GbmGraphColumnId? id = graphColumnById(raw);
    if (id == null || !id.isMovable || !seen.add(id)) continue;
    movable.add(id);
  }
  for (final GbmGraphColumnId id in kGraphColumnOrderDefault) {
    if (!id.isMovable || seen.contains(id)) continue;
    movable.add(id);
    seen.add(id);
  }

  return <GbmGraphColumnId>[
    for (final GbmGraphColumnId id in kGraphColumnOrderDefault)
      if (!id.isMovable) id,
    ...movable,
  ];
}

/// Turns a persisted `graphColumns.widths` map into a complete one.
///
/// A stored width is honoured only when it is finite, positive, and belongs
/// to a resizable column; anything else falls back to the column's default,
/// and a value outside `[minWidth, maxWidth]` is clamped rather than
/// rejected (a user who dragged to an extreme should land at the extreme,
/// not back at the default).
Map<GbmGraphColumnId, double> resolveGraphColumnWidths(
  Map<String, double> stored,
) {
  return <GbmGraphColumnId, double>{
    for (final GbmGraphColumnId id in GbmGraphColumnId.values)
      id: _resolveWidth(id, stored[id.storageId]),
  };
}

double _resolveWidth(GbmGraphColumnId id, double? value) {
  if (!id.isResizable) return id.defaultWidth;
  if (value == null || !value.isFinite || value <= 0) return id.defaultWidth;
  return math.min(id.maxWidth, math.max(id.minWidth, value));
}
