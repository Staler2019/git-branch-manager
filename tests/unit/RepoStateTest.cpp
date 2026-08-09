// buildStateBannerText() turns a RepoState plus an optionally-known conflict
// count into the banner text MainWindow shows. See RepoState.h for why the
// conflict count is std::optional rather than a plain size_t: StartupReadGate
// can hold the cold `git status` scan back for tens of seconds on a large
// repository, so the banner must be able to render before that count is known
// without ever claiming a count it doesn't have.
#include "core/git/RepoState.h"

#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

TEST(BuildStateBannerText, MergeWithKnownConflictsProducesHeadlineAndInstruction) {
    RepoState state;
    state.flags = RepoState::Merge;

    const StateBannerText banner = buildStateBannerText(state, /*conflictedFileCount=*/3);

    EXPECT_NE(banner.headline.find("Merge"), std::string::npos);
    EXPECT_NE(banner.headline.find('3'), std::string::npos);
    EXPECT_FALSE(banner.instruction.empty());
    // Design C2: the instruction now points at the banner's own Resolve
    // Conflicts entry point rather than describing the (removed) embedded
    // panel in the abstract -- see MainWindow's bannerResolveButton_.
    EXPECT_NE(banner.instruction.find("Resolve Conflicts"), std::string::npos);
    EXPECT_TRUE(banner.isConflict);
}

TEST(BuildStateBannerText, RebaseWithNoConflictsHasNoConflictInstruction) {
    RepoState state;
    state.flags = RepoState::RebaseMerge;
    state.rebaseStep = 4;
    state.rebaseTotal = 17;

    const StateBannerText banner = buildStateBannerText(state, /*conflictedFileCount=*/0);

    EXPECT_NE(banner.headline.find("Rebase"), std::string::npos);
    EXPECT_TRUE(banner.instruction.empty());
    EXPECT_FALSE(banner.isConflict);
}

TEST(BuildStateBannerText, NoSequencerStateButConflictedFilesStillProducesHeadline) {
    // `git apply --3way` leaves conflict markers in the work tree without
    // writing any sequencer state file, so flags stays None. The banner must
    // still appear -- this is the second half of issue #20.
    RepoState state;
    state.flags = RepoState::None;

    const StateBannerText banner = buildStateBannerText(state, /*conflictedFileCount=*/2);

    EXPECT_FALSE(banner.headline.empty());
    EXPECT_NE(banner.headline.find('2'), std::string::npos);
    EXPECT_TRUE(banner.isConflict);
}

TEST(BuildStateBannerText, CleanStateWithNoConflictsProducesEmptyHeadline) {
    RepoState state;
    state.flags = RepoState::None;

    const StateBannerText banner = buildStateBannerText(state, /*conflictedFileCount=*/0);

    EXPECT_TRUE(banner.headline.empty());
}

TEST(BuildStateBannerText, UnknownConflictCountNeverClaimsANumber) {
    // Status hasn't loaded yet (StartupReadGate still holding it back): the
    // banner may say a merge is in progress, but must never append a
    // fabricated conflict count -- the headline should be exactly what
    // describe() reports, untouched.
    RepoState state;
    state.flags = RepoState::Merge;

    const StateBannerText banner =
        buildStateBannerText(state, /*conflictedFileCount=*/std::nullopt);

    EXPECT_EQ(banner.headline, state.describe());
    EXPECT_FALSE(banner.isConflict);
}

}  // namespace
}  // namespace gbm
