/// Mirrors `gbm::OperationRunner::UndoEntry` (src/core/git/OperationRunner.h)
/// as serialized by `capi::toJson(const OperationRunner::UndoEntry&)`.
class UndoEntry {
  const UndoEntry({
    required this.id,
    required this.description,
    required this.headBefore,
    required this.branchBefore,
    required this.timestamp,
  });

  factory UndoEntry.fromJson(Map<String, dynamic> json) {
    return UndoEntry(
      id: json['id'] as int,
      description: json['description'] as String,
      headBefore: json['headBefore'] as String,
      branchBefore: json['branchBefore'] as String,
      timestamp: json['timestamp'] as int,
    );
  }

  static List<UndoEntry> listFromJson(List<dynamic> json) =>
      json.map((e) => UndoEntry.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  final int id;
  final String description;
  final String headBefore;
  /// Empty when HEAD was detached at the time this entry was recorded.
  final String branchBefore;
  final int timestamp;
}
