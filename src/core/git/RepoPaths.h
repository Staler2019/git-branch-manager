#pragma once

#include <filesystem>
#include <string>
#include <utility>

namespace gbm {

/// The set of directories that identify a repository.
///
/// `gitDir` and `commonDir` differ for linked worktrees: each worktree has its
/// own HEAD, index and refs/bisect, but objects, packed-refs and most refs live
/// in the shared common directory. Carrying both in one value type — and never
/// building a `.git/...` path by string concatenation — is what keeps worktree
/// support from becoming a painful retrofit later.
class RepoPaths {
public:
    RepoPaths() = default;

    RepoPaths(std::filesystem::path workDir,
              std::filesystem::path gitDir,
              std::filesystem::path commonDir)
        : workDir_(std::move(workDir)),
          gitDir_(std::move(gitDir)),
          commonDir_(commonDir.empty() ? gitDir_ : std::move(commonDir)) {}

    /// The working tree root. Empty for a bare repository.
    const std::filesystem::path& workDir() const noexcept { return workDir_; }

    /// This worktree's private git directory ($GIT_DIR).
    const std::filesystem::path& gitDir() const noexcept { return gitDir_; }

    /// The shared git directory ($GIT_COMMON_DIR). Equal to gitDir() for a
    /// normal checkout.
    const std::filesystem::path& commonDir() const noexcept { return commonDir_; }

    bool isBare() const noexcept { return workDir_.empty(); }

    bool isLinkedWorktree() const noexcept { return gitDir_ != commonDir_; }

    bool isValid() const noexcept { return !gitDir_.empty(); }

    /// The directory to pass to `git -C`. Bare repositories have no work tree,
    /// so the git directory itself is used.
    const std::filesystem::path& commandDir() const noexcept {
        return workDir_.empty() ? gitDir_ : workDir_;
    }

    // --- Per-worktree state. These live in gitDir(), never in commonDir(). ---

    std::filesystem::path headFile() const { return gitDir_ / "HEAD"; }

    std::filesystem::path indexFile() const { return gitDir_ / "index"; }

    std::filesystem::path indexLockFile() const { return gitDir_ / "index.lock"; }

    std::filesystem::path mergeHeadFile() const { return gitDir_ / "MERGE_HEAD"; }

    std::filesystem::path cherryPickHeadFile() const { return gitDir_ / "CHERRY_PICK_HEAD"; }

    std::filesystem::path revertHeadFile() const { return gitDir_ / "REVERT_HEAD"; }

    std::filesystem::path bisectLogFile() const { return gitDir_ / "BISECT_LOG"; }

    std::filesystem::path rebaseMergeDir() const { return gitDir_ / "rebase-merge"; }

    std::filesystem::path rebaseApplyDir() const { return gitDir_ / "rebase-apply"; }

    std::filesystem::path sequencerDir() const { return gitDir_ / "sequencer"; }

    // --- Shared state. These live in commonDir(). ---

    std::filesystem::path packedRefsFile() const { return commonDir_ / "packed-refs"; }

    std::filesystem::path refsDir() const { return commonDir_ / "refs"; }

    std::filesystem::path objectsDir() const { return commonDir_ / "objects"; }

    std::filesystem::path worktreesDir() const { return commonDir_ / "worktrees"; }

    std::filesystem::path configFile() const { return commonDir_ / "config"; }

    std::filesystem::path shallowFile() const { return commonDir_ / "shallow"; }

    /// The single-file commit-graph. Lives under commonDir(): the object store
    /// is shared across linked worktrees, so every worktree sees one graph.
    std::filesystem::path commitGraphFile() const { return objectsDir() / "info" / "commit-graph"; }

    /// The split commit-graph chain (`commit-graph write --split`, git >= 2.24).
    /// A repository has one form or the other, never both.
    std::filesystem::path commitGraphChainFile() const {
        return objectsDir() / "info" / "commit-graphs" / "commit-graph-chain";
    }

    /// A human-facing name for the repository, derived from the work tree (or
    /// the git directory for bare repos).
    std::string displayName() const {
        if (!workDir_.empty()) {
            return workDir_.filename().string();
        }
        std::string name = gitDir_.filename().string();
        if (name == ".git" && gitDir_.has_parent_path()) {
            return gitDir_.parent_path().filename().string();
        }
        return name;
    }

private:
    std::filesystem::path workDir_;
    std::filesystem::path gitDir_;
    std::filesystem::path commonDir_;
};

}  // namespace gbm
