#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"
#include "core/graph/GraphSnapshot.h"

#include <chrono>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace gbm {

/// What history to walk. Every field here maps onto a rev-list argument rather
/// than being filtered in our process: `--author`, `--grep` and path limiting are
/// orders of magnitude faster inside git, and a filter proxy in front of 500k
/// rows would be unusable. Changing a filter restarts the walk.
struct HistoryQuery {
    /// Tips to walk from before `--all`, purely to order them ahead of it --
    /// the graph builder gives lane 0 to the first tip it sees, which is how
    /// HEAD's branch (or the trunk) stays leftmost. Every commit reachable
    /// from any ref is still included; this never narrows the walk. Populated
    /// automatically from the refs whenever includeRefs is empty -- see
    /// RepositorySession::refreshHistory.
    std::vector<std::string> seedRefs;
    /// When non-empty, narrows the walk to only what's reachable from these
    /// refs -- no implicit `--all`. This is what "Branches…" (the graph
    /// branch filter) sets. Every ref here must exist in the current
    /// RefSnapshot before being handed to rev-list: a name that's gone stale
    /// (e.g. a pruned `refs/remotes/origin/*`) aborts the whole walk with
    /// "unknown revision" rather than just being skipped.
    std::vector<std::string> includeRefs;
    std::vector<std::string> excludeRefs;
    std::optional<std::string> pathFilter;
    std::optional<std::string> grep;
    std::optional<std::string> author;
    std::optional<std::int64_t> since;
    std::optional<std::int64_t> until;
    bool firstParentOnly = false;
    bool includeReflog = false;  ///< Adds --reflog, so post-reset commits appear.
    bool dateOrder = false;      ///< Interleaves branches; the graph will zig-zag.
    std::uint32_t maxCount = 0;  ///< 0 means unlimited.

    std::vector<std::string> toRevListArgs() const;
};

/// Streams `git rev-list` into graph snapshots.
///
/// Publishing a snapshot copies the rows built so far and rebuilds its lookup
/// index, so each publish costs O(rows). The chunk schedule therefore *grows
/// geometrically*: a small first chunk gets pixels on screen immediately, then the
/// threshold doubles, which keeps the total publishing cost linear in history size.
///
/// A fixed interval instead of this is a trap worth naming, because it looks
/// perfectly reasonable: with a 30 ms timer, once a copy takes longer than 30 ms
/// every single row triggers another publish, and the walk becomes quadratic. On a
/// 200k-commit repository that measured 470 seconds instead of ~2.
class HistoryProvider {
public:
    /// Rows in the first chunk. Small on purpose: this is what the user sees first.
    static constexpr std::size_t kFirstChunkRows = 256;
    /// The row threshold doubles after each publish, up to this ceiling.
    static constexpr std::size_t kMaxChunkRows = 131072;
    /// A slow repository still paints early: the first chunk may be published on
    /// this timer even if it has not reached kFirstChunkRows yet.
    static constexpr std::chrono::milliseconds kFirstChunkInterval{30};

    using ChunkSink = std::function<void(GraphSnapshotPtr)>;

    HistoryProvider(IProcessRunner& runner, RepoPaths paths);

    /// Walks history, invoking `onChunk` on the calling (worker) thread. The
    /// final chunk has `complete == true`.
    GitResult<GraphSnapshotPtr> walk(const HistoryQuery& query,
                                     const ChunkSink& onChunk,
                                     CancellationToken token);

    /// Parses one `rev-list --parents --timestamp` record. Exposed for tests,
    /// which is where the tolerance for malformed input gets pinned down.
    struct Record {
        ObjectId oid;
        std::vector<ObjectId> parents;
        std::uint32_t commitTime = 0;
        bool valid = false;
    };

    static Record parseRevListLine(std::string_view line);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
