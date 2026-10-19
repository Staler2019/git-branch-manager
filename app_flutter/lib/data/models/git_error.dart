import 'url_credential_redaction.dart';

/// Mirrors `gbm::GitError` (src/core/base/Error.h) as serialized by
/// `capi::toJson(const GitError&)` (src/capi/JsonCodec.cpp).
class GitError {
  const GitError({
    required this.code,
    required this.codeName,
    required this.message,
    required this.detail,
    required this.argv,
    required this.exitCode,
  });

  /// Masks credentials in URLs on the way in (ruling R6, security review
  /// P3-F); see [redactUrlCredentials].
  factory GitError.fromJson(Map<String, dynamic> json) {
    return GitError(
      code: json['code'] as int,
      codeName: json['codeName'] as String,
      message: redactUrlCredentials(json['message'] as String),
      detail: redactUrlCredentials(json['detail'] as String),
      argv: List<String>.unmodifiable(
        (json['argv'] as List<dynamic>).cast<String>().map(
          redactUrlCredentials,
        ),
      ),
      exitCode: json['exitCode'] as int,
    );
  }

  final int code;
  final String codeName;
  final String message;
  final String detail;
  final List<String> argv;
  final int exitCode;

  @override
  String toString() => '$codeName: $message';
}
