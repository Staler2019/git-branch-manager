/// Mirrors `gbm::LfsInstallation` (src/core/git/ops/LfsOps.h) as serialized
/// by `capi::toJson(const LfsInstallation&)`.
class LfsInstallation {
  const LfsInstallation({required this.available, required this.version});

  static const LfsInstallation unknown = LfsInstallation(available: false, version: '');

  factory LfsInstallation.fromJson(Map<String, dynamic> json) {
    return LfsInstallation(available: json['available'] as bool, version: json['version'] as String);
  }

  final bool available;
  final String version;
}

/// Mirrors `gbm::LfsFileInfo` as serialized by
/// `capi::toJson(const LfsFileInfo&)`.
class LfsFileInfo {
  const LfsFileInfo({required this.path, required this.oid, required this.downloadedLocally});

  factory LfsFileInfo.fromJson(Map<String, dynamic> json) {
    return LfsFileInfo(
      path: json['path'] as String,
      oid: json['oid'] as String,
      downloadedLocally: json['downloadedLocally'] as bool,
    );
  }

  static List<LfsFileInfo> listFromJson(List<dynamic> json) =>
      json.map((e) => LfsFileInfo.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  final String path;
  final String oid;
  final bool downloadedLocally;
}
