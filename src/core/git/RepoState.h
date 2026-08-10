#pragma once

#include "core/git/RepoPaths.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace gbm {

/// Text for the state/conflict banner MainWindow shows above the working
/// copy. Separate from RepoState::describe() (which stays as the short,
/// state-only label existing callers rely on) because the banner needs more:
/// a conflict count, an instruction, and a decision on whether to show at
/// all when there is no sequencer state but the work tree still has
/// conflicts (see buildStateBannerText()).
struct StateBannerText {
    std::string headline;
    std::string instruction;
    bool isConflict = false;
};

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

/// Builds the banner text MainWindow shows for `state`.
///
/// `conflictedFileCount` is nullopt when the working copy status hasn't
/// loaded yet (StartupReadGate can hold that scan back for tens of seconds
/// on a large repository) -- in that case the banner may still describe an
/// in-progress sequencer operation, but must never state a conflict count,
/// since a stale "0 files" would be a lie the moment the real status arrives.
///
/// A conflict count greater than zero produces a headline even when `state`
/// has no sequencer flags set at all: `git apply --3way` leaves conflict
/// markers in the work tree without writing any sequencer state file, so
/// RepoState alone can't see it.
StateBannerText buildStateBannerText(const RepoState& state,
                                     std::optional<std::size_t> conflictedFileCount);

}  // namespace gbm
