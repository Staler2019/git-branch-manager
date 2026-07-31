#pragma once

#include "core/git/OperationRunner.h"

#include <filesystem>
#include <memory>
#include <string>

namespace gbm {

struct CreateTagRequest {
    std::string name;
    std::string target;   ///< Commit-ish; empty means HEAD.
    std::string message;  ///< Non-empty makes this an annotated tag.
    bool force = false;
};

struct DeleteTagRequest {
    std::string name;
    /// Also deletes the tag on `remoteName` after the local delete succeeds.
    bool alsoRemote = false;
    std::string remoteName;
    std::filesystem::path askpassDir;
};

struct PushTagRequest {
    std::string remoteName;
    std::string name;  ///< Empty pushes every tag (`--tags`).
    std::filesystem::path askpassDir;
};

/// `git tag`, lightweight or annotated depending on whether `message` is set.
/// Validated against the same ref-name rules as a branch before git ever runs.
std::unique_ptr<Operation> makeCreateTagOperation(CreateTagRequest request);

/// `git tag -d`, optionally followed by `git push <remote> --delete <tag>`.
std::unique_ptr<Operation> makeDeleteTagOperation(DeleteTagRequest request);

/// `git push <remote> <tag>` or `git push <remote> --tags`.
std::unique_ptr<Operation> makePushTagOperation(PushTagRequest request);

}  // namespace gbm
