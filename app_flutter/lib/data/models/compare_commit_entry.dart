/// Mirrors `gbm::CompareCommitEntry` (src/core/git/ops/CompareOps.h) as
/// serialized by `capi::toJson(const CompareCommitEntry&)`.
class CompareCommitEntry {
  const CompareCommitEntry({
    required this.oid,
    required this.onRightOnly,
    required this.authorName,
    required this.authorDate,
    required this.subject,
  });

  factory CompareCommitEntry.fromJson(Map<String, dynamic> json) {
    return CompareCommitEntry(
      oid: json['oid'] as String,
      onRightOnly: json['onRightOnly'] as bool,
      authorName: json['authorName'] as String,
      authorDate: json['authorDate'] as int,
      subject: json['subject'] as String,
    );
  }

  static List<CompareCommitEntry> listFromJson(List<dynamic> json) {
    return json
        .map((e) => CompareCommitEntry.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  final String oid;

  /// True when this commit is reachable from the right ref but not the
  /// left; false when it's the reverse (reachable from left, not right).
  final bool onRightOnly;
  final String authorName;
  final int authorDate;
  final String subject;
}
