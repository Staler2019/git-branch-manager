#include "core/git/TransferProgress.h"

#include <charconv>
#include <system_error>

namespace gbm {

namespace {

constexpr std::string_view kReceiving = "Receiving objects:";
constexpr std::string_view kResolving = "Resolving deltas:";

/// Reads an unsigned count that must end exactly at `terminator`. Advances
/// `text` past the terminator on success.
std::optional<std::uint64_t> readCount(std::string_view& text, char terminator) {
    std::uint64_t value = 0;
    const char* first = text.data();
    const char* last = text.data() + text.size();
    const auto [end, ec] = std::from_chars(first, last, value);
    if (ec != std::errc{} || end == last || *end != terminator) {
        return std::nullopt;
    }
    text.remove_prefix(static_cast<std::size_t>(end - first) + 1);
    return value;
}

/// One '\r'/'\n'-free segment: `<label> NN% (current/total)[, ...]`.
std::optional<TransferProgress> parseLine(std::string_view line) {
    TransferProgress progress;
    if (line.starts_with(kReceiving)) {
        progress.phase = TransferProgress::Phase::ReceivingObjects;
        line.remove_prefix(kReceiving.size());
    } else if (line.starts_with(kResolving)) {
        progress.phase = TransferProgress::Phase::ResolvingDeltas;
        line.remove_prefix(kResolving.size());
    } else {
        return std::nullopt;
    }
    const std::size_t open = line.find('(');
    if (open == std::string_view::npos) {
        return std::nullopt;
    }
    line.remove_prefix(open + 1);
    const std::optional<std::uint64_t> current = readCount(line, '/');
    if (!current) {
        return std::nullopt;
    }
    const std::optional<std::uint64_t> total = readCount(line, ')');
    if (!total) {
        return std::nullopt;
    }
    progress.current = *current;
    progress.total = *total;
    return progress;
}

}  // namespace

std::optional<TransferProgress> parseTransferProgress(std::string_view chunk) {
    std::optional<TransferProgress> latest;
    while (!chunk.empty()) {
        const std::size_t end = chunk.find_first_of("\r\n");
        const std::string_view line = chunk.substr(0, end);
        if (std::optional<TransferProgress> parsed = parseLine(line)) {
            latest = parsed;
        }
        if (end == std::string_view::npos) {
            break;
        }
        chunk.remove_prefix(end + 1);
    }
    return latest;
}

}  // namespace gbm
