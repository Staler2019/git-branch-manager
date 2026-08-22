import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/graph_column.dart';
import '../../theme/theme_mode_provider.dart' show sharedPreferencesProvider;

/// Persists graph column visibility, order, and width settings app-level
/// (not per-repository). Configuration survives app restarts via SharedPreferences.
class GraphColumnsRepository {
  GraphColumnsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String keyPrefix = 'graphColumns.';

  /// Returns the persisted visibility map (column id -> visible bool),
  /// or an empty map if nothing has been saved yet or data is corrupt.
  Map<String, bool> readVisibility() {
    final String? raw = _prefs.getString('${keyPrefix}visibility');
    if (raw == null) return <String, bool>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, bool>{};
      return decoded.cast<String, bool>();
    } on FormatException {
      return <String, bool>{};
    }
  }

  /// Persists the visibility map for all columns.
  Future<void> writeVisibility(Map<String, bool> visibility) {
    return _prefs.setString('${keyPrefix}visibility', jsonEncode(visibility));
  }

  /// Returns the persisted column order list (column ids in display order),
  /// or an empty list if nothing has been saved yet or data is corrupt.
  List<String> readOrder() {
    final String? raw = _prefs.getString('${keyPrefix}order');
    if (raw == null) return <String>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return <String>[];
      return decoded.cast<String>();
    } on FormatException {
      return <String>[];
    }
  }

  /// Persists the column order list.
  Future<void> writeOrder(List<String> order) {
    return _prefs.setString('${keyPrefix}order', jsonEncode(order));
  }

  /// Returns the persisted width map (column id -> width in pixels),
  /// or an empty map if nothing has been saved yet or data is corrupt.
  Map<String, double> readWidths() {
    final String? raw = _prefs.getString('${keyPrefix}widths');
    if (raw == null) return <String, double>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, double>{};
      return decoded.map<String, double>(
        (String key, dynamic value) => MapEntry(key, (value as num).toDouble()),
      );
    } on FormatException {
      return <String, double>{};
    }
  }

  /// Persists the width map for all columns.
  Future<void> writeWidths(Map<String, double> widths) {
    return _prefs.setString('${keyPrefix}widths', jsonEncode(widths));
  }
}

final Provider<GraphColumnsRepository> graphColumnsRepositoryProvider =
    Provider<GraphColumnsRepository>((ref) {
      return GraphColumnsRepository(ref.watch(sharedPreferencesProvider));
    });

/// The two columns spec page 02 item 16 pins open: "Graph 與 Message 固定
/// 不可關". Enforced in the store rather than only in the picker's disabled
/// checkbox -- a disabled control is an affordance, not an invariant, and a
/// hand-edited or corrupt preferences file reaches the same state.
const Set<String> kLockedGraphColumnIds = <String>{'graph', 'message'};

/// Whether [columnId] is on, given a (possibly partial) [visibility] map.
/// Unseen columns default to visible: a first run has an empty map and must
/// show the spec's own annotated layout.
bool isGraphColumnVisible(Map<String, bool> visibility, String columnId) {
  if (kLockedGraphColumnIds.contains(columnId)) return true;
  return visibility[columnId] ?? true;
}

/// Column visibility as live state rather than a value read once.
///
/// [GraphColumnsSelector] used to hold this map in its own `State` and write
/// it straight to SharedPreferences. Nothing under `lib/` read it back on
/// the render path, so toggling a column changed the stored preference and
/// nothing on screen -- the orphan-wiring shape this repository's audits
/// keep finding. A StateNotifier is what lets both the picker and
/// CommitGraphView sit on one source; the shape mirrors
/// [ChromeVisibilityNotifier], its closest sibling.
class GraphColumnVisibilityNotifier extends StateNotifier<Map<String, bool>> {
  GraphColumnVisibilityNotifier(this._repo) : super(_repo.readVisibility());

  final GraphColumnsRepository _repo;

  Future<void> setVisible(String columnId, bool visible) async {
    if (kLockedGraphColumnIds.contains(columnId)) return;
    final Map<String, bool> next = <String, bool>{...state, columnId: visible};
    state = next;
    await _repo.writeVisibility(next);
  }
}

final StateNotifierProvider<GraphColumnVisibilityNotifier, Map<String, bool>>
graphColumnVisibilityProvider =
    StateNotifierProvider<GraphColumnVisibilityNotifier, Map<String, bool>>((
      ref,
    ) {
      return GraphColumnVisibilityNotifier(
        ref.watch(graphColumnsRepositoryProvider),
      );
    });

/// The switched-off columns, in the shape `planCommitRowColumns` takes.
/// Locked columns can never appear here, whatever the stored map says.
final Provider<Set<String>> hiddenGraphColumnsProvider = Provider<Set<String>>((
  ref,
) {
  final Map<String, bool> visibility = ref.watch(graphColumnVisibilityProvider);
  return <String>{
    for (final MapEntry<String, bool> entry in visibility.entries)
      if (!entry.value && !kLockedGraphColumnIds.contains(entry.key)) entry.key,
  };
});

