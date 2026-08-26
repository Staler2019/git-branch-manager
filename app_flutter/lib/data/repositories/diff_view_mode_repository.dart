import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart';

/// How History's commit detail lays out one file's diff.
///
/// **Not the same switch as the Working Copy's `2 file` / `unified`**
/// ([WorkingCopyDiffMode], `working_copy_diff_pane.dart`), and deliberately
/// not sharing its stored value: that one's two columns are *unstaged* and
/// *staged*, this one's are *old* and *new*. They look alike and mean
/// different things, so one preference flipping both would be a surprise in
/// whichever view the user was not looking at.
enum DiffViewMode {
  /// One column, git's own unified diff. The default -- see [_kDefault].
  unified,

  /// Two columns, 變更前 left and 變更後 right, paired by
  /// `pairHunkForSideBySide` (`features/diff/side_by_side_diff.dart`).
  sideBySide,
}

const String _kDiffViewModeKey = 'diffViewMode';

/// Unified, and the reason is measured rather than a taste call. At the app's
/// own default 1280x720 the centre column is about 834px (1280 minus the
/// 250px sidebar, the 186px Changed files column and the two dividers), and
/// the commit detail spans it. Halved, each side loses a 36px line-number
/// gutter and its padding, leaving roughly 360px of monospace -- about 48-52
/// characters. That is narrow enough that side-by-side should be something a
/// user opts into, and persisting the choice means they opt in exactly once.
const DiffViewMode _kDefault = DiffViewMode.unified;

/// Persists [DiffViewMode] app-wide, keyed on [_kDiffViewModeKey].
///
/// Shaped after [FileListViewModeRepository]
/// (`file_list_view_mode_repository.dart`) rather than inventing a second
/// idiom for the same job: read on construction, write through on change.
class DiffViewModeRepository {
  DiffViewModeRepository(this._prefs);

  final SharedPreferences _prefs;

  /// Reads the persisted mode, falling back to [_kDefault] both when nothing
  /// has been stored and when the stored string is not one this version
  /// knows -- a value written by a future build must not leave the diff pane
  /// unable to pick a layout.
  DiffViewMode read() {
    return switch (_prefs.getString(_kDiffViewModeKey)) {
      'sideBySide' => DiffViewMode.sideBySide,
      'unified' => DiffViewMode.unified,
      _ => _kDefault,
    };
  }

  Future<void> write(DiffViewMode mode) {
    final String value = switch (mode) {
      DiffViewMode.unified => 'unified',
      DiffViewMode.sideBySide => 'sideBySide',
    };
    return _prefs.setString(_kDiffViewModeKey, value);
  }
}

final Provider<DiffViewModeRepository> diffViewModeRepositoryProvider =
    Provider<DiffViewModeRepository>((ref) {
      return DiffViewModeRepository(ref.watch(sharedPreferencesProvider));
    });

class DiffViewModeNotifier extends StateNotifier<DiffViewMode> {
  DiffViewModeNotifier(this._repo) : super(_repo.read());

  final DiffViewModeRepository _repo;

  /// Updates the mode and persists it. A no-op re-set still writes, which is
  /// harmless here -- unlike [GbmSegmentedControl], which swallows a tap on
  /// the key already selected, so this is not reached on one anyway.
  Future<void> setMode(DiffViewMode mode) async {
    state = mode;
    await _repo.write(mode);
  }
}

final StateNotifierProvider<DiffViewModeNotifier, DiffViewMode>
diffViewModeProvider =
    StateNotifierProvider<DiffViewModeNotifier, DiffViewMode>((ref) {
      return DiffViewModeNotifier(ref.watch(diffViewModeRepositoryProvider));
    });
