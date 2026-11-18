import 'package:flutter/widgets.dart';

/// Carries WorkspaceScreen's open-only log action to its subtree, so a panel's
/// failure banner (`Open log`) opens the drawer exactly the way the status
/// bar's red error summary does.
///
/// Open-only on purpose: `GbmActionId.viewLog` toggles, and a button meaning
/// 「show me this error」 must never close a drawer someone is reading.
class WorkspaceLogScope extends InheritedWidget {
  const WorkspaceLogScope({
    super.key,
    required this.openLogAtNewestError,
    required super.child,
  });

  /// Opens the log drawer and jumps to the newest error-level line.
  final VoidCallback openLogAtNewestError;

  static WorkspaceLogScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceLogScope>();

  @override
  bool updateShouldNotify(WorkspaceLogScope oldWidget) =>
      openLogAtNewestError != oldWidget.openLogAtNewestError;
}
