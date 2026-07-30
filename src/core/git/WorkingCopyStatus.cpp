#include "core/git/WorkingCopyStatus.h"

#include "core/base/ThreadCheck.h"

#include <charconv>
#include <chrono>
#include <utility>

namespace gbm {

namespace {

FileChangeKind kindForCode(char c) {
    switch (c) {
        case 'A':
            return FileChangeKind::Added;
        case 'D':
            return FileChangeKind::Deleted;
        case 'R':
            return FileChangeKind::Renamed;
        case 'C':
            return FileChangeKind::Copied;
        case 'T':
            return FileChangeKind::TypeChanged;
        case 'M':
        default:
            return FileChangeKind::Modified;
    }
}

ConflictKind conflictForXY(char x, char y) {
    if (x == 'A' && y == 'A') return ConflictKind::BothAdded;
    if (x == 'U' && y == 'U') return ConflictKind::BothModified;
    if (x == 'D' && y == 'D') return ConflictKind::BothDeleted;
    if (x == 'A' && y == 'U') return ConflictKind::AddedByUs;
    if (x == 'D' && y == 'U') return ConflictKind::DeletedByUs;
    if (x == 'U' && y == 'A') return ConflictKind::AddedByThem;
    if (x == 'U' && y == 'D') return ConflictKind::DeletedByThem;
    return ConflictKind::BothModified;  // Unexpected pairing: still a conflict either way.
}

/// Splits on ' ' into at most `maxFields` tokens; the final token absorbs
/// everything left over, so a path containing spaces is never cut apart.
std::vector<std::string_view> splitFieldsMax(std::string_view line, std::size_t maxFields) {
    std::vector<std::string_view> fields;
    std::size_t start = 0;
    while (fields.size() + 1 < maxFields) {
        const std::size_t space = line.find(' ', start);
        if (space == std::string_view::npos) {
            break;
        }
        fields.push_back(line.substr(start, space - start));
        start = space + 1;
    }
    fields.push_back(line.substr(start));
    return fields;
}

/// Reads the trailing digits of a rename/copy score field, e.g. "R100" -> 100.
int parseScore(std::string_view scoreField) {
    std::size_t digitsStart = 0;
    while (digitsStart < scoreField.size() &&
           (scoreField[digitsStart] < '0' || scoreField[digitsStart] > '9')) {
        ++digitsStart;
    }
    int value = 0;
    std::from_chars(scoreField.data() + digitsStart, scoreField.data() + scoreField.size(), value);
    return value;
}

}  // namespace

std::vector<const WorkingCopyEntry*> WorkingCopyStatus::staged() const {
    std::vector<const WorkingCopyEntry*> result;
    for (const auto& entry : entries) {
        if (entry.staged && !entry.isConflicted()) {
            result.push_back(&entry);
        }
    }
    return result;
}

std::vector<const WorkingCopyEntry*> WorkingCopyStatus::unstaged() const {
    std::vector<const WorkingCopyEntry*> result;
    for (const auto& entry : entries) {
        if (entry.hasUnstagedChange && !entry.untracked && !entry.isConflicted()) {
            result.push_back(&entry);
        }
    }
    return result;
}

std::vector<const WorkingCopyEntry*> WorkingCopyStatus::untracked() const {
    std::vector<const WorkingCopyEntry*> result;
    for (const auto& entry : entries) {
        if (entry.untracked) {
            result.push_back(&entry);
        }
    }
    return result;
}

std::vector<const WorkingCopyEntry*> WorkingCopyStatus::conflicted() const {
    std::vector<const WorkingCopyEntry*> result;
    for (const auto& entry : entries) {
        if (entry.isConflicted()) {
            result.push_back(&entry);
        }
    }
    return result;
}

WorkingCopyStatusReader::WorkingCopyStatusReader(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<WorkingCopyStatusPtr> WorkingCopyStatusReader::read(CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    // No --branch: ahead/behind and the current branch name are RefStore's job
    // already, via %(upstream:track) in a single for-each-ref call. Asking for
    // both here would mean two sources of truth for the same numbers.
    std::vector<std::string> args{
        "status", "--porcelain=v2", "-z", "--untracked-files=all", "--ignore-submodules=none"};
    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);

    // Deliberately uncached -- see the class comment.
    std::vector<std::string> records;
    const LineSink sink = [&records](std::string_view record) {
        records.emplace_back(record);
        return true;
    };

    auto result =
        runner_.streamSeparated(command, IProcessRunner::Separator::Nul, sink, nullptr, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    auto status = std::make_shared<WorkingCopyStatus>();
    for (std::size_t i = 0; i < records.size();) {
        const std::string_view record = records[i];
        if (record.empty()) {
            ++i;
            continue;
        }

        const char type = record.front();

        // Ordinary changed entry ('1') or rename/copy ('2', followed by a
        // second NUL-terminated record carrying the original path).
        if (type == '1' || type == '2') {
            const std::size_t fieldCount = type == '1' ? 8 : 9;
            const auto fields = splitFieldsMax(record, fieldCount + 1);
            if (fields.size() < fieldCount + 1) {
                ++i;
                continue;  // Malformed record; skip rather than misreport a path.
            }
            const std::string_view xy = fields[1];
            const std::string_view sub = fields[2];

            WorkingCopyEntry entry;
            entry.path = std::string(fields.back());
            entry.isSubmodule = !sub.empty() && sub.front() == 'S';

            const char x = !xy.empty() ? xy[0] : '.';
            const char y = xy.size() > 1 ? xy[1] : '.';
            if (x != '.') {
                entry.staged = true;
                entry.indexStatus = kindForCode(x);
            }
            if (y != '.') {
                entry.hasUnstagedChange = true;
                entry.worktreeStatus = kindForCode(y);
            }

            if (type == '2') {
                entry.similarity = parseScore(fields[8]);
                if (i + 1 < records.size()) {
                    entry.oldPath = records[i + 1];
                    ++i;
                }
            }
            status->entries.push_back(std::move(entry));
            ++i;
            continue;
        }

        // Unmerged (conflicted) entry.
        if (type == 'u') {
            const auto fields = splitFieldsMax(record, 11);
            if (fields.size() < 11) {
                ++i;
                continue;
            }
            const std::string_view xy = fields[1];
            const std::string_view sub = fields[2];

            WorkingCopyEntry entry;
            entry.path = std::string(fields.back());
            entry.isSubmodule = !sub.empty() && sub.front() == 'S';
            entry.conflict = conflictForXY(!xy.empty() ? xy[0] : '?', xy.size() > 1 ? xy[1] : '?');
            status->entries.push_back(std::move(entry));
            ++i;
            continue;
        }

        // Untracked path.
        if (type == '?') {
            WorkingCopyEntry entry;
            entry.path = record.size() > 2 ? std::string(record.substr(2)) : std::string();
            entry.untracked = true;
            status->entries.push_back(std::move(entry));
            ++i;
            continue;
        }

        // '!' (ignored, only present with --ignored, which we never pass) and
        // anything else unrecognised: skip rather than guess.
        ++i;
    }

    return WorkingCopyStatusPtr(status);
}

}  // namespace gbm
