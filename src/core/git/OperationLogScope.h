#pragma once

#include <filesystem>
#include <span>
#include <string>

namespace gbm {

/// Whether an operation-log record belongs to an open session.
///
/// gbm::Log's operation sink is process-wide and knows nothing of sessions,
/// so Session fans each record out by `recordRepoDir` -- the UTF-8 directory
/// its git command ran in (`OperationRecord::repoDir`). `sessionDirs` is
/// every directory a session's own commands run in: its work tree (or git
/// dir, for a bare repository) and each linked worktree it last listed,
/// since `attachPendingCounts` runs `git status` in those.
///
/// Compared through `fsutil::canonicalKey`, so a trailing separator or, on a
/// case-insensitive filesystem, a case difference is still the same
/// directory. When no string matches, `fsutil::resolvedDirId` decides, so a
/// path reached through a symlinked parent (macOS /var vs /private/var), a
/// link to the directory itself, or an 8.3 alias names the directory git
/// reports by its resolved path.
///
/// An empty `recordRepoDir` belongs to no session: clone, init and the
/// git-version probe run with no directory, and clone's argv carries the
/// remote URL, which is where a token would be.
bool recordBelongsToSession(const std::string& recordRepoDir,
                            std::span<const std::filesystem::path> sessionDirs);

}  // namespace gbm
