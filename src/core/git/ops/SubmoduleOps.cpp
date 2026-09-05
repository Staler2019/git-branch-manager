#include "core/git/ops/SubmoduleOps.h"

#include "core/git/AskpassHelper.h"

#include <unordered_map>
#include <utility>

namespace gbm {

namespace {

void appendPathsArgs(std::vector<std::string>& args, const std::vector<std::string>& paths) {
    if (paths.empty()) {
        return;
    }
    args.emplace_back("--");
    for (const auto& path : paths) {
        args.push_back(path);
    }
}

class AddSubmoduleOperation final : public Operation {
public:
    explicit AddSubmoduleOperation(AddSubmoduleRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Add submodule " + request_.url; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.url.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "A submodule URL is required");
            return outcome;
        }

        std::vector<std::string> args{"submodule", "add"};
        if (!request_.branch.empty()) {
            args.emplace_back("-b");
            args.push_back(request_.branch);
        }
        args.push_back(request_.url);
        if (!request_.path.empty()) {
            args.push_back(request_.path);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        command.idleTimeout = GitCommand::kHangCeiling;  // clones a remote; can be slow.
        askpass::wire(command, request_.askpassDir);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    AddSubmoduleRequest request_;
};

class InitSubmodulesOperation final : public Operation {
public:
    explicit InitSubmodulesOperation(SubmodulePathsRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Initialise submodules"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"submodule", "init"};
        appendPathsArgs(args, request_.paths);

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(60);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    SubmodulePathsRequest request_;
};

class UpdateSubmodulesOperation final : public Operation {
public:
    explicit UpdateSubmodulesOperation(UpdateSubmodulesRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Update submodules"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"submodule", "update"};
        if (request_.init) {
            args.emplace_back("--init");
        }
        if (request_.recursive) {
            args.emplace_back("--recursive");
        }
        if (request_.remote) {
            args.emplace_back("--remote");
        }
        appendPathsArgs(args, request_.paths);

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        command.idleTimeout = GitCommand::kHangCeiling;  // clones/fetches; can be slow.
        askpass::wire(command, request_.askpassDir);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    UpdateSubmodulesRequest request_;
};

class SyncSubmodulesOperation final : public Operation {
public:
    explicit SyncSubmodulesOperation(SubmodulePathsRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Sync submodule URLs"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"submodule", "sync"};
        if (request_.recursive) {
            args.emplace_back("--recursive");
        }
        appendPathsArgs(args, request_.paths);

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(60);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    SubmodulePathsRequest request_;
};

class DeinitSubmodulesOperation final : public Operation {
public:
    explicit DeinitSubmodulesOperation(DeinitSubmodulesRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Deinitialise submodules"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"submodule", "deinit"};
        if (request_.force) {
            args.emplace_back("-f");
        }
        if (request_.paths.empty()) {
            // `git submodule deinit` refuses a bare invocation with no pathspec
            // and no `--all`, unlike init/update/sync, which default to every
            // submodule -- so the "every submodule" case needs the flag spelled
            // out explicitly here.
            args.emplace_back("--all");
        } else {
            appendPathsArgs(args, request_.paths);
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
        outcome.summary = describe();
        return outcome;
    }

private:
    DeinitSubmodulesRequest request_;
};

}  // namespace

SubmoduleStore::SubmoduleStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<SubmoduleInfo>> SubmoduleStore::list(CancellationToken token) {
    struct Declared {
        std::string name;
        std::string url;
        std::string branch;
    };

    // Keyed by path: `.gitmodules` sections are keyed by name, but that name is
    // usually (not always) equal to the path, so parsing keys off the `.path`
    // entry each section declares rather than assuming name == path.
    std::unordered_map<std::string, Declared> byPath;

    {
        std::error_code ec;
        const bool hasGitmodules = !paths_.workDir().empty() &&
                                   std::filesystem::exists(paths_.workDir() / ".gitmodules", ec);
        if (hasGitmodules) {
            GitCommand configCmd(
                paths_.commandDir(),
                {"config", "--file", ".gitmodules", "--get-regexp", "^submodule\\."});
            configCmd.timeout = std::chrono::seconds(30);
            auto configResult = runner_.run(configCmd, token);
            if (configResult) {
                // Each line is "submodule.<name>.<key> <value>"; <name> may itself
                // contain dots, so the key is split from the right, not the left.
                static constexpr std::string_view kPrefix = "submodule.";
                std::unordered_map<std::string, Declared> byName;
                std::size_t start = 0;
                while (start <= configResult->out.size()) {
                    const std::size_t at = configResult->out.find('\n', start);
                    const std::string_view line(
                        configResult->out.data() + start,
                        (at == std::string::npos ? configResult->out.size() : at) - start);
                    const std::size_t sp = line.find(' ');
                    if (sp != std::string_view::npos && line.starts_with(kPrefix)) {
                        const std::string_view key = line.substr(0, sp);
                        const std::string_view value = line.substr(sp + 1);
                        const std::string_view withoutPrefix = key.substr(kPrefix.size());
                        const std::size_t lastDot = withoutPrefix.rfind('.');
                        if (lastDot != std::string_view::npos) {
                            const std::string name(withoutPrefix.substr(0, lastDot));
                            const std::string_view attr = withoutPrefix.substr(lastDot + 1);
                            Declared& entry = byName[name];
                            entry.name = name;
                            if (attr == "url") {
                                entry.url = std::string(value);
                            } else if (attr == "branch") {
                                entry.branch = std::string(value);
                            } else if (attr == "path") {
                                byPath[std::string(value)] = entry;
                            }
                        }
                    }
                    if (at == std::string::npos) {
                        break;
                    }
                    start = at + 1;
                }
                // A second pass so url/branch entries seen after path are not
                // dropped, since the map above snapshots `entry` at path-time.
                for (auto& [path, declared] : byPath) {
                    auto found = byName.find(declared.name);
                    if (found != byName.end()) {
                        declared.url = found->second.url;
                        declared.branch = found->second.branch;
                    }
                }
            }
            // A malformed .gitmodules is not fatal to listing status below; the
            // submodule simply shows up with no url/branch metadata attached.
        }
    }

    GitCommand statusCmd(paths_.commandDir(), {"submodule", "status"});
    statusCmd.timeout = std::chrono::seconds(120);
    auto statusResult = runner_.run(statusCmd, token);
    if (!statusResult) {
        return fail(std::move(statusResult).error());
    }

    // Each line: a one-character status prefix, a 40-(or more, for sha256)
    // character oid, a space, the path, and an optional " (<describe>)" suffix
    // that is dropped here -- this is the same "Would remove " prefix-matching
    // leniency CleanPreviewer uses, since `git submodule status` has no
    // `--porcelain` form to parse instead.
    std::vector<SubmoduleInfo> infos;
    std::size_t start = 0;
    while (start <= statusResult->out.size()) {
        const std::size_t at = statusResult->out.find('\n', start);
        const std::string_view line(
            statusResult->out.data() + start,
            (at == std::string::npos ? statusResult->out.size() : at) - start);
        if (line.size() > 1) {
            const char statusChar = line.front();
            std::string_view rest = line.substr(1);
            const std::size_t sp = rest.find(' ');
            if (sp != std::string_view::npos) {
                SubmoduleInfo info;
                info.headOid = std::string(rest.substr(0, sp));
                std::string_view pathAndDescribe = rest.substr(sp + 1);
                const std::size_t paren = pathAndDescribe.rfind(" (");
                info.path =
                    std::string(paren == std::string_view::npos ? pathAndDescribe
                                                                : pathAndDescribe.substr(0, paren));
                switch (statusChar) {
                    case '-':
                        info.state = SubmoduleInfo::State::NotInitialized;
                        break;
                    case '+':
                        info.state = SubmoduleInfo::State::Modified;
                        break;
                    case 'U':
                        info.state = SubmoduleInfo::State::Conflicted;
                        break;
                    default:
                        info.state = SubmoduleInfo::State::UpToDate;
                        break;
                }
                if (auto found = byPath.find(info.path); found != byPath.end()) {
                    info.name = found->second.name;
                    info.url = found->second.url;
                    info.branch = found->second.branch;
                } else {
                    info.name = info.path;
                }
                infos.push_back(std::move(info));
            }
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return infos;
}

std::unique_ptr<Operation> makeAddSubmoduleOperation(AddSubmoduleRequest request) {
    return std::make_unique<AddSubmoduleOperation>(std::move(request));
}

std::unique_ptr<Operation> makeInitSubmodulesOperation(SubmodulePathsRequest request) {
    return std::make_unique<InitSubmodulesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeUpdateSubmodulesOperation(UpdateSubmodulesRequest request) {
    return std::make_unique<UpdateSubmodulesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeSyncSubmodulesOperation(SubmodulePathsRequest request) {
    return std::make_unique<SyncSubmodulesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeDeinitSubmodulesOperation(DeinitSubmodulesRequest request) {
    return std::make_unique<DeinitSubmodulesOperation>(std::move(request));
}

}  // namespace gbm
