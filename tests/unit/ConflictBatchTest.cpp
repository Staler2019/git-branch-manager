// Design B2: WorkingCopyStatus::conflicted() stops reporting a path the
// moment it's `git add`-ed (resolved), whether that happened through this
// app's own resolve window or a plain terminal command run alongside it.
// A rail that binds directly to conflicted() would make a just-resolved
// file vanish from the list entirely -- no checkmark, no progress count,
// no way to tell it apart from a file that was never conflicted. ConflictBatch
// is a union across every git-status refresh during one merge/rebase/
// cherry-pick, not a snapshot of any single one -- see merge()'s own
// doc comment for why a rebase specifically needs this (each commit it
// replays can introduce new conflicts on top of ones from an earlier step).
#include "core/git/ConflictBatch.h"

#include <gtest/gtest.h>

#include <string>
#include <vector>

namespace gbm {
namespace {

WorkingCopyEntry makeConflictedEntry(const std::string& path, ConflictKind kind) {
    WorkingCopyEntry entry;
    entry.path = path;
    entry.conflict = kind;
    return entry;
}

TEST(ConflictBatch, ForOperationStartsEmpty) {
    const ConflictBatch batch = ConflictBatch::forOperation("fingerprint-a");
    EXPECT_TRUE(batch.entries().empty());
    EXPECT_EQ(batch.resolvedCount(), 0u);
    EXPECT_FALSE(batch.allResolved());
    EXPECT_EQ(batch.operationFingerprint(), "fingerprint-a");
}

TEST(ConflictBatch, FirstMergeRecordsEveryConflictedPathAsUnresolved) {
    ConflictBatch batch = ConflictBatch::forOperation("op-1");
    const WorkingCopyEntry a = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    const WorkingCopyEntry b = makeConflictedEntry("b.h", ConflictKind::BothAdded);
    batch.merge({&a, &b});

    ASSERT_EQ(batch.entries().size(), 2u);
    EXPECT_EQ(batch.entries()[0].path, "a.cpp");
    EXPECT_EQ(batch.entries()[0].kind, ConflictKind::BothModified);
    EXPECT_EQ(batch.entries()[0].state, ConflictFileState::Unresolved);
    EXPECT_EQ(batch.entries()[1].path, "b.h");
    EXPECT_EQ(batch.resolvedCount(), 0u);
    EXPECT_FALSE(batch.allResolved());
}

// Rebase replays one commit at a time -- a later step can introduce a
// conflict on a path that had nothing to do with any earlier step. merge()
// must append it rather than requiring every conflicted path to be known
// up front.
TEST(ConflictBatch, ANewConflictAppearingMidwayIsAppended) {
    ConflictBatch batch = ConflictBatch::forOperation("op-1");
    const WorkingCopyEntry a = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    batch.merge({&a});

    const WorkingCopyEntry aStillConflicted = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    const WorkingCopyEntry c = makeConflictedEntry("c.txt", ConflictKind::BothAdded);
    batch.merge({&aStillConflicted, &c});

    ASSERT_EQ(batch.entries().size(), 2u);
    EXPECT_EQ(batch.entries()[0].path, "a.cpp");
    EXPECT_EQ(batch.entries()[0].state, ConflictFileState::Unresolved);
    EXPECT_EQ(batch.entries()[1].path, "c.txt");
    EXPECT_EQ(batch.entries()[1].state, ConflictFileState::Unresolved);
}

// A path git add-ed outside this app entirely (a plain terminal command)
// must be picked up the same way as one resolved through this app's own
// window -- merge()'s differencing logic can't tell the two apart and
// doesn't need to: absence from the freshly scanned conflicted() list is
// the only signal available either way.
TEST(ConflictBatch, APathMissingFromALaterScanBecomesResolved) {
    ConflictBatch batch = ConflictBatch::forOperation("op-1");
    const WorkingCopyEntry a = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    const WorkingCopyEntry b = makeConflictedEntry("b.h", ConflictKind::BothAdded);
    batch.merge({&a, &b});

    // b.h no longer appears -- resolved, whether by this app or externally.
    batch.merge({&a});

    ASSERT_EQ(batch.entries().size(), 2u);
    EXPECT_EQ(batch.entries()[0].state, ConflictFileState::Unresolved);
    EXPECT_EQ(batch.entries()[1].path, "b.h");
    EXPECT_EQ(batch.entries()[1].state, ConflictFileState::Resolved);
    EXPECT_EQ(batch.resolvedCount(), 1u);
    EXPECT_FALSE(batch.allResolved());
}

TEST(ConflictBatch, AllResolvedIsTrueOnlyWhenEveryTrackedPathIsResolved) {
    ConflictBatch batch = ConflictBatch::forOperation("op-1");
    const WorkingCopyEntry a = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    const WorkingCopyEntry b = makeConflictedEntry("b.h", ConflictKind::BothAdded);
    batch.merge({&a, &b});

    batch.merge({&a});
    EXPECT_FALSE(batch.allResolved());

    batch.merge({});
    EXPECT_TRUE(batch.allResolved());
    EXPECT_EQ(batch.resolvedCount(), 2u);
}

// entries() must always report paths in first-appearance order, regardless
// of resolution order or which scan a path was first seen in -- a rail
// bound to this would otherwise jump rows around under the user as they
// resolve files out of order.
TEST(ConflictBatch, EntryOrderIsStableAcrossResolutionAndNewArrivals) {
    ConflictBatch batch = ConflictBatch::forOperation("op-1");
    const WorkingCopyEntry a = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    const WorkingCopyEntry b = makeConflictedEntry("b.h", ConflictKind::BothAdded);
    const WorkingCopyEntry c = makeConflictedEntry("c.txt", ConflictKind::BothAdded);
    batch.merge({&a, &b});
    // Resolve a.cpp (drops out), c.txt shows up mid-rebase.
    batch.merge({&b, &c});

    ASSERT_EQ(batch.entries().size(), 3u);
    EXPECT_EQ(batch.entries()[0].path, "a.cpp");
    EXPECT_EQ(batch.entries()[0].state, ConflictFileState::Resolved);
    EXPECT_EQ(batch.entries()[1].path, "b.h");
    EXPECT_EQ(batch.entries()[1].state, ConflictFileState::Unresolved);
    EXPECT_EQ(batch.entries()[2].path, "c.txt");
    EXPECT_EQ(batch.entries()[2].state, ConflictFileState::Unresolved);
}

// A path resolved in one scan reappearing conflicted in a later one (e.g. a
// later rebase step touches the same file again) must flip back to
// Unresolved rather than staying stuck on a stale Resolved that no longer
// matches reality -- state is always re-derived fresh from the latest scan,
// never "sticky" once set.
TEST(ConflictBatch, APathThatBecomesConflictedAgainFlipsBackToUnresolved) {
    ConflictBatch batch = ConflictBatch::forOperation("op-1");
    const WorkingCopyEntry a = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    batch.merge({&a});
    batch.merge({});  // resolved
    ASSERT_EQ(batch.entries()[0].state, ConflictFileState::Resolved);

    const WorkingCopyEntry aAgain = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    batch.merge({&aAgain});
    EXPECT_EQ(batch.entries()[0].state, ConflictFileState::Unresolved);
}

// Different fingerprint means a different operation entirely (e.g.
// `git merge --abort` followed by a fresh merge that hits different
// conflicts) -- forOperation() always starts a brand new, empty batch
// rather than carrying over any previous operation's entries. There is no
// migration path between fingerprints by design: the caller is expected to
// simply construct a new ConflictBatch and discard the old one (see the
// app-side persistence layer, which checks the fingerprint before deciding
// whether to reuse or replace its saved batch).
TEST(ConflictBatch, ForOperationWithADifferentFingerprintStartsFreshAndEmpty) {
    ConflictBatch first = ConflictBatch::forOperation("op-1");
    const WorkingCopyEntry a = makeConflictedEntry("a.cpp", ConflictKind::BothModified);
    first.merge({&a});
    ASSERT_FALSE(first.entries().empty());

    const ConflictBatch second = ConflictBatch::forOperation("op-2");
    EXPECT_TRUE(second.entries().empty());
    EXPECT_EQ(second.operationFingerprint(), "op-2");
}

}  // namespace
}  // namespace gbm
