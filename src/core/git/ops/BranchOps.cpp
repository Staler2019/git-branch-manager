#include "core/git/ops/BranchOps.h"

#include "core/base/FsUtil.h"
#include "core/git/AskpassHelper.h"
#include "core/git/RefStore.h"

#include <algorithm>
#include <chrono>
#include <optional>
#include <set>
#include <sstream>
#include <string_view>
#include <utility>
#include <vector>

namespace gbm {

namespace {

/// What refineSummaryFromRemoteRefs found, so the caller can pick a "Delete
/// anyway" explanation that agrees with the summary it just wrote -- without
/// this, a FoundElsewhere summary ("...will not lose anything") sat next to
/// an explanation that still claimed "only reachable through the reflog",
/// two directly contradictory claims in the one dialog the whole probe exists
/// to make trustworthy.
enum class RemoteRefProbeOutcome {
    ProbeFailed,
    NotFoundElsewhere,
    FoundElsewhere,
};

/// After `git branch -d <name>` refuses because the branch is "not fully
/// merged", checks whether a remote-tracking ref other than the branch's own
/// already contains it -- the exact state left by squash- or merge-committing
/// a PR without having pulled the integration branch since. `-d` only checks
/// reachability from local refs, so it cannot tell "genuinely unmerged" apart
/// from "merged on the remote, local view is stale" on its own.
///
/// This can only narrow "not found" down to "not found in the last-fetched
/// view" -- refs/remotes/ is a local cache, not the remote's live state -- so
/// the "not found" branch below must say exactly that rather than asserting
/// the branch was never merged anywhere.
RemoteRefProbeOutcome refineSummaryFromRemoteRefs(IProcessRunner& runner,
                                                  const RepoPaths& paths,
                                                  const std::string& name,
                                                  CancellationToken token,
                                                  OperationOutcome& outcome) {
    GitCommand probe(paths.commandDir(),
                     {"for-each-ref", "--format=%(refname)", "--contains", name, "refs/remotes/"});
    probe.timeout = std::chrono::milliseconds(5000);

    auto probeResult = runner.run(probe, token);
    if (!probeResult) {
        // The probe failing (offline, corrupt ref, timeout) must not mask the
        // real delete failure with something less informative -- leave
        // outcome.summary exactly as the caller already set it.
        return RemoteRefProbeOutcome::ProbeFailed;
    }

    static constexpr std::string_view kRemotesPrefix = "refs/remotes/";
    std::string elsewhere;
    std::istringstream lines(probeResult->out);
    std::string line;
    while (std::getline(lines, line)) {
        if (line.empty()) {
            continue;
        }
        // The branch's own remote-tracking ref (e.g. refs/remotes/origin/<name>)
        // only means it was pushed, not that anything merged it -- exclude it
        // so a plain `git push` doesn't get misread as "safe to delete".
        const bool isOwnUpstream =
            line.size() > name.size() + 1 &&
            line.compare(line.size() - name.size(), name.size(), name) == 0 &&
            line[line.size() - name.size() - 1] == '/';
        if (isOwnUpstream) {
            continue;
        }
        // refs/remotes/<remote>/HEAD is a symref alias for that remote's
        // default branch, not a real one -- `for-each-ref` lists it
        // alongside the branches it points at (and, sorting alphabetically,
        // before them), so without this it would win as "the" remote to
        // name and tell the user their commits are safe on a ref that means
        // nothing to them.
        static constexpr std::string_view kHeadSuffix = "/HEAD";
        if (line.size() >= kHeadSuffix.size() &&
            line.compare(line.size() - kHeadSuffix.size(), kHeadSuffix.size(), kHeadSuffix) == 0) {
            continue;
        }
        elsewhere = line;
        break;
    }

    if (elsewhere.empty()) {
        outcome.summary =
            "This branch's commits were not found on any remote-tracking ref from your last "
            "fetch. If it was just merged on the remote, fetch and try again -- otherwise "
            "deleting it makes them reachable only through the reflog";
        return RemoteRefProbeOutcome::NotFoundElsewhere;
    }

    const std::string label = elsewhere.rfind(kRemotesPrefix, 0) == 0
                                  ? elsewhere.substr(kRemotesPrefix.size())
                                  : elsewhere;
    outcome.summary = "This branch's commits already exist on " + label +
                      "; deleting it will not lose anything, your local branch is just behind";
    return RemoteRefProbeOutcome::FoundElsewhere;
}

/// Every local branch that exists right now, by short name.
///
/// `git branch -d/-D` is **per-name**: it deletes the names it can and exits 1
/// if any one of them failed. Measured on git 2.55.0:
///
///     $ git branch -d a cur b
///     error: cannot delete branch 'cur' used by worktree at '...'
///     Deleted branch a (was 668c5ce).
///     Deleted branch b (was 668c5ce).
///     exit=1
///
/// So a single exit-code check cannot answer "what happened", and reading the
/// per-name stderr instead is not an option: git's messages go through gettext
/// and change with the user's locale. Comparing this set before and after the
/// run is locale-immune, and it is the same command either way.
///
/// std::nullopt when the probe itself failed. Callers then behave exactly as
/// they did before it existed -- a probe that cannot see must not make the
/// delete worse than not probing at all.
std::optional<std::set<std::string>> readLocalBranchNames(IProcessRunner& runner,
                                                          const RepoPaths& paths,
                                                          CancellationToken token) {
    GitCommand probe(paths.commandDir(),
                     {"for-each-ref", "--format=%(refname:short)", "refs/heads/"});
    probe.timeout = std::chrono::milliseconds(5000);

    auto result = runner.run(probe, token);
    if (!result) {
        return std::nullopt;
    }

    std::set<std::string> names;
    std::istringstream lines(result->out);
    std::string line;
    while (std::getline(lines, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (!line.empty()) {
            names.insert(line);
        }
    }
    return names;
}

std::string joinBranchNames(const std::vector<std::string>& names) {
    std::string joined;
    for (std::size_t i = 0; i < names.size(); ++i) {
        if (i > 0) {
            joined += ", ";
        }
        joined += names[i];
    }
    return joined;
}

class CreateBranchOperation final : public Operation {
public:
    explicit CreateBranchOperation(CreateBranchRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Create branch " + request_.name; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (!RefStore::isValidBranchName(request_.name)) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "\"" + request_.name + "\" is not a valid branch name");
            return outcome;
        }

        std::vector<std::string> args{"branch", request_.name};
        if (!request_.startPoint.empty()) {
            args.push_back(request_.startPoint);
        }
        if (request_.setUpstream && !request_.upstream.empty()) {
            args.emplace_back("--track");
            args.push_back(request_.upstream);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(60);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }

        if (request_.checkoutAfter) {
            GitCommand checkoutCommand(paths.commandDir(), {"checkout", request_.name});
            checkoutCommand.timeout = std::chrono::seconds(60);
            auto checkoutResult = runner.run(checkoutCommand, token);
            if (!checkoutResult) {
                // The branch exists at this point -- report the checkout
                // failure rather than silently leaving HEAD where it was,
                // since the caller asked to switch to it.
                outcome.error = std::move(checkoutResult).error();
                outcome.summary = outcome.error->message;
                return outcome;
            }
        }

        outcome.succeeded = true;
        outcome.summary = "Created branch " + request_.name;
        return outcome;
    }

private:
    CreateBranchRequest request_;
};

class RenameBranchOperation final : public Operation {
public:
    explicit RenameBranchOperation(RenameBranchRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Rename branch " + request_.from + " to " + request_.to;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (!RefStore::isValidBranchName(request_.to)) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "\"" + request_.to + "\" is not a valid branch name");
            return outcome;
        }

