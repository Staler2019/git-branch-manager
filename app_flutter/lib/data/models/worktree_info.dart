/// Mirrors `gbm::WorktreeInfo` (src/core/git/ops/WorktreeOps.h) as
/// serialized by `capi::toJson(const WorktreeInfo&)`.
class WorktreeInfo {
  const WorktreeInfo({
    required this.path,
    required this.headOid,
    required this.branch,
    required this.isMain,
    required this.isBare,
    required this.isDetached,
    required this.isLocked,
    required this.lockReason,
    required this.isPrunable,
    required this.prunableReason,
  });

  factory WorktreeInfo.fromJson(Map<String, dynamic> json) {
    return WorktreeInfo(
      path: json['path'] as String,
      headOid: json['headOid'] as String,
      branch: json['branch'] as String,
      isMain: json['isMain'] as bool,
      isBare: json['isBare'] as bool,
      isDetached: json['isDetached'] as bool,
      isLocked: json['isLocked'] as bool,
      lockReason: json['lockReason'] as String,
      isPrunable: json['isPrunable'] as bool,
      prunableReason: json['prunableReason'] as String,
    );
  }

  static List<WorktreeInfo> listFromJson(List<dynamic> json) =>
      json.map((e) => WorktreeInfo.fromJson(e as Map<String, dynamic>)).toList(growable: false);

  final String path;
  final String headOid;
  final String branch;
  final bool isMain;
  final bool isBare;
  final bool isDetached;
  final bool isLocked;
  final String lockReason;
  final bool isPrunable;
  final String prunableReason;
}
