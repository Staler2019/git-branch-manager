import 'signature.dart';

/// Mirrors `gbm::FileHistoryEntry` (src/core/git/FileHistoryStore.h) as
/// serialized by `capi::toJson(const FileHistoryEntry&)`.
class FileHistoryEntry {
  const FileHistoryEntry({
    required this.oid,
    required this.author,
    required this.subject,
    required this.status,
    required this.renamedFrom,
    required this.path,
  });

  factory FileHistoryEntry.fromJson(Map<String, dynamic> json) {
    return FileHistoryEntry(
      oid: json['oid'] as String,
      author: Signature.fromJson(json['author'] as Map<String, dynamic>),
      subject: json['subject'] as String,
      status: json['status'] as String,
      renamedFrom: json['renamedFrom'] as String,
      path: json['path'] as String,
    );
  }

  static List<FileHistoryEntry> listFromJson(List<dynamic> json) => json
      .map((e) => FileHistoryEntry.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  final String oid;
  final Signature author;
  final String subject;

  /// Raw `--name-status` code: A, M, D, or R###/C### for a rename/copy.
  final String status;
  final String renamedFrom;

  /// The path this file had in this commit -- the old name for a commit older
  /// than a rename, since `git log --follow` keeps walking under it.
  final String path;
}
