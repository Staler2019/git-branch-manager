#include "core/git/ReflogStore.h"

#include <charconv>
#include <utility>

namespace gbm {

namespace {

/// Parses "<ref>@{N}" into N, the same trick StashStore uses for `%gd`.
int parseReflogIndex(std::string_view gd) {
    const auto open = gd.find('{');
    const auto close = gd.find('}', open);
    if (open == std::string_view::npos || close == std::string_view::npos) {
        return 0;
    }
    int value = 0;
    const std::string_view digits = gd.substr(open + 1, close - open - 1);
    std::from_chars(digits.data(), digits.data() + digits.size(), value);
    return value;
}

}  // namespace

ReflogStore::ReflogStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<ReflogEntry>> ReflogStore::list(const std::string& ref,
                                                      CancellationToken token) {
    std::vector<std::string> args{
        "reflog", "show", "--format=%H%x09%gd%x09%an%x09%ae%x09%at%x09%gs"};
    args.push_back(ref.empty() ? "HEAD" : ref);

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(60);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<ReflogEntry> entries;
    std::size_t start = 0;
    while (start <= result->out.size()) {
        const std::size_t at = result->out.find('\n', start);
        const std::string_view line(result->out.data() + start,
                                    (at == std::string::npos ? result->out.size() : at) - start);
        if (!line.empty()) {
            ReflogEntry entry;
            std::size_t pos = 0;
            for (int col = 0; col < 6; ++col) {
                const std::size_t tab = line.find('\t', pos);
                const std::string_view value = line.substr(
                    pos, tab == std::string_view::npos ? std::string_view::npos : tab - pos);
                switch (col) {
                    case 0:
                        entry.oid = ObjectId::fromHex(value);
                        break;
                    case 1:
                        entry.index = parseReflogIndex(value);
                        break;
                    case 2:
                        entry.who.name = std::string(value);
                        break;
                    case 3:
                        entry.who.email = std::string(value);
                        break;
                    case 4: {
                        std::int64_t ts = 0;
                        std::from_chars(value.data(), value.data() + value.size(), ts);
                        entry.who.when = ts;
                        break;
                    }
                    case 5:
                        entry.message = std::string(value);
                        break;
                }
                if (tab == std::string_view::npos) {
                    break;
                }
                pos = tab + 1;
            }
            entries.push_back(std::move(entry));
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return entries;
}

}  // namespace gbm
