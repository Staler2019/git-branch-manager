import 'working_copy_status.dart';

/// Mirrors `gbm::ChangedFile` as serialized by `capi::toJson(const
/// ChangedFile&)`.
class ChangedFile {
  const ChangedFile({
    required this.path,
    required this.oldPath,
    required this.kind,
    required this.oldMode,
    required this.newMode,
    required this.oldBlob,
    required this.newBlob,
    required this.similarity,
    required this.addedLines,
    required this.removedLines,
  });

  factory ChangedFile.fromJson(Map<String, dynamic> json) {
    return ChangedFile(
      path: json['path'] as String,
      oldPath: json['oldPath'] as String,
      kind: FileChangeKind.fromValue(json['kind'] as int),
      oldMode: json['oldMode'] as String,
      newMode: json['newMode'] as String,
      oldBlob: json['oldBlob'] as String,
      newBlob: json['newBlob'] as String,
      similarity: json['similarity'] as int,
      addedLines: json['addedLines'] as int,
      removedLines: json['removedLines'] as int,
    );
  }

  static List<ChangedFile> listFromJson(List<dynamic> json) {
    return json
        .map((e) => ChangedFile.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  final String path;
  final String oldPath;
  final FileChangeKind kind;
  final String oldMode;
  final String newMode;
  final String oldBlob;
  final String newBlob;
  final int similarity;

  /// Spec page 02 item 10's "+12" badge, from `git diff-tree --numstat`
  /// joined onto the raw file list in `DiffService::changedFiles()`. Both
  /// read 0 for a binary blob -- numstat reports "-" rather than a number
  /// there -- and the Changed files panel draws no badge for a 0, which is
  /// the honest rendering for something that has no lines.
  final int addedLines;
  final int removedLines;
}
