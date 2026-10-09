#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"

#include <string>

namespace gbm {

/// The commit message git has prepared for an in-progress merge or squash
/// merge, as `git commit` would commit it: readPreparedCommitMessage()'s
/// SQUASH_MSG-then-MERGE_MSG text with comment lines stripped by
/// `git stripspace --strip-comments`, so git's own comment character
/// (core.commentChar) decides what a comment is, not a hard-coded '#'
/// (prepared-commit-message-spec.html M2/M5, ruling ①: the Working Copy box
/// shows exactly what will be committed).
///
/// Empty, with no subprocess run, when git prepared no message. The trailing
/// newline is not guaranteed ([CPP-run-not-byte-exact]); the Dart side splits
/// on lines, so it does not depend on one.
///
/// Read-only, like SquashMessageStore: no Operation, because nothing mutates.
class PreparedMessageStore {
public:
    PreparedMessageStore(IProcessRunner& runner, RepoPaths paths);

    GitResult<std::string> read(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
