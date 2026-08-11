import 'signature.dart';

/// Mirrors `gbm::ReflogEntry` (src/core/git/ReflogStore.h) as serialized by
/// `capi::toJson(const ReflogEntry&)`.
class ReflogEntry {
  const ReflogEntry({required this.index, required this.oid, required this.message, required this.who});

  factory ReflogEntry.fromJson(Map<String, dynamic> json) {
    return ReflogEntry(
      index: json['index'] as int,
      oid: json['oid'] as String,
      message: json['message'] as String,
      who: Signature.fromJson(json['who'] as Map<String, dynamic>),
    );
  }

  static List<ReflogEntry> listFromJson(List<dynamic> json) =>
      json.map((e) => ReflogEntry.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  /// N in `<ref>@{N}`; 0 is the most recent.
  final int index;
  final String oid;
  final String message;
  final Signature who;
}
