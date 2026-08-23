import 'operation_record.dart';
import 'remote_prune_preview_entry.dart';

/// Builds the [AppLogEntry] lines spec page 10's `LOGRULES` 記什麼 row asks
/// for: 「應用層事件（開啟 repo、切分支、prune 掉哪些 ref）」, plus the
/// gone-marking warning page 10's own mockup draws.
///
/// A factory rather than four `AppLogEntry(...)` literals scattered through
/// [RepoSessionController], for two reasons that are not style:
///
///  * The wording is the product surface. These strings are copied into bug
///    reports verbatim (`LOGRULES` 匯出: 「回報問題時附這份即可」), so they
///    are worth pinning in tests, and a test cannot pin a literal buried in
///    an event handler that only a live FFI session can reach --
///    `repositoryOpened` in particular is emitted on a path
///    `FakeRepoSessionController` never executes, because its
///    `FakeGbmBindings.sessionOpen()` returns `nullptr` by design.
///  * `LOGRULES`' 不記什麼 row (認證資訊、remote URL 中的 token、檔案內容)
///    is a rule about what may appear in a log line. One place that builds
///    every line is one place to check it. Note what these take: a work-tree
///    path, a branch name, a *remote name* and ref names -- never a remote
///    URL, which is where a token would live.
abstract final class AppLogEvents {
  /// 「開啟 repo」. The work tree, not the git dir: it is what the window
  /// title and the repository switcher show, so it is what the reader will
  /// recognise.
  static AppLogEntry repositoryOpened(
    String workDir, {
    required int atEpochMs,
  }) {
    return AppLogEntry(
      whenEpochMs: atEpochMs,
      level: OperationLogLevel.info,
      message: 'Opened repository $workDir',
    );
  }

  /// 「切分支」. Says which of checkout's three shapes happened, because
  /// "Checked out abc1234" and "Created branch x at abc1234" are different
  /// events to anyone reading back what they did.
  static AppLogEntry branchCheckedOut({
    required String target,
    required bool detach,
    required bool createBranch,
    required String newBranchName,
    required int atEpochMs,
  }) {
    final String message;
    if (createBranch && newBranchName.isNotEmpty) {
      message = 'Created branch $newBranchName at $target and checked it out';
    } else if (detach) {
      message = 'Checked out $target (detached HEAD)';
    } else {
      message = 'Checked out $target';
    }
    return AppLogEntry(
      whenEpochMs: atEpochMs,
      level: OperationLogLevel.info,
      message: message,
    );
  }

  /// Page 10's mockup row, which it draws at warning level:
  /// 「origin/graph-lanes 已不存在於遠端，標記為 gone（尚未 prune）」.
  ///
  /// Warning, not error: nothing failed. It is the first of spec page 02's
  /// three stages, and saying "not pruned" in the line itself is what stops
  /// a reader assuming the ref is already gone from disk.
  ///
  /// Written in English like every other string in this app. The spec's
  /// wording is Chinese because the spec is; the app's UI is not.
  static AppLogEntry remoteRefGone(String ref, {required int atEpochMs}) {
    return AppLogEntry(
      whenEpochMs: atEpochMs,
      level: OperationLogLevel.warning,
      message:
          '${shortRemoteRefName(ref)} no longer exists on the remote; '
          'marked as gone (not pruned)',
    );
  }

  /// 「prune 掉哪些 ref」 -- the row names them, because "which" is the whole
  /// point of that clause. The count is stated too so a long list is still
  /// readable at a glance.
  ///
  /// [refs] may arrive in either form (the Prune dialog sends short names,
  /// `sidebar_panel.dart` sends full ones), so it is normalised for display.
  static AppLogEntry refsPruned({
    required String remote,
    required List<String> refs,
    required int atEpochMs,
  }) {
    final List<String> names = refs
        .map(shortRemoteRefName)
        .toList(growable: false);
    final String noun = names.length == 1
        ? 'remote-tracking ref'
        : 'remote-tracking refs';
    return AppLogEntry(
      whenEpochMs: atEpochMs,
      level: OperationLogLevel.info,
      message: 'Pruned ${names.length} $noun on $remote: ${names.join(', ')}',
    );
  }
}
