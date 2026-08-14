import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart' show sharedPreferencesProvider;

const String _kRecentsKey = 'recents.repos';
const int _kMaxRecents = 10;

/// Entry tracking a recently-opened repository.
class RecentRepoEntry {
  const RecentRepoEntry({
    required this.workDir,
    required this.lastOpenedEpochMs,
  });

  factory RecentRepoEntry.fromJson(Map<String, dynamic> json) {
    return RecentRepoEntry(
      workDir: json['workDir'] as String,
      lastOpenedEpochMs: json['lastOpenedEpochMs'] as int,
    );
  }

  final String workDir;
  final int lastOpenedEpochMs;

  Map<String, dynamic> toJson() => {
    'workDir': workDir,
    'lastOpenedEpochMs': lastOpenedEpochMs,
  };
}

/// Persists a list of recently-opened repositories, ordered newest-first,
/// capped at [_kMaxRecents]. Mirrors the [PanelLayoutRepository] pattern.
class RecentsRepository {
  RecentsRepository(this._prefs);

  final SharedPreferences _prefs;

  /// Returns the list of recently-opened repos (newest-first), or empty if
  /// nothing has been saved yet.
  List<RecentRepoEntry> read() {
    final String? raw = _prefs.getString(_kRecentsKey);
    if (raw == null) return const <RecentRepoEntry>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <RecentRepoEntry>[];
      return decoded
          .map(
            (e) =>
                e is Map<String, dynamic> ? RecentRepoEntry.fromJson(e) : null,
          )
          .whereType<RecentRepoEntry>()
          .toList(growable: false);
    } on FormatException {
      return const <RecentRepoEntry>[];
    }
  }

  /// Records that a repository was opened. Updates [workDir]'s timestamp to
  /// now (epoch ms), dedupes by workDir, caps the list at [_kMaxRecents],
  /// and persists newest-first.
  Future<void> recordOpen(String workDir) async {
    final entries = read().toList();

    // Remove if already present
    entries.removeWhere((e) => e.workDir == workDir);

    // Add at front with current timestamp
    final now = DateTime.now().millisecondsSinceEpoch;
    entries.insert(
      0,
      RecentRepoEntry(workDir: workDir, lastOpenedEpochMs: now),
    );

    // Cap at max
    if (entries.length > _kMaxRecents) {
      entries.removeRange(_kMaxRecents, entries.length);
    }

    await _prefs.setString(_kRecentsKey, jsonEncode(entries));
  }
}

final Provider<RecentsRepository> recentsRepositoryProvider =
    Provider<RecentsRepository>((ref) {
      return RecentsRepository(ref.watch(sharedPreferencesProvider));
    });
