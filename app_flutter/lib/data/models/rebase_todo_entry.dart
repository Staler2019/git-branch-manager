/// Mirrors `gbm::RebaseTodoEntry::Action` (src/core/git/ops/RebaseOps.h) --
/// ordinal order matters, it round-trips through `action`/`gbm_rebase_
/// interactive_start`'s `actions` array as-is. `Reword` is deliberately not
/// offered -- see RebaseTodoEntry's doc comment in RebaseOps.h.
enum RebaseTodoAction { pick, edit, squash, fixup, drop }

/// Mirrors `gbm::RebaseTodoEntry` as serialized by
/// `capi::toJson(const RebaseTodoEntry&)`.
class RebaseTodoEntry {
  const RebaseTodoEntry({required this.action, required this.oid, required this.shortOid, required this.subject});

  factory RebaseTodoEntry.fromJson(Map<String, dynamic> json) {
    return RebaseTodoEntry(
      action: RebaseTodoAction.values[json['action'] as int],
      oid: json['oid'] as String,
      shortOid: json['shortOid'] as String,
      subject: json['subject'] as String,
    );
  }

  static List<RebaseTodoEntry> listFromJson(List<dynamic> json) =>
      json.map((e) => RebaseTodoEntry.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  RebaseTodoEntry copyWith({RebaseTodoAction? action}) =>
      RebaseTodoEntry(action: action ?? this.action, oid: oid, shortOid: shortOid, subject: subject);

  final RebaseTodoAction action;
  final String oid;
  final String shortOid;
  final String subject;
}
