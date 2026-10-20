import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/clone_job.dart';
import '../../data/repositories/clone_job_repository.dart';
import '../../routing/app_router.dart';
import '../../routing/dialog_route.dart';
import '../../routing/route_paths.dart';

/// The app-wide half of every clone job, above the router like
/// `AppExitSessionCleanup`: a clone outlives the window that started it.
///
/// - A job that starts asking for a credential gets its dialog
///   ([RoutePaths.cloneCredentialDialog]); the dialog closes itself when the
///   job stops asking.
/// - A job that succeeds opens the new repository (R10, DLGS 「完成後自動
///   開啟」). Its rows are already in that repository's Log by then (R12).
///
/// Renders [child] unchanged.
class CloneJobListener extends ConsumerStatefulWidget {
  const CloneJobListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CloneJobListener> createState() => _CloneJobListenerState();
}

class _CloneJobListenerState extends ConsumerState<CloneJobListener> {
  StreamSubscription<String>? _opened;

  @override
  void initState() {
    super.initState();
    _opened = ref
        .read(cloneJobsProvider.notifier)
        .opened
        .listen(
          (String dest) => ref
              .read(appRouterProvider)
              .go(RoutePaths.workspaceFor(repoIdFor(dest))),
        );
  }

  @override
  void dispose() {
    unawaited(_opened?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<CloneJob>>(cloneJobsProvider, (
      List<CloneJob>? previous,
      List<CloneJob> next,
    ) {
      for (final CloneJob job in next) {
        final String? before = _promptOf(previous, job.id);
        // On the transition only: right after an Esc the prompt is still
        // set until the deferred cancel lands, and a progress event in that
        // gap must not bring the dialog back.
        if (job.credentialPrompt != null && before == null) {
          pushDialogRouteOn(
            ref.read(appRouterProvider),
            RoutePaths.cloneCredentialDialogPath(job.id),
          );
        }
      }
    });
    return widget.child;
  }

  static String? _promptOf(List<CloneJob>? jobs, int id) {
    for (final CloneJob job in jobs ?? const <CloneJob>[]) {
      if (job.id == id) return job.credentialPrompt;
    }
    return null;
  }
}
