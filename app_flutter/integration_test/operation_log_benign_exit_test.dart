// Device-tier E2E: the reported defect, on the surface it was reported from.
//
// `git config --local --get user.name` exits 1 when the key is unset, and the
// operation log recorded every invocation with its exit code and no way to say
// "that was an answer, not a refusal" -- so opening a repository with no local
// identity and pressing Refresh wrote two red ERROR rows every time.
//
// This is the one tier that exercises the whole chain at once: the real
// gbm_capi dylib declaring the benign code, the real JSON crossing the FFI,
// the real Dart decode, and the real LogDrawer. The C++ and Dart tests each
// cover their own end of that; nothing below this tier joins them up.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_action_shortcuts.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    // createTempGitRepo() configures user.name/user.email into --local scope
    // so it can make its seed commit, and must keep doing so. Unsetting them
    // afterwards leaves exactly the state the reporter's repository is in:
    // commits exist, no per-repository identity override.
    runGit(repoPath, <String>['config', '--local', '--unset', 'user.name']);
    runGit(repoPath, <String>['config', '--local', '--unset', 'user.email']);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets('reading an unset local identity logs INFO, not ERROR', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repoPath);

    // Session open does *not* read the local identity -- verified here, by
    // this test failing on an empty record list before the refresh was added.
    // `refreshRepoStatus()` is what sweeps it in, and F5 / View → Refresh is
    // the one entry point ([STATE-refresh-entry-point]), which is also exactly
    // where the defect was reported from: 「log 在 refresh 時一直出現」.
    //
    // Dispatched from below WorkspaceActionShortcuts, since Actions.invoke
    // searches upwards.
    Actions.invoke(
      tester.element(find.byType(StatusBar)),
      const GbmActionIntent(GbmActionId.viewRefresh),
    );

    // Not pumpAndSettle: a refresh puts an indeterminate spinner on screen,
    // which schedules frames forever ([TEST-no-pumpandsettle-with-spinner]).
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final LogDrawer drawer = tester.widget<LogDrawer>(find.byType(LogDrawer));
    final List<OperationRecord> identityReads = drawer.records
        .whereType<OperationRecord>()
        .where(
          (OperationRecord r) =>
              r.argv.contains('--get') && r.argv.contains('user.name'),
        )
        .toList(growable: false);

    expect(
      identityReads,
      isNotEmpty,
      reason: 'the app should have read user.name at least once',
    );

    // The local read is the one that exits 1 here; the effective read (no
    // --local) finds whatever the machine's global config holds, which on a
    // developer's machine is usually set. Assert on the local one only, and
    // assert the exit code first -- if a future git stops answering an unset
    // key with 1, or the arrangement above stops taking effect, this must go
    // red rather than pass for the wrong reason.
    final Iterable<OperationRecord> localReads = identityReads.where(
      (OperationRecord r) => r.argv.contains('--local'),
    );
    expect(localReads, isNotEmpty, reason: 'no --local read was recorded');

    for (final OperationRecord read in localReads) {
      expect(
        read.exitCode,
        1,
        reason: 'the arrangement no longer produces the unset-key exit',
      );
      expect(read.benignExit, isTrue, reason: read.commandLine);
      expect(read.failed, isFalse, reason: read.commandLine);
      expect(read.level, OperationLogLevel.info, reason: read.commandLine);
      expect(read.levelLabel, 'INFO', reason: read.commandLine);
    }
  });
}