/// Column order as live state.
///
/// Sibling of [GraphColumnVisibilityNotifier], and orphaned for the same
/// reason until now: [GraphColumnsRepository.readOrder] had no caller on the
/// render path at all.
///
/// State is always a fully resolved order -- every column exactly once, the
/// two locked ones pinned to the front -- so the render path can index it
/// without re-validating. [move] is the only transition; it re-resolves
/// after applying, so an out-of-range or locked-slot drag degrades to a
/// no-op rather than corrupting the list.
class GraphColumnOrderNotifier extends StateNotifier<List<GbmGraphColumnId>> {
  GraphColumnOrderNotifier(this._repo)
    : super(resolveGraphColumnOrder(_repo.readOrder()));

  final GraphColumnsRepository _repo;

  /// Moves the column at [oldIndex] to [newIndex], both indices into the
  /// full order (locked columns included, so the picker's own indices and
  /// these agree).
  ///
  /// Refused, as a no-op, when either index is out of range or either end
  /// touches a locked slot: spec pins Graph and Message, and a `ReorderableListView`
  /// that excludes them from its children is an affordance, not the invariant.
  Future<void> move(int oldIndex, int newIndex) async {
    final List<GbmGraphColumnId> current = state;
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex < 0 || newIndex >= current.length) return;
    if (!current[oldIndex].isMovable) return;
    if (!current[newIndex].isMovable) return;
    if (oldIndex == newIndex) return;

    final List<GbmGraphColumnId> next = <GbmGraphColumnId>[...current];
    next.insert(newIndex, next.removeAt(oldIndex));

    state = resolveGraphColumnOrder(<String>[
      for (final GbmGraphColumnId id in next) id.storageId,
    ]);
    await _repo.writeOrder(<String>[
      for (final GbmGraphColumnId id in state) id.storageId,
    ]);
  }
}

final StateNotifierProvider<GraphColumnOrderNotifier, List<GbmGraphColumnId>>
graphColumnOrderProvider =
    StateNotifierProvider<GraphColumnOrderNotifier, List<GbmGraphColumnId>>((
      ref,
    ) {
      return GraphColumnOrderNotifier(
        ref.watch(graphColumnsRepositoryProvider),
      );
    });

/// Column widths as live state, with the write deliberately separated from
/// the state change.
///
/// A resize drag calls [setWidth] on every frame; persisting there would
/// write SharedPreferences at the frame rate. [commitWidths] is what the
/// drag-end handler calls instead -- the same split
/// `split_pane.dart` makes between its drag updates and its `_persist`.
class GraphColumnWidthNotifier
    extends StateNotifier<Map<GbmGraphColumnId, double>> {
  GraphColumnWidthNotifier(this._repo)
    : super(resolveGraphColumnWidths(_repo.readWidths()));

  final GraphColumnsRepository _repo;

  /// Sets [id]'s width, clamped to its own range. State only -- call
  /// [commitWidths] once the gesture ends.
  void setWidth(GbmGraphColumnId id, double width) {
    if (!id.isResizable) return;
    final double clamped = width.clamp(id.minWidth, id.maxWidth).toDouble();
    if (state[id] == clamped) return;
    state = <GbmGraphColumnId, double>{...state, id: clamped};
  }

  /// Persists the current widths. Only resizable columns are written: the
  /// other two have no width of their own, and storing one would be a value
  /// [resolveGraphColumnWidths] then has to ignore on the way back in.
  Future<void> commitWidths() {
    return _repo.writeWidths(<String, double>{
      for (final MapEntry<GbmGraphColumnId, double> entry in state.entries)
        if (entry.key.isResizable) entry.key.storageId: entry.value,
    });
  }
}

final StateNotifierProvider<
  GraphColumnWidthNotifier,
  Map<GbmGraphColumnId, double>
>
graphColumnWidthProvider =
    StateNotifierProvider<
      GraphColumnWidthNotifier,
      Map<GbmGraphColumnId, double>
    >((ref) {
      return GraphColumnWidthNotifier(
        ref.watch(graphColumnsRepositoryProvider),
      );
    });

/// Order, width and visibility as one value.
///
/// The commit rows, the layout ladder and the resize strips all need the
/// same three facts, and each deriving them separately is how the three
/// drift apart. Everything downstream reads this.
class GraphColumnLayout {
  const GraphColumnLayout({
    required this.order,
    required this.widths,
    required this.visibility,
  });

  /// Every column, in display order, locked ones first.
  final List<GbmGraphColumnId> order;
  final Map<GbmGraphColumnId, double> widths;
  final Map<String, bool> visibility;

  double widthOf(GbmGraphColumnId id) => widths[id] ?? id.defaultWidth;

  bool isVisible(GbmGraphColumnId id) =>
      isGraphColumnVisible(visibility, id.storageId);

  /// [order] without the switched-off columns.
  List<GbmGraphColumnId> get visibleOrder => <GbmGraphColumnId>[
    for (final GbmGraphColumnId id in order)
      if (isVisible(id)) id,
  ];

  /// The switched-off columns, in the shape `planCommitRowColumns` takes.
  Set<String> get hiddenStorageIds => <String>{
    for (final GbmGraphColumnId id in order)
      if (!isVisible(id)) id.storageId,
  };
}

final Provider<GraphColumnLayout> graphColumnLayoutProvider =
    Provider<GraphColumnLayout>((ref) {
      return GraphColumnLayout(
        order: ref.watch(graphColumnOrderProvider),
        widths: ref.watch(graphColumnWidthProvider),
        visibility: ref.watch(graphColumnVisibilityProvider),
      );
    });
