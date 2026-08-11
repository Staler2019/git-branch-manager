/// Mirrors `gbm::FileChangeKind` (src/core/git/UnifiedDiffParser.h).
enum FileChangeKind {
  modified(0),
  added(1),
  deleted(2),
  renamed(3),
  copied(4),
  typeChanged(5),
  modeChanged(6);

  const FileChangeKind(this.value);

  final int value;

  static FileChangeKind fromValue(int value) =>
      FileChangeKind.values.firstWhere((k) => k.value == value, orElse: () => FileChangeKind.modified);
}

/// Mirrors `gbm::ConflictKind` (src/core/git/WorkingCopyStatus.h).
enum ConflictKind {
  none(0),
  bothAdded(1),
  bothModified(2),
  bothDeleted(3),
  addedByUs(4),
  deletedByUs(5),
  addedByThem(6),
  deletedByThem(7);

  const ConflictKind(this.value);

  final int value;

  static ConflictKind fromValue(int value) =>
      ConflictKind.values.firstWhere((k) => k.value == value, orElse: () => ConflictKind.none);
}

/// Mirrors `gbm::WorkingCopyEntry` as serialized by
/// `capi::toJson(const WorkingCopyStatus&)`.
class WorkingCopyEntry {
  const WorkingCopyEntry({
    required this.path,
    required this.oldPath,
    required this.untracked,
    required this.staged,
    required this.indexStatus,
    required this.hasUnstagedChange,
    required this.worktreeStatus,
    required this.conflict,
    required this.ancestorBlob,
    required this.oursBlob,
    required this.theirsBlob,
    required this.similarity,
    required this.isSubmodule,
    required this.isConflicted,
  });

  factory WorkingCopyEntry.fromJson(Map<String, dynamic> json) {
    return WorkingCopyEntry(
      path: json['path'] as String,
      oldPath: json['oldPath'] as String,
      untracked: json['untracked'] as bool,
      staged: json['staged'] as bool,
      indexStatus: FileChangeKind.fromValue(json['indexStatus'] as int),
      hasUnstagedChange: json['hasUnstagedChange'] as bool,
      worktreeStatus: FileChangeKind.fromValue(json['worktreeStatus'] as int),
      conflict: ConflictKind.fromValue(json['conflict'] as int),
      ancestorBlob: json['ancestorBlob'] as String,
      oursBlob: json['oursBlob'] as String,
      theirsBlob: json['theirsBlob'] as String,
      similarity: json['similarity'] as int,
      isSubmodule: json['isSubmodule'] as bool,
      isConflicted: json['isConflicted'] as bool,
    );
  }

  final String path;
  final String oldPath;
  final bool untracked;
  final bool staged;
  final FileChangeKind indexStatus;
  final bool hasUnstagedChange;
  final FileChangeKind worktreeStatus;
  final ConflictKind conflict;
  final String ancestorBlob;
  final String oursBlob;
  final String theirsBlob;
  final int similarity;
  final bool isSubmodule;
  final bool isConflicted;
}

/// Mirrors `gbm::WorkingCopyStatus` as serialized by
/// `capi::toJson(const WorkingCopyStatus&)`.
class WorkingCopyStatus {
  const WorkingCopyStatus({required this.entries});

  factory WorkingCopyStatus.fromJson(Map<String, dynamic> json) {
    return WorkingCopyStatus(
      entries: (json['entries'] as List<dynamic>)
          .map((e) => WorkingCopyEntry.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  static const WorkingCopyStatus empty = WorkingCopyStatus(entries: <WorkingCopyEntry>[]);

  final List<WorkingCopyEntry> entries;

  bool get isClean => entries.isEmpty;
  List<WorkingCopyEntry> get staged => entries.where((e) => e.staged).toList(growable: false);
  List<WorkingCopyEntry> get unstaged => entries.where((e) => e.hasUnstagedChange).toList(growable: false);
  List<WorkingCopyEntry> get untrackedFiles => entries.where((e) => e.untracked).toList(growable: false);
  List<WorkingCopyEntry> get conflicted => entries.where((e) => e.isConflicted).toList(growable: false);
}
