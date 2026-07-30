#include "core/discovery/RepoClassifier.h"

#include "core/base/FsUtil.h"

#include <algorithm>
#include <system_error>

namespace gbm {

namespace {

bool isDirectory(const std::filesystem::path& path) {
    std::error_code ec;
    return std::filesystem::is_directory(fsutil::longPathSafe(path), ec);
}

bool isRegularFile(const std::filesystem::path& path) {
    std::error_code ec;
    return std::filesystem::is_regular_file(fsutil::longPathSafe(path), ec);
}

/// Normalises a resolved path: `lexically_normal()` leaves a trailing separator
/// behind for inputs like "gitdir/../..", and that stray slash would make
/// gitDir != commonDir compare unequal for a plain checkout — silently turning
/// every repository into a "linked worktree".
std::filesystem::path normalizeDir(const std::filesystem::path& path) {
    std::filesystem::path normalized = path.lexically_normal();
    const std::string text = normalized.generic_string();
    if (text.size() > 1 && text.back() == '/') {
        return std::filesystem::path(text.substr(0, text.size() - 1));
    }
    return normalized;
}

std::string trimmed(std::string text) {
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r' || text.back() == ' ')) {
        text.pop_back();
    }
    std::size_t start = 0;
    while (start < text.size() && (text[start] == ' ' || text[start] == '\t')) {
        ++start;
    }
    return text.substr(start);
}

}  // namespace

std::optional<std::filesystem::path> RepoClassifier::resolveGitDirFile(
    const std::filesystem::path& gitFile, const std::filesystem::path& containingDir) {
    auto contents = fsutil::readSmallFile(gitFile, 4096);
    if (!contents) {
        return std::nullopt;
    }
    const std::string text = trimmed(std::move(*contents));
    constexpr std::string_view kPrefix = "gitdir:";
    if (text.rfind(kPrefix, 0) != 0) {
        return std::nullopt;
    }

    std::filesystem::path target(trimmed(text.substr(kPrefix.size())));
    if (target.empty()) {
        return std::nullopt;
    }
    if (target.is_relative()) {
        target = containingDir / target;
    }
    return normalizeDir(target);
}

std::filesystem::path RepoClassifier::resolveCommonDir(const std::filesystem::path& gitDir) {
    // A linked worktree's git dir holds a `commondir` file pointing at the
    // shared directory. Getting this wrong is how tools end up reading the wrong
    // HEAD for a worktree, so it is resolved once, here.
    const auto commonDirFile = gitDir / "commondir";
    if (auto contents = fsutil::readSmallFile(commonDirFile, 4096)) {
        std::filesystem::path target(trimmed(std::move(*contents)));
        if (!target.empty()) {
            if (target.is_relative()) {
                target = gitDir / target;
            }
            return normalizeDir(target);
        }
    }
    return normalizeDir(gitDir);
}

bool RepoClassifier::looksBare(const std::filesystem::path& directory) {
    // The shape of a bare repository: HEAD plus objects/ plus refs/. Checking the
    // shape rather than running `git rev-parse --is-bare-repository` is what keeps
    // classification to a few stats.
    if (!isRegularFile(directory / "HEAD")) {
        return false;
    }
    if (!isDirectory(directory / "objects") || !isDirectory(directory / "refs")) {
        return false;
    }
    // `core.bare = true` confirms it, but a mirror clone directory named
    // `<name>.git` with the right shape is bare in practice even if the config is
    // unreadable.
    if (auto config = fsutil::readSmallFile(directory / "config", 256 * 1024)) {
        if (config->find("bare = true") != std::string::npos) {
            return true;
        }
        if (config->find("bare = false") != std::string::npos) {
            return false;
        }
    }
    return directory.extension() == ".git";
}

ClassifiedRepo RepoClassifier::classify(const std::filesystem::path& directory) {
    ClassifiedRepo result;

    const auto dotGit = directory / ".git";

    // --- a normal checkout: .git is a directory containing HEAD --------------
    if (isDirectory(dotGit)) {
        if (!isRegularFile(dotGit / "HEAD")) {
            // A directory called .git that is not a git directory. Rare, but
            // treating it as a repository would produce a broken entry.
            result.unreadable = true;
            return result;
        }
        result.kind = RepoKind::Normal;
        result.paths = RepoPaths(directory, dotGit, resolveCommonDir(dotGit));
        return result;
    }

    // --- .git is a file: a linked worktree, or a submodule ------------------
    if (isRegularFile(dotGit)) {
        auto gitDir = resolveGitDirFile(dotGit, directory);
        if (!gitDir) {
            result.unreadable = true;
            return result;
        }
        if (!isDirectory(*gitDir)) {
            // Points somewhere that no longer exists: a worktree whose parent
            // repository was deleted, or an uninitialised submodule.
            result.unreadable = true;
            return result;
        }

        const std::filesystem::path commonDir = resolveCommonDir(*gitDir);
        const std::string gitDirText = gitDir->generic_string();

        // The target path tells us which case this is: `.../worktrees/<name>` for
        // a linked worktree, `.../modules/<name>` for a submodule.
        if (gitDirText.find("/worktrees/") != std::string::npos) {
            result.kind = RepoKind::LinkedWorktree;
        } else if (gitDirText.find("/modules/") != std::string::npos) {
            result.kind = RepoKind::Submodule;
        } else {
            result.kind = RepoKind::Normal;
        }
        result.paths = RepoPaths(directory, *gitDir, commonDir);
        return result;
    }

    // --- the directory itself is a bare repository --------------------------
    if (looksBare(directory)) {
        result.kind = RepoKind::Bare;
        result.paths = RepoPaths({}, directory, resolveCommonDir(directory));
        return result;
    }

    return result;
}

}  // namespace gbm
