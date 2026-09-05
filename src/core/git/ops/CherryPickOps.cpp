#include "core/git/ops/CherryPickOps.h"

#include <utility>

namespace gbm {

namespace {

class CherryPickOperation final : public Operation {
public:
    explicit CherryPickOperation(CherryPickRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        if (request_.commits.size() == 1) {
            return "Cherry-pick " + request_.commits.front().shortHex();
        }
        return "Cherry-pick " + std::to_string(request_.commits.size()) + " commits";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.commits.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No commits selected to pick");
            return outcome;
        }

        if (request_.stashFirst) {
            GitCommand stash(paths.commandDir(),
                             {"stash",
                              "push",
                              "--include-untracked",
                              "-m",
                              "git-branch-manager: before cherry-pick"});
            stash.timeout = std::chrono::seconds(600);
            auto stashed = runner.run(stash, token);
            if (!stashed) {
                outcome.error = std::move(stashed).error();
                outcome.summary = "Could not stash your changes, so nothing was picked";
                return outcome;
            }
        }

        std::vector<std::string> args{"cherry-pick"};
        if (request_.mainline > 0) {
            args.emplace_back("-m");
            args.push_back(std::to_string(request_.mainline));
        }
        if (request_.noCommit) {
            args.emplace_back("--no-commit");
        }
        for (const ObjectId& commit : request_.commits) {
            args.push_back(commit.hex());
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        command.idleTimeout = GitCommand::kHangCeiling;

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = describe();
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // A dirty-work-tree failure used to push StashAndRetry/Abort choices
        // here -- see MergeOps.cpp's identical comment; the same
        // [CULT-orphan-wiring] shape applies: no Dart reader for a
        // "cherry-pick"-kind outcome's choices.

        // As with a conflicting merge, this is git stopping exactly where it
        // should: the conflict is recorded in the index and CHERRY_PICK_HEAD, and
        // any remaining commits stay queued in the sequencer for --continue or
        // --skip. Nothing here recovers on its own.
        if (error.code == GitError::Code::Conflict) {
            outcome.summary = "Cherry-pick stopped with conflicts to resolve";
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    CherryPickRequest request_;
};

/// Shared by --continue/--skip/--abort: same shape, different verb, all legal
/// only while a pick sequence is actually in progress.
class CherryPickControlOperation final : public Operation {
public:
    enum class Verb { Continue, Skip, Abort };

    CherryPickControlOperation(Verb verb, std::string description)
        : verb_(verb), description_(std::move(description)) {}

    std::string describe() const override { return description_; }

    bool allowedDuringSequencerOperation() const override { return true; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        const char* flag = verb_ == Verb::Continue ? "--continue"
                           : verb_ == Verb::Skip   ? "--skip"
                                                   : "--abort";
        GitCommand command(paths.commandDir(), {"cherry-pick", flag});
        command.timeout = std::chrono::seconds(120);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = description_;
        return outcome;
    }

private:
    Verb verb_;
    std::string description_;
};

}  // namespace

std::unique_ptr<Operation> makeCherryPickOperation(CherryPickRequest request) {
    return std::make_unique<CherryPickOperation>(std::move(request));
}

std::unique_ptr<Operation> makeCherryPickContinueOperation() {
    return std::make_unique<CherryPickControlOperation>(CherryPickControlOperation::Verb::Continue,
                                                        "Continue cherry-pick");
}

std::unique_ptr<Operation> makeCherryPickSkipOperation() {
    return std::make_unique<CherryPickControlOperation>(CherryPickControlOperation::Verb::Skip,
                                                        "Skip commit");
}

std::unique_ptr<Operation> makeCherryPickAbortOperation() {
    return std::make_unique<CherryPickControlOperation>(CherryPickControlOperation::Verb::Abort,
                                                        "Abort cherry-pick");
}

}  // namespace gbm
