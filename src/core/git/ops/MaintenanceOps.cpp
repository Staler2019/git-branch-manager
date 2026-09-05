#include "core/git/ops/MaintenanceOps.h"

#include "core/git/GitCommand.h"

#include <utility>

namespace gbm {

bool hasCommitGraph(const RepoPaths& paths) {
    std::error_code ec;
    return std::filesystem::exists(paths.commitGraphFile(), ec) ||
           std::filesystem::exists(paths.commitGraphChainFile(), ec);
}

bool shouldOfferCommitGraph(bool hasGraph,
                            std::uint32_t rowCount,
                            CommitGraphPreference preference) {
    if (hasGraph) {
        return false;
    }
    if (preference != CommitGraphPreference::Unset) {
        // Enabled means the graph should already be getting written elsewhere
        // (or was, before something removed it -- e.g. a `git gc` that pruned
        // an out-of-date one); Declined means the user was asked and said no.
        // Neither is "ask again".
        return false;
    }
    return rowCount >= kCommitGraphAdviceMinRows;
}

namespace {

class WriteCommitGraphOperation final : public Operation {
public:
    explicit WriteCommitGraphOperation(WriteCommitGraphRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Build commit-graph"; }

    /// git writes the new graph to a temp file under objects/info/ and renames
    /// it into place only on success, so killing this leaves the object store
    /// exactly as it was -- unlike a checkout or rebase, there is no
    /// half-applied state a cancel could strand the repository in.
    bool killableMidFlight() const override { return true; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        std::vector<std::string> args = {"commit-graph", "write", "--reachable"};
        if (request_.changedPaths) {
            args.emplace_back("--changed-paths");
        }
        if (request_.split) {
            args.emplace_back("--split");
        }

        GitCommand command(paths.commandDir(), std::move(args));
        // A commit-graph write over a repository with hundreds of thousands of
        // commits can legitimately take a while; cancellation (not a timeout) is
        // the right way to stop it, same reasoning as CheckoutOperation's
        // network-op timeout of 0.
        command.timeout = std::chrono::milliseconds(0);
        command.idleTimeout = GitCommand::kHangCeiling;

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = "Built commit-graph";
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;
        outcome.error = std::move(error);
        return outcome;
    }

private:
    WriteCommitGraphRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeWriteCommitGraphOperation(WriteCommitGraphRequest request) {
    return std::make_unique<WriteCommitGraphOperation>(request);
}

}  // namespace gbm
