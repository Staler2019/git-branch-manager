import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../data/models/dart_error_report.dart';

/// Where a Dart error goes: `gbm_report_external_error`, in the app.
typedef ExternalErrorReport = void Function(
  String where,
  String summary,
  String detail,
);

/// [installDartErrorHandlers]'s shape, so a bootstrap test can stand in for it.
typedef InstallDartErrorHandlers = void Function() Function({
  required ExternalErrorReport report,
});

/// Sends framework errors and uncaught async errors to [report], through a
/// [DartErrorLimiter], and passes each one on to the handler that was there before, so
/// the console output and the engine's default stay as they were. Returns the function
/// that puts both previous handlers back.
///
/// Reporting must never fail the error it reports: a [report] that throws, or an error
/// raised while one is being reported, is dropped here rather than reported again.
void Function() installDartErrorHandlers({
  required ExternalErrorReport report,
}) {
  final FlutterExceptionHandler? previousFlutter = FlutterError.onError;
  final ErrorCallback? previousDispatcher = PlatformDispatcher.instance.onError;
  bool reporting = false;
  final DartErrorLimiter limiter = DartErrorLimiter(
    emit: (DartErrorReport r) => report(r.where, r.summary, r.detail),
  );

  void send(String where, Object error, StackTrace? stack) {
    if (reporting) return;
    reporting = true;
    try {
      limiter.add(
        DartErrorReport.fromError(where: where, error: error, stack: stack),
      );
      // Anything at all, Errors included: this runs inside the handler of another error.
    } catch (_) {
    } finally {
      reporting = false;
    }
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    send('FlutterError', details.exception, details.stack);
    previousFlutter?.call(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    send('PlatformDispatcher', error, stack);
    return previousDispatcher?.call(error, stack) ?? false;
  };

  return () {
    limiter.dispose();
    FlutterError.onError = previousFlutter;
    PlatformDispatcher.instance.onError = previousDispatcher;
  };
}
