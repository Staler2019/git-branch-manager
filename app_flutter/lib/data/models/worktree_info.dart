/// Whether a worktree's pending-change count holds an answer, and if not,
/// why not. Mirrors `gbm::WorktreePendingCountState`
/// (src/core/git/ops/WorktreeOps.h); the wire spellings are
/// `JsonCodec.cpp`'s `pendingCountStateName()`.
///
/// This is an enum rather than a sentinel value in the count itself, and the
/// distinction is load-bearing in two places. [WorktreeInfo.pendingChanges]
/// can then report a measured `0` as a real zero -- the worktree is clean --
/// where `[GIT-zero-means-unmeasured]` has to spend `0` on both meanings
/// because its line counts have no spare slot. And [failed] stays
/// distinguishable from [unmeasured], which is what lets the panel cache a
/// failure instead of re-asking for it on every republish.
enum WorktreePendingCountState {
  /// No count has been requested for this worktree yet -- what a plain
  /// `gbm_worktree_refresh()` produces. The per-worktree status pass is a
  /// separate, panel-driven request.
  unmeasured,

  /// [WorktreeInfo.pendingChanges] is a real count, `0` included.
  measured,

  /// The command could not be run at all: a bare worktree has no work tree,
  /// and a prunable one's directory is gone.
  notApplicable,

  /// The command ran and failed. An answer like any other, so a caller that
  /// caches on "do I have an answer" terminates instead of spinning.
  failed,
}

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
    required this.isPrimary,
    required this.pendingChanges,
    required this.pendingCountState,
    required this.createdAt,
  }) : assert(
         (pendingChanges != null) ==
             (pendingCountState == WorktreePendingCountState.measured),
         'pendingChanges is non-null exactly when the count was measured',
       );

  factory WorktreeInfo.fromJson(Map<String, dynamic> json) {
    // Both sentinels are resolved here, at the boundary, so nothing above
    // this line ever sees a `0` that might mean two things. The wire always
    // carries a number for `pendingChanges`; whether it means anything is
    // `pendingCountState`'s job to say.
    final WorktreePendingCountState state = _stateFromWire(
      json['pendingCountState'] as String,
    );
    final int createdAtUnix = json['createdAtUnix'] as int;

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
      isPrimary: json['isPrimary'] as bool,
      pendingChanges: state == WorktreePendingCountState.measured
          ? json['pendingChanges'] as int
          : null,
      pendingCountState: state,
      // `<= 0` rather than `== 0`: the core rejects a non-positive reflog
      // timestamp before it ever sets this, so a negative here could only be
      // corruption, and rendering it as 1969 would be worse than absent.
      createdAt: createdAtUnix <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAtUnix * 1000),
    );
  }

  static WorktreePendingCountState _stateFromWire(String wire) =>
      switch (wire) {
        'measured' => WorktreePendingCountState.measured,
        'notApplicable' => WorktreePendingCountState.notApplicable,
        'failed' => WorktreePendingCountState.failed,
        // Including the literal 'unmeasured'. An unrecognised spelling can
        // only come from a core newer than this binary, and "not measured"
        // is the one reading that makes no false claim about the work tree.
        _ => WorktreePendingCountState.unmeasured,
      };

  static List<WorktreeInfo> listFromJson(List<dynamic> json) => json
      .map((e) => WorktreeInfo.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

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

  /// The repository's **main** worktree -- the one `git worktree remove`
  /// refuses to remove.
  ///
  /// Not the same worktree as [isMain], and the naming is the trap: [isMain]
  /// means "the one this session is open on" (the mockup's `current` badge),
  /// because the core resolves it against the session's own work dir. On an
  /// ordinary clone they coincide on the first entry, which is why gating
  /// removal on the wrong one went unnoticed; open gbm on a linked worktree
  /// and the gate blocks the removable row and offers the unremovable one.
  final bool isPrimary;

  /// Uncommitted changes in this worktree, or null when
  /// [pendingCountState] is anything but [WorktreePendingCountState.measured].
  /// `0` therefore means "measured, and clean" and nothing else.
  final int? pendingChanges;

  /// Why [pendingChanges] is or is not an answer. A surface that renders the
  /// count must switch on this, not on `pendingChanges == null` -- the three
  /// non-measured states read differently to a user.
  final WorktreePendingCountState pendingCountState;

  /// When `git worktree add` created this worktree, from its own
  /// `logs/HEAD`, or null when git did not record it. See
  /// `attachCreatedAt()` in WorktreeOps.h for the four situations that
  /// produce a null -- one of which (an expired reflog) would otherwise
  /// produce a plausible wrong answer.
  final DateTime? createdAt;
}
