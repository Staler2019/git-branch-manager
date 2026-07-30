#pragma once

#include "core/git/RepoPaths.h"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>

namespace gbm {

enum class RepoKind : std::uint8_t {
    NotARepo = 0xFF,
    Normal = 0,
    Bare = 1,
    LinkedWorktree = 2,
    Submodule = 3,
};

struct ClassifiedRepo {
    RepoKind kind = RepoKind::NotARepo;
    RepoPaths paths;
    bool unreadable = false;  ///< Looks like a repo but we could not read it.

    bool isRepo() const noexcept { return kind != RepoKind::NotARepo; }
};

/// Decides whether a directory is a git repository, and what sort.
///
/// The whole point is that this must be cheap. A scan may consider 200,000
/// candidate directories, so classification uses two or three stats plus (at
/// most) one small file read. Running an actual git command per directory — even
/// a fast one — turns a 15-second scan into many minutes.
class RepoClassifier {
public:
    /// `directory` is the candidate. Also resolves `.git` pointer files, which is
    /// how linked worktrees and submodules are told apart from a normal checkout.
    static ClassifiedRepo classify(const std::filesystem::path& directory);

    /// Reads a `.git` file's `gitdir: <path>` target, resolving it relative to
    /// `containingDir` when it is not absolute.
    static std::optional<std::filesystem::path> resolveGitDirFile(
        const std::filesystem::path& gitFile, const std::filesystem::path& containingDir);

    /// Finds `$GIT_COMMON_DIR` for a git directory. For a linked worktree this is
    /// the parent repository's git directory, read from the `commondir` file.
    static std::filesystem::path resolveCommonDir(const std::filesystem::path& gitDir);

    /// True when a directory has the shape of a bare repository.
    static bool looksBare(const std::filesystem::path& directory);
};

}  // namespace gbm
