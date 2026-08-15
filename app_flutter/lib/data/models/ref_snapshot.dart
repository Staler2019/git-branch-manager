/// Mirrors `gbm::RefKind` (src/core/git/RefStore.h).
enum RefKind {
  localBranch(0),
  remoteBranch(1),
  tag(2),
  note(3),
  stash(4),
  other(5);

  const RefKind(this.value);

  final int value;

  static RefKind fromValue(int value) => RefKind.values.firstWhere(
    (k) => k.value == value,
    orElse: () => RefKind.other,
  );
}

/// Mirrors `gbm::RefInfo`.
class RefInfo {
  const RefInfo({
    required this.fullName,
    required this.shortName,
    required this.kind,
    required this.target,
    required this.upstream,
    required this.ahead,
    required this.behind,
    required this.hasTrackingInfo,
    required this.isGone,
    required this.isHead,
    required this.isSymbolic,
    required this.worktreePath,
  });

  factory RefInfo.fromJson(Map<String, dynamic> json) {
    return RefInfo(
      fullName: json['fullName'] as String,
      shortName: json['shortName'] as String,
      kind: RefKind.fromValue(json['kind'] as int),
      target: json['target'] as String,
      upstream: json['upstream'] as String,
      ahead: json['ahead'] as int,
      behind: json['behind'] as int,
      hasTrackingInfo: json['hasTrackingInfo'] as bool,
      isGone: json['isGone'] as bool,
      isHead: json['isHead'] as bool,
      isSymbolic: json['isSymbolic'] as bool,
      worktreePath: json['worktreePath'] as String,
    );
  }

  final String fullName;
  final String shortName;
  final RefKind kind;
  final String target;
  final String upstream;
  final int ahead;
  final int behind;
  final bool hasTrackingInfo;
  final bool isGone;
  final bool isHead;
  final bool isSymbolic;
  final String worktreePath;
}

/// Mirrors `gbm::HeadInfo::Kind`.
enum HeadKind {
  branch(0),
  detached(1),
  unborn(2);

  const HeadKind(this.value);

  final int value;

  static HeadKind fromValue(int value) => HeadKind.values.firstWhere(
    (k) => k.value == value,
    orElse: () => HeadKind.unborn,
  );
}

/// Mirrors `gbm::HeadInfo`.
class HeadInfo {
  const HeadInfo({
    required this.kind,
    required this.branchName,
    required this.fullRef,
    required this.target,
  });

  factory HeadInfo.fromJson(Map<String, dynamic> json) {
    return HeadInfo(
      kind: HeadKind.fromValue(json['kind'] as int),
      branchName: json['branchName'] as String,
      fullRef: json['fullRef'] as String,
      target: json['target'] as String,
    );
  }

  final HeadKind kind;
  final String branchName;
  final String fullRef;
  final String target;
}

/// Mirrors `gbm::RefSnapshot` as serialized by `capi::toJson(const
/// RefSnapshot&)`.
class RefSnapshot {
  const RefSnapshot({
    required this.head,
    required this.refs,
    required this.refCountGuardTripped,
    required this.totalRefCount,
  });

  factory RefSnapshot.fromJson(Map<String, dynamic> json) {
    return RefSnapshot(
      head: HeadInfo.fromJson(json['head'] as Map<String, dynamic>),
      refs: (json['refs'] as List<dynamic>)
          .map((e) => RefInfo.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      refCountGuardTripped: json['refCountGuardTripped'] as bool,
      totalRefCount: json['totalRefCount'] as int,
    );
  }

  static const RefSnapshot empty = RefSnapshot(
    head: HeadInfo(
      kind: HeadKind.unborn,
      branchName: '',
      fullRef: '',
      target: '',
    ),
    refs: <RefInfo>[],
    refCountGuardTripped: false,
    totalRefCount: 0,
  );

  final HeadInfo head;
  final List<RefInfo> refs;
  final bool refCountGuardTripped;
  final int totalRefCount;

  List<RefInfo> get localBranches =>
      refs.where((r) => r.kind == RefKind.localBranch).toList(growable: false);

  /// All remote branches (e.g., origin/main, origin/dev).
  List<RefInfo> get remoteBranches =>
      refs.where((r) => r.kind == RefKind.remoteBranch).toList(growable: false);

  /// All tags (e.g., v1.0.0, release-2024).
  List<RefInfo> get tags =>
      refs.where((r) => r.kind == RefKind.tag).toList(growable: false);
}
