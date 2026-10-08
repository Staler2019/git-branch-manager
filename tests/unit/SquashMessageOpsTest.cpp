// SquashMessageStore against FakeProcessRunner: the command it runs and how
// it reads git's answers. Whether the text really equals the SQUASH_MSG git
// writes is GitIntegrationTest's job (RealRepoTest.SquashPreviewMatches...),
// because only a real git can disagree with it.
#include "core/git/ops/SquashMessageOps.h"
#include "support/FakeProcessRunner.h"

#include <algorithm>
#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

RepoPaths testPaths() {
    return RepoPaths("/repo", "/repo/.git", "/repo/.git");
}

const std::string kHead(40, 'a');
const std::string kSource(40, 'b');

FakeProcessRunner::Response ok(std::string out) {
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    response.out = std::move(out);
    return response;
}

void scriptOids(FakeProcessRunner& runner) {
    runner.whenArgsContain({"rev-parse", "HEAD^{commit}"}, ok(kHead + "\n"));
    runner.whenArgsContain({"rev-parse", "feature^{commit}"}, ok(kSource + "\n"));
}

std::vector<std::string> logArgs(const FakeProcessRunner& runner) {
    for (std::size_t i = 0; i < runner.invocations().size(); ++i) {
        std::vector<std::string> args = runner.invokedArgs(i);
        if (!args.empty() && args.front() == "log") return args;
    }
    return {};
}

bool contains(const std::vector<std::string>& args, const std::string& token) {
    return std::find(args.begin(), args.end(), token) != args.end();
}

TEST(SquashMessageStore, LogsTheExactOidRangeWithConfigProofFlags) {
    FakeProcessRunner runner;
    scriptOids(runner);
    runner.whenArgsContain({"log"}, ok("commit " + kSource + "\n"));

    SquashMessageStore store(runner, testPaths());
    auto preview = store.preview("feature", CancellationToken{});
    ASSERT_TRUE(preview) << preview.error().message;

    const std::vector<std::string> args = logArgs(runner);
    // The oids, not the names: the message must describe exactly the
    // commits the returned headOid/sourceOid name.
    EXPECT_TRUE(contains(args, kHead + ".." + kSource));
    // Each of these is a user/repo config git log honours and the squash
    // walk does not -- without the flag, the preview drifts from SQUASH_MSG.
    for (const char* flag : {"--pretty=medium",
                             "--no-decorate",
                             "--no-abbrev-commit",
                             "--no-mailmap",
                             "--no-notes",
                             "--no-show-signature",
                             "--no-color",
                             "--date=default"}) {
        EXPECT_TRUE(contains(args, flag)) << flag;
    }
    EXPECT_EQ(preview->headOid.hex(), kHead);
    EXPECT_EQ(preview->sourceOid.hex(), kSource);
}

TEST(SquashMessageStore, PrefixesGitsHeaderAndKeepsTheFinalNewline) {
    FakeProcessRunner runner;
    scriptOids(runner);
    // IProcessRunner drops the last line separator ([CPP-run-not-byte-exact]);
    // SQUASH_MSG ends with one.
    runner.whenArgsContain({"log"}, ok("commit " + kSource + "\nAuthor: T <t@t>"));

    SquashMessageStore store(runner, testPaths());
    auto preview = store.preview("feature", CancellationToken{});
    ASSERT_TRUE(preview);
    EXPECT_EQ(preview->message,
              "Squashed commit of the following:\n\ncommit " + kSource + "\nAuthor: T <t@t>\n");
}

TEST(SquashMessageStore, AnEmptyRangeIsAnEmptyMessageNotAnError) {
    FakeProcessRunner runner;
    scriptOids(runner);
    runner.whenArgsContain({"log"}, ok(""));

    SquashMessageStore store(runner, testPaths());
    auto preview = store.preview("feature", CancellationToken{});
    ASSERT_TRUE(preview);
    EXPECT_TRUE(preview->message.empty());
}

TEST(SquashMessageStore, RefusesASourceThatGitWouldReadAsAnOption) {
    FakeProcessRunner runner;
    SquashMessageStore store(runner, testPaths());
    auto preview = store.preview("--output=/tmp/x", CancellationToken{});
    ASSERT_FALSE(preview);
    EXPECT_EQ(preview.error().code, GitError::Code::InvalidArgument);
    EXPECT_TRUE(runner.invocations().empty());
}

}  // namespace
}  // namespace gbm
