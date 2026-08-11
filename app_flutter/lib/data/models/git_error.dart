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

  factory GitError.fromJson(Map<String, dynamic> json) {
    return GitError(
      code: json['code'] as int,
      codeName: json['codeName'] as String,
      message: json['message'] as String,
      detail: json['detail'] as String,
      argv: (json['argv'] as List<dynamic>).cast<String>(),
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
