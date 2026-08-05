#pragma once

#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"

#include <cstdint>
#include <memory>

namespace gbm {

/// Whether a commit-graph file (single-file or split-chain form) already exists
/// for this repository. No subprocess: this is a filesystem check so it is cheap
/// enough to call on the "should we offer to speed this up" advice path, which
/// runs once per completed history walk.
bool hasCommitGraph(const RepoPaths& paths);

/// The user's answer to "build a commit-graph for this repository?", persisted
/// per repository. `Unset` is the state a repository starts in and the only one
/// in which the advice banner is offered at all -- see shouldOfferCommitGraph().
enum class CommitGraphPreference {
    Unset,
    Enabled,
    Declined,
};

/// Below this row count, `git rev-list` is already fast enough that the
/// commit-graph write itself (and the disk space it costs) isn't worth
/// advertising. Calibrated from the same-run A/B measurements in
/// docs/PERFORMANCE.md's commit-graph gate section, not guessed.
inline constexpr std::uint32_t kCommitGraphAdviceMinRows = 25000;

/// Decides whether the "this repository would load faster with a commit-graph"
/// hint should be shown. Pure and core-side (no RepositorySession, no Qt, no
/// filesystem access beyond what the caller already did) specifically so the
/// decision is unit-testable without a real repository -- RepositorySession
/// itself has no test harness (see docs/PERFORMANCE.md), so pushing judgment
/// out of it into a pure function is the only way this logic gets tested.
bool shouldOfferCommitGraph(bool hasGraph,
                            std::uint32_t rowCount,
                            CommitGraphPreference preference);

struct WriteCommitGraphRequest {
    /// `commit-graph write --split`: gated on GitCapabilities::commitGraphSplit
    /// (>= 2.24) by the caller, not assumed here -- see
    /// RepositorySession::writeCommitGraph().
    bool split = false;
    /// `--changed-paths`: gated on GitCapabilities::changedPathBloom (also
    /// >= 2.24, same flag family) by the caller.
    bool changedPaths = true;
};

/// `git commit-graph write --reachable [--changed-paths] [--split]`.
///
/// Writes into the object store, but always to a temp file that is renamed into
/// place on success -- unlike a checkout or rebase, there is no half-applied
/// state to leave behind, so this is the rare operation that is safe to kill
/// mid-flight.
std::unique_ptr<Operation> makeWriteCommitGraphOperation(WriteCommitGraphRequest request);

}  // namespace gbm
