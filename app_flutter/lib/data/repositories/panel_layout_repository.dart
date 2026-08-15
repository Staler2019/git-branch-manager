import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart' show sharedPreferencesProvider;

const String _kPanelLayoutKeyPrefix = 'panelLayout.';

/// Persists a splitter's current flex weights (or, for a fixed-first-pane
/// splitter like the sidebar, its single pixel extent) so panel sizing
/// survives app restarts. Keyed by the stable splitter id from spec page 09
/// (GbmLayout.splitterMainSidebar etc.) -- main window and conflict window
/// splitters use disjoint id namespaces ('main.*' vs 'cw.*') so they never
/// collide in the same SharedPreferences instance.
class PanelLayoutRepository {
  PanelLayoutRepository(this._prefs);

  final SharedPreferences _prefs;

  /// Returns the persisted weights for [splitterId], or null if nothing has
  /// been saved yet, or if what's stored is corrupt/unreadable -- either
  /// way the caller falls back to the spec's default.
  List<double>? read(String splitterId) {
    final String? raw = _prefs.getString('$_kPanelLayoutKeyPrefix$splitterId');
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map((Object? e) => (e as num).toDouble()).toList();
    } on FormatException {
      return null;
    }
  }

  Future<void> write(String splitterId, List<double> flex) {
    return _prefs.setString(
      '$_kPanelLayoutKeyPrefix$splitterId',
      jsonEncode(flex),
    );
  }

  /// Forgets every persisted splitter size, so each [GbmSplitPane] falls back
  /// to its spec default. Backs View → Reset panel sizes (Ctrl/Cmd+0, spec
  /// page 04). Only keys under this repository's own prefix are touched --
  /// theme, file-list mode and recents live in the same SharedPreferences
  /// instance and must survive a layout reset.
  Future<void> clear() async {
    final List<String> keys = _prefs
        .getKeys()
        .where((String k) => k.startsWith(_kPanelLayoutKeyPrefix))
        .toList(growable: false);
    for (final String key in keys) {
      await _prefs.remove(key);
    }
  }
}

/// Bumped by View → Reset panel sizes. Every mounted [GbmSplitPane] listens
/// to this and snaps back to its spec default when it changes.
///
/// A generation counter rather than a `clear()`-and-rebuild: split panes read
/// their stored size once in `initState` (so a drag is not fought by a
/// rebuild on every frame), which means clearing storage alone would not be
/// visible until the next app start.
final StateProvider<int> panelLayoutGenerationProvider = StateProvider<int>(
  (ref) => 0,
);

final Provider<PanelLayoutRepository> panelLayoutRepositoryProvider =
    Provider<PanelLayoutRepository>((ref) {
      return PanelLayoutRepository(ref.watch(sharedPreferencesProvider));
    });
