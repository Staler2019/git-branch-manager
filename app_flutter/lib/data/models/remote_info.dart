/// Mirrors `gbm::RemoteInfo` (src/core/git/ops/RemoteOps.h) as serialized by
/// `capi::toJson(const RemoteInfo&)`.
class RemoteInfo {
  const RemoteInfo({
    required this.name,
    required this.fetchUrl,
    required this.pushUrl,
  });

  factory RemoteInfo.fromJson(Map<String, dynamic> json) {
    return RemoteInfo(
      name: json['name'] as String,
      fetchUrl: json['fetchUrl'] as String,
      pushUrl: json['pushUrl'] as String,
    );
  }

  static List<RemoteInfo> listFromJson(List<dynamic> json) => json
      .map((e) => RemoteInfo.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  final String name;
  final String fetchUrl;
  final String pushUrl;
}
