#pragma once

#include "core/base/Error.h"

#include <filesystem>
#include <string>
#include <vector>

namespace gbm {

struct GitVersion {
    int major = 0;
    int minor = 0;
    int patch = 0;

    std::string toString() const {
        return std::to_string(major) + "." + std::to_string(minor) + "." + std::to_string(patch);
    }

    friend bool operator<(const GitVersion& a, const GitVersion& b) {
        if (a.major != b.major) return a.major < b.major;
        if (a.minor != b.minor) return a.minor < b.minor;
        return a.patch < b.patch;
    }

    friend bool operator>=(const GitVersion& a, const GitVersion& b) { return !(a < b); }

    static GitVersion parse(std::string_view versionOutput);
};

/// What the resolved git supports. Because the entire backend is the git CLI,
/// the user's git version is a hard capability boundary — we detect it once and
/// degrade features explicitly rather than letting commands fail mysteriously.
struct GitCapabilities {
    bool fsMonitor = false;           ///< core.fsmonitor built-in daemon (>= 2.37)
    bool mergeTreeWriteTree = false;  ///< `merge-tree --write-tree` preview (>= 2.38)
    bool commitGraphSplit = false;    ///< `commit-graph write --split` (>= 2.24)
    bool changedPathBloom = false;    ///< `--changed-paths` bloom filters (>= 2.24)
    bool sparseIndex = false;         ///< sparse index support (>= 2.32)
};

struct GitInstallation {
    std::filesystem::path executable;
    GitVersion version;
    GitCapabilities capabilities;

    /// Lowest version we will run against at all. Below this, porcelain=v2 and
    /// several `-z` output forms we depend on are missing or differ.
    static constexpr GitVersion minimumSupported() { return {2, 30, 0}; }

    bool isUsable() const { return !executable.empty() && version >= minimumSupported(); }

    /// Warnings to surface in Settings: the app works, but with reduced
    /// performance or missing features.
    std::vector<std::string> warnings() const;
};

/// Locates the git executable and interrogates its version.
///
/// The app never bundles git. Detection order is deliberate, and an explicit
/// user-configured path always wins so someone with several gits installed
/// (Git for Windows, Scoop, WSL) can pin the right one.
class GitExecutable {
public:
    /// `preferred` is the user's configured path; may be empty.
    static GitResult<GitInstallation> detect(const std::filesystem::path& preferred = {});

    /// Runs `<candidate> --version` and parses the result.
    static GitResult<GitInstallation> probe(const std::filesystem::path& candidate);

    /// Candidate locations, in priority order, for the current platform.
    static std::vector<std::filesystem::path> searchPath();

private:
    static GitCapabilities capabilitiesFor(const GitVersion& version);
};

}  // namespace gbm
