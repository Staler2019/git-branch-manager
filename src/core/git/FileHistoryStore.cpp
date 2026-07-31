#include "core/git/FileHistoryStore.h"

#include <charconv>
#include <utility>

namespace gbm {

namespace {

/// Marks the start of a commit's record in log output whose remainder (name
/// status lines, or a -L hunk) is otherwise free-form and could start with
/// almost anything. `\x01` cannot appear in a subject line or a diff, so it is
/// an unambiguous separator without needing `-z` and NUL-splitting.
constexpr char kRecordMarker = '\x01';

std::vector<std::string_view> splitLines(std::string_view text) {
    std::vector<std::string_view> lines;
    std::size_t start = 0;
    while (start <= text.size()) {
        const std::size_t at = text.find('\n', start);
        lines.push_back(
            text.substr(start, at == std::string_view::npos ? std::string_view::npos : at - start));
        if (at == std::string_view::npos) {
            break;
        }
        start = at + 1;
    }
    return lines;
}

/// Splits a "%H\t%an\t%ae\t%at\t%s" record (marker already stripped) into its
/// five fields, tolerating a subject that itself contains tabs.
struct CommitFields {
    ObjectId oid;
    Signature author;
    std::string subject;
};

CommitFields parseCommitFields(std::string_view record) {
    CommitFields fields;
    std::size_t pos = 0;
    for (int col = 0; col < 5; ++col) {
        const std::size_t tab = record.find('\t', pos);
        const std::string_view value =
            record.substr(pos, tab == std::string_view::npos ? std::string_view::npos : tab - pos);
        switch (col) {
            case 0:
                fields.oid = ObjectId::fromHex(value);
                break;
            case 1:
                fields.author.name = std::string(value);
                break;
            case 2:
                fields.author.email = std::string(value);
                break;
            case 3: {
                std::int64_t ts = 0;
                std::from_chars(value.data(), value.data() + value.size(), ts);
                fields.author.when = ts;
                break;
            }
            case 4:
                fields.subject = std::string(value);
                break;
        }
        if (tab == std::string_view::npos) {
            break;
        }
        pos = tab + 1;
    }
    return fields;
}

}  // namespace

FileHistoryStore::FileHistoryStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<FileHistoryEntry>> FileHistoryStore::fileHistory(
    const std::string& path, const std::string& startRevision, CancellationToken token) {
    if (path.empty()) {
        return fail(GitError::Code::InvalidArgument, "No file selected");
    }

    std::vector<std::string> args{
        "log", "--follow", "--name-status", "--format=\x01%H\x09%an\x09%ae\x09%at\x09%s"};
    if (!startRevision.empty()) {
        args.push_back(startRevision);
    }
    args.emplace_back("--");
    args.push_back(path);

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(60);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<FileHistoryEntry> entries;
    for (std::string_view line : splitLines(result->out)) {
        if (line.empty()) {
            continue;
        }
        if (line.front() == kRecordMarker) {
            const CommitFields fields = parseCommitFields(line.substr(1));
            FileHistoryEntry entry;
            entry.oid = fields.oid;
            entry.author = fields.author;
            entry.subject = fields.subject;
            entries.push_back(std::move(entry));
            continue;
        }
        if (entries.empty()) {
            continue;
        }
        // A name-status line: "<status>\t<path>" or "R###\t<old>\t<new>".
        const std::size_t tab = line.find('\t');
        if (tab == std::string_view::npos) {
            continue;
        }
        const std::string_view status = line.substr(0, tab);
        entries.back().status = std::string(status);
        if (!status.empty() && (status.front() == 'R' || status.front() == 'C')) {
            const std::string_view rest = line.substr(tab + 1);
            const std::size_t tab2 = rest.find('\t');
            if (tab2 != std::string_view::npos) {
                entries.back().renamedFrom = std::string(rest.substr(0, tab2));
            }
        }
    }
    return entries;
}

GitResult<std::vector<LineHistoryChunk>> FileHistoryStore::lineHistory(
    const std::string& path,
    int startLine,
    int endLine,
    const std::string& startRevision,
    CancellationToken token) {
    if (path.empty() || startLine <= 0 || endLine < startLine) {
        return fail(GitError::Code::InvalidArgument, "Invalid line range");
    }

    std::vector<std::string> args{
        "log",
        "-L",
        std::to_string(startLine) + "," + std::to_string(endLine) + ":" + path,
        "--format=\x01%H\x09%an\x09%ae\x09%at\x09%s"};
    if (!startRevision.empty()) {
        args.push_back(startRevision);
    }

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(60);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<LineHistoryChunk> chunks;
    for (std::string_view line : splitLines(result->out)) {
        if (line.empty()) {
            if (!chunks.empty()) {
                chunks.back().diffText += '\n';
            }
            continue;
        }
        if (line.front() == kRecordMarker) {
            const CommitFields fields = parseCommitFields(line.substr(1));
            LineHistoryChunk chunk;
            chunk.oid = fields.oid;
            chunk.author = fields.author;
            chunk.subject = fields.subject;
            chunks.push_back(std::move(chunk));
            continue;
        }
        if (chunks.empty()) {
            continue;
        }
        chunks.back().diffText += line;
        chunks.back().diffText += '\n';
    }
    return chunks;
}

}  // namespace gbm
