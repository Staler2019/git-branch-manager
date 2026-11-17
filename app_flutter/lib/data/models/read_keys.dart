/// The request keys of the reads a surface waits on, as sent and as echoed
/// back on their READY event (read-failure-states-spec.html). The controller
/// builds one when it sends and the event parser builds one from the reply,
/// both through the same type, so equality means 「this reply answers that
/// request」. Each field is kept exactly as it was sent -- no normalising.
library;

/// `gbm_request_blame`'s arguments; `revision` empty is the working tree,
/// `startLine`/`endLine` 0 the whole file.
class BlameKey {
  const BlameKey({
    required this.path,
    this.revision = '',
    this.startLine = 0,
    this.endLine = 0,
  });

  factory BlameKey.fromJson(Map<String, dynamic> json) => BlameKey(
    path: json['path'] as String,
    revision: json['revision'] as String,
    startLine: json['startLine'] as int,
    endLine: json['endLine'] as int,
  );

  final String path;
  final String revision;
  final int startLine;
  final int endLine;

  @override
  bool operator ==(Object other) =>
      other is BlameKey &&
      other.path == path &&
      other.revision == revision &&
      other.startLine == startLine &&
      other.endLine == endLine;

  @override
  int get hashCode => Object.hash(path, revision, startLine, endLine);

  @override
  String toString() => 'BlameKey($path, $revision, $startLine, $endLine)';
}

/// `gbm_request_file_history`'s arguments; `startRevision` empty is HEAD.
class FileHistoryKey {
  const FileHistoryKey({required this.path, this.startRevision = ''});

  factory FileHistoryKey.fromJson(Map<String, dynamic> json) => FileHistoryKey(
    path: json['path'] as String,
    startRevision: json['startRevision'] as String,
  );

  final String path;
  final String startRevision;

  @override
  bool operator ==(Object other) =>
      other is FileHistoryKey &&
      other.path == path &&
      other.startRevision == startRevision;

  @override
  int get hashCode => Object.hash(path, startRevision);

  @override
  String toString() => 'FileHistoryKey($path, $startRevision)';
}

/// `gbm_request_line_history`'s arguments: the range as sent, `startRevision`
/// empty is HEAD.
class LineHistoryKey {
  const LineHistoryKey({
    required this.path,
    required this.startLine,
    required this.endLine,
    this.startRevision = '',
  });

  factory LineHistoryKey.fromJson(Map<String, dynamic> json) => LineHistoryKey(
    path: json['path'] as String,
    startLine: json['startLine'] as int,
    endLine: json['endLine'] as int,
    startRevision: json['startRevision'] as String,
  );

  final String path;
  final int startLine;
  final int endLine;
  final String startRevision;

  @override
  bool operator ==(Object other) =>
      other is LineHistoryKey &&
      other.path == path &&
      other.startLine == startLine &&
      other.endLine == endLine &&
      other.startRevision == startRevision;

  @override
  int get hashCode => Object.hash(path, startLine, endLine, startRevision);

  @override
  String toString() =>
      'LineHistoryKey($path, $startLine, $endLine, $startRevision)';
}
