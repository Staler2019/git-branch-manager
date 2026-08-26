import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How to submit the diff area's current one-shot temporary scope, or null
/// when there is no live text selection to submit.
///
/// This exists so `GbmActionId.repositoryStageSelectedLines` (Ctrl/Cmd+Alt+S,
/// and the Repository menu item beside it) can act on the same thing the
/// temporary card's button does. The action is dispatched from
/// `WorkspaceScreen._buildActionHandlers()`, several layers above the diff
/// column, and an [Actions] entry installed by the column could not be
/// reached from there -- intents travel up from the focused context, not
/// down from the shell.
///
/// **Null is the disabled state**, and it is what greys the menu item out
/// rather than letting the shortcut silently no-op: the handler map is read
/// by all three dispatch paths, so registering here reaches the keyboard,
/// the in-window menu and the macOS system menu at once.
///
/// Only the **unstaged** column registers. The action's verb is "stage", and
/// a shortcut has no way to say which of the two columns it meant.
final StateProvider<void Function()?> temporaryScopeSubmitProvider =
    StateProvider<void Function()?>((Ref ref) => null);
