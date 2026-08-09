#pragma once

#include "core/git/WorkingCopyStatus.h"

#include <cstddef>
#include <string>
#include <vector>

namespace gbm {

/// Whether a batch-tracked path is still stuck in conflict or has been
/// resolved -- by this app's own resolve window, or externally (a plain
/// `git add` run in a terminal alongside it). merge() can't tell the two
/// apart and doesn't need to; see its own doc comment.
enum class ConflictFileState { Unresolved, Resolved };

struct ConflictBatchEntry {
    std::string path;
    ConflictKind kind = ConflictKind::None;
    ConflictFileState state = ConflictFileState::Unresolved;
};

/// Tracks every conflicted path seen across the lifetime of one merge,
/// rebase, or cherry-pick -- a *union* of every git-status scan taken
/// during that operation, not a snapshot of any single one.
///
/// The problem this solves: WorkingCopyStatus::conflicted() only reports
/// paths that are *currently* unmerged in the index. The instant a path is
/// resolved (`git add`-ed, by this app or by hand), it silently drops out
/// of that list -- a rail bound directly to conflicted() would make a
/// just-finished file vanish entirely rather than show a checkmark, and
/// the running "N of M resolved" count would have no way to remember M
/// once some files stop being reported at all.
///
/// A rebase specifically needs the *union* behaviour, not just the
/// resolved-tracking: it replays one commit at a time, and a later step
/// can introduce a fresh conflict on a path that had nothing to do with an
/// earlier one. merge() must accept new paths appearing partway through,
/// not require the full conflict set to be known upfront.
///
/// Construction is only ever through the forOperation() factory (DDD
/// factory-pattern convention used elsewhere in core) -- there is no
/// meaningful "empty, no operation" ConflictBatch to default-construct.
class ConflictBatch {
public:
    /// `operationFingerprint` identifies one merge/rebase/cherry-pick run
    /// (e.g. MERGE_HEAD/REBASE_HEAD's oid plus the RepoState kind) -- a
    /// different fingerprint means a different operation, and the caller
    /// is expected to simply construct a new ConflictBatch rather than
    /// migrate entries from the old one (there is no such migration path
    /// by design; see the app-side persistence layer, added separately,
    /// which is what actually decides whether to reuse a saved batch or
    /// discard it based on this value).
    static ConflictBatch forOperation(std::string operationFingerprint);

    /// Rebuilds a batch from entries in their last-known state, verbatim --
    /// used by the app-side QSettings persistence layer to resume a batch
    /// across app restarts, where there is no live git-status scan to
    /// merge() against yet (see WorkingCopyStatus::conflicted()'s own
    /// unavailability at that point). Trusts the caller's `entries` as-is,
    /// including whatever order and state they were saved in -- this is a
    /// resume aid, not a second way to derive state, so the very next
    /// merge() call re-derives every entry fresh from the first real scan
    /// the same way it always does, silently correcting anything stale a
    /// restore might have carried over (a file resolved by hand while the
    /// app was closed, say).
    static ConflictBatch restore(std::string operationFingerprint,
                                  std::vector<ConflictBatchEntry> entries);

    /// Merges in one git-status scan's conflicted paths:
    ///  - Every path already tracked has its state re-derived fresh from
    ///    whether it's still present in `conflicted` -- present means
    ///    Unresolved, absent means Resolved. This is why a path that
    ///    somehow becomes conflicted again after being marked resolved
    ///    (a later rebase step touching the same file) flips back to
    ///    Unresolved automatically rather than staying stuck on a stale
    ///    Resolved that no longer matches reality -- state is never
    ///    "sticky", always recomputed from the latest scan.
    ///  - Any path in `conflicted` not already tracked is appended, in the
    ///    order it appears in `conflicted` -- entries() always reports
    ///    paths in first-appearance order across every merge() call, so a
    ///    rail bound to it never reorders rows out from under the user as
    ///    they resolve files.
    void merge(const std::vector<const WorkingCopyEntry*>& conflicted);

    const std::vector<ConflictBatchEntry>& entries() const { return entries_; }
    std::size_t resolvedCount() const;
    /// True only once every tracked path is Resolved -- vacuously false
    /// for an empty batch (nothing to call "all resolved" about yet).
    bool allResolved() const;
    const std::string& operationFingerprint() const { return operationFingerprint_; }

private:
    ConflictBatch() = default;

    std::string operationFingerprint_;
    std::vector<ConflictBatchEntry> entries_;
};

}  // namespace gbm
