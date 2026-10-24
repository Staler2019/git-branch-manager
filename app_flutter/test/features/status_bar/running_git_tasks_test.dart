// What the status bar's progress zone shows for git work: one task per
// running git invocation that belongs to a queued operation of this session
// (OperationRecord.queuedOperationId != 0). Core gives a session non-zero ids
// only for its own queue, and reads (refresh sweeps, previews) never run in
// one -- so the id alone separates "the user's action is running" from
// background noise, with no list of read-only argv shapes to keep in sync.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/features/status_bar/background_task.dart';
import 'package:gbm_flutter/features/status_bar/running_git_tasks.dart';

/// argv as ProcessRunner builds it: executable, global flags, `-C <dir>`,
/// then the command's own arguments.
List<String> _argv(List<String> args) => <String>[
  r'C:\Program Files\Git\cmd\git.exe',
  '-c',
  'core.quotepath=false',
  '--no-optional-locks',
  '-C',
  '/repo',
  ...args,
];

OperationRecord _record(
  List<String> args, {
  int id = 1,
  int queuedOperationId = 7,
  bool running = true,
}) => OperationRecord(
  whenEpochMs: 0,
  repoDir: '/repo',
  argv: _argv(args),
  commandLine: args.join(' '),
  exitCode: 0,
  durationMs: 0,
  stderrText: '',
  cancelled: false,
  timedOut: false,
  id: id,
  running: running,
  queuedOperationId: queuedOperationId,
);

List<String> _labels(List<OperationRecord> log) =>
    backgroundTasksFromOperationLog(log).map((t) => t.label).toList();

