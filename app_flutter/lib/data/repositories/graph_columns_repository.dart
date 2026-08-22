import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
