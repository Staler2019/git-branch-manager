#pragma once

#include "core/git/OperationRunner.h"

#include <memory>
#include <string>

namespace gbm {

struct CommitRequest {
    /// Full message: subject line, optionally followed by a blank line and a
    /// body. Left empty together with `amend` to keep the existing message
    /// unchanged (`git commit --amend --no-edit`); empty otherwise is rejected
    /// before git is ever run.
    std::string message;
    bool amend = false;
    bool signOff = false;
};

/// `git commit` / `git commit --amend`. The message travels over stdin via
/// `--file -` rather than `-m`, so a multi-paragraph body needs no escaping and
/// is never at the mercy of an argv length limit.
std::unique_ptr<Operation> makeCommitOperation(CommitRequest request);

}  // namespace gbm
