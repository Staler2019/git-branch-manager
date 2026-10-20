/// What one app action came to.
///
/// The structured fields ([actionName], [startedAt], [duration] and the
/// subtype) are what a future telemetry span is built from. [message] is
/// free text written for the Log: it has already been through
/// `redactUrlCredentials`, but an exporter must still apply its own
/// redaction rules to it before it leaves the machine (security review F5).
/// There is deliberately no field carrying a URL or an argv.
sealed class AppActionOutcome<T> {
  const AppActionOutcome({
    required this.actionName,
    required this.startedAt,
    required this.duration,
    required this.message,
  });

  final String actionName;
  final DateTime startedAt;
  final Duration duration;
  final String message;
}

final class AppActionSucceeded<T> extends AppActionOutcome<T> {
  const AppActionSucceeded({
    required this.value,
    required super.actionName,
    required super.startedAt,
    required super.duration,
    required super.message,
  });

  final T value;
}

final class AppActionFailed<T> extends AppActionOutcome<T> {
  const AppActionFailed({
    required super.actionName,
    required super.startedAt,
    required super.duration,
    required super.message,
  });
}

final class AppActionCancelled<T> extends AppActionOutcome<T> {
  const AppActionCancelled({
    required super.actionName,
    required super.startedAt,
    required super.duration,
    required super.message,
  });
}
