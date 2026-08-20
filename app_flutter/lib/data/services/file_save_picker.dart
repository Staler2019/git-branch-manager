import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The system's native "save as" and "choose a folder" dialogs.
///
/// Wrapped in a class behind [fileSavePickerProvider] rather than called
/// straight from a widget for the same reason [DesktopLauncher] is: a widget
/// test must be able to assert which destination an action *would* have
/// written to, without a real modal appearing and blocking the run.
///
/// Native rather than a path text field (which is what `patches_dialog.dart`
/// still uses) because spec page 01's platform-differences list names the
/// system file picker as one of the three things the app takes from the OS
/// instead of drawing itself, alongside the macOS `PlatformMenuBar` and the
/// window title bar.
class FileSavePicker {
  const FileSavePicker();

  /// Asks where to save a file, pre-filled with [suggestedName]. Returns the
  /// chosen absolute path, or null if the user cancelled.
  Future<String?> saveFile({required String suggestedName}) async {
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: suggestedName,
    );
    return location?.path;
  }

  /// Asks for a directory. Returns its absolute path, or null if the user
  /// cancelled.
  Future<String?> pickDirectory() => getDirectoryPath();
}

/// Overridden in tests with a fake that records the request and returns a
/// canned destination.
final Provider<FileSavePicker> fileSavePickerProvider =
    Provider<FileSavePicker>((ref) => const FileSavePicker());
