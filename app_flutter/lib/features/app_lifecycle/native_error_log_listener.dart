import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_log_events.dart';
import '../../data/models/native_error_coalescer.dart';
import '../../data/models/native_error_report.dart';
import '../../data/repositories/native_error_events_provider.dart';
import '../../data/repositories/open_repo_sessions.dart';
import '../../data/repositories/window_log_repository.dart';

/// Puts each failure `gbm_capi` reports into the window's Log and every open repository's,
/// where an error-level line lights the status bar's red summary. A native failure belongs
/// to no one repository, so it is above the router, and it never swallows an event.
///
/// Renders [child] unchanged -- this widget contributes no layout.
class NativeErrorLogListener extends ConsumerStatefulWidget {
  const NativeErrorLogListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NativeErrorLogListener> createState() =>
      _NativeErrorLogListenerState();
}

class _NativeErrorLogListenerState
    extends ConsumerState<NativeErrorLogListener> {
  late final NativeErrorCoalescer _coalescer;
  late final StreamSubscription<NativeErrorReport> _subscription;

  @override
  void initState() {
    super.initState();
    final WindowLogController windowLog = ref.read(windowLogProvider.notifier);
    final OpenRepoSessions sessions = ref.read(openRepoSessionsProvider);
    _coalescer = NativeErrorCoalescer(
      emit: (NativeErrorReport report) {
        final entry = AppLogEvents.nativeError(report);
        windowLog.recordAppLog(entry);
        sessions.recordAppLogToAll(entry);
      },
    );
    _subscription = ref
        .read(nativeErrorEventsProvider)
        .reports
        .listen(_coalescer.add);
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _coalescer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
