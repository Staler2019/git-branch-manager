/// Mirrors `gbm::RepoState::Flags` (src/core/git/RepoState.h) -- a bitmask,
/// not a closed enum, since several sequencer states can theoretically
/// overlap on disk.
abstract final class RepoStateFlags {
  static const int merge = 1 << 0;
  static const int cherryPick = 1 << 1;
  static const int revert = 1 << 2;
  static const int rebaseMerge = 1 << 3;
  static const int rebaseApply = 1 << 4;
  static const int bisect = 1 << 5;
  static const int sequencer = 1 << 6;
}

/// Mirrors `gbm::RepoState` (src/core/git/RepoState.h) as serialized by
/// `capi::toJson(const RepoState&)`.
class RepoState {
  const RepoState({
    required this.flags,
    required this.isClean,
    required this.isSequencerOperation,
    required this.rebaseStep,
    required this.rebaseTotal,
    required this.rebaseOntoLabel,
    required this.indexLocked,
    required this.indexLockAgeSeconds,
    required this.describe,
    this.preparedMessagePending = false,
  });

  factory RepoState.fromJson(Map<String, dynamic> json) {
    return RepoState(
      flags: json['flags'] as int,
      isClean: json['isClean'] as bool,
      isSequencerOperation: json['isSequencerOperation'] as bool,
      rebaseStep: json['rebaseStep'] as int,
      rebaseTotal: json['rebaseTotal'] as int,
      rebaseOntoLabel: json['rebaseOntoLabel'] as String,
      indexLocked: json['indexLocked'] as bool,
      indexLockAgeSeconds: json['indexLockAgeSeconds'] as int?,
      describe: json['describe'] as String,
      preparedMessagePending: json['preparedMessagePending'] as bool,
    );
  }

  final int flags;
  final bool isClean;
  final bool isSequencerOperation;
  final int rebaseStep;
  final int rebaseTotal;
  final String rebaseOntoLabel;
  final bool indexLocked;
  final int? indexLockAgeSeconds;
  final String describe;

  /// Mirrors `gbm::RepoState::preparedMessagePending`: a merge (MERGE_HEAD)
  /// or a squash (SQUASH_MSG) has a message waiting for the Working Copy
  /// box. A cherry-pick/revert conflict's MERGE_MSG does not count.
  ///
  /// Required on the wire (capi always sends it, `JsonCodecTest`), defaulted
  /// only in the constructor so hand-built test states need not spell it.
  final bool preparedMessagePending;

  bool get isMerging => flags & RepoStateFlags.merge != 0;
  bool get isCherryPicking => flags & RepoStateFlags.cherryPick != 0;
  bool get isReverting => flags & RepoStateFlags.revert != 0;
  bool get isRebasing =>
      flags & (RepoStateFlags.rebaseMerge | RepoStateFlags.rebaseApply) != 0;
}
