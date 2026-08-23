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
    this.globalGitignoreSource = '',
    this.cherryPickAddsSourceLine = true,
    this.confirmForcePush = true,
    this.logMemoryLimit = 2000,
    this.logRetentionDays = 7,
    this.autoUpdateCheckEnabled = true,
    this.skippedVersion = '',
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

  /// Where [globalGitignorePath] came from: `''` (never set), `'imported'`
  /// (read from the user's pre-existing `git config --global
  /// core.excludesFile` at some point), or `'manual'` (typed into the path
  /// field). Scoped down from the original ask: nothing in this app
  /// currently *detects* an importable value (that would mean reading the
  /// user's global git config, which has no capi entry point yet), so today
  /// only the `''`/`'manual'` states are ever actually reached in
  /// production. `'imported'` exists so a future round can wire up
  /// detection without another field-plus-migration round trip, and so the
  /// label-rendering logic in `_GitSection` has something real to switch on
  /// and test now.
  final String globalGitignoreSource;

  /// Git. Spec page 07's `MSGS` table, Cherry-pick row: the trailing
  /// "(cherry picked from commit …)" line "可在 Preferences 關閉".
  final bool cherryPickAddsSourceLine;

  /// Advanced. Spec page 06's Force push row: "可在 Preferences 關閉此確認".
  final bool confirmForcePush;

  /// Advanced. Spec page 10's `LOGRULES` retention row: "記憶體中保留最近
  /// 2,000 筆，寫檔保留 7 天並輪替。上限寫在 Preferences，不隱藏".
  final int logMemoryLimit;
  final int logRetentionDays;

  /// General. Not from the spec -- the 21-page design predates the update
  /// feature entirely. On by default because an update the user never hears
  /// about is the state this exists to fix; off is a real setting that is
  /// really honoured (the check never reaches the network).
  final bool autoUpdateCheckEnabled;

  /// The one release the user asked not to be reminded about, as
  /// [AppVersion.toString] renders it (`9.9.9`, no `v`), or `''` for none.
  ///
  /// An equality match, deliberately not an ordering. The two rules only
  /// disagree when the offered release is *older* than the skipped one --
  /// reachable when a skipped release is unpublished and
  /// `/releases/latest` rolls back to an earlier one that is still newer
  /// than the installed build. An ordering would silence that forever.
  /// Only the *automatic* check consults it -- a
  /// manual Check for updates… always reports what it found, or the user
  /// would have no way to reach a release they once skipped.
  ///
  /// Stored here rather than under a raw key so the Preferences dialog can
  /// show it and offer to clear it. A suppression the user cannot see or
  /// undo is exactly the hidden material state this app's own UX rubric
  /// flags.
  final String skippedVersion;

  AppPreferences copyWith({
    bool? autoFetchEnabled,
    int? autoFetchMinutes,
    bool? autoFetchPrune,
    bool? recordManualOpens,
    bool? autoScanEnabled,
    int? autoScanMinutes,
    bool? globalGitignoreEnabled,
    String? globalGitignorePath,
    String? globalGitignoreSource,
    bool? cherryPickAddsSourceLine,
    bool? confirmForcePush,
    int? logMemoryLimit,
    int? logRetentionDays,
    bool? autoUpdateCheckEnabled,
    String? skippedVersion,
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
      globalGitignoreSource:
          globalGitignoreSource ?? this.globalGitignoreSource,
      cherryPickAddsSourceLine:
          cherryPickAddsSourceLine ?? this.cherryPickAddsSourceLine,
      confirmForcePush: confirmForcePush ?? this.confirmForcePush,
      logMemoryLimit: logMemoryLimit ?? this.logMemoryLimit,
      logRetentionDays: logRetentionDays ?? this.logRetentionDays,
      autoUpdateCheckEnabled:
          autoUpdateCheckEnabled ?? this.autoUpdateCheckEnabled,
      skippedVersion: skippedVersion ?? this.skippedVersion,
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
          _prefs.getBool('${_kPrefix}autoFetchPrune') ??
          defaults.autoFetchPrune,
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
      globalGitignoreSource:
          _prefs.getString('${_kPrefix}globalGitignoreSource') ??
          defaults.globalGitignoreSource,
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
      autoUpdateCheckEnabled:
          _prefs.getBool('${_kPrefix}autoUpdateCheckEnabled') ??
          defaults.autoUpdateCheckEnabled,
      skippedVersion:
          _prefs.getString('${_kPrefix}skippedVersion') ??
          defaults.skippedVersion,
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
    await _prefs.setString(
      '${_kPrefix}globalGitignoreSource',
      p.globalGitignoreSource,
    );
    await _prefs.setBool(
      '${_kPrefix}cherryPickAddsSourceLine',
      p.cherryPickAddsSourceLine,
    );
    await _prefs.setBool('${_kPrefix}confirmForcePush', p.confirmForcePush);
    await _prefs.setInt('${_kPrefix}logMemoryLimit', p.logMemoryLimit);
    await _prefs.setInt('${_kPrefix}logRetentionDays', p.logRetentionDays);
    await _prefs.setBool(
      '${_kPrefix}autoUpdateCheckEnabled',
      p.autoUpdateCheckEnabled,
    );
    await _prefs.setString('${_kPrefix}skippedVersion', p.skippedVersion);
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
      return AppPreferencesNotifier(
        ref.watch(appPreferencesRepositoryProvider),
      );
    });
