import 'dart:async';

/// Thrown by [AppActionCancelToken.throwIfCancelled]; the one exception
/// [AppActionRunner] reads as "cancelled" rather than "failed".
final class AppActionCancelledException implements Exception {
  const AppActionCancelledException();

  @override
  String toString() => 'AppActionCancelledException';
}

/// Cancellation for one app action (ruling R4: an action is name + log +
/// cancellation token).
///
/// Whether cancelling actually stops anything is up to the action's body:
/// only a body that checks [isCancelled] or calls [throwIfCancelled] can be
/// stopped. A body that cannot be is given [none] by the runner, so it can
/// never report a cancellation it did not honour.
final class AppActionCancelToken {
  AppActionCancelToken() : _inert = false;

  AppActionCancelToken._inert() : _inert = true;

  /// A token that is never cancelled; [cancel] on it does nothing.
  static final AppActionCancelToken none = AppActionCancelToken._inert();

  final bool _inert;
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is first called; never, for [none].
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (_inert || _cancelled.isCompleted) return;
    _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const AppActionCancelledException();
  }
}
