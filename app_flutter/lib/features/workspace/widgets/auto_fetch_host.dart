import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../actions/auto_fetch_gate.dart';
import '../../../actions/gbm_action_availability.dart';
import '../../../actions/gbm_action_id.dart';
import '../../../data/repositories/app_preferences_repository.dart';
import '../../../data/repositories/auto_fetch_scheduler.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../routing/dialog_open_observer.dart';
import '../../status_bar/running_git_tasks.dart';

/// Runs spec P11 item 9's auto fetch for the repository this window shows:
/// one [AutoFetchScheduler] per [identity], so 「切換 repo 時計時器重置」 is
/// the old one disposed and a new one started, and only the current
/// repository is ever fetched.
///
/// Feeds the scheduler from each input's single source -- Preferences, the
/// session's [RepoSessionController.fetchFinished], the root navigator's
/// [DialogOpenObserver], `credentialPrompt`, [isActionEnabled]'s conflict
/// gate (the same id `TabRow.conflictActive` reads), and the status bar's
/// running git tasks -- and logs a pause through the session.
///
/// Renders [child] unchanged.
class AutoFetchHost extends ConsumerStatefulWidget {
  const AutoFetchHost({super.key, required this.identity, required this.child});

  final RepoIdentity identity;
  final Widget child;

  @override
  ConsumerState<AutoFetchHost> createState() => _AutoFetchHostState();
}

class _AutoFetchHostState extends ConsumerState<AutoFetchHost> {
  AutoFetchScheduler? _scheduler;
  StreamSubscription<FetchFinished>? _finished;

  @override
  void initState() {
    super.initState();
    _startAfterFrame(widget.identity);
  }

  @override
  void didUpdateWidget(AutoFetchHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _stop();
      _startAfterFrame(widget.identity);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  /// After the frame: the first configure fetches at once, and a fetch
  /// dispatched mid-build could publish session state during build.
  void _startAfterFrame(RepoIdentity identity) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || identity != widget.identity) return;
      _start(identity);
    });
  }

  void _start(RepoIdentity identity) {
    final RepoSessionController session = ref.read(
      repoSessionProvider(identity).notifier,
    );
    final AutoFetchScheduler scheduler = ref
        .read(autoFetchSchedulerFactoryProvider)
        .create(
          readConditions: () => _conditions(identity),
          fetch: () => session.fetchRemote(background: true),
          onPaused: session.recordAutoFetchPaused,
        );
    _scheduler = scheduler;
    _finished = session.fetchFinished.listen(
      (FetchFinished f) => scheduler.onFetchFinished(
        background: f.background,
        succeeded: f.succeeded,
        errorCodeName: f.errorCodeName,
      ),
    );
    _configure(ref.read(appPreferencesProvider));
  }

  void _stop() {
    unawaited(_finished?.cancel());
    _finished = null;
    _scheduler?.dispose();
    _scheduler = null;
  }

  void _configure(AppPreferences prefs) => _scheduler?.configure(
    enabled: prefs.autoFetchEnabled,
    minutes: prefs.autoFetchMinutes,
  );

  /// Read at each tick, never cached: every input can change between two.
  /// The two the scheduler owns are left false for it to overwrite.
  AutoFetchConditions _conditions(RepoIdentity identity) {
    final RepoSessionState session = ref.read(repoSessionProvider(identity));
    return AutoFetchConditions(
      pausedAfterAuthFailure: false,
      autoFetchInFlight: false,
      dialogOpen: ref.read(dialogOpenObserverProvider).dialogOpen,
      credentialPromptPending: session.credentialPrompt != null,
      conflictActive: !isActionEnabled(
        GbmActionId.branchMergeIntoCurrent,
        session,
      ),
      foregroundOperationActive: backgroundTasksFromOperationLog(
        session.operationLog,
      ).isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppPreferences>(
      appPreferencesProvider,
      (_, AppPreferences next) => _configure(next),
    );
    return widget.child;
  }
}
