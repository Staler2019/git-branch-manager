import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart';

const String _kStatusBarVisibleKey = 'chrome.statusBarVisible';
const String _kCommitDetailVisibleKey = 'chrome.commitDetailVisible';

/// Persists the two View-menu chrome toggles that are neither a panel size
/// nor a per-repository setting: View → Status bar and View → Commit detail
/// (spec page 04's `MENUS` table; page 02 items 8 and 11).
///
/// Application-level and persisted, matching how spec page 02 item 16
/// describes the sibling Graph-columns setting ("設定存在應用層級，所有 repo
/// 共用") -- hiding the status bar in one repository and finding it back on
/// the next launch would read as the setting not having taken.
///
/// Both default to visible: the spec's own page-02 annotated screenshot
/// shows the status bar and commit detail present, so a first run must match
/// it.
class ChromeVisibilityRepository {
  ChromeVisibilityRepository(this._prefs);

  final SharedPreferences _prefs;

  bool readStatusBarVisible() => _prefs.getBool(_kStatusBarVisibleKey) ?? true;

  bool readCommitDetailVisible() =>
      _prefs.getBool(_kCommitDetailVisibleKey) ?? true;

  Future<void> writeStatusBarVisible(bool visible) =>
      _prefs.setBool(_kStatusBarVisibleKey, visible);

  Future<void> writeCommitDetailVisible(bool visible) =>
      _prefs.setBool(_kCommitDetailVisibleKey, visible);
}

final Provider<ChromeVisibilityRepository> chromeVisibilityRepositoryProvider =
    Provider<ChromeVisibilityRepository>((ref) {
      return ChromeVisibilityRepository(ref.watch(sharedPreferencesProvider));
    });

/// Immutable snapshot of the chrome toggles, so a single `watch` covers both
/// rather than one provider per bool.
class ChromeVisibility {
  const ChromeVisibility({
    required this.statusBarVisible,
    required this.commitDetailVisible,
  });

  final bool statusBarVisible;
  final bool commitDetailVisible;

  ChromeVisibility copyWith({bool? statusBarVisible, bool? commitDetailVisible}) {
    return ChromeVisibility(
      statusBarVisible: statusBarVisible ?? this.statusBarVisible,
      commitDetailVisible: commitDetailVisible ?? this.commitDetailVisible,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChromeVisibility &&
          runtimeType == other.runtimeType &&
          statusBarVisible == other.statusBarVisible &&
          commitDetailVisible == other.commitDetailVisible;

  @override
  int get hashCode => Object.hash(statusBarVisible, commitDetailVisible);
}

class ChromeVisibilityNotifier extends StateNotifier<ChromeVisibility> {
  ChromeVisibilityNotifier(this._repo)
    : super(
        ChromeVisibility(
          statusBarVisible: _repo.readStatusBarVisible(),
          commitDetailVisible: _repo.readCommitDetailVisible(),
        ),
      );

  final ChromeVisibilityRepository _repo;

  Future<void> toggleStatusBar() async {
    final bool next = !state.statusBarVisible;
    state = state.copyWith(statusBarVisible: next);
    await _repo.writeStatusBarVisible(next);
  }

  Future<void> toggleCommitDetail() async {
    final bool next = !state.commitDetailVisible;
    state = state.copyWith(commitDetailVisible: next);
    await _repo.writeCommitDetailVisible(next);
  }
}

final StateNotifierProvider<ChromeVisibilityNotifier, ChromeVisibility>
chromeVisibilityProvider =
    StateNotifierProvider<ChromeVisibilityNotifier, ChromeVisibility>((ref) {
      return ChromeVisibilityNotifier(
        ref.watch(chromeVisibilityRepositoryProvider),
      );
    });
