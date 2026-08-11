import 'git_error.dart';
import 'operation_choice.dart';

/// Mirrors `gbm::OperationOutcome` (src/core/git/OperationRunner.h) as
/// serialized by `capi::toJson(const OperationOutcome&)`.
class OperationOutcome {
  const OperationOutcome({
    required this.succeeded,
    required this.error,
    required this.choices,
    required this.summary,
  });

  factory OperationOutcome.fromJson(Map<String, dynamic> json) {
    final Object? error = json['error'];
    return OperationOutcome(
      succeeded: json['succeeded'] as bool,
      error: error == null ? null : GitError.fromJson(error as Map<String, dynamic>),
      choices: OperationChoice.listFromJson(json['choices'] as List<dynamic>),
      summary: json['summary'] as String,
    );
  }

  final bool succeeded;
  final GitError? error;
  /// Populated when the failure is recoverable by choosing one of these
  /// (e.g. "Stash changes and checkout"). Empty otherwise.
  final List<OperationChoice> choices;
  final String summary;
}
