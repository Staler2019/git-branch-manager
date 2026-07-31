#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace gbm {

/// One line of `git blame` output.
struct BlameLine {
    ObjectId commitOid;
    std::string authorName;
    std::string authorEmail;
    std::int64_t authorTime = 0;
    std::string summary;    ///< The commit's subject line.
    int finalLine = 0;      ///< 1-based line number in the revision being blamed.
    int originalLine = 0;   ///< 1-based line number in the commit that introduced it.
    std::string content;    ///< The line itself, without its trailing newline.
    bool boundary = false;  ///< True at a shallow/grafted history's edge.
};

struct BlameResult {
    std::vector<BlameLine> lines;
    /// True when the output was truncated by kMaxBytes -- a generated or binary
    /// file blamed by mistake should not allocate unboundedly.
    bool truncated = false;
};

using BlameResultPtr = std::shared_ptr<const BlameResult>;

/// Runs and parses `git blame`. Read-only, like RefStore, so it is never routed
/// through OperationRunner.
class BlameStore {
public:
    /// Above this many bytes of `--line-porcelain` output, parsing stops rather
    /// than continuing unboundedly -- see DiffService's diff cap for the same
    /// reasoning.
    static constexpr std::size_t kMaxBytes = 16u * 1024u * 1024u;

    BlameStore(IProcessRunner& runner, RepoPaths paths);

    /// Blames `path` as of `revision` (empty means the working tree). `startLine`
    /// and `endLine` are 1-based and inclusive; either being zero blames the
    /// whole file.
    GitResult<BlameResultPtr> blame(const std::string& path,
                                    const std::string& revision,
                                    int startLine,
                                    int endLine,
                                    CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
