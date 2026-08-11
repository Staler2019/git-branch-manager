/// Mirrors `gbm::BaseFolderRecord` (src/core/cache/RepoIndexDb.h) as
/// serialized by `capi::toJson(const BaseFolderRecord&)`.
class BaseFolderRecord {
  const BaseFolderRecord({
    required this.id,
    required this.path,
    required this.enabled,
    required this.maxDepth,
    required this.followLinks,
    required this.lastScanStarted,
    required this.lastScanFinished,
    required this.lastScanDirs,
    required this.lastScanMs,
  });

  factory BaseFolderRecord.fromJson(Map<String, dynamic> json) {
    return BaseFolderRecord(
      id: json['id'] as int,
      path: json['path'] as String,
      enabled: json['enabled'] as bool,
      maxDepth: json['maxDepth'] as int,
      followLinks: json['followLinks'] as bool,
      lastScanStarted: json['lastScanStarted'] as int,
      lastScanFinished: json['lastScanFinished'] as int,
      lastScanDirs: json['lastScanDirs'] as int,
      lastScanMs: json['lastScanMs'] as int,
    );
  }

  static List<BaseFolderRecord> listFromJson(List<dynamic> json) =>
      json.map((e) => BaseFolderRecord.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  final int id;
  final String path;
  final bool enabled;
  final int maxDepth;
  final bool followLinks;
  final int lastScanStarted;
  final int lastScanFinished;
  final int lastScanDirs;
  final int lastScanMs;
}
