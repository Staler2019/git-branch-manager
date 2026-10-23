import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a dialog is on the root navigator right now, for the auto fetch's
/// gate: 使用者裁定 2026-10-24 「開 dialog 時都不能做背景 fetch」 -- a dialog
/// (Force Push most of all) may be showing counts read from a
/// remote-tracking ref that a fetch would move underneath it.
///
/// A dialog is a [RawDialogRoute] (`showDialog`, `showGeneralDialog`) or a
/// non-opaque [PageRoute] -- `dialogRoute`'s `CustomTransitionPage` builds the
/// latter, not a [PopupRoute], so counting popup routes would miss every
/// routed dialog. A context menu (`showMenu`'s popup route) is not a dialog.
///
/// A set of routes rather than a counter, so a route removed without a pop
/// cannot leave the count stuck high, nor one reported twice push it higher.
class DialogOpenObserver extends NavigatorObserver {
  final Set<Route<dynamic>> _open = <Route<dynamic>>{};

  bool get dialogOpen => _open.isNotEmpty;

  static bool _isDialog(Route<dynamic> route) =>
      route is RawDialogRoute || (route is PageRoute && !route.opaque);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isDialog(route)) _open.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _open.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _open.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _open.remove(oldRoute);
    if (newRoute != null && _isDialog(newRoute)) _open.add(newRoute);
  }
}

/// App-scoped: one observer on the root navigator (`appRouterProvider`), read
/// by every workspace's auto fetch.
final Provider<DialogOpenObserver> dialogOpenObserverProvider =
    Provider<DialogOpenObserver>((Ref ref) => DialogOpenObserver());
