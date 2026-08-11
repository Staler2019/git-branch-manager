/// Mirrors `gbm::StashEntry` (src/core/git/ops/StashOps.h) as serialized by
/// `capi::toJson(const StashEntry&)`.
class StashEntry {
  const StashEntry({required this.index, required this.message, required this.oid, required this.timestamp});

  factory StashEntry.fromJson(Map<String, dynamic> json) {
    return StashEntry(
      index: json['index'] as int,
      message: json['message'] as String,
      oid: json['oid'] as String,
      timestamp: json['timestamp'] as int,
    );
  }

  static List<StashEntry> listFromJson(List<dynamic> json) =>
      json.map((e) => StashEntry.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  final int index;
  final String message;
  final String oid;
  final int timestamp;
}