        // A case-only rename ("Feature" -> "feature") fails on Windows and macOS,
        // where the ref file path is the same name to the filesystem. Going via a
        // temporary name is the only way to make it work on those platforms.
        const bool caseOnlyRename =
            request_.from != request_.to && fsutil::pathsEquivalent(request_.from, request_.to);

        if (caseOnlyRename && fsutil::caseInsensitiveFilesystem()) {
            const std::string temporary = request_.from + ".gbm-rename-tmp";
            GitCommand first(paths.commandDir(), {"branch", "-m", request_.from, temporary});
            first.timeout = std::chrono::seconds(60);
            auto step = runner.run(first, token);
            if (!step) {
                outcome.error = std::move(step).error();
                outcome.summary = outcome.error->message;
                return outcome;
            }

            GitCommand second(paths.commandDir(), {"branch", "-m", temporary, request_.to});
            second.timeout = std::chrono::seconds(60);
            auto finish = runner.run(second, token);
            if (!finish) {
                outcome.error = std::move(finish).error();
                // Leaving the branch under a temporary name would be worse than the
                // original failure, so say exactly where it ended up.
                outcome.summary =
                    "The branch is currently named " + temporary + "; rename it manually to finish";
                return outcome;
            }
            return finishLocalRename(runner, paths, token);
        }

        std::vector<std::string> args{
            "branch", request_.force ? "-M" : "-m", request_.from, request_.to};
        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(60);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        return finishLocalRename(runner, paths, token);
    }

