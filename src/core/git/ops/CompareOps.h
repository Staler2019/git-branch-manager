#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"
#include "core/git/UnifiedDiffParser.h"

#include <cstdint>
#include <string>
#include <vector>

namespace gbm {

/// One commit unique to a side of a two-ref comparison ("git log
/// --left-right"), for the M6 Compare tab's commit list -- see spec page 12.
struct CompareCommitEntry {
    ObjectId oid;
    /// true: reachable from the right ref only (git's '>' marker); false:
    /// reachable from the left ref only ('<'). Two-dot mode (left..right)
    /// never produces a left-only entry, because the range itself excludes
    /// everything reachable from left -- see CompareRequest::threeDot.
    bool onRightOnly = false;
    std::string authorName;
    std::int64_t authorDate = 0;
    std::string subject;
};

struct CompareRequest {
    std::string leftRef;
    std::string rightRef;
    /// true: `left...right`, the symmetric difference off the merge base --
    /// the GitHub-style "compare branches" view, showing commits unique to
    /// either side. false: `left..right`, only what right has that left
    /// doesn't -- "what would land if this were merged/rebased onto left".
    bool threeDot = true;
};

struct CompareResult {
    /// Null (`ObjectId::isNull()`) when the two refs share no common
    /// ancestor -- unrelated histories are a valid state to display, not an
    /// error (see CompareOps.cpp's readMergeBase for how git signals this).
    ObjectId mergeBase;
    std::vector<CompareCommitEntry> commits;
    /// File-level summary only (kind, paths, line counts) -- no hunks. Use
    /// compareFileDiff() for one file's full diff.
    std::vector<DiffFile> files;
};

struct CompareFileDiffRequest {
    std::string leftRef;
    std::string rightRef;
    bool threeDot = true;
    std::string path;
};

/// Runs the read-only two-ref comparison queries backing the M6 Compare tab
/// (spec page 12): merge-base, the commit lists unique to each side, the
/// changed-file summary, and a single file's full diff.
///
/// All four are reads via `git diff`/`git log`/`git merge-base` -- there is
/// no `Operation` subclass here because nothing mutates the repository, the
/// same reasoning as RefStore/RemoteStore. Unlike RemoteStore::list() (which
/// publishes one "current" snapshot), a Compare tab's inputs are two
/// user-chosen refs and the UI allows several tabs open at once with
/// different ref pairs -- so this is consumed through the capi layer's
/// per-request "echo the query params back" pattern
/// (Session::requestCommitFileDiff is the existing precedent), not the
/// single-published-state pattern.
class CompareStore {
public:
    CompareStore(IProcessRunner& runner, RepoPaths paths);

    /// mergeBase + commits + files together: opening a Compare tab always
    /// wants all three, so this is one call rather than three round trips.
    GitResult<CompareResult> compare(CompareRequest request, CancellationToken token);

    /// A single file's full diff between the two refs, via
    /// UnifiedDiffParser -- see CompareOps.cpp for why this doesn't go
    /// through DiffService.
    GitResult<ParsedDiff> compareFileDiff(CompareFileDiffRequest request, CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
