import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart';

/// Application-level settings behind spec page 11's Preferences dialog --
/// the six sections General / Repository sources / Git / Appearance /
/// Shortcuts / Advanced.
///
/// Deliberately *not* the same thing as Repository settings (spec page 06),
/// which is per-repository and lives in `RepoSessionState` /
/// `repository_settings_dialog.dart`. The spec keeps them separate ("與
/// repository settings 分開"), and so does this: nothing here is keyed by
/// repository.
///
/// Only the settings this layer can actually honour are stored. Where the
/// spec describes behaviour that needs core/FFI support this rewrite does
/// not expose yet (metered-network pausing, log file rotation on disk), the
/// field is absent rather than present-and-ignored -- a preference that
/// silently does nothing is worse than one that is not offered.
class AppPreferences {
  const AppPreferences({
    this.autoFetchEnabled = false,
    this.autoFetchMinutes = 10,
    this.autoFetchPrune = false,
    this.recordManualOpens = true,
    this.autoScanEnabled = false,
    this.autoScanMinutes = 30,
    this.globalGitignoreEnabled = false,
    this.globalGitignorePath = '',
    this.cherryPickAddsSourceLine = true,
    this.confirmForcePush = true,
    this.logMemoryLimit = 2000,
    this.logRetentionDays = 7,
  });

  /// General. Spec page 11 item 9: "只針對目前開啟的 repository，預設每 10
  /// 分鐘一次… 純 fetch 不動 working tree".
  final bool autoFetchEnabled;
  final int autoFetchMinutes;
  final bool autoFetchPrune;

  /// General. Spec page 11 item 6: manually-opened repositories are recorded
  /// in their own list rather than mixed into the base folders.
  final bool recordManualOpens;

  /// Repository sources. Spec page 11 item 4: background rescan of the base
  /// folders; when off, scanning only happens on an explicit Rescan now.
  final bool autoScanEnabled;
  final int autoScanMinutes;

  /// Git. Spec page 11 item 8: writes `core.excludesFile`, shared with the
  /// CLI. Disabling removes the setting without deleting the file.
  final bool globalGitignoreEnabled;
  final String globalGitignorePath;

  /// Git. Spec page 07's `MSGS` table, Cherry-pick row: the trailing
  /// "(cherry picked from commit …)" line "可在 Preferences 關閉".
  final bool cherryPickAddsSourceLine;

  /// Advanced. Spec page 06's Force push row: "可在 Preferences 關閉此確認".
  final bool confirmForcePush;

  /// Advanced. Spec page 10's `LOGRULES` retention row: "記憶體中保留最近
  /// 2,000 筆，寫檔保留 7 天並輪替。上限寫在 Preferences，不隱藏".
  final int logMemoryLimit;
  final int logRetentionDays;

  AppPreferences copyWith({
    bool? autoFetchEnabled,
    int? autoFetchMinutes,
    bool? autoFetchPrune,
    bool? recordManualOpens,
    bool? autoScanEnabled,
    int? autoScanMinutes,
    bool? globalGitignoreEnabled,
    String? globalGitignorePath,
    bool? cherryPickAddsSourceLine,
    bool? confirmForcePush,
    int? logMemoryLimit,
    int? logRetentionDays,
  }) {
    return AppPreferences(
      autoFetchEnabled: autoFetchEnabled ?? this.autoFetchEnabled,
      autoFetchMinutes: autoFetchMinutes ?? this.autoFetchMinutes,
      autoFetchPrune: autoFetchPrune ?? this.autoFetchPrune,
      recordManualOpens: recordManualOpens ?? this.recordManualOpens,
      autoScanEnabled: autoScanEnabled ?? this.autoScanEnabled,
      autoScanMinutes: autoScanMinutes ?? this.autoScanMinutes,
      globalGitignoreEnabled:
          globalGitignoreEnabled ?? this.globalGitignoreEnabled,
      globalGitignorePath: globalGitignorePath ?? this.globalGitignorePath,
      cherryPickAddsSourceLine:
          cherryPickAddsSourceLine ?? this.cherryPickAddsSourceLine,
      confirmForcePush: confirmForcePush ?? this.confirmForcePush,
      logMemoryLimit: logMemoryLimit ?? this.logMemoryLimit,
      logRetentionDays: logRetentionDays ?? this.logRetentionDays,
    );
  }
}

const String _kPrefix = 'appPrefs.';

