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
  // Graph is the one column whose *content* width is not a preference: it is
  // `laneWidth * (laneCount + 1)`, so a busy repository can ask for any width
  // at all. These three numbers turn that open-ended demand into a budget.
  //
  //  * `defaultWidth` 153 is a **cap, not a size**: the column takes its
  //    natural width and stops there, so a two-lane history still draws two
  //    lanes and leaves the rest to the message. 153 = 17 x 9, i.e. eight
  //    parallel lanes plus the trailing half-slot. **Eight is ours, not
  //    spec's** -- the spec has nothing to say about how thick the graph may
  //    get. It is the point where the column stops reading as "where am I"
  //    and starts reading as a wall, and it is a single constant to change if
  //    that judgement is wrong.
  //  * `minWidth` 34 = 17 x 2 is one lane. **The column is never removable**
  //    (it stays `isLocked`, per spec's "Graph 與 Message 固定不可關"); this
  //    is how far a drag may collapse it, and one lane is still a graph.
  //  * `maxWidth` 425 = 17 x 25 is twenty-four lanes, past which the row is
  //    all graph on any ordinary window.
  //
  // Literals rather than `GbmLayout.graphLaneWidth * 9`: this file has no
  // imports at all, which is what lets the repository depend on it instead of
  // the reverse. `graph_column_test.dart` asserts all three stay exact lane
  // multiples, so the derivation is checked even though it is not expressed.
  graph('graph', 'Graph', defaultWidth: 153, minWidth: 34, maxWidth: 425),
  message('message', 'Message', defaultWidth: 0, minWidth: 0, maxWidth: 0),
  // 104, and the corridor it sits in was re-measured this round after the
  // lane pitch went from 18 to 17. Both bounds are measured, not reasoned
  // about.
  //
  //  * Floor 91. The HEAD chip is the sole thing in the row that says where
  //    you are, and spec labels it `HEAD → main` (`spec_logic.js:439`).
  //    `_RefChipStrip` clips left-aligned, so a column narrower than that
  //    chip renders `HEAD → ` and nothing useful. Measured off the bundled
  //    `assets/fonts/JetBrainsMono-Medium.ttf` -- the font `GbmTagChip`
  //    actually sets -- at `GbmTypography.textXs`: 72.6px of text plus 16px
  //    of horizontal padding plus 2px of border = 90.6px. (A widget test
  //    cannot check this: the Ahem test font makes every glyph one em wide
  //    and puts the same chip at 141.75px.)
  //  * **Ceiling 105**, re-bisected against
  //    `workspace_narrow_window_test.dart`'s twelve-lane case at 1280x720 --
  //    the app's own default window size. At 106 the ladder starts giving up
  //    the Author column there, which that test exists to forbid.
  //
  // **The previous ceiling was 92, and that 13px is exactly the graph column
  // getting narrower**: its natural width is `laneWidth * (laneCount + 1)`,
  // so twelve lanes went from `18 x 13 = 234` to `17 x 13 = 221`. The old
  // corridor was 91..92 -- 1.4px wide -- and the value had to be 92.
  //
  // What that bought is a defect closed rather than merely more room. At 92 a
  // HEAD **synced with its upstream** did not fit: that chip is `HEAD → main`
  // plus a 3px gap and a 9.5px cloud icon (`GbmTagChip`), i.e. 103.1px, and
  // the strip clips left-aligned -- so the cloud was the first thing lost and
  // what remained was glow-without-cloud, which is precisely the signature
  // spec assigns to the *opposite* state ("目前 HEAD，且遠端不在這裡",
  // `spec_raw.html:1392`). 104 is `ceil(103.1)`, so the synced chip now
  // renders whole at the default width.
  //
  // Anything longer than a four-character branch name still clips at the
  // default and needs a drag -- up to `maxWidth`, and remembered after.
  // `graph_column_test.dart` pins the floor; the narrow-window test pins the
  // ceiling; neither is free to move quietly.
  refs('refs', 'Refs', defaultWidth: 104, minWidth: 48, maxWidth: 400),
  author('author', 'Author', defaultWidth: 110, minWidth: 48, maxWidth: 320),
  date('date', 'Date', defaultWidth: 80, minWidth: 48, maxWidth: 240),
  // Spec spells these "Commit hash" and "Changed files"; the picker they
  // replace used "Hash" and "Changed Files".
  //
  // 64 is a slot rather than the intrinsic width of eight hex characters on
  // purpose: a widget test renders in the Ahem font, where every glyph is one
  // em wide, so an intrinsic hash measures ~88px in a test and ~53px on a
  // device. Sizing it explicitly makes the row's width budget mean the same
  // thing in both.
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

  /// Seven columns -- everything except Message, which is the sole flex
  /// column and so has no width of its own to drag or remember.
  ///
  /// **Graph is resizable but still locked**, and that combination is
  /// deliberate rather than an oversight. Spec's "其餘可開關並拖曳排序" keeps
  /// it unclosable, which [isLocked] honours; what a drag changes is the cap
  /// on how many lanes it will draw before clipping, not whether the column
  /// exists. Collapsing it to [minWidth] still leaves one lane, so the
  /// "Graph 固定不可關" guarantee holds at every width.
  bool get isResizable => this != GbmGraphColumnId.message;
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
