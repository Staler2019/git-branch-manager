/// Mirrors `gbm::LocalIdentity` (src/core/git/ops/ConfigOps.h) as serialized
/// by `capi::toJson(const LocalIdentity&)`.
class LocalIdentity {
  const LocalIdentity({
    required this.name,
    required this.email,
    required this.overridden,
  });

  static const LocalIdentity empty = LocalIdentity(
    name: '',
    email: '',
    overridden: false,
  );

  factory LocalIdentity.fromJson(Map<String, dynamic> json) {
    return LocalIdentity(
      name: json['name'] as String,
      email: json['email'] as String,
      overridden: json['overridden'] as bool,
    );
  }

  final String name;
  final String email;
  final bool overridden;
}

/// Mirrors `gbm::EffectiveIdentity` as serialized by
/// `capi::toJson(const EffectiveIdentity&)`.
class EffectiveIdentity {
  const EffectiveIdentity({required this.name, required this.email});

  static const EffectiveIdentity empty = EffectiveIdentity(name: '', email: '');

  factory EffectiveIdentity.fromJson(Map<String, dynamic> json) {
    return EffectiveIdentity(
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  final String name;
  final String email;
}
