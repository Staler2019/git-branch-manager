#include "core/git/ops/RebaseOps.h"

#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <system_error>
#include <utility>

namespace gbm {

namespace {

std::string actionVerb(RebaseTodoEntry::Action action) {
    switch (action) {
        case RebaseTodoEntry::Action::Pick:
            return "pick";
        case RebaseTodoEntry::Action::Edit:
            return "edit";
        case RebaseTodoEntry::Action::Squash:
            return "squash";
        case RebaseTodoEntry::Action::Fixup:
            return "fixup";
        case RebaseTodoEntry::Action::Drop:
            return "drop";
    }
    return "pick";
}

std::string serializeTodo(const std::vector<RebaseTodoEntry>& todo) {
    std::string text;
    for (const auto& entry : todo) {
        text += actionVerb(entry.action);
        text += ' ';
        text += entry.shortOid.empty() ? entry.oid.hex() : entry.shortOid;
        text += ' ';
        text += entry.subject;
        text += '\n';
    }
    return text;
}

/// Writes `content` to a fresh temp file and returns its path, or an empty path
/// on failure.
std::filesystem::path writeTempFile(const std::string& content) {
    std::error_code ec;
    const auto dir = std::filesystem::temp_directory_path(ec);
    if (ec) {
        return {};
    }
    static std::atomic<std::uint64_t> counter{0};
    const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto path = dir / ("gbm-rebase-todo-" + std::to_string(now) + "-" +
                             std::to_string(counter.fetch_add(1)) + ".txt");
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        return {};
    }
    out << content;
    out.close();
    return path;
}

/// A single-quoted POSIX shell literal. Git always runs the sequence/message
/// editor command through a shell, and a temp directory containing spaces is
/// routine on Windows ("...\Local\Temp"), so the path must be quoted rather
/// than passed bare.
std::string shellQuote(const std::filesystem::path& path) {
    std::string quoted = "'";
    for (char c : path.string()) {
        if (c == '\'') {
            quoted += "'\\''";
        } else {
            quoted += c;
        }
    }
    quoted += "'";
    return quoted;
}

/// `cp` stands in for an interactive editor: git invokes `$GIT_SEQUENCE_EDITOR
/// <path-to-its-generated-todo>`, so setting it to `cp <ourfile>` makes that
/// invocation copy our pre-built plan over git's own before the sequencer reads
/// it back. `cp` needs nothing bundled: Git for Windows carries its own
/// coreutils and prepends them to PATH for exactly this kind of child process,
/// so this works unmodified on all three platforms -- see the CLI-only-backend
/// note in the README for why we lean on git's own toolchain rather than
/// shipping anything ourselves.
void applyRebaseEnv(GitCommand& command, const std::filesystem::path& todoFile) {
    command.envOverrides.emplace_back("GIT_SEQUENCE_EDITOR", "cp " + shellQuote(todoFile));
    // No terminal is available to write a squash/fixup message either, so the
    // default (git's own concatenation of the combined commits) is always
    // accepted, exactly as MergeOps does for a no-ff merge commit's message.
    command.envOverrides.emplace_back("GIT_EDITOR", "true");
}

class RebaseInteractiveOperation final : public Operation {
public:
    explicit RebaseInteractiveOperation(RebaseInteractiveRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override {
        return "Interactive rebase onto " +
               (request_.onto.empty() ? request_.upstream : request_.onto);
    }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.upstream.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No base commit selected to rebase onto");
            return outcome;
        }
        if (request_.todo.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "There are no commits to rebase");
            return outcome;
        }

        if (request_.stashFirst) {
            GitCommand stash(paths.commandDir(),
                             {"stash",
                              "push",
                              "--include-untracked",
                              "-m",
                              "git-branch-manager: before rebase"});
            stash.timeout = std::chrono::seconds(600);
            auto stashed = runner.run(stash, token);
            if (!stashed) {
                outcome.error = std::move(stashed).error();
                outcome.summary = "Could not stash your changes, so nothing was rebased";
                return outcome;
            }
        }

        const auto todoFile = writeTempFile(serializeTodo(request_.todo));
        if (todoFile.empty()) {
            outcome.error = GitError(GitError::Code::Io, "Could not write a temporary rebase plan");
            return outcome;
        }

        struct TempFileGuard {
            std::filesystem::path path;

            ~TempFileGuard() {
                std::error_code ec;
                std::filesystem::remove(path, ec);
            }
        } guard{todoFile};

        std::vector<std::string> args{"rebase", "-i"};
        if (!request_.onto.empty()) {
            args.emplace_back("--onto");
            args.push_back(request_.onto);
        }
        args.push_back(request_.upstream);

        GitCommand command(paths.commandDir(), std::move(args));
        applyRebaseEnv(command, todoFile);
        command.timeout = std::chrono::milliseconds(0);

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary =
                "Rebased onto " + (request_.onto.empty() ? request_.upstream : request_.onto);
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // A dirty-work-tree failure used to push StashAndRetry/Abort choices
        // here (via the now-deleted addDirtyWorkTreeChoices helper) -- see
        // MergeOps.cpp's identical comment; the same [CULT-orphan-wiring]
        // shape applies: no Dart reader for a "rebase"-kind outcome's
        // choices.
        // As with a conflicting merge or cherry-pick, this is git stopping
        // exactly where it should -- the conflict is recorded in the index, and
        // the remaining todo stays queued in rebase-merge/ for --continue,
        // --skip or --abort to work through.
        if (error.code == GitError::Code::Conflict) {
            outcome.summary = "Rebase stopped with conflicts to resolve";
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    RebaseInteractiveRequest request_;
};

class RebaseOperation final : public Operation {
public:
    explicit RebaseOperation(RebaseRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Rebase onto " + (request_.onto.empty() ? request_.upstream : request_.onto);
    }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.upstream.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No base commit selected to rebase onto");
            return outcome;
        }

