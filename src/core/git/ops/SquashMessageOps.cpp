#include "core/git/ops/SquashMessageOps.h"

#include <chrono>
#include <string_view>
#include <utility>

namespace gbm {

namespace {

/// `git rev-parse --verify <rev>^{commit}`, trimmed to its oid.
GitResult<ObjectId> resolveCommit(IProcessRunner& runner,
                                  const RepoPaths& paths,
                                  const std::string& rev,
                                  CancellationToken token) {
    GitCommand command(paths.commandDir(), {"rev-parse", "--verify", rev + "^{commit}"});
    command.timeout = std::chrono::seconds(30);
    auto result = runner.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }
    std::string_view out(result->out);
    while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) {
        out.remove_suffix(1);
    }
    return ObjectId::fromHex(out);
}

}  // namespace

SquashMessageStore::SquashMessageStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<SquashMessagePreview> SquashMessageStore::preview(const std::string& source,
                                                            CancellationToken token) {
    // A name starting with '-' would reach rev-parse as an option. No branch
    // can be named that way (git check-ref-format refuses it), so it is never
    // a ref the dialog offered.
    if (source.empty() || source.front() == '-') {
        return fail(GitError::Code::InvalidArgument, "Not a branch to squash: " + source);
    }

    SquashMessagePreview out;
    auto head = resolveCommit(runner_, paths_, "HEAD", token);
    if (!head) {
        return fail(std::move(head).error());
    }
    out.headOid = *head;
    auto tip = resolveCommit(runner_, paths_, source, token);
    if (!tip) {
        return fail(std::move(tip).error());
    }
    out.sourceOid = *tip;

    // What `git merge --squash` writes is "Squashed commit of the following:"
    // and a blank line, then this walk in git log's medium format (measured
    // byte-identical on git 2.56). The flags override config git log honours
    // and the squash walk does not: format.pretty, log.decorate,
    // log.abbrevCommit and log.mailmap (on by default since 2.29) are each
    // measured to change the text without their flag (GitIntegrationTest's
    // SquashPreviewMatchesTheSquashMsgGitWrites). --no-expand-tabs is not
    // config: medium expands a body tab to spaces, SQUASH_MSG keeps the tab
    // (measured, same test); log.showSignature, color.ui
    // and log.date by documentation. --no-notes is measured *redundant*: an
    // explicit --pretty already suppresses the default notes display. It is
    // kept as a guard, not as a fix for anything observed. The range is the
    // two oids, so the text is exactly the commits headOid/sourceOid name.
    GitCommand command(paths_.commandDir(),
                       {"log",
                        "--pretty=medium",
                        "--no-decorate",
                        "--no-abbrev-commit",
                        "--no-mailmap",
                        "--no-expand-tabs",
                        "--no-notes",
                        "--no-show-signature",
                        "--no-color",
                        "--date=default",
                        out.headOid.hex() + ".." + out.sourceOid.hex()});
    command.timeout = std::chrono::seconds(60);
    auto log = runner_.run(command, token);
    if (!log) {
        return fail(std::move(log).error());
    }
    if (log->out.empty()) {
        return out;  // nothing to squash: git would write no SQUASH_MSG either
    }
    // run() drops the final line separator ([CPP-run-not-byte-exact]);
    // SQUASH_MSG ends with one.
    out.message = "Squashed commit of the following:\n\n" + log->out + "\n";
    return out;
}

}  // namespace gbm
