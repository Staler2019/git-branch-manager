#pragma once

// Serializes core types to the JSON shapes documented in gbm_capi.h and the
// implementation plan. One function per type; each produces a complete JSON
// value (object or array), never a fragment, so callers can drop the result
// straight into the staging buffer or an event payload.

#include "core/base/Error.h"
#include "core/cache/RepoIndexDb.h"
#include "core/git/CommitMeta.h"
#include "core/git/OperationRunner.h"
#include "core/git/RefStore.h"
#include "core/git/RepoState.h"
#include "core/git/UnifiedDiffParser.h"
#include "core/git/WorkingCopyStatus.h"

#include <string>
#include <vector>

namespace gbm::capi {

std::string toJson(const GitError& error);
std::string toJson(const RepoState& state);
std::string toJson(const CommitMeta& meta);
std::string toJson(const OperationOutcome& outcome);
std::string toJson(const RepoRecord& record);
std::string toJson(const std::vector<RepoRecord>& records);
std::string toJson(const BaseFolderRecord& record);
std::string toJson(const std::vector<BaseFolderRecord>& records);
std::string toJson(const RefSnapshot& refs);
std::string toJson(const WorkingCopyStatus& status);
std::string toJson(const ParsedDiff& diff);

}  // namespace gbm::capi
