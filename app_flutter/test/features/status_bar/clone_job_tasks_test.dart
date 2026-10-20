// The status bar's row for each running clone job (welcome-and-clone-spec
// screen 2: 「Cloning <repo 名> — <phase> <n> / <m>」, W-D7).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/clone_events.dart';
import 'package:gbm_flutter/data/models/clone_job.dart';
import 'package:gbm_flutter/features/status_bar/background_task.dart';
import 'package:gbm_flutter/features/status_bar/clone_job_tasks.dart';

void main() {
  test('one cancellable task per job, phase and counts from progress', () {
    final List<BackgroundTask> tasks = backgroundTasksFromCloneJobs(
      const <CloneJob>[
        CloneJob(
          id: 3,
          url: 'u',
          destPath: '/src/design-tokens',
          progress: CloneProgress(
            phase: ClonePhase.receiving,
            current: 12480,
            total: 31206,
          ),
        ),
        CloneJob(id: 4, url: 'u', destPath: '/src/other'),
      ],
    );
    expect(tasks, hasLength(2));
    final BackgroundTask first = tasks.first;
    expect(first.id, cloneTaskId(3));
    expect(first.label, 'Cloning design-tokens');
    expect(first.phase, 'receiving objects');
    expect(first.current, 12480);
    expect(first.total, 31206);
    expect(first.cancellable, isTrue);
    // Before the first progress: the name alone, indeterminate bar.
    expect(tasks.last.label, 'Cloning other');
    expect(tasks.last.phase, '');
    expect(tasks.last.total, 0);
  });

  test('a task id maps back to its job, and nothing else does', () {
    expect(cloneJobIdOf(cloneTaskId(12)), 12);
    expect(cloneJobIdOf('git-1234567'), isNull);
    expect(cloneJobIdOf('clone-x'), isNull);
  });
}
