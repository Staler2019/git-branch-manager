import 'dart:io';

/// What a dialog's target folder already holds, for the dialogs that create
/// something there (New repository, Add worktree).
enum TargetDirectoryState { missing, empty, nonEmpty, gitRepository }

/// Reads [path] synchronously; the dialogs call it on every keystroke, and
/// a `stat` plus one directory listing is cheap enough for that.
///
/// `.git` is checked before emptiness, as a directory or a file — a linked
/// worktree's `.git` is a file — because a repository is also non-empty and
/// the two call for different answers.
TargetDirectoryState probeTargetDirectory(String path) {
  if (path.isEmpty) return TargetDirectoryState.missing;
  final Directory dir = Directory(path);
  if (!dir.existsSync()) return TargetDirectoryState.missing;
  final String gitPath = '$path${Platform.pathSeparator}.git';
  if (FileSystemEntity.typeSync(gitPath) != FileSystemEntityType.notFound) {
    return TargetDirectoryState.gitRepository;
  }
  return dir.listSync().isEmpty
      ? TargetDirectoryState.empty
      : TargetDirectoryState.nonEmpty;
}
