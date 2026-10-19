import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_action.dart';
import '../models/app_action_cancel_token.dart';
import '../models/app_action_outcome.dart';
import '../models/operation_record.dart';
import '../models/url_credential_redaction.dart';

/// Where an action's Log line goes. The caller takes it before the first
/// await -- `ref.read(repoSessionProvider(identity).notifier).recordAppLog`
/// -- so the line is written even if the widget that started the action is
/// gone by the time it finishes. `null` where there is no Log to write to.
typedef AppLogSink = void Function(AppLogEntry entry);

final class AppActionRunner {
  const AppActionRunner({this.clock = DateTime.now});

  /// Injected so a test can pin [AppActionOutcome.startedAt] and duration.
  final DateTime Function() clock;

  Future<AppActionOutcome<T>> run<T>(
    AppAction<T> action, {
    required AppLogSink? sink,
    AppActionCancelToken? token,
  }) async {
    final AppActionCancelToken caller = token ?? AppActionCancelToken.none;
    final DateTime startedAt = clock();

    // Every message is masked before it reaches the outcome or the Log: a
    // factory's describe* may quote a URL the user typed (ruling R6).
    AppActionOutcome<T> finish(
      OperationLogLevel level,
      String message,
      AppActionOutcome<T> Function(Duration duration) build,
    ) {
      final DateTime endedAt = clock();
      final AppActionOutcome<T> outcome = build(endedAt.difference(startedAt));
      sink?.call(
        AppLogEntry(
          whenEpochMs: endedAt.millisecondsSinceEpoch,
          level: level,
          message: message,
        ),
      );
      return outcome;
    }

    AppActionOutcome<T> cancelled() {
      final String message = redactUrlCredentials(action.describeCancelled());
      return finish(
        OperationLogLevel.warning,
        message,
        (Duration d) => AppActionCancelled<T>(
          actionName: action.name,
          startedAt: startedAt,
          duration: d,
          message: message,
        ),
      );
    }

    if (caller.isCancelled) return cancelled();

    // A body that does not check its token never sees the caller's, so it
    // cannot be reported as cancelled while it ran to completion (F8).
    final AppActionCancelToken bodyToken = action.cancellable
        ? caller
        : AppActionCancelToken.none;
    try {
      final T value = await action.body(bodyToken);
      final String message = redactUrlCredentials(
        action.describeSuccess(value),
      );
      return finish(
        OperationLogLevel.info,
        message,
        (Duration d) => AppActionSucceeded<T>(
          value: value,
          actionName: action.name,
          startedAt: startedAt,
          duration: d,
          message: message,
        ),
      );
    } on AppActionCancelledException {
      return cancelled();
    } on Exception catch (error) {
      // Exceptions only: an Error is a bug and propagates unlogged (F6).
      final String message = redactUrlCredentials(
        action.describeFailure(error),
      );
      return finish(
        OperationLogLevel.error,
        message,
        (Duration d) => AppActionFailed<T>(
          actionName: action.name,
          startedAt: startedAt,
          duration: d,
          message: message,
        ),
      );
    }
  }
}

final Provider<AppActionRunner> appActionRunnerProvider =
    Provider<AppActionRunner>((Ref ref) => const AppActionRunner());
