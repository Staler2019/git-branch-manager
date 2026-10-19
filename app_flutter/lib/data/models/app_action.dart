import 'app_action_cancel_token.dart';

/// One thing the app does on the user's behalf, separate from the widget
/// that asked for it (ruling R4: 「動作應該是跟 ui 分開的，log一定跟動作強綁
/// 定」). Run it through `AppActionRunner`, which times it, honours
/// cancellation and writes exactly one Log line for it.
///
/// Built by named factories next to the feature that owns the action, never
/// by a widget assembling the closures inline.
final class AppAction<T> {
  const AppAction({
    required this.name,
    required this.cancellable,
    required this.body,
    required this.describeSuccess,
    required this.describeFailure,
    required this.describeCancelled,
  });

  /// Stable identifier, e.g. `openExternalApp`; the future span name.
  final String name;

  /// Whether [body] checks the token it is handed. When false the runner
  /// hands it [AppActionCancelToken.none], so the outcome is always what the
  /// body actually did (security review F8).
  final bool cancellable;

  final Future<T> Function(AppActionCancelToken token) body;

  /// The Log line for a success.
  final String Function(T value) describeSuccess;

  /// The Log line for a failure, chosen by the exception's type (F6).
  final String Function(Exception error) describeFailure;

  /// The Log line for a cancellation.
  final String Function() describeCancelled;
}
