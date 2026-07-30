#pragma once

#include "core/git/OperationRunner.h"

#include <memory>
#include <string>
#include <vector>

namespace gbm {

struct StageFilesRequest {
    std::vector<std::string> paths;
};

struct UnstageFilesRequest {
    std::vector<std::string> paths;
};

/// A pre-built patch -- see UnifiedDiffParser::buildHunkPatch and
/// buildLineSelectionPatch -- applied to the index only, never the work tree.
struct ApplyPatchRequest {
    std::string patch;

    /// False to stage: `patch` must come from the *unstaged* diff (work tree
    /// vs index), applied with `git apply --cached`.
    /// True to unstage: `patch` must come from the *staged* diff (index vs
    /// HEAD), applied with `git apply --cached --reverse`. This is not the
    /// same as building an already-reversed patch: see the note on
    /// buildLineSelectionPatch.
    bool reverse = false;
};

/// `git add -- <paths>`. Works uniformly for modified, added and deleted
/// paths: given an explicit pathspec (never a glob), `add` stages a removal
/// exactly as readily as a modification.
std::unique_ptr<Operation> makeStageFilesOperation(StageFilesRequest request);

/// `git restore --staged -- <paths>`.
std::unique_ptr<Operation> makeUnstageFilesOperation(UnstageFilesRequest request);

/// `git apply --cached`, for hunk- and line-level staging. Only the index
/// moves -- the work tree is untouched -- which is what lets one hunk in a
/// file be staged while its neighbours stay unstaged.
std::unique_ptr<Operation> makeApplyPatchOperation(ApplyPatchRequest request);

}  // namespace gbm
