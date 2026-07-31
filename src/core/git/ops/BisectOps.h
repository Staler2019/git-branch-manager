#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"

#include <memory>
#include <string>
#include <vector>

namespace gbm {

/// Current state of a `git bisect` session, read from `BISECT_LOG` rather than
/// tracked in memory -- same reasoning as RepoState: a bisect survives closing
/// the app, and a terminal may have advanced it in the meantime.
struct BisectStatus {
    bool active = false;
    std::string currentOid;         ///< HEAD; the commit currently being tested.
    std::string badOid;             ///< Empty until a bad commit has been marked.
    std::vector<std::string> goodOids;
    std::vector<std::string> skippedOids;
    /// The raw `git bisect log` output, for a "show the log" view; also the
    /// input `git bisect replay` would need, which this app does not expose.
    std::string logText;
};

/// Reads `BISECT_LOG`, read-only like RefStore.
class BisectStore {
public:
    BisectStore(IProcessRunner& runner, RepoPaths paths);

    GitResult<BisectStatus> status(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct BisectStartRequest {
    /// Both may be empty: `git bisect start` with no revisions is valid and
    /// simply waits for `good`/`bad` to be given afterward.
    std::string badRef;
    std::vector<std::string> goodRefs;
    /// Limits the bisect to commits touching these paths.
    std::vector<std::string> paths;
    /// `--no-checkout`: leaves the work tree alone and only moves `BISECT_HEAD`,
    /// for repositories too large to check out every candidate.
    bool noCheckout = false;
};

struct BisectMarkRequest {
    bool good = false;  ///< true marks `good`, false marks `bad`.
    std::string ref;    ///< Empty means the current `HEAD`.
};

struct BisectSkipRequest {
    /// Empty skips the current commit (`HEAD`); otherwise these specific revs.
    std::vector<std::string> refs;
};

struct BisectResetRequest {
    /// Empty returns to the branch/commit `git bisect start` was run from.
    std::string target;
};

/// `git bisect start [<bad> [<good>...]] [--] [<paths>...]`.
std::unique_ptr<Operation> makeBisectStartOperation(BisectStartRequest request);

/// `git bisect good|bad [<ref>]`. May conclude the bisect (git prints
/// "is the first bad commit"), in which case OperationOutcome::summary carries
/// that message verbatim -- there is no separate "done" signal to poll for.
std::unique_ptr<Operation> makeBisectMarkOperation(BisectMarkRequest request);

/// `git bisect skip [<refs...>]`, for a commit that cannot be tested.
std::unique_ptr<Operation> makeBisectSkipOperation(BisectSkipRequest request);

/// `git bisect reset [<target>]`: ends the session and restores the work tree.
std::unique_ptr<Operation> makeBisectResetOperation(BisectResetRequest request);

}  // namespace gbm
