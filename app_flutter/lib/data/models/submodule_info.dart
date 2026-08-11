/// Mirrors `gbm::SubmoduleInfo::State` (src/core/git/ops/SubmoduleOps.h) --
/// ordinal order matters, it comes straight off the wire as `state`.
enum SubmoduleState { notInitialized, upToDate, modified, conflicted }

/// Mirrors `gbm::SubmoduleInfo` as serialized by
/// `capi::toJson(const SubmoduleInfo&)`.
class SubmoduleInfo {
  const SubmoduleInfo({
    required this.name,
    required this.path,
    required this.url,
    required this.branch,
    required this.headOid,
    required this.state,
  });

  factory SubmoduleInfo.fromJson(Map<String, dynamic> json) {
    return SubmoduleInfo(
      name: json['name'] as String,
      path: json['path'] as String,
      url: json['url'] as String,
      branch: json['branch'] as String,
      headOid: json['headOid'] as String,
      state: SubmoduleState.values[json['state'] as int],
    );
  }

  static List<SubmoduleInfo> listFromJson(List<dynamic> json) =>
      json.map((e) => SubmoduleInfo.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  final String name;
  final String path;
  final String url;
  final String branch;
  final String headOid;
  final SubmoduleState state;
}
