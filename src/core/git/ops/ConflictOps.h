#pragma once

#include "core/git/OperationRunner.h"

#include <memory>
#include <string>

namespace gbm {

enum class ConflictResolution : std::uint8_t {
    /// Take stage 2 (HEAD's side) for this path. If it does not exist at
    /// stage 2 (we deleted it), the path is removed instead.
    TakeOurs,
    /// Take stage 3 (the incoming side) for this path. If it does not exist at
    /// stage 3 (they deleted it), the path is removed instead.
    TakeTheirs,
    /// The user edited the file themselves (or it is already correct as-is):
    /// just clear the conflict stages and stage the current working-tree
    /// content, whatever that is.
    MarkResolved,
    /// The caller supplies the resolved file content directly (e.g. an
    /// in-app editor): write `resolvedContent` to the path on disk, then
    /// clear the conflict stages and stage it, same as MarkResolved.
    WriteResolved,
};

struct ResolveConflictRequest {
    std::string path;
    ConflictResolution resolution = ConflictResolution::MarkResolved;
    /// Needed only for TakeOurs/TakeTheirs to tell a real deletion apart from
    /// an ordinary content pick -- see WorkingCopyEntry::oursBlob/theirsBlob.
    bool oursBlobMissing = false;
    bool theirsBlobMissing = false;
    /// Only for WriteResolved: written to `path` verbatim (no line-ending or
    /// encoding translation), replacing whatever is currently on disk. Must
    /// be non-empty -- an empty value is rejected rather than truncating the
    /// file, since an empty edit is far more likely to be a caller bug than
    /// an intentionally emptied file.
    std::string resolvedContent;
};

/// Resolves one conflicted path and stages the result, ready for the commit
/// that finishes the merge/cherry-pick/revert. Never touches paths other than
/// the one requested, so resolving one file at a time never disturbs the rest
/// of a large conflicted set.
std::unique_ptr<Operation> makeResolveConflictOperation(ResolveConflictRequest request);

}  // namespace gbm
