// The wording of these lines is a product surface, not an implementation
// detail: LOGRULES' 匯出 row says a bug report should be the exported log and
// nothing else (「回報問題時附這份即可，不需要另外重現」), so what each line
// actually says is worth pinning.
//
// It also puts LOGRULES' 不記什麼 rule (認證資訊、remote URL 中的 token、
// 檔案內容) in one checkable place: every argument below is a work-tree path,
// a branch name, a remote *name* or a ref name -- never a URL.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_log_events.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';

void main() {
  group('AppLogEvents.repositoryOpened', () {
    test('names the work tree and is info level', () {
      final AppLogEntry entry = AppLogEvents.repositoryOpened(
        '/Users/dev/project',
        atEpochMs: 7,
      );

      expect(entry.message, 'Opened repository /Users/dev/project');
      expect(entry.level, OperationLogLevel.info);
      expect(entry.whenEpochMs, 7);
    });
  });

  group('AppLogEvents.branchCheckedOut', () {
    AppLogEntry checkout({
      String target = 'main',
      bool detach = false,
      bool createBranch = false,
      String newBranchName = '',
    }) {
      return AppLogEvents.branchCheckedOut(
        target: target,
        detach: detach,
        createBranch: createBranch,
        newBranchName: newBranchName,
        atEpochMs: 0,
      );
    }

    test('a plain checkout names the target', () {
      expect(checkout(target: 'feature/x').message, 'Checked out feature/x');
    });

    // "Checked out abc1234" and "Created branch x at abc1234" are different
    // events to anyone reading back what they did, so the three shapes of
    // checkout do not collapse into one sentence.
    test('creating a branch says so, and names both', () {
      expect(
        checkout(
          target: 'origin/main',
          createBranch: true,
          newBranchName: 'feature/x',
        ).message,
        'Created branch feature/x at origin/main and checked it out',
      );
    });

    test('a detached checkout says so', () {
      expect(
        checkout(target: 'abc1234', detach: true).message,
        'Checked out abc1234 (detached HEAD)',
      );
    });

    // createBranch with no name is not a state the UI can produce, but the
    // request object allows it; falling back to the plain wording beats
    // emitting "Created branch  at main".
    test('createBranch with an empty name falls back to the plain wording', () {
      expect(
        checkout(target: 'main', createBranch: true).message,
        'Checked out main',
      );
    });
  });

  group('AppLogEvents.remoteRefGone', () {
    test('is a warning and says the ref has not been pruned', () {
      // Page 10's mockup draws this row with a warn icon:
      // 「origin/graph-lanes 已不存在於遠端，標記為 gone（尚未 prune）」.
      // Nothing failed -- it is stage 1 of page 02's three-stage flow -- and
      // saying "not pruned" in the line itself is what stops a reader
      // assuming the ref is already gone from disk.
      final AppLogEntry entry = AppLogEvents.remoteRefGone(
        'origin/graph-lanes',
        atEpochMs: 0,
      );

      expect(entry.level, OperationLogLevel.warning);
      expect(
        entry.message,
        'origin/graph-lanes no longer exists on the remote; '
        'marked as gone (not pruned)',
      );
    });

    test('shows the short name even when handed a full ref', () {
      expect(
        AppLogEvents.remoteRefGone(
          'refs/remotes/origin/graph-lanes',
          atEpochMs: 0,
        ).message,
        startsWith('origin/graph-lanes '),
      );
    });
  });

  group('AppLogEvents.refsPruned', () {
    // LOGRULES says 「prune 掉哪些 ref」 -- *which*, not merely that a prune
    // happened -- so the names are in the line.
    test('names every pruned ref', () {
      expect(
        AppLogEvents.refsPruned(
          remote: 'origin',
          refs: <String>['origin/a', 'origin/b'],
          atEpochMs: 0,
        ).message,
        'Pruned 2 remote-tracking refs on origin: origin/a, origin/b',
      );
    });

    test('reads as a singular for one ref', () {
      expect(
        AppLogEvents.refsPruned(
          remote: 'origin',
          refs: <String>['origin/a'],
          atEpochMs: 0,
        ).message,
        'Pruned 1 remote-tracking ref on origin: origin/a',
      );
    });

    // pruneRemote's two call sites disagree on form -- the Prune dialog
    // sends git's short names, sidebar_panel.dart sends full ones -- so the
    // same prune must not read differently depending on where it came from.
    test('renders the same line for full and short ref names', () {
      final String fromDialog = AppLogEvents.refsPruned(
        remote: 'origin',
        refs: <String>['origin/a'],
        atEpochMs: 0,
      ).message;
      final String fromSidebar = AppLogEvents.refsPruned(
        remote: 'origin',
        refs: <String>['refs/remotes/origin/a'],
        atEpochMs: 0,
      ).message;

      expect(fromSidebar, fromDialog);
    });
  });
}
