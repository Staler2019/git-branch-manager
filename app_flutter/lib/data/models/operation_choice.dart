/// Mirrors `gbm::OperationChoice::Kind` (src/core/git/OperationRunner.h) --
/// ordinal order matters, it comes straight off the wire as `kind`.
enum OperationChoiceKind {
  stashAndRetry,
  forceDiscard,
  abort,
  retry,
  removeLock,
}

/// Mirrors `gbm::OperationChoice` as serialized by
/// `capi::toJson(const OperationChoice&)` (part of `OperationOutcome`'s
/// `choices` array): a recoverable-failure option, e.g. offered after a
/// checkout refuses on a dirty work tree. The wire carries only `kind` and
/// `destructive` -- no label/explanation strings. Every reader composes its
/// own copy (English button labels, Chinese explanations) from `kind` via
/// `features/dialogs/recovery_choice_copy.dart`'s
/// `recoveryChoiceLabel()`/`recoveryChoiceExplanation()`, never off the wire;
/// see that file's header comment for why.
class OperationChoice {
  const OperationChoice({required this.kind, required this.destructive});

  factory OperationChoice.fromJson(Map<String, dynamic> json) {
    return OperationChoice(
      kind: OperationChoiceKind.values[json['kind'] as int],
      destructive: json['destructive'] as bool,
    );
  }

  static List<OperationChoice> listFromJson(List<dynamic> json) => json
      .map((e) => OperationChoice.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  final OperationChoiceKind kind;
  final bool destructive;
}
