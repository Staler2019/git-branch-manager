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
/// `choices` array): a recoverable-failure option, e.g. "Stash changes and
/// checkout" offered after a checkout refuses on a dirty work tree.
class OperationChoice {
  const OperationChoice({
    required this.kind,
    required this.label,
    required this.explanation,
    required this.destructive,
  });

  factory OperationChoice.fromJson(Map<String, dynamic> json) {
    return OperationChoice(
      kind: OperationChoiceKind.values[json['kind'] as int],
      label: json['label'] as String,
      explanation: json['explanation'] as String,
      destructive: json['destructive'] as bool,
    );
  }

  static List<OperationChoice> listFromJson(List<dynamic> json) => json
      .map((e) => OperationChoice.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  final OperationChoiceKind kind;
  final String label;
  final String explanation;
  final bool destructive;
}
