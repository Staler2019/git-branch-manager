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
