#include "core/git/ConflictBatch.h"

#include <algorithm>
#include <utility>

namespace gbm {

ConflictBatch ConflictBatch::forOperation(std::string operationFingerprint) {
    ConflictBatch batch;
    batch.operationFingerprint_ = std::move(operationFingerprint);
    return batch;
}

void ConflictBatch::merge(const std::vector<const WorkingCopyEntry*>& conflicted) {
    // Re-derive every already-tracked path's state fresh from this scan --
    // see the header's own comment on why this must never be "sticky".
    for (ConflictBatchEntry& entry : entries_) {
        const bool stillConflicted =
            std::any_of(conflicted.begin(), conflicted.end(),
                        [&entry](const WorkingCopyEntry* candidate) {
                            return candidate->path == entry.path;
                        });
        entry.state = stillConflicted ? ConflictFileState::Unresolved : ConflictFileState::Resolved;
    }

    // Append any path not already tracked, in the order it appears here --
    // entries_'s existing order is left untouched above, so first-appearance
    // order holds across every call.
    for (const WorkingCopyEntry* candidate : conflicted) {
        const bool alreadyTracked =
            std::any_of(entries_.begin(), entries_.end(), [candidate](const ConflictBatchEntry& entry) {
                return entry.path == candidate->path;
            });
        if (alreadyTracked) {
            continue;
        }
        entries_.push_back(
            ConflictBatchEntry{candidate->path, candidate->conflict, ConflictFileState::Unresolved});
    }
}

std::size_t ConflictBatch::resolvedCount() const {
    return static_cast<std::size_t>(
        std::count_if(entries_.begin(), entries_.end(), [](const ConflictBatchEntry& entry) {
            return entry.state == ConflictFileState::Resolved;
        }));
}

bool ConflictBatch::allResolved() const {
    return !entries_.empty() && resolvedCount() == entries_.size();
}

}  // namespace gbm
