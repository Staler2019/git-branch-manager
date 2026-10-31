import 'package:flutter/widgets.dart';

import '../diff/sync_scroll/sync_scroll_controller.dart';
import '../diff/sync_scroll/user_scroll.dart';

/// Makes [column] the synced leader of the conflict window's three columns
/// on a user's own scroll ([userScrollAxis]), for that scroll's axis. A
/// scrollbar thumb drag is one too (its `ScrollStartNotification` carries
/// drag details); unlike `ScopedDiffView` there is no pointer-down lead,
/// because no selection autoscrolls these columns.
class ConflictColumnSyncLead extends StatelessWidget {
  const ConflictColumnSyncLead({
    super.key,
    required this.column,
    required this.vertical,
    required this.horizontal,
    required this.child,
  });

  final int column;
  final SyncScrollController vertical;
  final SyncScrollController horizontal;
  final Widget child;

  @override
  Widget build(BuildContext context) => NotificationListener<Notification>(
    onNotification: (Notification notification) {
      switch (userScrollAxis(notification)) {
        case Axis.vertical:
          vertical.lead(column);
        case Axis.horizontal:
          horizontal.lead(column);
        case null:
      }
      return false;
    },
    child: child,
  );
}
