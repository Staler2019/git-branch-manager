import 'package:flutter/widgets.dart';

import '../actions/workspace_log_scope.dart';
import 'gbm_button.dart';

/// `Open log` on a panel's failure banner (read-failure-states-spec.html:
/// `.gbm-btn .gbm-btn-secondary .gbm-btn-sm`, after P07's in-banner buttons).
///
/// Calls [WorkspaceLogScope.openLogAtNewestError], the same open-only method
/// as the status bar's red summary, never View → Log's toggle. Outside a
/// workspace there is no log to open, so it draws nothing.
class GbmOpenLogButton extends StatelessWidget {
  const GbmOpenLogButton({super.key});

  @override
  Widget build(BuildContext context) {
    final WorkspaceLogScope? scope = WorkspaceLogScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return GbmButton(
      label: 'Open log',
      size: GbmButtonSize.sm,
      onPressed: scope.openLogAtNewestError,
    );
  }
}
