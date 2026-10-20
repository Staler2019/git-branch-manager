// A running clone is a row in the status bar's progress area, wherever the
// user is (welcome-and-clone-spec screen 2), and its Cancel reaches the job
// (TASKS 「可取消」).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/clone_job_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';

import '../support/fake_clone_job_native.dart';
import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

void main() {
  testWidgets('the workspace shows a running clone and cancels it', (
    tester,
  ) async {
    final FakeCloneJobNative native = FakeCloneJobNative();
    final PumpedWorkspace w = await pumpWorkspace(
      tester,
      identity: _identity,
      overrides: [cloneJobNativeProvider.overrideWithValue(native)],
    );
    w.container
        .read(cloneJobsProvider.notifier)
        .start(
          url: 'https://h/design-tokens.git',
          destPath: '/src/design-tokens',
          recurseSubmodules: false,
          shallow: false,
          origin: CloneLogTarget.window(
            w.container.read(windowLogProvider.notifier),
          ),
        );
    await tester.pump();
    expect(find.text('Cloning design-tokens'), findsOneWidget);

    native.emit(0, GbmEventType.cloneProgress, <String, Object>{
      'phase': 'resolving',
      'current': 3912,
      'total': 20477,
    });
    await tester.pump();
    expect(
      find.text('Cloning design-tokens — resolving deltas 3,912 / 20,477'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(native.jobs.single.calls, <String>['cancel']);

    native.emit(0, GbmEventType.cloneFinished, <String, Object>{'ok': false});
    await tester.pump();
    // The status bar's own 3-second linger, then the row is gone.
    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('Cloning design-tokens'), findsNothing);
  });
}
