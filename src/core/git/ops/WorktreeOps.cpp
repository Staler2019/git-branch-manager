#include "core/git/ops/WorktreeOps.h"

#include "core/base/FsUtil.h"
#include "core/git/GitCommand.h"
#include "core/git/RefStore.h"
#include "core/git/WorkingCopyStatus.h"

#include <algorithm>
#include <charconv>
#include <optional>
#include <system_error>
#include <utility>

namespace gbm {

namespace {

/// Splits `git worktree list --porcelain` into per-worktree line groups. Each
/// entry starts with a `worktree <path>` line and ends at the next one (or
/// EOF); blank lines are separators, not part of any entry.
std::vector<std::vector<std::string_view>> splitEntries(std::string_view text) {
    std::vector<std::vector<std::string_view>> entries;
    std::size_t start = 0;
    while (start <= text.size()) {
        const std::size_t at = text.find('\n', start);
        const std::string_view line =
            text.substr(start, (at == std::string_view::npos ? text.size() : at) - start);
        if (line.rfind("worktree ", 0) == 0) {
            entries.emplace_back();
        }
        if (!line.empty() && !entries.empty()) {
            entries.back().push_back(line);
        }
        if (at == std::string_view::npos) {
            break;
        }
        start = at + 1;
    }
    return entries;
}

/// One `<commonDir>/worktrees/<name>/` directory, keyed both ways: by file
/// identity for a worktree still on disk, and by canonical path string for one
/// whose directory is gone and therefore has no identity left to compare.
struct AdminDirEntry {
    std::filesystem::path adminDir;
    std::optional<fsutil::FileId> id;
    std::string key;
};

std::string_view trimmed(std::string_view text) {
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r' || text.back() == ' ')) {
        text.remove_suffix(1);
    }
    return text;
}

/// The unix timestamp of one reflog entry, or nullopt if the line is not one.
///
/// **The timestamp is the second-to-last whitespace token, never a fixed field
/// index.** A reflog entry is `<old> <new> <committer>\t<message>`, and
/// `<committer>` is `Name <email> <unixtime> <tz>` where `Name` is a human name
/// that may contain spaces: measured, `user.name = "Jia Jyun Van Der Berg"`
/// puts the literal string `Van` at field 5. The tab is optional in the same
/// breath -- the first line `git worktree add` writes carries no message and
/// no tab at all, and that is the only line this function is ever asked about.
std::optional<std::int64_t> reflogEntryTime(std::string_view line) {
    const std::size_t tab = line.find('\t');
    if (tab != std::string_view::npos) {
        line = line.substr(0, tab);
    }
    line = trimmed(line);

    const std::size_t tzAt = line.rfind(' ');
    if (tzAt == std::string_view::npos) {
        return std::nullopt;
    }
    const std::string_view head = line.substr(0, tzAt);
    const std::size_t timeAt = head.rfind(' ');
    if (timeAt == std::string_view::npos) {
        return std::nullopt;
    }

    const std::string_view stamp = head.substr(timeAt + 1);
    std::int64_t seconds = 0;
    const auto* const end = stamp.data() + stamp.size();
    const std::from_chars_result parsed = std::from_chars(stamp.data(), end, seconds);
    if (parsed.ec != std::errc() || parsed.ptr != end || seconds <= 0) {
        return std::nullopt;
    }
    return seconds;
}

WorktreeInfo parseEntry(const std::vector<std::string_view>& lines,
                        const std::filesystem::path& mainWorkDir) {
    WorktreeInfo info;
    for (std::string_view line : lines) {
        if (line.rfind("worktree ", 0) == 0) {
            info.path = std::filesystem::path(std::string(line.substr(9)));
        } else if (line.rfind("HEAD ", 0) == 0) {
            info.headOid = std::string(line.substr(5));
        } else if (line.rfind("branch ", 0) == 0) {
            std::string ref(line.substr(7));
            const std::string_view prefix = "refs/heads/";
            if (ref.rfind(prefix, 0) == 0) {
                ref = ref.substr(prefix.size());
            }
            info.branch = ref;
        } else if (line == "bare") {
            info.isBare = true;
        } else if (line == "detached") {
            info.isDetached = true;
        } else if (line.rfind("locked", 0) == 0) {
            info.isLocked = true;
            if (line.size() > 7 && line[6] == ' ') {
                info.lockReason = std::string(line.substr(7));
            }
        } else if (line.rfind("prunable", 0) == 0) {
            info.isPrunable = true;
            if (line.size() > 9 && line[8] == ' ') {
                info.prunableReason = std::string(line.substr(9));
            }
        }
    }
    if (!mainWorkDir.empty() && !info.path.empty()) {
        // File identity rather than a string compare: git reports each
        // worktree's realpath, which on macOS differs textually from a path
        // built through /var (a symlink to /private/var) even though it names
        // the same directory. fileIdOf sidesteps that entirely.
        const auto entryId = fsutil::fileIdOf(info.path);
        const auto mainId = fsutil::fileIdOf(mainWorkDir);
        info.isMain = entryId.has_value() && mainId.has_value() && *entryId == *mainId;
    }
    return info;
}

class AddWorktreeOperation final : public Operation {
public:
    explicit AddWorktreeOperation(AddWorktreeRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Add worktree at " + request_.path.string(); }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.path.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No worktree path given");
            return outcome;
        }
        if (request_.createBranch && !RefStore::isValidBranchName(request_.newBranchName)) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument,
                         "\"" + request_.newBranchName + "\" is not a valid branch name");
            return outcome;
        }

        std::vector<std::string> args{"worktree", "add"};
        if (request_.force) {
            args.emplace_back("--force");
        }
        if (request_.createBranch) {
            args.emplace_back("-b");
            args.push_back(request_.newBranchName);
        } else if (request_.detach) {
            args.emplace_back("--detach");
        }
        args.push_back(request_.path.string());
        if (!request_.branch.empty()) {
            args.push_back(request_.branch);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Added worktree at " + request_.path.string();
        return outcome;
    }

