#include "core/git/BlameStore.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <utility>

namespace gbm {

namespace {

bool looksLikeObjectHex(std::string_view token) {
    if (token.size() != 40 && token.size() != 64) {
        return false;
    }
    return std::all_of(token.begin(), token.end(), [](unsigned char c) {
        return std::isxdigit(c) != 0;
    });
}

}  // namespace

BlameStore::BlameStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<BlameResultPtr> BlameStore::blame(const std::string& path,
                                            const std::string& revision,
                                            int startLine,
                                            int endLine,
                                            CancellationToken token) {
    if (path.empty()) {
        return fail(GitError::Code::InvalidArgument, "No file selected to blame");
    }

    std::vector<std::string> args{"blame", "--line-porcelain"};
    if (startLine > 0 && endLine > 0) {
        args.emplace_back("-L");
        args.push_back(std::to_string(startLine) + "," + std::to_string(endLine));
    }
    if (!revision.empty()) {
        args.push_back(revision);
    }
    args.emplace_back("--");
    args.push_back(path);

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    auto blameResult = std::make_shared<BlameResult>();
    blameResult->truncated = result->out.size() > kMaxBytes;
    const std::string_view text(result->out.data(), std::min(result->out.size(), kMaxBytes));

    std::size_t pos = 0;
    while (pos < text.size()) {
        const std::size_t lineEnd = text.find('\n', pos);
        const std::string_view line =
            text.substr(pos, lineEnd == std::string_view::npos ? std::string_view::npos
                                                                : lineEnd - pos);
        pos = lineEnd == std::string_view::npos ? text.size() : lineEnd + 1;

        if (line.empty()) {
            continue;
        }

        if (line.front() == '\t') {
            if (!blameResult->lines.empty()) {
                blameResult->lines.back().content = std::string(line.substr(1));
            }
            continue;
        }

        const std::size_t sp1 = line.find(' ');
        const std::string_view firstToken = line.substr(0, sp1);

        if (sp1 != std::string_view::npos && looksLikeObjectHex(firstToken)) {
            BlameLine entry;
            entry.commitOid = ObjectId::fromHex(firstToken);
            const std::size_t sp2 = line.find(' ', sp1 + 1);
            const std::string_view origStr = line.substr(
                sp1 + 1, sp2 == std::string_view::npos ? std::string_view::npos : sp2 - sp1 - 1);
            entry.originalLine = std::atoi(std::string(origStr).c_str());
            if (sp2 != std::string_view::npos) {
                const std::size_t sp3 = line.find(' ', sp2 + 1);
                const std::string_view finalStr = line.substr(
                    sp2 + 1, sp3 == std::string_view::npos ? std::string_view::npos : sp3 - sp2 - 1);
                entry.finalLine = std::atoi(std::string(finalStr).c_str());
            }
            blameResult->lines.push_back(std::move(entry));
            continue;
        }

        if (blameResult->lines.empty()) {
            continue;
        }
        BlameLine& current = blameResult->lines.back();

        if (line.starts_with("author ")) {
            current.authorName = std::string(line.substr(7));
        } else if (line.starts_with("author-mail ")) {
            std::string mail(line.substr(12));
            if (mail.size() >= 2 && mail.front() == '<' && mail.back() == '>') {
                mail = mail.substr(1, mail.size() - 2);
            }
            current.authorEmail = std::move(mail);
        } else if (line.starts_with("author-time ")) {
            current.authorTime = std::strtoll(std::string(line.substr(12)).c_str(), nullptr, 10);
        } else if (line.starts_with("summary ")) {
            current.summary = std::string(line.substr(8));
        } else if (line == "boundary") {
            current.boundary = true;
        }
    }

    return BlameResultPtr(blameResult);
}

}  // namespace gbm
