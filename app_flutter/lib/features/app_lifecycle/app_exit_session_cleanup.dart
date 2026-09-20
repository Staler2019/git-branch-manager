import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/open_repo_sessions.dart';

/// Closes every open `gbm_capi` session before the app is allowed to quit.
///
/// Flutter never pops a route on Cmd+Q, the window's close button, or
/// File -> Exit's `SystemNavigator.pop()` -- `repoSessionProvider` is a
/// plain (non-autoDispose) family, so with no route pop nothing ever calls
/// `RepoSessionController.dispose()` on the ordinary quit path, and
/// `Session::~Session()`'s clean-up never runs for whichever repositories
/// are still open. The process then reaches `exit()` with the process-wide
/// shared read pool still holding background work tied to those sessions,
/// racing the Dart engine's own teardown -- the SIGSEGV this widget exists
/// to prevent.
///
/// [openRepoSessionsProvider]/[OpenRepoSessions.closeAll] already existed
/// for exactly this "close every open session before the process ends"
/// need -- built for the self-install flow (`update_dialog.dart`'s
/// `_closeSessions()`, so an interrupted refresh does not strand a `git`
/// child holding `.git/index.lock`) and, as of this widget, also the
/// ordinary quit path.
///
/// Renders [child] unchanged -- this widget contributes no layout.
class AppExitSessionCleanup extends ConsumerStatefulWidget {
  const AppExitSessionCleanup({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppExitSessionCleanup> createState() =>
      _AppExitSessionCleanupState();
}

class _AppExitSessionCleanupState extends ConsumerState<AppExitSessionCleanup> {
  AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onExitRequested: _handleExitRequested);
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _handleExitRequested() async {
    // Synchronous per session (Session::~Session() itself now bounds its
    // own wait by cancelling before draining -- see
    // docs/rules/fn-cpp-core.md's [CPP-session-dtor-order]), so this
    // completes without an app-side timeout of its own.
    ref.read(openRepoSessionsProvider).closeAll();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
