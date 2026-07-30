#pragma once

#include "core/git/RepoPaths.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace gbm {

/// Which multi-step git operation, if any, is part-way through.
///
/// This is computed from files on disk rather than tracked in memory, and that is
/// deliberate: a rebase interrupted by a conflict survives closing the app, and a
/// user may well continue it from a terminal. Anything we remembered in RAM would
/// be a lie after a restart.
struct RepoState {
    enum Flags : std::uint32_t {
        None = 0,
        Merge = 1u << 0,
        CherryPick = 1u << 1,
        Revert = 1u << 2,
        RebaseMerge = 1u << 3,  ///< Interactive or merge-based rebase.
        RebaseApply = 1u << 4,  ///< `git am` or the older rebase backend.
        Bisect = 1u << 5,
        Sequencer = 1u << 6,  ///< A multi-pick sequence is queued.
    };

    std::uint32_t flags = None;

    /// Rebase progress, when the backend records it.
    int rebaseStep = 0;
    int rebaseTotal = 0;
    std::string rebaseOntoLabel;

    /// True when a lock file is present, meaning another git process (a terminal,
    /// an IDE, a hook) is very likely working in this repository right now.
    bool indexLocked = false;
    /// Age of that lock, used to decide whether to offer removal at all.
    std::optional<std::int64_t> indexLockAgeSeconds;

    bool isClean() const noexcept { return flags == None; }

    bool inProgress() const noexcept { return flags != None; }

    /// True for states driven by git's sequencer, where the correct controls are
    /// continue / skip / abort rather than an ordinary commit.
    bool isSequencerOperation() const noexcept {
        return (flags & (CherryPick | Revert | RebaseMerge | RebaseApply | Sequencer)) != 0;
    }

    /// A short label for the banner, e.g. "Rebase in progress - stopped at 4/17".
    std::string describe() const;

    /// Reads the state. Only stats a handful of paths, so it is cheap enough to
    /// run on every repository open, after every operation, and on watcher events.
    static RepoState read(const RepoPaths& paths);

    /// The files worth watching to know when this state might have changed.
    /// Deliberately a short list inside .git: watching the work tree would need
    /// one watch per directory and silently cap out on a large repository.
    static std::vector<std::filesystem::path> watchTargets(const RepoPaths& paths);
};

}  // namespace gbm
