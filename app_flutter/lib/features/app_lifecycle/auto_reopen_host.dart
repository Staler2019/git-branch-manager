import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ffi/native_error_events.dart';
import '../../data/models/app_log_events.dart';
import '../../data/repositories/auto_reopen_marker_repository.dart';
import '../../data/repositories/gbm_bindings_provider.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/repositories/window_log_repository.dart';

/// Whether a session's first load is over, one way or the other: an error means the app
/// survived the open, and an open session with no read outstanding has read its refs, history
/// and repo state. #207's crash is inside the open itself, long before either.
bool isFirstLoadSettled(RepoSessionState state) =>
    state.lastError != null || (state.isOpen && !state.isRefreshing);

/// Carries the launch's auto-reopen marker through the run: clears it once the repository it
/// names has settled its first load, and puts the row saying a reopen was skipped into the
/// window's Log, whose error level lights the status bar's red summary (spec P15 B: 「只是
/// 通知結果的留在 log 抽屜與狀態列」).
///
/// Above the router, so it outlives the workspace that opened the session and runs once per
/// app run however often the welcome screen is shown. Renders [child] unchanged.
class AutoReopenHost extends ConsumerStatefulWidget {
  const AutoReopenHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AutoReopenHost> createState() => _AutoReopenHostState();
}

class _AutoReopenHostState extends ConsumerState<AutoReopenHost> {
  ProviderSubscription<RepoSessionState>? _session;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    final String? skipped = ref.read(skippedAutoReopenProvider);
    if (skipped != null) {
      // A provider written while the tree builds throws; a microtask runs after this build.
      Future<void>.microtask(() {
        if (!mounted) return;
        ref
            .read(windowLogProvider.notifier)
            .recordAppLog(
              AppLogEvents.autoReopenSkipped(
                skipped,
                logPath: readNativeErrorLogPath(ref.read(gbmBindingsProvider)),
                atEpochMs: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      });
    }
    final String? pending = ref.read(pendingAutoReopenProvider);
    if (pending != null) {
      // Immediately too: the first load may have settled before this mounted, and a listener
      // alone never sees the value already there.
      _session = ref.listenManual<RepoSessionState>(
        repoSessionProvider(RepoIdentity.forWorkDir(pending)),
        (RepoSessionState? previous, RepoSessionState next) {
          if (isFirstLoadSettled(next)) _settle();
        },
        fireImmediately: true,
      );
      if (_settled) _session?.close();
    }
  }

  void _settle() {
    if (_settled) return;
    _settled = true;
    _session?.close();
    unawaited(ref.read(autoReopenMarkerRepositoryProvider).clear());
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