private:
    /// Everything after the local rename has landed. Either carries the
    /// rename through to the remote -- push the new name, then delete the
    /// old one, in that order -- or, when the branch is staying local-only,
    /// drops the tracking config `git branch -m` would otherwise have left
    /// pointing at the old remote branch.
    ///
    /// A failure here is reported as a failure with the local rename spelled
    /// out in the summary, the same shape DeleteTagOperation uses: the branch
    /// really has been renamed, and saying only "push failed" would leave the
    /// user unable to tell which half happened.
    OperationOutcome finishLocalRename(IProcessRunner& runner,
                                       const RepoPaths& paths,
                                       CancellationToken token) {
        OperationOutcome outcome;
        outcome.succeeded = true;
        outcome.summary = "Renamed to " + request_.to;

        if (!request_.renameRemote) {
            // `git branch -m` carries branch.<name>.remote/.merge across with
            // the rename, so without this the renamed branch would still
            // track the *old* remote branch. Its exit code is deliberately
            // ignored rather than swallowed: --unset-upstream fails when
            // there was no upstream to begin with, which is the common case
            // and not an error -- either way the branch ends up with no
            // upstream, which is the whole point.
            GitCommand unsetUpstream(paths.commandDir(),
                                     {"branch", "--unset-upstream", request_.to});
            unsetUpstream.timeout = std::chrono::seconds(60);
            (void)runner.run(unsetUpstream, token);
            return outcome;
        }

        // No local timeout on either remote step: the budget belongs to the
        // network, exactly as PushTagOperation/DeleteTagOperation do it.
        GitCommand push(paths.commandDir(),
                        {"push", "--set-upstream", request_.remoteName, request_.to});
        push.timeout = std::chrono::milliseconds(0);
        push.idleTimeout = GitCommand::kHangCeiling;
        askpass::wire(push, request_.askpassDir);
        auto pushed = runner.run(push, token);
        if (!pushed) {
            outcome.succeeded = false;
            outcome.error = std::move(pushed).error();
            outcome.summary = "Renamed locally to " + request_.to + ", but could not push it to " +
                              request_.remoteName + ": " + outcome.error->message;
            return outcome;
        }

        GitCommand deleteOld(paths.commandDir(),
                             {"push", request_.remoteName, "--delete", request_.from});
        deleteOld.timeout = std::chrono::milliseconds(0);
        deleteOld.idleTimeout = GitCommand::kHangCeiling;
        askpass::wire(deleteOld, request_.askpassDir);
        auto deleted = runner.run(deleteOld, token);
        if (!deleted) {
            outcome.succeeded = false;
            outcome.error = std::move(deleted).error();
            outcome.summary = "Renamed to " + request_.to +
                              " and pushed it, but could not delete " + request_.from + " on " +
                              request_.remoteName + ": " + outcome.error->message;
            return outcome;
        }

        outcome.summary = "Renamed to " + request_.to + " locally and on " + request_.remoteName;
        return outcome;
    }

    RenameBranchRequest request_;
};

class DeleteBranchOperation final : public Operation {
public:
    explicit DeleteBranchOperation(DeleteBranchRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Delete branch" + std::string(request_.names.size() > 1 ? "es " : " ") + joinNames();
    }

