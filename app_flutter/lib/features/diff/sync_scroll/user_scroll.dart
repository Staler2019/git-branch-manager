import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The axis [notification] is a user's own scroll on, or null when it is
/// not one: a non-idle `UserScrollNotification` (the wheel sends one) or a
/// drag's `ScrollStartNotification`. A synced follower's guarded `jumpTo`
/// goes idle, which reports an idle direction from a column that did not
/// lead, so it never counts.
Axis? userScrollAxis(Notification notification) {
  final bool user = switch (notification) {
    UserScrollNotification(:final ScrollDirection direction) =>
      direction != ScrollDirection.idle,
    ScrollStartNotification(:final DragStartDetails? dragDetails) =>
      dragDetails != null,
    _ => false,
  };
  return user ? (notification as ScrollNotification).metrics.axis : null;
}
