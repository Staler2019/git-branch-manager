import '../../actions/gbm_sequencer_operation.dart';
import '../../data/models/operation_record.dart';
import 'background_task.dart';

/// The status bar's tasks for git work that is running right now: one per
/// running [OperationRecord] that belongs to a queued operation of this
/// session ([OperationRecord.queuedOperationId] != 0).
///
/// The queued id is the whole filter. Core gives a session a non-zero id only
/// for operations its own queue runs, and reads -- refresh sweeps, previews,
/// `stash show`, `remote prune --dry-run` -- never run in one. So "the user's
/// action is running" needs no list of read-only argv shapes to keep in sync.
///
/// Derived, not tracked: the outcome record replaces its running row
/// (`RepoSessionState.withOperationRecord`), so a task cannot outlive the
/// invocation that owns it.
///
/// Every task's Cancel is enabled. Whether a running unit can stop is core's
/// decision (使用者裁定 2026-10-15: 「實作不是用 cancellable…吃
/// cancellationToken…capi不行cancel會拋錯」); a refusal comes back as an error.
///
/// `total` is 0: core reports no object counts (使用者裁定: 計數「改spec，
/// 沒有計畫」), so the bar is indeterminate.
List<BackgroundTask> backgroundTasksFromOperationLog(List<GbmLogEntry> log) {
  final List<BackgroundTask> foreground = <BackgroundTask>[];
  final List<BackgroundTask> folded = <BackgroundTask>[];
  for (final GbmLogEntry entry in log) {
    if (entry is! OperationRecord ||
        !entry.running ||
        entry.queuedOperationId == 0) {
      continue;
    }
    final List<String> args = _commandArgs(entry.argv);
    if (args.isEmpty) continue;
    final (String label, bool isFolded)? kind = _taskKind(args);
    if (kind == null) continue;
    (kind.$2 ? folded : foreground).add(
      BackgroundTask.gitCommand(
        id: 'git-${entry.id}',
        label: kind.$1,
        queuedOperationId: entry.queuedOperationId,
      ),
    );
  }
  return <BackgroundTask>[...foreground, ...folded];
}

/// The command's own arguments, subcommand first: argv minus the executable,
/// `GitCommand::globalFlags()`, and `-C <dir>`/`-c <key=value>` wherever they
/// sit before the subcommand (`ProcessRunner.cpp`'s `buildArgv`).
List<String> _commandArgs(List<String> argv) {
  int i = 1;
  while (i < argv.length) {
    final String arg = argv[i];
    if (arg == '-C' || arg == '-c') {
      i += 2;
    } else if (arg.startsWith('-')) {
      i += 1;
    } else {
      break;
    }
  }
  return i < argv.length ? argv.sublist(i) : const <String>[];
}

/// The first positional argument after the subcommand, or null.
String? _firstPositional(List<String> args) {
  for (final String arg in args.skip(1)) {
    if (!arg.startsWith('-')) return arg;
  }
  return null;
}

/// Label, and whether spec page 10 TASKS folds it (Prune / GC / LFS
/// 「摺疊在 tasks 計數內」; stash and commit are folded with them). Null for a
/// subcommand that is not the user's action -- a rev-parse inside a checkout.
(String, bool)? _taskKind(List<String> args) {
  final String? remote = _firstPositional(args);
  return switch (args.first) {
    'fetch' => (remote == null ? 'Fetching' : 'Fetching $remote', false),
    'pull' => ('Pulling', false),
    'push' => (remote == null ? 'Pushing' : 'Pushing $remote', false),
    'checkout' || 'switch' => ('Checking out', false),
    'merge' => (SequencerOperationKind.merge.gerund, false),
    'rebase' => (SequencerOperationKind.rebase.gerund, false),
    'cherry-pick' => (SequencerOperationKind.cherryPick.gerund, false),
    'revert' => (SequencerOperationKind.revert.gerund, false),
    'gc' => ('Collecting garbage', true),
    'lfs' => ('LFS', true),
    'remote' when args.length > 1 && args[1] == 'prune' => (
      args.length > 2 ? 'Pruning ${args[2]}' : 'Pruning',
      true,
    ),
    'stash' => ('Stashing', true),
    'commit' => ('Committing', true),
    'worktree' when args.length > 1 => _worktreeTaskKind(args[1]),
    _ => null,
  };
}

/// TASKS has no worktree row. 使用者裁定 2026-10-21: add and remove rewrite
/// a working tree, so they show like Checkout; prune, lock and unlock fold
/// like Prune. `list` is a read, not the user's action.
(String, bool)? _worktreeTaskKind(String subcommand) => switch (subcommand) {
  'add' => ('Adding worktree', false),
  'remove' => ('Removing worktree', false),
  'prune' => ('Pruning worktrees', true),
  'lock' => ('Locking worktree', true),
  'unlock' => ('Unlocking worktree', true),
  _ => null,
};
