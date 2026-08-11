/// Identifies one repository to open a session for -- the FFI equivalent of
/// a `repoId` route parameter (see the plan's routing table). `commonDir`
/// empty means "same as gitDir" (a normal, non-worktree checkout), matching
/// `RepoPaths`'s own default (src/core/git/RepoPaths.h).
class RepoIdentity {
  const RepoIdentity({required this.workDir, required this.gitDir, this.commonDir = ''});

  factory RepoIdentity.forWorkDir(String workDir) =>
      RepoIdentity(workDir: workDir, gitDir: '$workDir/.git');

  final String workDir;
  final String gitDir;
  final String commonDir;

  @override
  bool operator ==(Object other) =>
      other is RepoIdentity &&
      other.workDir == workDir &&
      other.gitDir == gitDir &&
      other.commonDir == commonDir;

  @override
  int get hashCode => Object.hash(workDir, gitDir, commonDir);

  @override
  String toString() => 'RepoIdentity($workDir)';
}
