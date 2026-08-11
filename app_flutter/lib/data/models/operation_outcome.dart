import 'git_error.dart';

/// Mirrors `gbm::OperationOutcome` (src/core/git/OperationRunner.h) as
/// serialized by `capi::toJson(const OperationOutcome&)`.
class OperationOutcome {
  const OperationOutcome({required this.succeeded, required this.error, required this.summary});

  factory OperationOutcome.fromJson(Map<String, dynamic> json) {
    final Object? error = json['error'];
    return OperationOutcome(
      succeeded: json['succeeded'] as bool,
      error: error == null ? null : GitError.fromJson(error as Map<String, dynamic>),
      summary: json['summary'] as String,
    );
  }

  final bool succeeded;
  final GitError? error;
  final String summary;
}
