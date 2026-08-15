import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A [GoRoute] that renders as a modal dialog: non-opaque, with a scrim
/// barrier, dismissible by tapping outside or the system back gesture.
/// Matches the plan's routing-table note on preferring routed dialogs over
/// ad hoc `showDialog()` calls, so every dialog stays deep-linkable and gets
/// consistent Esc/back dismissal -- this is the pattern M3 sets out to
/// validate for the ~30 remaining Qt dialogs (see docs/FEATURES.md).
GoRoute dialogRoute({
  required String path,
  required Widget Function(BuildContext, GoRouterState) builder,
}) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => CustomTransitionPage<void>(
      key: state.pageKey,
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 160),
      child: builder(context, state),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
