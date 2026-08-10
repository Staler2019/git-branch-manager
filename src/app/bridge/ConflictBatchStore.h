#pragma once

#include "core/git/ConflictBatch.h"
#include "core/git/RepoPaths.h"
#include "core/git/RepoState.h"

#include <string>

namespace gbm {

/// Design B2's QSettings persistence adapter for ConflictBatch. Lives here
/// (src/app/bridge, alongside RepositorySession/ThemeManager) rather than in
/// core: ConflictBatch itself links no Qt target (see
/// src/core/CMakeLists.txt's own comment on that boundary), so QSettings
/// access has to happen on this side.
class ConflictBatchStore {
public:
    /// Identifies "this operation, this far along" -- repo path plus
    /// RepoState's flags and rebase step/total. Deliberately *not* MERGE_HEAD/
    /// REBASE_HEAD's oid: that would need a raw-content file read, and every
    /// other synchronous repo-state check this app makes from the UI thread
    /// (RepositorySession::state(), used throughout MainWindow) goes through
    /// RepoState::read() specifically because it only stats a handful of
    /// paths rather than reading any file's bytes. Reusing that same cheap
    /// call here keeps this off the UI-thread-blocking-read path too, at the
    /// cost of a narrow, bounded gap: two sequential operations that happen
    /// to stop at the exact same rebase step (or both a plain, stepless
    /// Merge) collide onto one fingerprint and reuse the older saved batch.
    /// The result is at worst a stale ✔ on a row that's freshly conflicted
    /// again -- self-correcting the moment a live scan runs (see
    /// ConflictBatch::merge()'s "never sticky" behaviour) -- never a
    /// corrupted file, so this trade-off is accepted rather than adding an
    /// async oid read for it.
    static std::string operationFingerprint(const RepoPaths& paths, const RepoState& state);

    /// Loads the batch saved for `paths`' repo, if any, and if its saved
    /// fingerprint still matches `fingerprint` -- otherwise (nothing saved,
    /// or it belongs to a different operation entirely) returns a fresh
    /// empty ConflictBatch::forOperation(fingerprint), matching
    /// forOperation()'s own "no migration between fingerprints" contract.
    static ConflictBatch load(const RepoPaths& paths, const std::string& fingerprint);

    /// Persists `batch` under `paths`' repo-hash key.
    static void save(const RepoPaths& paths, const ConflictBatch& batch);

    /// Removes the saved batch for `paths` -- call once
    /// ConflictBatch::allResolved() and the sequencer operation has actually
    /// ended, so no stale entry lingers past the operation it was for.
    static void clear(const RepoPaths& paths);
};

}  // namespace gbm
