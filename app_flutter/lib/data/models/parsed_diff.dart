import 'working_copy_status.dart';

/// Mirrors `gbm::DiffLineKind` (src/core/git/UnifiedDiffParser.h).
enum DiffLineKind {
  context(0),
  added(1),
  removed(2),
  noNewlineMarker(3);

  const DiffLineKind(this.value);

  final int value;

  static DiffLineKind fromValue(int value) => DiffLineKind.values.firstWhere(
    (k) => k.value == value,
    orElse: () => DiffLineKind.context,
  );
}

/// Mirrors `gbm::DiffLine`.
class DiffLine {
  const DiffLine({
    required this.kind,
    required this.oldLine,
    required this.newLine,
    required this.text,
  });

  factory DiffLine.fromJson(Map<String, dynamic> json) {
    return DiffLine(
      kind: DiffLineKind.fromValue(json['kind'] as int),
      oldLine: json['oldLine'] as int,
      newLine: json['newLine'] as int,
      text: json['text'] as String,
    );
  }

  final DiffLineKind kind;
  final int oldLine;
  final int newLine;
  final String text;
}

/// Mirrors `gbm::DiffHunk`.
class DiffHunk {
  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.heading,
    required this.lines,
  });

  factory DiffHunk.fromJson(Map<String, dynamic> json) {
    return DiffHunk(
      oldStart: json['oldStart'] as int,
      oldCount: json['oldCount'] as int,
      newStart: json['newStart'] as int,
      newCount: json['newCount'] as int,
      heading: json['heading'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((e) => DiffLine.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String heading;
  final List<DiffLine> lines;
}

/// Mirrors `gbm::DiffFile`.
class DiffFile {
  const DiffFile({
    required this.oldPath,
    required this.newPath,
    required this.kind,
    required this.oldMode,
    required this.newMode,
    required this.oldBlob,
    required this.newBlob,
    required this.binary,
    required this.similarity,
    required this.addedLines,
    required this.removedLines,
    required this.displayPath,
    required this.hunks,
  });

  factory DiffFile.fromJson(Map<String, dynamic> json) {
    return DiffFile(
      oldPath: json['oldPath'] as String,
      newPath: json['newPath'] as String,
      kind: FileChangeKind.fromValue(json['kind'] as int),
      oldMode: json['oldMode'] as String,
      newMode: json['newMode'] as String,
      oldBlob: json['oldBlob'] as String,
      newBlob: json['newBlob'] as String,
      binary: json['binary'] as bool,
      similarity: json['similarity'] as int,
      addedLines: json['addedLines'] as int,
      removedLines: json['removedLines'] as int,
      displayPath: json['displayPath'] as String,
      hunks: (json['hunks'] as List<dynamic>)
          .map((e) => DiffHunk.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final String oldPath;
  final String newPath;
  final FileChangeKind kind;
  final String oldMode;
  final String newMode;
  final String oldBlob;
  final String newBlob;
  final bool binary;
  final int similarity;
  final int addedLines;
  final int removedLines;
  final String displayPath;
  final List<DiffHunk> hunks;
}

/// Mirrors `gbm::ParsedDiff` as serialized by `capi::toJson(const
/// ParsedDiff&)`.
class ParsedDiff {
  const ParsedDiff({
    required this.files,
    required this.truncated,
    required this.inputBytes,
  });

  factory ParsedDiff.fromJson(Map<String, dynamic> json) {
    return ParsedDiff(
      files: (json['files'] as List<dynamic>)
          .map((e) => DiffFile.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      truncated: json['truncated'] as bool,
      inputBytes: json['inputBytes'] as int,
    );
  }

  static const ParsedDiff empty = ParsedDiff(
    files: <DiffFile>[],
    truncated: false,
    inputBytes: 0,
  );

  final List<DiffFile> files;
  final bool truncated;
  final int inputBytes;
}