class AppPreferencesRepository {
  AppPreferencesRepository(this._prefs);

  final SharedPreferences _prefs;

  AppPreferences read() {
    const AppPreferences defaults = AppPreferences();
    return AppPreferences(
      autoFetchEnabled:
          _prefs.getBool('${_kPrefix}autoFetchEnabled') ??
          defaults.autoFetchEnabled,
      autoFetchMinutes:
          _prefs.getInt('${_kPrefix}autoFetchMinutes') ??
          defaults.autoFetchMinutes,
      autoFetchPrune:
          _prefs.getBool('${_kPrefix}autoFetchPrune') ?? defaults.autoFetchPrune,
      recordManualOpens:
          _prefs.getBool('${_kPrefix}recordManualOpens') ??
          defaults.recordManualOpens,
      autoScanEnabled:
          _prefs.getBool('${_kPrefix}autoScanEnabled') ??
          defaults.autoScanEnabled,
      autoScanMinutes:
          _prefs.getInt('${_kPrefix}autoScanMinutes') ??
          defaults.autoScanMinutes,
      globalGitignoreEnabled:
          _prefs.getBool('${_kPrefix}globalGitignoreEnabled') ??
          defaults.globalGitignoreEnabled,
      globalGitignorePath:
          _prefs.getString('${_kPrefix}globalGitignorePath') ??
          defaults.globalGitignorePath,
      cherryPickAddsSourceLine:
          _prefs.getBool('${_kPrefix}cherryPickAddsSourceLine') ??
          defaults.cherryPickAddsSourceLine,
      confirmForcePush:
          _prefs.getBool('${_kPrefix}confirmForcePush') ??
          defaults.confirmForcePush,
      logMemoryLimit:
          _prefs.getInt('${_kPrefix}logMemoryLimit') ?? defaults.logMemoryLimit,
      logRetentionDays:
          _prefs.getInt('${_kPrefix}logRetentionDays') ??
          defaults.logRetentionDays,
    );
  }

  Future<void> write(AppPreferences p) async {
    await _prefs.setBool('${_kPrefix}autoFetchEnabled', p.autoFetchEnabled);
    await _prefs.setInt('${_kPrefix}autoFetchMinutes', p.autoFetchMinutes);
    await _prefs.setBool('${_kPrefix}autoFetchPrune', p.autoFetchPrune);
    await _prefs.setBool('${_kPrefix}recordManualOpens', p.recordManualOpens);
    await _prefs.setBool('${_kPrefix}autoScanEnabled', p.autoScanEnabled);
    await _prefs.setInt('${_kPrefix}autoScanMinutes', p.autoScanMinutes);
    await _prefs.setBool(
      '${_kPrefix}globalGitignoreEnabled',
      p.globalGitignoreEnabled,
    );
    await _prefs.setString(
      '${_kPrefix}globalGitignorePath',
      p.globalGitignorePath,
    );
    await _prefs.setBool(
      '${_kPrefix}cherryPickAddsSourceLine',
      p.cherryPickAddsSourceLine,
    );
    await _prefs.setBool('${_kPrefix}confirmForcePush', p.confirmForcePush);
    await _prefs.setInt('${_kPrefix}logMemoryLimit', p.logMemoryLimit);
    await _prefs.setInt('${_kPrefix}logRetentionDays', p.logRetentionDays);
  }
}

final Provider<AppPreferencesRepository> appPreferencesRepositoryProvider =
    Provider<AppPreferencesRepository>((ref) {
      return AppPreferencesRepository(ref.watch(sharedPreferencesProvider));
    });

class AppPreferencesNotifier extends StateNotifier<AppPreferences> {
  AppPreferencesNotifier(this._repo) : super(_repo.read());

  final AppPreferencesRepository _repo;

  /// Applies [update] to the current value and persists the result. Callers
  /// pass a `copyWith` closure so a single setting can change without every
  /// call site restating all twelve fields.
  Future<void> update(AppPreferences Function(AppPreferences) mutate) async {
    state = mutate(state);
    await _repo.write(state);
  }
}

final StateNotifierProvider<AppPreferencesNotifier, AppPreferences>
appPreferencesProvider =
    StateNotifierProvider<AppPreferencesNotifier, AppPreferences>((ref) {
      return AppPreferencesNotifier(ref.watch(appPreferencesRepositoryProvider));
    });
