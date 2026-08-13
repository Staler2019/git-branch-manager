#include "core/git/CommitMetaStore.h"

namespace gbm {

CommitMetaStore::CommitMetaStore(std::filesystem::path gitExecutable, RepoPaths paths)
    : batch_(std::move(gitExecutable), std::move(paths)) {}

CommitMetaStore::~CommitMetaStore() = default;

std::vector<CommitMeta> CommitMetaStore::read(const std::vector<ObjectId>& oids,
                                              CancellationToken token) {
    return batch_.readCommits(oids, token);
}

void CommitMetaStore::stop() {
    batch_.stop();
}

}  // namespace gbm