    std::string kind() const override { return "delete-branch"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        // The names actually sent to git. For a local delete this drops any
        // that no longer exist, which is the difference between the
        // "Delete anyway" retry working and failing: the first `-d` pass
        // partially succeeds (see readLocalBranchNames), so resending the
        // user's whole selection makes git answer "branch 'x' not found" for
        // the ones it already removed and exit 1 for work that is done.
        std::vector<std::string> targets = request_.names;
        std::optional<std::set<std::string>> before;
        if (!request_.isRemote) {
            before = readLocalBranchNames(runner, paths, token);
            // An *empty* answer is treated as "could not tell", not as
            // "every branch is already gone": a repository you are deleting
            // a local branch in always has at least that branch, so an empty
            // refs/heads/ listing means the probe told us nothing useful --
            // and acting on it would report success for a delete that never
            // ran. Only a non-empty listing is evidence.
            if (before && before->empty()) {
                before.reset();
            }
            if (before) {
                std::vector<std::string> live;
                for (const std::string& name : targets) {
                    if (before->count(name) != 0) {
                        live.push_back(name);
                    }
                }
                if (live.empty()) {
                    // Nothing left to do. Running git here could only print
                    // "not found" and turn a completed request into a
                    // failure dialog.
                    outcome.succeeded = true;
                    outcome.summary = "Already deleted: " + joinNames();
                    return outcome;
                }
                targets = std::move(live);
            }
        }

        std::vector<std::string> args;
        if (request_.isRemote) {
            // Deleting a remote branch is a network operation with a very
            // different blast radius from deleting a local ref.
            args = {"push", request_.remoteName, "--delete"};
        } else {
            args = {"branch", request_.force ? "-D" : "-d"};
        }
        args.insert(args.end(), targets.begin(), targets.end());

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout =
            request_.isRemote ? std::chrono::milliseconds(0) : std::chrono::milliseconds(60000);

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = "Deleted " + joinBranchNames(targets);
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // Exit 1 does not mean nothing happened. Re-reading the branch list
        // says which of `targets` really went, so the message can name both
        // halves instead of implying the whole selection survived. Computed
        // here and prefixed at the end, after every branch below has had its
        // say about *why* the rest failed.
        std::vector<std::string> deleted;
        if (before) {
            std::optional<std::set<std::string>> after = readLocalBranchNames(runner, paths, token);
            if (after) {
                for (const std::string& name : targets) {
                    if (after->count(name) == 0) {
                        deleted.push_back(name);
                    }
                }
            }
        }

        // The same probe answers a second question, and the message was the
        // only thing reading it: a failed outcome that nonetheless moved
        // refs/heads still owes every refs consumer a refresh, which
        // Session::submitOperation gates on this flag (see
        // OperationOutcome::mutatedRefs). Evidence-driven on purpose -- an
        // empty `deleted` means either nothing went or the probe could not
        // tell, and neither is grounds for claiming the repository changed.
        outcome.mutatedRefs = !deleted.empty();

        // `-d` refuses to delete unmerged work. Offering `-D` is legitimate, but
        // it has to be labelled honestly. Left unhandled this falls through to
        // classifyGitStderr's generic "Git reported an error" fallback, which
        // sends the user hunting through a collapsed Details pane for git's own
        // "not fully merged" phrasing -- see the worktree case below, which
        // already avoids exactly that.
        const bool notMerged = error.detail.find("not fully merged") != std::string::npos;
        if (notMerged && !request_.force) {
            // Matches describe()'s singular/plural split above: a multi-branch
            // delete can legitimately hit this with more than one name in
            // request_.names, and "This branch" reads wrong when several were
            // selected.
            outcome.summary = targets.size() > 1
                                  ? "These branches have commits that are not merged into any "
                                    "other branch you have locally"
                                  : "This branch has commits that are not merged into any other "
                                    "branch you have locally";
            // "Not merged locally" and "genuinely unmerged" are different claims:
            // a local integration branch that is simply behind its remote (the
            // exact situation right after squash- or merge-committing a PR and
            // not yet pulling) fails `-d` too, even though deleting it loses
            // nothing. Single-branch only, matching the shape of the summary
            // this produces; a multi-branch delete keeps the message above.
            //
            // The return value (RemoteRefProbeOutcome) used to drive a
            // "Delete anyway" explanation string built right here -- that
            // string no longer exists (OperationChoice carries no
            // label/explanation; DeleteBranchRecoveryDialogContent in
            // app_flutter composes its own from `kind` instead). What still
            // matters is the *side effect*: on a FoundElsewhere probe, this
            // rewrites outcome.summary in place to name the concrete
            // remote-tracking ref (e.g. "origin/main"), and that summary is
            // what actually reaches the dialog, via lastError.message.
            if (targets.size() == 1) {
                refineSummaryFromRemoteRefs(runner, paths, targets.front(), token, outcome);
            }
            // No Abort entry: DeleteBranchRecoveryDialogContent (app_flutter)
            // filters `abort` out of both its action-button row and its body
            // list, and its retryDeleteBranchWithChoice dispatch is a no-op
            // for it -- see CheckoutOp.cpp's identical reasoning just above.
            outcome.choices.push_back({OperationChoice::Kind::ForceDiscard, true});
        }

        // A branch checked out in another worktree cannot be deleted; git names
        // the worktree in its message, which is the useful part to surface.
        if (error.detail.find("used by worktree") != std::string::npos) {
            outcome.summary = "This branch is checked out in another worktree";
        }

        // Prefixed last so it survives every rewrite above. Reads as
        // "Deleted a, b. <why the rest did not go>" -- the honest shape,
        // where the old message said only the second half.
        if (!deleted.empty()) {
            std::vector<std::string> remaining;
            for (const std::string& name : targets) {
                if (std::find(deleted.begin(), deleted.end(), name) == deleted.end()) {
                    remaining.push_back(name);
                }
            }
            outcome.summary = "Deleted " + joinBranchNames(deleted) + ". " +
                              joinBranchNames(remaining) + ": " + outcome.summary;
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    std::string joinNames() const {
        std::string joined;
        for (std::size_t i = 0; i < request_.names.size(); ++i) {
            if (i > 0) {
                joined += ", ";
            }
            joined += request_.names[i];
        }
        return joined;
    }

    DeleteBranchRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeCreateBranchOperation(CreateBranchRequest request) {
    return std::make_unique<CreateBranchOperation>(std::move(request));
}

std::unique_ptr<Operation> makeRenameBranchOperation(RenameBranchRequest request) {
    return std::make_unique<RenameBranchOperation>(std::move(request));
}

std::unique_ptr<Operation> makeDeleteBranchOperation(DeleteBranchRequest request) {
    return std::make_unique<DeleteBranchOperation>(std::move(request));
}

}  // namespace gbm
