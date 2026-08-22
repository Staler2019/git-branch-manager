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
#include <string_view>
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
    /// Adds --no-merges, so merge commits get no row of their own -- but every
    /// commit that *arrived through* a merge still gets one. Separate from
    /// firstParentOnly, which is the opposite trade: it keeps the merge row and
    /// drops the whole second-parent side. The sidebar branch filter sets this
    /// one alone when it narrows to exactly one branch -- see isLinearWalk().
    bool noMerges = false;
    bool includeReflog = false;  ///< Adds --reflog, so post-reset commits appear.
    bool dateOrder = false;      ///< Interleaves branches; the graph will zig-zag.
    std::uint32_t maxCount = 0;  ///< 0 means unlimited.

    std::vector<std::string> toRevListArgs() const;

    /// True when the walk should be drawn as one straight line: every emitted
    /// row linked to the next, no parallel lanes and no merge rows. This is
    /// what turns on parent bridging in HistoryProvider's walk loop.
    ///
    /// **Read this before assuming the line means ancestry -- it does not.**
    /// An earlier version of this predicate also required `firstParentOnly`
    /// and justified the bridge with a subsequence argument: one tip walked
    /// `--first-parent` visits exactly that chain in order, so consecutive
    /// `--no-merges` rows were still first-parent ancestor and descendant.
    /// That argument was sound and the feature built on it was wrong, because
    /// `--first-parent` also discards every commit that landed through a
    /// merge -- on this project's own `main`, 3 rows instead of 442. What the
    /// user asked for is the merged-in work *present*, with only the merge
    /// commits gone.
    ///
    /// So the bridge is now list decoration, not topology: a segment means
    /// "the next row", nothing more. Two adjacent rows need not be related at
    /// all, and even when a row's real parent is emitted it may not be the
    /// next one -- topo order can interleave a side branch's commits between a
    /// trunk commit and its parent, and the bridge links to the interleaved
    /// row anyway. Anything that wants real edges must read an unfiltered
    /// snapshot.
    ///
    /// One property does survive and is worth keeping: `toRevListArgs()`
    /// always emits `--topo-order` or `--date-order`, and both guarantee a
    /// parent is never printed before its children, so a bridged segment never
    /// points from an ancestor down to its own descendant. **That depends on
    /// the ordering flag staying unconditional** -- make it optional and this
    /// stops holding.
    ///
    /// Both remaining conditions are load-bearing: two tips (or `--all`)
    /// interleave unrelated histories into one column, which is a lie of a
    /// different size; and without `--no-merges` nothing is removed, so there
    /// is nothing to bridge and the real graph is what the user asked to see.
    bool isLinearWalk() const { return includeRefs.size() == 1 && noMerges; }
};

/// Why a history walk was started. RepositorySession threads this from each
/// walk's trigger site through to `graphUpdated`, so a background resync
/// never looks identical to the initial walk just running slowly -- see
/// docs/reports/vscode-graph-performance.md, bottleneck #3.
enum class GraphUpdateOrigin : std::uint8_t {
    /// Repo open, the Refresh button, a filter/checkout/operation-driven
    /// refresh, or any other direct call -- everything except the one case
    /// below.
    Explicit,
    /// `RepositorySession::refreshRefsAndHistory()` called after
    /// `maybeAutoFetch()`'s background `git fetch` succeeded and moved refs.
    AutoFetchResync,
};

/// Short label for logging and tests -- "explicit" / "auto-fetch resync".
std::string_view toString(GraphUpdateOrigin origin);

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
