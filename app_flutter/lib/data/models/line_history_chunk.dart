import 'signature.dart';

/// Mirrors `gbm::LineHistoryChunk` (src/core/git/FileHistoryStore.h) as
/// serialized by `capi::toJson(const LineHistoryChunk&)`.
class LineHistoryChunk {
  const LineHistoryChunk({required this.oid, required this.author, required this.subject, required this.diffText});

  factory LineHistoryChunk.fromJson(Map<String, dynamic> json) {
    return LineHistoryChunk(
      oid: json['oid'] as String,
      author: Signature.fromJson(json['author'] as Map<String, dynamic>),
      subject: json['subject'] as String,
      diffText: json['diffText'] as String,
    );
  }

  static List<LineHistoryChunk> listFromJson(List<dynamic> json) =>
      json.map((e) => LineHistoryChunk.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  final String oid;
  final Signature author;
  final String subject;
  /// The diff/hunk text git prints for this commit's change to the range,
  /// as it comes from git -- headers, `@@` markers and all.
  final String diffText;
}
