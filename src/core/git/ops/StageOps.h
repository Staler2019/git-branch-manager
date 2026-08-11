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

/// Hunk- or line-level staging for a single file: recomputes that file's
/// diff fresh (working tree vs index when `staged` is false, index vs HEAD
/// when true -- the same meaning as DiffService::workingTreeDiff's `staged`
/// parameter), locates `hunkIndex` within it, builds a patch with
/// UnifiedDiffParser::buildHunkPatch (or buildLineSelectionPatch when
/// `lineIndices` is non-empty), and applies it to the index only via `git
/// apply --cached` (`--reverse` when `staged`, mirroring `staged`'s own
/// direction) -- see UnifiedDiffParser.h's doc comments for why staging and
/// unstaging need direction-aware patch reconstruction, not just `git apply
/// --reverse` on an identical patch.
///
/// Recomputing the diff here (rather than requiring the caller to have one
/// in hand already) keeps this consistent with every other capi read --
/// gbm_working_copy_diff also always recomputes -- and means a hunk/line
/// index that no longer matches (the file changed since it was last
/// displayed) surfaces as an ordinary "patch does not apply"-style failure
/// rather than silently staging the wrong lines.
struct PartialStageRequest {
    std::string path;
    bool staged = false;
    std::size_t hunkIndex = 0;
    /// Empty selects the whole hunk; otherwise these are indices into that
    /// hunk's `lines` array, selecting which added/removed lines take
    /// effect (context and no-newline-marker lines always pass through
    /// regardless -- see buildLineSelectionPatch).
    std::vector<std::size_t> lineIndices;
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

/// See PartialStageRequest's doc comment.
std::unique_ptr<Operation> makePartialStageOperation(PartialStageRequest request);

}  // namespace gbm
