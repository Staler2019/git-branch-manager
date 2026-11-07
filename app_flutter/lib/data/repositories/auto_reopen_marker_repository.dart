import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart' show sharedPreferencesProvider;

/// Remembers, across runs, which repository a launch is reopening on its own until its first
/// load has settled. Still set at the next launch, it means the app ended while opening it --
/// #207's loop, where every launch reopened the repository that crashed it -- so that launch
/// lands on the welcome screen instead (使用者裁定 2026-11-08: 「開 repo 前留標記、成功後清除；
/// 若上次沒成功，就不自動重開」, cleared 「開啟完成就清」).
class AutoReopenMarkerRepository {
  AutoReopenMarkerRepository(this._prefs);

  static const String key = 'launch.autoReopenPending';

  final SharedPreferences _prefs;

  /// The work dir being reopened, or null.
  String? read() => _prefs.getString(key);

  /// Awaited before the session opens: the marker has to be on disk before anything can crash.
  Future<void> set(String workDir) => _prefs.setString(key, workDir);

  Future<void> clear() => _prefs.remove(key);
}

final Provider<AutoReopenMarkerRepository> autoReopenMarkerRepositoryProvider =
    Provider<AutoReopenMarkerRepository>(
      (ref) => AutoReopenMarkerRepository(ref.watch(sharedPreferencesProvider)),
    );

/// The work dir this launch set the marker for. Only `bootstrapApp` overrides it, after the
/// marker is written; null otherwise, so nothing else ever watches a session for it.
final Provider<String?> pendingAutoReopenProvider = Provider<String?>(
  (ref) => null,
);

/// The work dir this launch did not reopen because the last one ended while opening it. Only
/// `bootstrapApp` overrides it; null otherwise.
final Provider<String?> skippedAutoReopenProvider = Provider<String?>(
  (ref) => null,
);
