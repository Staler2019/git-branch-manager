#pragma once

#include "core/base/ObjectId.h"
#include "core/git/OperationRunner.h"

#include <memory>
#include <string>

namespace gbm {

struct UndoRequest {
    ObjectId headBefore;       ///< See OperationRunner::UndoEntry.
    std::string branchBefore;  ///< Empty when HEAD was detached at the time.
};

/// Reverses one entry from OperationRunner::undoJournal() by hard-resetting
/// back to where HEAD stood before it ran. Refuses if the checked-out branch
/// has since changed: undoing "as if the operation never happened" only makes
/// sense while still on the branch it actually touched.
std::unique_ptr<Operation> makeUndoOperation(UndoRequest request);

}  // namespace gbm
