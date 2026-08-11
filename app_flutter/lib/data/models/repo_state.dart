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
}
