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