private:
    AddWorktreeRequest request_;
};

class RemoveWorktreeOperation final : public Operation {
public:
    explicit RemoveWorktreeOperation(RemoveWorktreeRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Remove worktree " + request_.path.string(); }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"worktree", "remove"};
        if (request_.force) {
            args.emplace_back("--force");
        }
        args.push_back(request_.path.string());

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(120);
        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = "Removed worktree " + request_.path.string();
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        const bool dirtyOrLocked = error.detail.find("is dirty") != std::string::npos ||
                                   error.detail.find("locked working tree") != std::string::npos ||
                                   error.detail.find("contains modified") != std::string::npos;
        if (dirtyOrLocked && !request_.force) {
            outcome.choices.push_back(
                {OperationChoice::Kind::ForceDiscard,
                 "Remove anyway",
                 "Any uncommitted changes in this worktree are permanently lost.",
                 true});
            outcome.choices.push_back(
                {OperationChoice::Kind::Abort, "Cancel", "Leave the worktree in place.", false});
        }
        outcome.error = std::move(error);
        return outcome;
    }

private:
    RemoveWorktreeRequest request_;
};

class PruneWorktreesOperation final : public Operation {
public:
    explicit PruneWorktreesOperation(PruneWorktreesRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Prune worktrees"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"worktree", "prune", "--verbose"};
        if (request_.dryRun) {
            args.emplace_back("--dry-run");
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(60);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = result->out.empty() ? "Nothing to prune" : result->out;
        return outcome;
    }

private:
    PruneWorktreesRequest request_;
};

class LockWorktreeOperation final : public Operation {
public:
    explicit LockWorktreeOperation(LockWorktreeRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Lock worktree " + request_.path.string(); }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"worktree", "lock"};
        if (!request_.reason.empty()) {
            args.emplace_back("--reason");
            args.push_back(request_.reason);
        }
        args.push_back(request_.path.string());

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(30);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Locked " + request_.path.string();
        return outcome;
    }

private:
    LockWorktreeRequest request_;
};

class UnlockWorktreeOperation final : public Operation {
public:
    explicit UnlockWorktreeOperation(UnlockWorktreeRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Unlock worktree " + request_.path.string(); }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(), {"worktree", "unlock", request_.path.string()});
        command.timeout = std::chrono::seconds(30);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Unlocked " + request_.path.string();
        return outcome;
    }

private:
    UnlockWorktreeRequest request_;
};

class MoveWorktreeOperation final : public Operation {
public:
    explicit MoveWorktreeOperation(MoveWorktreeRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Move worktree to " + request_.to.string(); }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(),
                           {"worktree", "move", request_.from.string(), request_.to.string()});
        command.timeout = std::chrono::seconds(120);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Moved worktree to " + request_.to.string();
        return outcome;
    }

private:
    MoveWorktreeRequest request_;
};

}  // namespace

