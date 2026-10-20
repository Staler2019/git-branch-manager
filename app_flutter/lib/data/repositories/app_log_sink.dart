import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_action_runner.dart';
import 'repo_identity.dart';
import 'repo_session_repository.dart';
import 'window_log_repository.dart';

/// The Log an action's lines go to, from the window it was started in:
/// the repository at [workDir] when one is open, otherwise the
/// no-repository window's own Log (ruling R13).
///
/// For a surface that opens in either window -- the repository switcher,
/// an app-level dialog that carries `?origin=`. Read, not watched: the
/// caller takes the sink before its first await, so the line is written
/// even if the surface is gone by then (ruling R4, verifier A3).
AppLogSink appLogSinkFor(WidgetRef ref, String? workDir) => workDir == null
    ? ref.read(windowLogProvider.notifier).recordAppLog
    : ref
          .read(repoSessionProvider(RepoIdentity.forWorkDir(workDir)).notifier)
          .recordAppLog;
