#include "core/git/ops/CompareOps.h"

#include <charconv>
#include <unordered_map>
#include <utility>

namespace gbm {

namespace {

std::string rangeExpr(const std::string& left, const std::string& right, bool threeDot) {
    return left + (threeDot ? "..." : "..") + right;
}

/// Splits NUL-delimited records from `-z` output, dropping the single empty
/// record a trailing terminator would otherwise leave -- git always ends -z
/// output with a NUL after the last record, never a partial one.
std::vector<std::string_view> splitNul(std::string_view text) {
    std::vector<std::string_view> records;
    std::size_t start = 0;
    while (start < text.size()) {
        const std::size_t at = text.find('\0', start);
        if (at == std::string_view::npos) {
            records.push_back(text.substr(start));
            break;
        }
        records.push_back(text.substr(start, at - start));
        start = at + 1;
    }
    return records;
}

/// `git merge-base left right`. Exit code 1 with no other classification is
/// git's documented signal for "no common ancestor" (unrelated histories) --
/// that is data to display (a null merge base), not a failure to report.
GitResult<ObjectId> readMergeBase(IProcessRunner& runner,
                                  const RepoPaths& paths,
                                  const std::string& left,
                                  const std::string& right,
                                  CancellationToken token) {
    GitCommand command(paths.commandDir(), {"merge-base", left, right});
    command.timeout = std::chrono::seconds(30);
    auto result = runner.run(command, token);
    if (!result) {
        const GitError& error = result.error();
        if (error.exitCode == 1) {
            return ObjectId{};
        }
        return fail(error);
    }

    std::string_view out(result->out);
    while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) {
        out.remove_suffix(1);
    }
    return ObjectId::fromHex(out);
}

/// `git log --left-right --format=...`. `--left-right` is requested
/// unconditionally: with a two-dot range it still parses cleanly, it just
/// never produces a '<' (left-only) entry, because two-dot excludes anything
/// reachable from the left ref from the walk in the first place.
GitResult<std::vector<CompareCommitEntry>> readCommits(IProcessRunner& runner,
                                                       const RepoPaths& paths,
                                                       const std::string& left,
                                                       const std::string& right,
                                                       bool threeDot,
                                                       CancellationToken token) {
    GitCommand command(paths.commandDir(),
                       {"log",
                        "--left-right",
                        "--format=%m\x01%H\x09%an\x09%at\x09%s",
                        rangeExpr(left, right, threeDot)});
    command.timeout = std::chrono::seconds(60);
    auto result = runner.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<CompareCommitEntry> commits;
    const std::string& out = result->out;
    std::size_t start = 0;
    while (start <= out.size()) {
        const std::size_t at = out.find('\n', start);
        const std::string_view line(out.data() + start,
                                    (at == std::string::npos ? out.size() : at) - start);
        if (!line.empty()) {
            const std::size_t marker = line.find('\x01');
            if (marker != std::string_view::npos) {
                const std::string_view side = line.substr(0, marker);
                std::string_view rest = line.substr(marker + 1);

                CompareCommitEntry entry;
                entry.onRightOnly = !side.empty() && side.front() == '>';

                const std::size_t t1 = rest.find('\t');
                if (t1 != std::string_view::npos) {
                    entry.oid = ObjectId::fromHex(rest.substr(0, t1));
                    rest = rest.substr(t1 + 1);
                    const std::size_t t2 = rest.find('\t');
                    if (t2 != std::string_view::npos) {
                        entry.authorName = std::string(rest.substr(0, t2));
                        rest = rest.substr(t2 + 1);
                        const std::size_t t3 = rest.find('\t');
                        const std::string_view dateField =
                            rest.substr(0, t3 == std::string_view::npos ? rest.size() : t3);
                        std::from_chars(dateField.data(),
                                        dateField.data() + dateField.size(),
                                        entry.authorDate);
                        if (t3 != std::string_view::npos) {
                            entry.subject = std::string(rest.substr(t3 + 1));
                        }
                    }
                }
                commits.push_back(std::move(entry));
            }
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return commits;
}

FileChangeKind kindFromStatus(char code) {
    switch (code) {
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

/// `git diff --name-status` for the change kind (plus similarity for
/// renames/copies, encoded as e.g. "R100") and `git diff --numstat` for
/// added/removed line counts, merged by path. Two invocations rather than
/// one: git's diff-options output-format field is a single slot, so
/// `--name-status` and `--numstat` cannot both take effect in the same
/// invocation. Both use `-z`, which sidesteps two separate ambiguities
/// `--numstat` has without it: pathnames get quoted/escaped, and a
/// rename/copy's two paths get printed as one abbreviated
/// "common/{old => new}" string rather than as full paths -- `-z` instead
/// splits a rename into three clean NUL-terminated records (empty path
/// field, then old path, then new path), which is what the parsing below
/// expects.
GitResult<std::vector<DiffFile>> readFiles(IProcessRunner& runner,
                                           const RepoPaths& paths,
                                           const std::string& left,
                                           const std::string& right,
                                           bool threeDot,
                                           CancellationToken token) {
    const std::string range = rangeExpr(left, right, threeDot);

    GitCommand statusCommand(paths.commandDir(), {"diff", "--name-status", "-M", "-z", range});
    statusCommand.timeout = std::chrono::seconds(60);
    auto statusResult = runner.run(statusCommand, token);
    if (!statusResult) {
        return fail(std::move(statusResult).error());
    }

    std::vector<DiffFile> files;
    std::unordered_map<std::string, std::size_t> indexByDisplayPath;

    const std::vector<std::string_view> statusRecords = splitNul(statusResult->out);
    for (std::size_t i = 0; i < statusRecords.size();) {
        const std::string_view status = statusRecords[i++];
        if (status.empty()) {
            continue;
        }
        DiffFile file;
        file.kind = kindFromStatus(status.front());
        if (file.kind == FileChangeKind::Renamed || file.kind == FileChangeKind::Copied) {
            if (status.size() > 1) {
                int similarity = 0;
                std::from_chars(status.data() + 1, status.data() + status.size(), similarity);
                file.similarity = similarity;
            }
            if (i < statusRecords.size()) {
                file.oldPath = std::string(statusRecords[i++]);
            }
            if (i < statusRecords.size()) {
                file.newPath = std::string(statusRecords[i++]);
            }
        } else {
            if (i < statusRecords.size()) {
                const std::string path(statusRecords[i++]);
                file.oldPath = path;
                file.newPath = path;
            }
        }
        if (file.kind == FileChangeKind::Added) {
            file.oldPath.clear();
        }
        if (file.kind == FileChangeKind::Deleted) {
            file.newPath.clear();
        }
        indexByDisplayPath[file.displayPath()] = files.size();
        files.push_back(std::move(file));
    }

    GitCommand numstatCommand(paths.commandDir(), {"diff", "--numstat", "-M", "-z", range});
    numstatCommand.timeout = std::chrono::seconds(60);
    auto numstatResult = runner.run(numstatCommand, token);
    if (!numstatResult) {
        return fail(std::move(numstatResult).error());
    }

    const std::vector<std::string_view> numRecords = splitNul(numstatResult->out);
    for (std::size_t i = 0; i < numRecords.size();) {
        const std::string_view record = numRecords[i++];
        const std::size_t t1 = record.find('\t');
        if (t1 == std::string_view::npos) {
            continue;
        }
        const std::size_t t2 = record.find('\t', t1 + 1);
        if (t2 == std::string_view::npos) {
            continue;
        }
        const std::string_view addedField = record.substr(0, t1);
        const std::string_view removedField = record.substr(t1 + 1, t2 - t1 - 1);
        const std::string_view pathField = record.substr(t2 + 1);
        const bool binary = addedField == "-" || removedField == "-";

        std::string displayPath;
        if (pathField.empty()) {
            // Rename/copy: the next two NUL records are the old and new
            // paths; name-status already recorded both, so only the new
            // path (which is what indexByDisplayPath is keyed on) is used
            // here to find the matching DiffFile.
            if (i < numRecords.size()) {
                ++i;  // old path, unused
            }
            if (i < numRecords.size()) {
                displayPath = std::string(numRecords[i++]);
            }
        } else {
            displayPath = std::string(pathField);
        }

        const auto it = indexByDisplayPath.find(displayPath);
        if (it == indexByDisplayPath.end()) {
            continue;
        }
        DiffFile& file = files[it->second];
        file.binary = binary;
        if (!binary) {
            std::uint32_t added = 0;
            std::uint32_t removed = 0;
            std::from_chars(addedField.data(), addedField.data() + addedField.size(), added);
            std::from_chars(
                removedField.data(), removedField.data() + removedField.size(), removed);
            file.addedLines = added;
            file.removedLines = removed;
        }
    }

    return files;
}

}  // namespace

CompareStore::CompareStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<CompareResult> CompareStore::compare(CompareRequest request, CancellationToken token) {
    if (request.leftRef.empty() || request.rightRef.empty()) {
        return fail(GitError::Code::InvalidArgument, "Compare needs two refs");
    }

    CompareResult out;

    auto mergeBase = readMergeBase(runner_, paths_, request.leftRef, request.rightRef, token);
    if (!mergeBase) {
        return fail(std::move(mergeBase).error());
    }
    out.mergeBase = *mergeBase;

    auto commits =
        readCommits(runner_, paths_, request.leftRef, request.rightRef, request.threeDot, token);
    if (!commits) {
        return fail(std::move(commits).error());
    }
    out.commits = std::move(*commits);

    auto files =
        readFiles(runner_, paths_, request.leftRef, request.rightRef, request.threeDot, token);
    if (!files) {
        return fail(std::move(files).error());
    }
    out.files = std::move(*files);

    return out;
}

GitResult<ParsedDiff> CompareStore::compareFileDiff(CompareFileDiffRequest request,
                                                    CancellationToken token) {
    if (request.leftRef.empty() || request.rightRef.empty() || request.path.empty()) {
        return fail(GitError::Code::InvalidArgument, "Compare file diff needs two refs and a path");
    }

    GitCommand command(paths_.commandDir(),
                       {"diff",
                        rangeExpr(request.leftRef, request.rightRef, request.threeDot),
                        "--",
                        request.path});
    command.timeout = std::chrono::seconds(60);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    UnifiedDiffParser parser;
    return parser.parse(result->out);
}

}  // namespace gbm