        if (request_.stashFirst) {
            GitCommand stash(paths.commandDir(),
                             {"stash",
                              "push",
                              "--include-untracked",
                              "-m",
                              "git-branch-manager: before rebase"});
            stash.timeout = std::chrono::seconds(600);
            auto stashed = runner.run(stash, token);
            if (!stashed) {
                outcome.error = std::move(stashed).error();
                outcome.summary = "Could not stash your changes, so nothing was rebased";
                return outcome;
            }
        }

        std::vector<std::string> args{"rebase"};
        if (!request_.onto.empty()) {
            args.emplace_back("--onto");
            args.push_back(request_.onto);
        }
        // Measured (scratch repo, git 2.55.0): a plain `git rebase
        // --rebase-merges <upstream>` with no `-i` preserves a merge commit
        // that the default apply backend would otherwise flatten.
        if (request_.rebaseMerges) {
            args.emplace_back("--rebase-merges");
        }
        // Measured the same way: `git rebase --autosquash <upstream>`, again
        // with no `-i`, folds a `fixup!`/`squash!`/`amend!` commit into its
        // target. git's own docs confirm this is intentional: --autosquash
        // "uses the --interactive machinery internally, but it can be run
        // without an explicit --interactive".
        if (request_.autosquash) {
            args.emplace_back("--autosquash");
        }
        args.push_back(request_.upstream);

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary =
                "Rebased onto " + (request_.onto.empty() ? request_.upstream : request_.onto);
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // A dirty-work-tree failure used to push StashAndRetry/Abort choices
        // here -- see the identical comment on this class's sibling method
        // above.
        if (error.code == GitError::Code::Conflict) {
            outcome.summary = "Rebase stopped with conflicts to resolve";
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    RebaseRequest request_;
};

/// Shared by --continue/--skip/--abort: same shape, different verb, all legal
/// only while a rebase is actually in progress.
class RebaseControlOperation final : public Operation {
public:
    enum class Verb { Continue, Skip, Abort };

    RebaseControlOperation(Verb verb, std::string description)
        : verb_(verb), description_(std::move(description)) {}

    std::string describe() const override { return description_; }

    bool allowedDuringSequencerOperation() const override { return true; }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        const char* flag = verb_ == Verb::Continue ? "--continue"
                           : verb_ == Verb::Skip   ? "--skip"
                                                   : "--abort";
        GitCommand command(paths.commandDir(), {"rebase", flag});
        if (verb_ == Verb::Continue) {
            // A squash/fixup step resumed by --continue can still need to write
            // the combined message; see applyRebaseEnv above for why this is
            // always "accept the default" rather than left to open an editor.
            command.envOverrides.emplace_back("GIT_EDITOR", "true");
        }
        command.timeout =
            verb_ == Verb::Abort ? std::chrono::seconds(120) : std::chrono::milliseconds(0);

        auto result = runner.run(command, token);
        if (!result) {
            GitError error = std::move(result).error();
            outcome.summary = error.message;
            if (error.code == GitError::Code::Conflict) {
                outcome.summary = "Rebase stopped with conflicts to resolve";
            }
            outcome.error = std::move(error);
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

RebasePlanner::RebasePlanner(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<RebaseTodoEntry>> RebasePlanner::plan(const std::string& upstream,
                                                            CancellationToken token) {
    if (upstream.empty()) {
        return fail(GitError::Code::InvalidArgument, "No base commit selected to rebase onto");
    }

    GitCommand command(paths_.commandDir(),
                       {"log", "--format=%H%x09%h%x09%s", "--reverse", upstream + "..HEAD"});
    command.timeout = std::chrono::seconds(60);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<RebaseTodoEntry> entries;
    std::size_t start = 0;
    while (start <= result->out.size()) {
        const std::size_t at = result->out.find('\n', start);
        const std::string_view line(result->out.data() + start,
                                    (at == std::string::npos ? result->out.size() : at) - start);
        if (!line.empty()) {
            const std::size_t firstTab = line.find('\t');
            const std::size_t secondTab = firstTab == std::string_view::npos
                                              ? std::string_view::npos
                                              : line.find('\t', firstTab + 1);
            if (firstTab != std::string_view::npos && secondTab != std::string_view::npos) {
                RebaseTodoEntry entry;
                entry.oid = ObjectId::fromHex(line.substr(0, firstTab));
                entry.shortOid = std::string(line.substr(firstTab + 1, secondTab - firstTab - 1));
                entry.subject = std::string(line.substr(secondTab + 1));
                entries.push_back(std::move(entry));
            }
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return entries;
}

std::unique_ptr<Operation> makeRebaseInteractiveOperation(RebaseInteractiveRequest request) {
    return std::make_unique<RebaseInteractiveOperation>(std::move(request));
}

std::unique_ptr<Operation> makeRebaseOperation(RebaseRequest request) {
    return std::make_unique<RebaseOperation>(std::move(request));
}

std::unique_ptr<Operation> makeRebaseContinueOperation() {
    return std::make_unique<RebaseControlOperation>(RebaseControlOperation::Verb::Continue,
                                                    "Continue rebase");
}

std::unique_ptr<Operation> makeRebaseSkipOperation() {
    return std::make_unique<RebaseControlOperation>(RebaseControlOperation::Verb::Skip,
                                                    "Skip commit");
}

std::unique_ptr<Operation> makeRebaseAbortOperation() {
    return std::make_unique<RebaseControlOperation>(RebaseControlOperation::Verb::Abort,
                                                    "Abort rebase");
}

}  // namespace gbm
