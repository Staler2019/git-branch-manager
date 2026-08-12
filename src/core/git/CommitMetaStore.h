#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/ObjectId.h"
#include "core/git/CatFileBatch.h"
#include "core/git/CommitMeta.h"
#include "core/git/RepoPaths.h"

#include <filesystem>
#include <vector>

namespace gbm {

/// Batch commit-metadata reads (author/subject/body) for viewport-driven UI,
/// e.g. showing the author name next to each row in a scrolling commit list.
///
/// Unlike BlameStore/FileHistoryStore, which spawn a fresh `git` process per
/// call, this is a thin wrapper around CatFileBatch's single long-lived
/// `git cat-file --batch` process -- this store is CatFileBatch's first
/// consumer (see its doc comment), so it owns that process's start()/stop()
/// lifecycle. Reads still lazily (re)start the process on demand, same as
/// CatFileBatch::read() itself; stop() only exists so a session teardown can
/// end it explicitly instead of waiting on destruction order.
class CommitMetaStore {
public:
    CommitMetaStore(std::filesystem::path gitExecutable, RepoPaths paths);
    ~CommitMetaStore();

    CommitMetaStore(const CommitMetaStore&) = delete;
    CommitMetaStore& operator=(const CommitMetaStore&) = delete;

    /// Batch commit-metadata read, newest-callers-win in no particular
    /// order -- results simply follow `oids`. A failure on one oid does not
    /// abort the rest (see CatFileBatch::readCommits()'s doc comment): a
    /// viewport request for hundreds of rows must still return whichever
    /// succeed rather than lose the whole batch to one bad oid.
    std::vector<CommitMeta> read(const std::vector<ObjectId>& oids, CancellationToken token);

    /// Explicitly stops the underlying `cat-file --batch` child. Not required
    /// before destruction -- the CatFileBatch member's own destructor tears
    /// the child down -- but exposed for symmetry with the rest of this
    /// store's lifecycle and for tests that want to assert restart behaviour.
    void stop();

private:
    CatFileBatch batch_;
};

}  // namespace gbm
