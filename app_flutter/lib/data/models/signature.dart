/// Mirrors `gbm::Signature` (src/core/git/CommitMeta.h) as serialized by
/// `capi::toJson(const Signature&)`. Shared by file-history/line-history/
/// reflog entries -- not just commit metadata.
class Signature {
  const Signature({
    required this.name,
    required this.email,
    required this.when,
    required this.tzOffsetMinutes,
  });

  factory Signature.fromJson(Map<String, dynamic> json) {
    return Signature(
      name: json['name'] as String,
      email: json['email'] as String,
      when: json['when'] as int,
      tzOffsetMinutes: json['tzOffsetMinutes'] as int,
    );
  }

  final String name;
  final String email;
  final int when;
  final int tzOffsetMinutes;
}
