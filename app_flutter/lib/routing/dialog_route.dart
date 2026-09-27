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

/// Pushes a dialog route, unless that exact dialog is already on the
/// navigation stack.
///
/// **The single way this app opens a dialog** (使用者裁定「全部 26 個對話框都加」).
/// Every `context.push` of a [dialogRoute] path goes through here, and
/// `dialog_push_single_source_test.dart` asserts there are no others -- without
/// that test the 47th call site quietly bypasses the guard.
///
/// It exists because a duplicate push really does mount a second instance:
/// measured, two `PruneRemoteBranchesDialogContent`s coexisted and each issued
/// its own `git remote prune --dry-run`. Nothing in the app guarded against it,
/// and the double-click that causes it is one keystroke or one impatient mouse.
///
/// Three facts decide the implementation, and each rules out an obvious
/// alternative:
///
/// - `currentConfiguration.uri` stays at the *base* location and does not
///   reflect a pushed dialog at all, so `GoRouterState.of(context).uri` cannot
///   answer this question.
/// - a pushed entry is an [ImperativeRouteMatch], and its `matches.uri` is the
///   only form that keeps the query string. `matchedLocation` drops it, which
///   would make `?remote=origin` and `?remote=upstream` the same dialog -- two
///   legitimately coexisting ones.
/// - `pop`, a barrier tap and `Navigator.pop` all clear the match, so the guard
///   is never permanent. That is the premise it rests on; without it this would
///   be a dialog that can be opened once per session.
void pushDialogRoute(BuildContext context, String location) =>
    pushDialogRouteOn(GoRouter.of(context), location);

/// [pushDialogRoute] for a caller that holds the router but no
/// [BuildContext] -- `app.dart`'s startup update check is the one such caller.
void pushDialogRouteOn(GoRouter router, String location) {
  for (final RouteMatchBase match
      in router.routerDelegate.currentConfiguration.matches) {
    if (match is ImperativeRouteMatch &&
        match.matches.uri.toString() == location) {
      return;
    }
  }
  router.push<void>(location);
}
