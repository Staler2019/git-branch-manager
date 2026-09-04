/// Branch-name validation shared by the dialogs that take one.
///
/// Git's own ref-name rules, limited to the ones a user hits by accident:
/// leading/trailing slash or dot, `..`, whitespace, and the characters
/// `~^:?*[\` plus control codes. Checked here so the button explains itself
/// before the operation is attempted, not *instead of* git's own validation
/// -- `check_ref_format` (via `RefStore::isValidBranchName` in core) remains
/// the authority, and core re-checks before git runs.
///
/// Lives as a pure function rather than a private method on one dialog's
/// State because two dialogs now need exactly these rules (New branch,
/// Rename branch) and spec page 13's RENAMEVALID table asks for the same
/// live feedback in both.
library;

/// Characters git refuses in a ref name, plus control codes and space.
final RegExp _illegalRefChars = RegExp(r'[\x00-\x20~^:?*\[\\\x7f]');

/// A human-readable reason [name] cannot be used as a branch name, or null
/// when it is usable.
///
/// An empty (or whitespace-only) [name] returns null rather than an error:
/// the caller disables its confirm button in that case, and nagging about a
/// field the user has not finished typing is exactly what spec page 13's
/// "空白或未改動：Rename disabled，不出現錯誤紅字" rules out.
String? branchNameError(String name, {required List<String> existingNames}) {
  final String trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  // RENAMEVALID row 1，格式「已存在 feature/x」；此處以「」標出名稱，
  // 與 checkout_dialog.dart 的分支名稱引用方式一致。
  if (existingNames.contains(trimmed)) {
    return '已存在「$trimmed」';
  }
  // RENAMEVALID row 2：「含 git 不允許的字元」。
  if (_illegalRefChars.hasMatch(trimmed)) {
    return '分支名稱不能包含空白或 ~^:?*[\\ 這些字元';
  }
  if (trimmed.startsWith('/') ||
      trimmed.endsWith('/') ||
      trimmed.startsWith('.') ||
      trimmed.endsWith('.') ||
      trimmed.contains('..') ||
      trimmed.endsWith('.lock')) {
    return '不是合法的分支名稱';
  }
  return null;
}
