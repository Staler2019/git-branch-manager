/// Typed route path/name constants -- see app_router.dart for the actual
/// GoRouter route table this backs, and the plan's routing-table section for
/// the full design (including routes not yet implemented: diff, conflicts,
/// the 30+ dialogs).
abstract final class RoutePaths {
  static const String repoList = '/';
  static const String workspace = '/repo/:repoId';
  static const String history = '/repo/:repoId/history';
  static const String workingCopy = '/repo/:repoId/working-copy';

  static String workspaceFor(String repoId) => historyFor(repoId);
  static String historyFor(String repoId) => '/repo/$repoId/history';
  static String workingCopyFor(String repoId) => '/repo/$repoId/working-copy';
}
