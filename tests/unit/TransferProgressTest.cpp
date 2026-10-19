// The strings below are git 2.56.0's own stderr from a `file://` clone of this
// repository under LC_ALL=C, copied byte for byte: the column padding after
// the colon and the trailing spaces on `remote:` lines are git's, not ours.
#include "core/git/TransferProgress.h"

#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

using Phase = TransferProgress::Phase;

TEST(TransferProgress, AReceivingLineGivesItsCounts) {
    EXPECT_EQ(parseTransferProgress("Receiving objects:  51% (8840/17333)"),
              (TransferProgress{Phase::ReceivingObjects, 8840, 17333}));
}

TEST(TransferProgress, AResolvingLineGivesItsCounts) {
    EXPECT_EQ(parseTransferProgress("Resolving deltas:  51% (6553/12848)"),
              (TransferProgress{Phase::ResolvingDeltas, 6553, 12848}));
}

TEST(TransferProgress, SeveralRedrawsInOneChunkGiveTheLast) {
    EXPECT_EQ(parseTransferProgress("Receiving objects:   0% (1/17333)\r"
                                    "Receiving objects:  12% (2080/17333)\r"
                                    "Receiving objects:  51% (8840/17333)\r"),
              (TransferProgress{Phase::ReceivingObjects, 8840, 17333}));
}

TEST(TransferProgress, AChunkSpanningBothPhasesGivesResolving) {
    EXPECT_EQ(parseTransferProgress(
                  "Receiving objects: 100% (17333/17333), 9.07 MiB | 56.66 MiB/s, done.\n"
                  "Resolving deltas:   0% (0/12848)\r"
                  "Resolving deltas:  51% (6553/12848)\r"),
              (TransferProgress{Phase::ResolvingDeltas, 6553, 12848}));
}

TEST(TransferProgress, TheDoneLineWithSizesGivesTheFinalCounts) {
    EXPECT_EQ(parseTransferProgress(
                  "Receiving objects: 100% (17333/17333), 9.07 MiB | 56.66 MiB/s, done.\n"),
              (TransferProgress{Phase::ReceivingObjects, 17333, 17333}));
    EXPECT_EQ(parseTransferProgress("Resolving deltas: 100% (12848/12848), done.\n"),
              (TransferProgress{Phase::ResolvingDeltas, 12848, 12848}));
}

TEST(TransferProgress, ALineFeedAloneSeparatesLines) {
    // The phase change and git's first line are separated by '\n' with no
    // '\r' redraw in between.
    EXPECT_EQ(parseTransferProgress("Receiving objects: 100% (17333/17333), done.\n"
                                    "Resolving deltas: 100% (12848/12848), done.\n"),
              (TransferProgress{Phase::ResolvingDeltas, 12848, 12848}));
    EXPECT_EQ(parseTransferProgress("Cloning into 'dst'...\n"
                                    "Receiving objects:   0% (1/17333)\r"),
              (TransferProgress{Phase::ReceivingObjects, 1, 17333}));
}

TEST(TransferProgress, CrLfLineEndsAreHandled) {
    EXPECT_EQ(parseTransferProgress("Resolving deltas: 100% (12848/12848), done.\r\n"),
              (TransferProgress{Phase::ResolvingDeltas, 12848, 12848}));
}

TEST(TransferProgress, ALaterUnrelatedLineDoesNotHideAnEarlierMatch) {
    // A chunk can end on git's own trailing chatter; the meter's last state
    // is still the latest progress in it.
    EXPECT_EQ(parseTransferProgress("Resolving deltas: 100% (12848/12848), done.\n"
                                    "Updating files:  40% (400/1000)\r"),
              (TransferProgress{Phase::ResolvingDeltas, 12848, 12848}));
}

TEST(TransferProgress, RemoteLinesAreNotTheTransfer) {
    EXPECT_EQ(
        parseTransferProgress("remote: Counting objects: 100% (17333/17333), done.        \n"),
        std::nullopt);
    EXPECT_EQ(parseTransferProgress("remote: Compressing objects:  50% (2500/5000)        \r"),
              std::nullopt);
    // Even a remote line that happens to quote our label.
    EXPECT_EQ(parseTransferProgress("remote: Receiving objects:  50% (1/2)\r"), std::nullopt);
}

TEST(TransferProgress, OtherLinesGiveNothing) {
    EXPECT_EQ(parseTransferProgress("Cloning into 'dst'...\n"), std::nullopt);
    EXPECT_EQ(parseTransferProgress(""), std::nullopt);
}

TEST(TransferProgress, ALineCutBeforeItsCountsGivesNothing) {
    EXPECT_EQ(parseTransferProgress("Receiving objects:  51% (884"), std::nullopt);
    EXPECT_EQ(parseTransferProgress("Receiving objects:  51%"), std::nullopt);
}

TEST(TransferProgress, ACutLineAfterACompleteOneKeepsTheCompleteOne) {
    EXPECT_EQ(parseTransferProgress("Receiving objects:  12% (2080/17333)\r"
                                    "Receiving objects:  51% (884"),
              (TransferProgress{Phase::ReceivingObjects, 2080, 17333}));
}

TEST(TransferProgress, NonNumericOrOverflowingCountsGiveNothing) {
    EXPECT_EQ(parseTransferProgress("Receiving objects:  51% (x/17333)"), std::nullopt);
    EXPECT_EQ(parseTransferProgress("Receiving objects:  51% (1/)"), std::nullopt);
    EXPECT_EQ(parseTransferProgress("Receiving objects:  51% (8840x17333)"), std::nullopt);
    EXPECT_EQ(parseTransferProgress("Receiving objects:  51% (-1/17333)"), std::nullopt);
    EXPECT_EQ(parseTransferProgress("Receiving objects:  51% (99999999999999999999/1)"),
              std::nullopt);
}

}  // namespace
}  // namespace gbm