void main() {
  group('labels', () {
    final Map<List<String>, String> cases = <List<String>, String>{
      <String>['fetch', '--progress', 'origin']: 'Fetching origin',
      <String>['fetch', '--progress', '--all']: 'Fetching',
      <String>['pull', '--progress', 'origin', 'main']: 'Pulling',
      <String>['push', '--progress', 'origin', 'main']: 'Pushing origin',
      <String>['push', '--progress']: 'Pushing',
      <String>['switch', 'feature']: 'Checking out',
      <String>['checkout', 'feature']: 'Checking out',
      <String>['merge', '--no-edit', 'feature']: 'Merging',
      <String>['rebase', 'main']: 'Rebasing',
      <String>['cherry-pick', 'abc123']: 'Cherry-picking',
      <String>['revert', '--no-edit', 'abc123']: 'Reverting',
      <String>['gc']: 'Collecting garbage',
      <String>['lfs', 'fetch']: 'LFS',
      <String>['remote', 'prune', 'origin']: 'Pruning origin',
      <String>['stash', 'push', '-m', 'wip']: 'Stashing',
      <String>['commit', '--file', '-']: 'Committing',
      // No TASKS row exists for worktrees; 使用者裁定 2026-10-21: add/remove
      // are foreground like Checkout, prune/lock/unlock fold like Prune.
      <String>['worktree', 'add', '-b', 'feature', '/wt']: 'Adding worktree',
      <String>['worktree', 'remove', '/wt']: 'Removing worktree',
      <String>['worktree', 'prune']: 'Pruning worktrees',
      <String>['worktree', 'lock', '--reason', 'x', '/wt']: 'Locking worktree',
      <String>['worktree', 'unlock', '/wt']: 'Unlocking worktree',
    };
    cases.forEach((List<String> args, String label) {
      test('${args.join(' ')} -> $label', () {
        expect(_labels(<OperationRecord>[_record(args)]), <String>[label]);
      });
    });
  });

  test('global flags and -C <dir> are skipped to find the subcommand', () {
    // `-C /repo` would read as subcommand "/repo" if -C's value were not
    // skipped, and `-c core.quotepath=false` likewise.
    expect(
      _labels(<OperationRecord>[
        _record(<String>['fetch', 'origin']),
      ]),
      <String>['Fetching origin'],
    );
  });

  test('an invocation outside any queued operation is not a task', () {
    // A refresh sweep's status/for-each-ref, or another session's operation.
    expect(
      _labels(<OperationRecord>[
        _record(<String>['fetch', 'origin'], queuedOperationId: 0),
      ]),
      isEmpty,
    );
  });

  test('a finished record is not a task', () {
    expect(
      _labels(<OperationRecord>[
        _record(<String>['fetch', 'origin'], running: false),
      ]),
      isEmpty,
    );
  });

  test('a subcommand with no label is not a task', () {
    // rev-parse inside a checkout operation, say: real, but not what the user
    // asked for, and gone in milliseconds.
    expect(
      _labels(<OperationRecord>[
        _record(<String>['rev-parse', 'HEAD']),
      ]),
      isEmpty,
    );
  });

  test('a task carries the queued id its Cancel names, and is cancellable', () {
    final List<BackgroundTask> tasks = backgroundTasksFromOperationLog(
      <OperationRecord>[
        _record(<String>['push', 'origin'], id: 12, queuedOperationId: 41),
      ],
    );
    expect(tasks.single.queuedOperationId, 41);
    expect(
      tasks.single.cancellable,
      isTrue,
      reason:
          'whether it can stop is core\'s call (使用者裁定: 「實作不是用 '
          'cancellable」); the button always asks',
    );
    expect(tasks.single.total, 0, reason: 'no object counts from core');
  });

  test('foreground work comes before the folded low-priority kinds', () {
    // Spec page 10 TASKS: Prune / GC / LFS 「摺疊在 tasks 計數內」.
    expect(
      _labels(<OperationRecord>[
        _record(<String>['gc'], id: 1, queuedOperationId: 1),
        _record(<String>['fetch', 'origin'], id: 2, queuedOperationId: 2),
      ]),
      <String>['Fetching origin', 'Collecting garbage'],
    );
  });

  test('worktree add/remove are foreground; prune, lock and unlock fold', () {
    expect(
      _labels(<OperationRecord>[
        _record(<String>['worktree', 'prune'], id: 1, queuedOperationId: 1),
        _record(
          <String>['worktree', 'lock', '/a'],
          id: 2,
          queuedOperationId: 2,
        ),
        _record(
          <String>['worktree', 'remove', '/b'],
          id: 3,
          queuedOperationId: 3,
        ),
        _record(
          <String>['worktree', 'unlock', '/c'],
          id: 4,
          queuedOperationId: 4,
        ),
        _record(<String>['worktree', 'add', '/d'], id: 5, queuedOperationId: 5),
      ]),
      <String>[
        'Removing worktree',
        'Adding worktree',
        'Pruning worktrees',
        'Locking worktree',
        'Unlocking worktree',
      ],
    );
  });

  test('a worktree read inside an operation is not a task', () {
    expect(
      _labels(<OperationRecord>[
        _record(<String>['worktree', 'list', '--porcelain']),
      ]),
      isEmpty,
    );
  });

  // 使用者裁定 2026-10-24 on spec P11 item 9 「只在 status bar 的 +N task
  // 內顯示」: 「可折」, alone it is the main item like Prune (「單獨時當主項
  // 目」), labelled 「Auto fetch」.
  test('an auto fetch folds behind foreground work, labelled Auto fetch', () {
    expect(
      _labels(<OperationRecord>[
        _record(
          <String>[
            'fetch',
            '--progress',
            '--no-auto-maintenance',
            '--no-write-fetch-head',
            '--all',
          ],
          id: 1,
          queuedOperationId: 1,
        ),
        _record(
          <String>['push', '--progress', 'origin'],
          id: 2,
          queuedOperationId: 2,
        ),
      ]),
      <String>['Pushing origin', 'Auto fetch'],
    );
  });

  test('a manual fetch stays a foreground Fetching task', () {
    expect(
      _labels(<OperationRecord>[
        _record(
          <String>['fetch', '--progress', '--all'],
          id: 1,
          queuedOperationId: 1,
        ),
        _record(
          <String>['push', '--progress', 'origin'],
          id: 2,
          queuedOperationId: 2,
        ),
      ]),
      <String>['Fetching', 'Pushing origin'],
    );
  });
}
