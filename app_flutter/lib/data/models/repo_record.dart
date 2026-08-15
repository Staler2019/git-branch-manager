/// Mirrors `gbm::RepoKind` (src/core/discovery/RepoClassifier.h).
enum RepoKind {
  normal(0),
  bare(1),
  linkedWorktree(2),
  submodule(3);

  const RepoKind(this.value);

  final int value;

  static RepoKind fromValue(int value) {
    return RepoKind.values.firstWhere(
      (kind) => kind.value == value,
      orElse: () => RepoKind.normal,
    );
  }
}

/// Mirrors `gbm::RepoRecord` (src/core/cache/RepoIndexDb.h) as serialized by
/// `capi::toJson(const RepoRecord&)`.
class RepoRecord {
  const RepoRecord({
    required this.id,
    required this.baseFolderId,
    required this.workDir,
    required this.gitDir,
    required this.commonDir,
    required this.kind,
    required this.name,
    required this.parentRepoId,
    required this.depth,
    required this.discoveredAt,
    required this.missingSince,
  });

  factory RepoRecord.fromJson(Map<String, dynamic> json) {
    return RepoRecord(
      id: json['id'] as int,
      baseFolderId: json['baseFolderId'] as int,
      workDir: json['workDir'] as String,
      gitDir: json['gitDir'] as String,
      commonDir: json['commonDir'] as String,
      kind: RepoKind.fromValue(json['kind'] as int),
      name: json['name'] as String,
      parentRepoId: json['parentRepoId'] as int?,
      depth: json['depth'] as int,
      discoveredAt: json['discoveredAt'] as int,
      missingSince: json['missingSince'] as int?,
    );
  }

  static List<RepoRecord> listFromJson(List<dynamic> json) => json
      .map((entry) => RepoRecord.fromJson(entry as Map<String, dynamic>))
      .toList(growable: false);

  final int id;
  final int baseFolderId;
  final String workDir;
  final String gitDir;
  final String commonDir;
  final RepoKind kind;
  final String name;
  final int? parentRepoId;
  final int depth;
  final int discoveredAt;
  final int? missingSince;

  bool get isMissing => missingSince != null;
}
