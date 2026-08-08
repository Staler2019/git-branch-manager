#include "core/git/RepoState.h"

#include "core/base/FsUtil.h"

#include <charconv>
#include <chrono>
#include <system_error>

namespace gbm {

namespace {

bool pathExists(const std::filesystem::path& path) {
    std::error_code ec;
    return std::filesystem::exists(fsutil::longPathSafe(path), ec);
}

int readIntFile(const std::filesystem::path& path) {
    auto contents = fsutil::readSmallFile(path, 64);
    if (!contents) {
        return 0;
    }
    int value = 0;
    std::string_view text(*contents);
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r' || text.back() == ' ')) {
        text.remove_suffix(1);
    }
    std::from_chars(text.data(), text.data() + text.size(), value);
    return value;
}

std::string readTrimmedFile(const std::filesystem::path& path) {
    auto contents = fsutil::readSmallFile(path, 4096);
    if (!contents) {
        return {};
    }
    std::string text = std::move(*contents);
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r')) {
        text.pop_back();
    }
    return text;
}

}  // namespace

RepoState RepoState::read(const RepoPaths& paths) {
    RepoState state;
    if (!paths.isValid()) {
        return state;
    }

    // Each of these is a single stat. All live in gitDir(), not commonDir(): a
    // rebase in one linked worktree must not appear as in-progress in another.
    if (pathExists(paths.mergeHeadFile())) {
        state.flags |= Merge;
    }
    if (pathExists(paths.cherryPickHeadFile())) {
        state.flags |= CherryPick;
    }
    if (pathExists(paths.revertHeadFile())) {
        state.flags |= Revert;
    }
    if (pathExists(paths.bisectLogFile())) {
        state.flags |= Bisect;
    }
    if (pathExists(paths.sequencerDir() / "todo")) {
        state.flags |= Sequencer;
    }

    if (pathExists(paths.rebaseMergeDir())) {
        state.flags |= RebaseMerge;
        state.rebaseStep = readIntFile(paths.rebaseMergeDir() / "msgnum");
        state.rebaseTotal = readIntFile(paths.rebaseMergeDir() / "end");
        state.rebaseOntoLabel = readTrimmedFile(paths.rebaseMergeDir() / "onto_name");
        if (state.rebaseOntoLabel.empty()) {
            state.rebaseOntoLabel = readTrimmedFile(paths.rebaseMergeDir() / "onto");
        }
    }
    if (pathExists(paths.rebaseApplyDir())) {
        state.flags |= RebaseApply;
        state.rebaseStep = readIntFile(paths.rebaseApplyDir() / "next");
        state.rebaseTotal = readIntFile(paths.rebaseApplyDir() / "last");
    }

    const auto lockPath = paths.indexLockFile();
    if (pathExists(lockPath)) {
        state.indexLocked = true;
        if (auto mtime = fsutil::modifiedTimeNs(lockPath)) {
            const auto nowNs = std::chrono::duration_cast<std::chrono::nanoseconds>(
                                   std::chrono::system_clock::now().time_since_epoch())
                                   .count();
            state.indexLockAgeSeconds = (nowNs - *mtime) / 1'000'000'000;
        }
    }

    return state;
}

std::string RepoState::describe() const {
    std::string label;
    if ((flags & RebaseMerge) != 0 || (flags & RebaseApply) != 0) {
        label = "Rebase in progress";
        if (rebaseTotal > 0) {
            label +=
                " - stopped at " + std::to_string(rebaseStep) + "/" + std::to_string(rebaseTotal);
        }
        if (!rebaseOntoLabel.empty()) {
            label += " onto " + rebaseOntoLabel;
        }
    } else if ((flags & CherryPick) != 0) {
        label = "Cherry-pick in progress";
    } else if ((flags & Revert) != 0) {
        label = "Revert in progress";
    } else if ((flags & Merge) != 0) {
        label = "Merge in progress";
    } else if ((flags & Bisect) != 0) {
        label = "Bisect in progress";
    } else if ((flags & Sequencer) != 0) {
        label = "A queued sequence of commits is in progress";
    }

    if (indexLocked) {
        if (!label.empty()) {
            label += "; ";
        }
        label += "another Git process appears to be running";
    }
    return label;
}

StateBannerText buildStateBannerText(const RepoState& state,
                                     std::optional<std::size_t> conflictedFileCount) {
    StateBannerText banner;
    banner.headline = state.describe();

    const bool hasKnownConflicts = conflictedFileCount.has_value() && *conflictedFileCount > 0;

    // `git apply --3way` leaves conflict markers in the work tree without
    // writing any sequencer state file, so describe() returns empty even
    // though there's an active conflict. Give the banner a headline anyway.
    if (banner.headline.empty() && hasKnownConflicts) {
        banner.headline = "Conflicts in the working copy";
    }

    if (banner.headline.empty()) {
        return banner;
    }

    if (hasKnownConflicts) {
        banner.isConflict = true;
        banner.headline += " — " + std::to_string(*conflictedFileCount) + " file" +
                           (*conflictedFileCount == 1 ? "" : "s") + " with conflicts";
        banner.instruction = "Resolve the conflicts, then mark them resolved before continuing.";
    }

    return banner;
}

std::vector<std::filesystem::path> RepoState::watchTargets(const RepoPaths& paths) {
    if (!paths.isValid()) {
        return {};
    }
    return {
        paths.headFile(),
        paths.indexFile(),
        paths.mergeHeadFile(),
        paths.cherryPickHeadFile(),
        paths.revertHeadFile(),
        paths.bisectLogFile(),
        paths.rebaseMergeDir(),
        paths.rebaseApplyDir(),
        paths.sequencerDir(),
        paths.refsDir(),
        paths.packedRefsFile(),
    };
}

}  // namespace gbm
