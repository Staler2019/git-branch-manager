#pragma once

#include "core/base/ObjectId.h"

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace gbm {

struct Signature {
    std::string name;
    std::string email;
    std::int64_t when = 0;    ///< Unix seconds.
    int tzOffsetMinutes = 0;  ///< Minutes east of UTC.
};

/// Everything the commit list needs to render one row, beyond what the graph
/// snapshot already holds.
///
/// This is fetched lazily in viewport-sized batches, never for all of history:
/// asking `rev-list` for author and subject forces git to inflate every commit
/// object, which costs seconds on a 500k-commit repository. The topology walk
/// stays cheap precisely because it does not ask for this.
struct CommitMeta {
    ObjectId oid;
    ObjectId tree;
    std::vector<ObjectId> parents;
    Signature author;
    Signature committer;
    std::string subject;  ///< First line of the message.
    std::string body;     ///< Remainder, with the blank separator removed.
    bool signedCommit = false;

    /// Parses a raw commit object as produced by `git cat-file`.
    /// Tolerant by design: unknown headers are skipped rather than rejected, so
    /// mergetag, gpgsig and future header types do not break history browsing.
    static CommitMeta parseRawCommit(const ObjectId& oid, std::string_view raw);
};

/// Parses "Name <email> 1699999999 +0200" as it appears in commit headers.
Signature parseSignature(std::string_view text);

}  // namespace gbm