WorktreeStore::WorktreeStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

void attachPendingCounts(IProcessRunner& runner,
                         std::vector<WorktreeInfo>& worktrees,
                         CancellationToken token) {
    for (WorktreeInfo& worktree : worktrees) {
        if (worktree.isBare || worktree.isPrunable) {
            worktree.pendingCountState = WorktreePendingCountState::NotApplicable;
            continue;
        }

        // **No worktreeReadFlags() here, deliberately.** That function is
        // scoped to `git diff` reads (GitCommand.h says so in its first
        // sentence), and its own closing paragraph names `git status` as the
        // command the flag must *not* reach -- fsmonitor exists to accelerate
        // status, on precisely the machines whose owners opted into it. This
        // is a status read, so it keeps fsmonitor, exactly as the session's
        // own read does (WorkingCopyStatusReader::read, pinned by
        // WorktreeReadFlagsTest's StatusReadItselfDoesNotPayForThem). Lock
        // safety is already covered: ProcessRunner prepends globalFlags(),
        // which carries --no-optional-locks on every invocation.
        //
        // --untracked-files=normal, not =all: -uall enumerates every file in
        // an unbuilt output directory, and 「N 個未提交變更」 counts changes,
        // for which a directory is one. This is the one place the panel's
        // number can differ from what the Working Copy tab lists for the same
        // worktree, and it is a ratified difference rather than an oversight.
        //
        // --ignore-submodules=none matches the session's own read for the
        // opposite reason: it overrides whatever `diff.ignoreSubmodules` or
        // `submodule.<name>.ignore` the user configured, so the count cannot
        // silently omit a dirty submodule that the Working Copy tab shows.
        GitCommand command(worktree.path,
                           {"status",
                            "--porcelain=v2",
                            "-z",
                            "--untracked-files=normal",
                            "--ignore-submodules=none"});
        command.timeout = std::chrono::seconds(30);

        std::vector<std::string> records;
        const LineSink sink = [&records](std::string_view record) {
            records.emplace_back(record);
            return true;
        };
        auto result =
            runner.streamSeparated(command, IProcessRunner::Separator::Nul, sink, nullptr, token);
        if (!result) {
            // A failure is an answer, and it is recorded as one. Leaving it
            // Unmeasured would make a caller that re-requests "whatever has no
            // count" spin forever on this worktree.
            worktree.pendingCountState = WorktreePendingCountState::Failed;
            continue;
        }

        // Parsed, never counted: a rename spends two NUL records, so a record
        // count is silently wrong from the first rename onwards.
        worktree.pendingChanges =
            static_cast<std::uint32_t>(parsePorcelainV2Records(records).size());
        worktree.pendingCountState = WorktreePendingCountState::Measured;
    }
}

