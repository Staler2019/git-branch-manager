/// Mirrors `gbm::CleanEntry` (src/core/git/ops/ResetOps.h) as serialized by
/// `capi::toJson(const CleanEntry&)`.
class CleanEntry {
  const CleanEntry({required this.path, required this.isDirectory});

  factory CleanEntry.fromJson(Map<String, dynamic> json) {
    return CleanEntry(path: json['path'] as String, isDirectory: json['isDirectory'] as bool);
  }

  static List<CleanEntry> listFromJson(List<dynamic> json) =>
      json.map((e) => CleanEntry.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  final String path;
  final bool isDirectory;
}
