#include "core/base/Error.h"

#include <algorithm>
#include <array>
#include <cctype>

namespace gbm {

namespace {

bool containsInsensitive(std::string_view haystack, std::string_view needle) {
    if (needle.size() > haystack.size()) {
        return false;
    }
    const auto it = std::search(
        haystack.begin(),
        haystack.end(),
        needle.begin(),
        needle.end(),
        [](unsigned char a, unsigned char b) { return std::tolower(a) == std::tolower(b); });
    return it != haystack.end();
}

struct Pattern {
    std::string_view needle;
    GitError::Code code;
    std::string_view summary;
};

// Ordered most-specific first: the first match wins. These are the failures a
// user actually hits, each mapped to a message that says what to do rather than
// echoing git's phrasing.
constexpr std::array kPatterns{
    Pattern{"unable to create", GitError::Code::LockHeld, "Could not create a Git lock file"},
    Pattern{"index.lock",
            GitError::Code::LockHeld,
            "Another Git process appears to be running in this repository"},
    Pattern{"cannot lock ref", GitError::Code::LockHeld, "Could not lock a Git reference"},
    Pattern{"would be overwritten by",
            GitError::Code::DirtyWorkTree,
            "Local changes would be overwritten"},
    Pattern{"local changes to the following files",
            GitError::Code::DirtyWorkTree,
            "Local changes would be overwritten"},
    Pattern{"please commit your changes or stash them",
            GitError::Code::DirtyWorkTree,
            "Commit or stash your changes first"},
    Pattern{
        "you have unstaged changes", GitError::Code::DirtyWorkTree, "You have unstaged changes"},
    Pattern{"conflict", GitError::Code::Conflict, "The operation stopped with conflicts"},
    Pattern{"after resolving the conflicts",
            GitError::Code::Conflict,
            "The operation stopped with conflicts"},
    Pattern{"non-fast-forward",
            GitError::Code::NonFastForward,
            "The remote has commits you do not have locally"},
    Pattern{"fetch first",
            GitError::Code::NonFastForward,
            "The remote has commits you do not have locally"},
    Pattern{"not possible to fast-forward",
            GitError::Code::NonFastForward,
            "Cannot fast-forward: the branches have diverged"},
    Pattern{"host key verification failed",
            GitError::Code::HostKey,
            "The server's host key could not be verified"},
    Pattern{"authenticity of host", GitError::Code::HostKey, "Unknown SSH host key"},
    Pattern{"authentication failed", GitError::Code::Auth, "Authentication failed"},
    Pattern{"could not read username", GitError::Code::Auth, "Git needs credentials"},
    Pattern{"permission denied (publickey", GitError::Code::Auth, "SSH key was rejected"},
    Pattern{"terminal prompts disabled", GitError::Code::Auth, "Git needs credentials"},
    Pattern{"pre-commit hook", GitError::Code::HookRejected, "A pre-commit hook rejected this"},
    Pattern{"commit-msg hook", GitError::Code::HookRejected, "A commit-msg hook rejected this"},
    Pattern{"hook declined", GitError::Code::HookRejected, "A Git hook rejected this"},
    Pattern{"nothing to commit",
            GitError::Code::InvalidArgument,
            "There is nothing staged to commit"},
    Pattern{"nothing added to commit",
            GitError::Code::InvalidArgument,
            "There is nothing staged to commit"},
    Pattern{"patch does not apply",
            GitError::Code::Conflict,
            "This change no longer matches the file; refresh and try again"},
    Pattern{"patch failed",
            GitError::Code::Conflict,
            "This change no longer matches the file; refresh and try again"},
    Pattern{"did not match any file", GitError::Code::NotFound, "No matching ref or path"},
    Pattern{"unknown revision", GitError::Code::NotFound, "Unknown revision"},
    Pattern{"not a git repository", GitError::Code::NotFound, "Not a Git repository"},
    Pattern{"bad object", GitError::Code::NotFound, "No such object"},
    Pattern{"does not exist", GitError::Code::NotFound, "Not found"},
    Pattern{"object file is empty", GitError::Code::Corrupt, "The repository has a corrupt object"},
    Pattern{"loose object", GitError::Code::Corrupt, "The repository has a corrupt object"},
    Pattern{"unknown option",
            GitError::Code::Unsupported,
            "This Git version does not support an option we used"},
    Pattern{"timed out", GitError::Code::Timeout, "The operation timed out"},
};

}  // namespace

std::string_view toString(GitError::Code code) {
    switch (code) {
        case GitError::Code::Unknown:
            return "Unknown";
        case GitError::Code::NotFound:
            return "NotFound";
        case GitError::Code::InvalidArgument:
            return "InvalidArgument";
        case GitError::Code::Conflict:
            return "Conflict";
        case GitError::Code::LockHeld:
            return "LockHeld";
        case GitError::Code::Auth:
            return "Auth";
        case GitError::Code::HostKey:
            return "HostKey";
        case GitError::Code::NonFastForward:
            return "NonFastForward";
        case GitError::Code::DirtyWorkTree:
            return "DirtyWorkTree";
        case GitError::Code::HookRejected:
            return "HookRejected";
        case GitError::Code::Cancelled:
            return "Cancelled";
        case GitError::Code::ProcessFailed:
            return "ProcessFailed";
        case GitError::Code::SpawnFailed:
            return "SpawnFailed";
        case GitError::Code::ParseError:
            return "ParseError";
        case GitError::Code::Corrupt:
            return "Corrupt";
        case GitError::Code::Unsupported:
            return "Unsupported";
        case GitError::Code::Timeout:
            return "Timeout";
        case GitError::Code::TooLarge:
            return "TooLarge";
        case GitError::Code::Database:
            return "Database";
        case GitError::Code::Io:
            return "Io";
    }
    return "Unknown";
}

GitError classifyGitStderr(std::string_view stderrText, int exitCode) {
    for (const auto& pattern : kPatterns) {
        if (containsInsensitive(stderrText, pattern.needle)) {
            GitError error(pattern.code, std::string(pattern.summary), std::string(stderrText));
            error.exitCode = exitCode;
            return error;
        }
    }

    GitError error(GitError::Code::ProcessFailed, "Git reported an error", std::string(stderrText));
    error.exitCode = exitCode;
    return error;
}

}  // namespace gbm
