#include "core/git/ops/ConfigOps.h"

#include "core/base/ThreadCheck.h"

#include <chrono>
#include <utility>
#include <vector>

namespace gbm {

namespace {

/// `git config --local --get <key>` exits 1 with empty stderr when the key is
/// unset -- not a genuine failure, just "nothing here". Treated as an empty
/// value rather than surfaced as an error, the same way every git GUI reads
/// optional config.
///
/// Saying that here was not enough, and for a long time it was not said where
/// it counted: the operation log records every invocation with its exit code,
/// so a repository with no local identity wrote two red ERROR rows on every
/// refresh -- for reading something that simply is not configured. `git push
/// … exit 1` is what spec page 10's LOGRULES means by error; this is an
/// answer. `benignExitCodes` is how the call site says so, and 1 only: 128
/// (broken config file, not a repository) stays an error.
std::string readConfigValue(IProcessRunner& runner,
                            const RepoPaths& paths,
                            std::vector<std::string> args,
                            CancellationToken token) {
    GitCommand command(paths.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(10);
    command.benignExitCodes = {1};
    auto result = runner.run(command, token);
    if (!result) {
        return {};
    }
    std::string value = result->out;
    while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) {
        value.pop_back();
    }
    return value;
}

/// `git config --local --get <key>` exits 1 with empty stderr when the key is
/// unset -- not a genuine failure, just "nothing here". Treated as an empty
/// value rather than surfaced as an error, the same way every git GUI reads
/// optional config.
std::string readLocalConfigValue(IProcessRunner& runner,
                                 const RepoPaths& paths,
                                 const char* key,
                                 CancellationToken token) {
    return readConfigValue(runner, paths, {"config", "--local", "--get", key}, token);
}

/// `git config --get <key>` with no scope flag: git resolves `--local` >
/// `--global` > system, exactly the precedence a new commit's author would
/// use. Same unset-key tolerance as readLocalConfigValue.
std::string readEffectiveConfigValue(IProcessRunner& runner,
                                     const RepoPaths& paths,
                                     const char* key,
                                     CancellationToken token) {
    return readConfigValue(runner, paths, {"config", "--get", key}, token);
}

class SetLocalIdentityOperation final : public Operation {
public:
    explicit SetLocalIdentityOperation(SetLocalIdentityRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Set repository Git identity"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        GitCommand nameCommand(paths.commandDir(),
                               {"config", "--local", "user.name", request_.name});
        nameCommand.timeout = std::chrono::seconds(10);
        auto nameResult = runner.run(nameCommand, token);
        if (!nameResult) {
            outcome.error = std::move(nameResult).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }

        GitCommand emailCommand(paths.commandDir(),
                                {"config", "--local", "user.email", request_.email});
        emailCommand.timeout = std::chrono::seconds(10);
        auto emailResult = runner.run(emailCommand, token);
        if (!emailResult) {
            outcome.error = std::move(emailResult).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }

        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    SetLocalIdentityRequest request_;
};

class ClearLocalIdentityOperation final : public Operation {
public:
    std::string describe() const override { return "Clear repository Git identity override"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        // `--unset` on a key that was never set locally exits non-zero; that is
        // not a failure for a "clear the override, if any" operation, so both
        // calls run best-effort and this always reports success.
        for (const char* key : {"user.name", "user.email"}) {
            GitCommand command(paths.commandDir(), {"config", "--local", "--unset", key});
            command.timeout = std::chrono::seconds(10);
            runner.run(command, token);
        }

        OperationOutcome outcome;
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }
};

}  // namespace

LocalIdentityStore::LocalIdentityStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<LocalIdentity> LocalIdentityStore::read(CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    LocalIdentity identity;
    identity.name = readLocalConfigValue(runner_, paths_, "user.name", token);
    identity.email = readLocalConfigValue(runner_, paths_, "user.email", token);
    identity.overridden = !identity.name.empty() || !identity.email.empty();
    return identity;
}

GitResult<EffectiveIdentity> LocalIdentityStore::readEffective(CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    EffectiveIdentity identity;
    identity.name = readEffectiveConfigValue(runner_, paths_, "user.name", token);
    identity.email = readEffectiveConfigValue(runner_, paths_, "user.email", token);
    return identity;
}

std::unique_ptr<Operation> makeSetLocalIdentityOperation(SetLocalIdentityRequest request) {
    return std::make_unique<SetLocalIdentityOperation>(std::move(request));
}

std::unique_ptr<Operation> makeClearLocalIdentityOperation() {
    return std::make_unique<ClearLocalIdentityOperation>();
}

}  // namespace gbm