void attachCreatedAt(const RepoPaths& paths, std::vector<WorktreeInfo>& worktrees) {
    std::error_code ec;
    const std::filesystem::path worktreesDir = paths.commonDir() / "worktrees";
    if (!std::filesystem::is_directory(worktreesDir, ec)) {
        return;  // No linked worktree has ever existed here.
    }

    std::vector<AdminDirEntry> index;
    for (const auto& entry : std::filesystem::directory_iterator(worktreesDir, ec)) {
        const std::optional<std::string> gitdir = fsutil::readSmallFile(entry.path() / "gitdir");
        if (!gitdir) {
            continue;
        }
        // The file holds `<workPath>/.git` plus a newline.
        const std::filesystem::path pointer = fsutil::pathFromUtf8(trimmed(*gitdir));
        if (pointer.empty()) {
            continue;
        }
        const std::filesystem::path workPath = pointer.parent_path();
        index.push_back({entry.path(), fsutil::fileIdOf(workPath), fsutil::canonicalKey(workPath)});
    }

    for (WorktreeInfo& worktree : worktrees) {
        // File identity when the directory is still there, for the same reason
        // parseEntry uses it: on macOS a path built through /var differs
        // textually from git's realpath through /private/var while naming the
        // same directory. A prunable worktree has no directory left to
        // identify, and the string key is the only thing left to match on.
        const std::optional<fsutil::FileId> id = fsutil::fileIdOf(worktree.path);
        const std::string key = fsutil::canonicalKey(worktree.path);
        const auto hit = std::find_if(index.begin(), index.end(), [&](const AdminDirEntry& admin) {
            return id && admin.id ? *id == *admin.id : admin.key == key;
        });
        if (hit == index.end()) {
            continue;  // The current worktree, whose administration is commonDir itself.
        }

        const std::optional<std::string> reflog =
            fsutil::readSmallFile(hit->adminDir / "logs" / "HEAD");
        if (!reflog) {
            continue;  // core.logAllRefUpdates off, or a directory older than it.
        }
        const std::optional<std::int64_t> at =
            reflogEntryTime(std::string_view(*reflog).substr(0, reflog->find('\n')));
        if (at) {
            worktree.createdAtUnix = *at;
        }
    }
}

GitResult<std::vector<WorktreeInfo>> WorktreeStore::list(CancellationToken token) {
    GitCommand command(paths_.commandDir(), {"worktree", "list", "--porcelain"});
    command.timeout = std::chrono::seconds(30);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<WorktreeInfo> infos;
    for (const auto& entry : splitEntries(result->out)) {
        if (!entry.empty()) {
            infos.push_back(parseEntry(entry, paths_.workDir()));
        }
    }
    // Positional, and it has to be: nothing in the porcelain output *says*
    // which worktree is the main one. Entry 0 is, from every vantage point.
    // Kept here rather than inside parseEntry() because parseEntry sees one
    // entry at a time and position is a property of the list.
    if (!infos.empty()) {
        infos.front().isPrimary = true;
    }
    // Part of the plain list, unlike attachPendingCounts: no process, no work
    // tree read. See its declaration for why that difference decides this.
    attachCreatedAt(paths_, infos);
    return infos;
}

std::unique_ptr<Operation> makeAddWorktreeOperation(AddWorktreeRequest request) {
    return std::make_unique<AddWorktreeOperation>(std::move(request));
}

std::unique_ptr<Operation> makeRemoveWorktreeOperation(RemoveWorktreeRequest request) {
    return std::make_unique<RemoveWorktreeOperation>(std::move(request));
}

std::unique_ptr<Operation> makePruneWorktreesOperation(PruneWorktreesRequest request) {
    return std::make_unique<PruneWorktreesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeLockWorktreeOperation(LockWorktreeRequest request) {
    return std::make_unique<LockWorktreeOperation>(std::move(request));
}

std::unique_ptr<Operation> makeUnlockWorktreeOperation(UnlockWorktreeRequest request) {
    return std::make_unique<UnlockWorktreeOperation>(std::move(request));
}

std::unique_ptr<Operation> makeMoveWorktreeOperation(MoveWorktreeRequest request) {
    return std::make_unique<MoveWorktreeOperation>(std::move(request));
}

}  // namespace gbm
