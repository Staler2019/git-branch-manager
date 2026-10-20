import '../../data/models/clone_job.dart';
import 'background_task.dart';

const String _prefix = 'clone-';

/// The status bar's task id for clone job [jobId].
String cloneTaskId(int jobId) => '$_prefix$jobId';

/// The clone job a task id names, or null for any other task -- what a
/// Cancel handler asks before routing to `CloneJobController.cancel`.
int? cloneJobIdOf(String taskId) => taskId.startsWith(_prefix)
    ? int.tryParse(taskId.substring(_prefix.length))
    : null;

/// One task per running clone: `Cloning <folder>`, with the phase and its
/// counts once git reports them (welcome-and-clone-spec screen 2, W-D7).
/// Before that, `total` is 0 and the bar is indeterminate.
List<BackgroundTask> backgroundTasksFromCloneJobs(List<CloneJob> jobs) =>
    <BackgroundTask>[
      for (final CloneJob job in jobs)
        BackgroundTask.cloneJob(
          id: cloneTaskId(job.id),
          label: 'Cloning ${job.name}',
          phase: job.progress?.phase.gitName ?? '',
          current: job.progress?.current ?? 0,
          total: job.progress?.total ?? 0,
        ),
    ];
