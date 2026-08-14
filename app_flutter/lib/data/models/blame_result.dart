/// Mirrors `gbm::BlameLine` (src/core/git/BlameStore.h) as serialized by
/// `capi::toJson(const BlameResult&)`.
class BlameLine {
  const BlameLine({
    required this.commitOid,
    required this.authorName,
    required this.authorEmail,
    required this.authorTime,
    required this.summary,
    required this.finalLine,
    required this.originalLine,
    required this.content,
    required this.boundary,
  });

  factory BlameLine.fromJson(Map<String, dynamic> json) {
    return BlameLine(
      commitOid: json['commitOid'] as String,
      authorName: json['authorName'] as String,
      authorEmail: json['authorEmail'] as String,
      authorTime: json['authorTime'] as int,
      summary: json['summary'] as String,
      finalLine: json['finalLine'] as int,
      originalLine: json['originalLine'] as int,
      content: json['content'] as String,
      boundary: json['boundary'] as bool,
    );
  }

  final String commitOid;
  final String authorName;
  final String authorEmail;
  final int authorTime;
  final String summary;
  final int finalLine;
  final int originalLine;
  final String content;
  final bool boundary;
}

/// Mirrors `gbm::BlameResult`.
class BlameResult {
  const BlameResult({required this.lines, required this.truncated});

  factory BlameResult.fromJson(Map<String, dynamic> json) {
    return BlameResult(
      lines: (json['lines'] as List<dynamic>)
          .map((e) => BlameLine.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      truncated: json['truncated'] as bool,
    );
  }

  final List<BlameLine> lines;
  final bool truncated;
}
