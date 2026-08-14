import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart';

/// Enum for file list display mode: flat list or tree structure.
enum FileListViewMode {
  /// Display files as a flat list (default).
  list,

  /// Display files as a hierarchical tree.
  tree,
}

const String _kFileListViewModeKey = 'fileListViewMode';

/// Persists the global file list view mode (List vs Tree) to SharedPreferences.
///
/// This setting is shared across all views that display file lists:
/// - Working Copy (staged/unstaged columns)
/// - History (changed files)
/// - Compare view (changed files)
/// - Conflict resolution window
class FileListViewModeRepository {
  FileListViewModeRepository(this._prefs);

  final SharedPreferences _prefs;

  /// Reads the persisted view mode, or [FileListViewMode.list] if nothing
  /// has been saved yet or the stored value is unrecognized.
  FileListViewMode read() {
    final String? stored = _prefs.getString(_kFileListViewModeKey);
    return switch (stored) {
      'tree' => FileListViewMode.tree,
      'list' => FileListViewMode.list,
      _ => FileListViewMode.list,
    };
  }

  /// Writes the view mode to SharedPreferences.
  Future<void> write(FileListViewMode mode) {
    final String value = switch (mode) {
      FileListViewMode.list => 'list',
      FileListViewMode.tree => 'tree',
    };
    return _prefs.setString(_kFileListViewModeKey, value);
  }
}

/// Riverpod provider for the file list view mode repository.
final Provider<FileListViewModeRepository> fileListViewModeRepositoryProvider =
    Provider<FileListViewModeRepository>((ref) {
      return FileListViewModeRepository(ref.watch(sharedPreferencesProvider));
    });

/// State notifier for file list view mode.
class FileListViewModeNotifier extends StateNotifier<FileListViewMode> {
  FileListViewModeNotifier(this._repo) : super(_repo.read());

  final FileListViewModeRepository _repo;

  /// Updates the view mode and persists it to SharedPreferences.
  Future<void> setMode(FileListViewMode mode) async {
    state = mode;
    await _repo.write(mode);
  }
}

/// Riverpod provider for the current file list view mode with state management.
///
/// Use [setMode] to update the mode and persist it to SharedPreferences.
final StateNotifierProvider<FileListViewModeNotifier, FileListViewMode>
fileListViewModeProvider =
    StateNotifierProvider<FileListViewModeNotifier, FileListViewMode>((ref) {
      final repo = ref.watch(fileListViewModeRepositoryProvider);
      return FileListViewModeNotifier(repo);
    });
