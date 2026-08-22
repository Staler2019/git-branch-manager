#include "core/git/DiffService.h"

#include "core/base/ThreadCheck.h"

#include <utility>

namespace gbm {

namespace {

FileChangeKind kindForStatusLetter(char letter) {
    switch (letter) {
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

std::size_t estimateBytes(const ParsedDiff& diff) {
    std::size_t total = sizeof(ParsedDiff);
    for (const DiffFile& file : diff.files) {
        total += sizeof(DiffFile) + file.oldPath.size() + file.newPath.size();
        for (const DiffHunk& hunk : file.hunks) {
            total += sizeof(DiffHunk) + hunk.heading.size();
            for (const DiffLine& line : hunk.lines) {
                total += sizeof(DiffLine) + line.text.capacity();
            }
        }
    }
    return total;
}

std::size_t estimateBytes(const std::vector<ChangedFile>& files) {
    std::size_t total = sizeof(std::vector<ChangedFile>);
    for (const ChangedFile& file : files) {
        total += sizeof(ChangedFile) + file.path.size() + file.oldPath.size();
    }
    return total;
}

}  // namespace

std::uint64_t DiffOptions::hash() const {
    // Part of every cache key: two diffs of the same blobs with different
    // whitespace or context settings are genuinely different results.
    std::uint64_t h = 0xcbf29ce484222325ULL;
    auto mix = [&h](std::uint64_t value) {
        h ^= value;
        h *= 0x100000001b3ULL;
    };
    mix(contextLines);
    mix(ignoreWhitespace ? 1 : 0);
    mix(ignoreEolOnly ? 1 : 0);
    mix(detectRenames ? 1 : 0);
    mix(firstParentOnly ? 1 : 0);
    mix(renameDetectionLimit);
    return h;
}

DiffService::DiffService(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

std::vector<std::string> DiffService::diffFlags(const DiffOptions& options) const {
    std::vector<std::string> flags;
    flags.emplace_back("--no-color");
    flags.emplace_back("-U" + std::to_string(options.contextLines));

    if (options.detectRenames) {
        flags.emplace_back("--find-renames");
        // Beyond the limit git silently skips rename detection anyway; passing it
        // explicitly means the behaviour is ours and is visible in the log.
        flags.emplace_back("-l" + std::to_string(options.renameDetectionLimit));
    } else {
        flags.emplace_back("--no-renames");
    }

    if (options.ignoreWhitespace) {
        flags.emplace_back("-w");
    } else if (options.ignoreEolOnly) {
        // On Windows, CRLF-only changes are constant noise; this hides them
        // without hiding genuine whitespace edits.
        flags.emplace_back("--ignore-cr-at-eol");
    }

    // The indent heuristic markedly improves hunk boundaries in real code, at no
    // measurable cost.
    flags.emplace_back("--indent-heuristic");
    return flags;
}

GitResult<DiffService::ChangedFilesPtr> DiffService::changedFiles(const ObjectId& commit,
                                                                  const DiffOptions& options,
                                                                  CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    const std::string cacheKey = commit.hex() + ":files:" + std::to_string(options.hash());
    if (auto cached = fileListCache_.get(cacheKey)) {
        return ChangedFilesPtr(cached);
    }

    // --root matters: without it, diff-tree prints nothing at all for a commit
    // with no parent, so the very first commit in a repository would show an empty
    // changed-file list. With it, the root commit reads as all-additions.
    std::vector<std::string> args{"diff-tree", "-r", "--raw", "-z", "--no-commit-id", "--root"};
    if (options.detectRenames) {
        args.emplace_back("--find-renames");
    }
    if (options.firstParentOnly) {
        args.emplace_back("--diff-merges=first-parent");
    }
    args.push_back(commit.hex());

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);

    // `--raw -z` emits NUL-separated fields, and rename entries span three
    // records (metadata, old path, new path) rather than two. Using -z rather
    // than parsing quoted paths is what keeps non-ASCII filenames correct.
    std::vector<std::string> records;
    const LineSink sink = [&records](std::string_view field) {
        records.emplace_back(field);
        return true;
    };

    auto result =
        runner_.streamSeparated(command, IProcessRunner::Separator::Nul, sink, nullptr, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    auto files = std::make_shared<std::vector<ChangedFile>>();
    for (std::size_t i = 0; i < records.size();) {
        std::string_view meta = records[i];
        if (meta.empty() || meta.front() != ':') {
            ++i;
            continue;
        }
        // ":<oldmode> <newmode> <oldsha> <newsha> <status>"
        meta.remove_prefix(1);
        std::vector<std::string_view> fields;
        std::size_t start = 0;
        while (start < meta.size()) {
            const std::size_t space = meta.find(' ', start);
            if (space == std::string_view::npos) {
                fields.push_back(meta.substr(start));
                break;
            }
            fields.push_back(meta.substr(start, space - start));
            start = space + 1;
        }
        if (fields.size() < 5) {
            ++i;
            continue;
        }

        ChangedFile file;
        file.oldMode = std::string(fields[0]);
        file.newMode = std::string(fields[1]);
        file.oldBlob = std::string(fields[2]);
        file.newBlob = std::string(fields[3]);

        const std::string_view status = fields[4];
        file.kind = kindForStatusLetter(status.empty() ? 'M' : status.front());
        if (status.size() > 1) {
            int similarity = 0;
            for (std::size_t d = 1; d < status.size(); ++d) {
                if (status[d] >= '0' && status[d] <= '9') {
                    similarity = similarity * 10 + (status[d] - '0');
                }
            }
            file.similarity = similarity;
        }

        const bool hasTwoPaths =
            file.kind == FileChangeKind::Renamed || file.kind == FileChangeKind::Copied;
        if (hasTwoPaths && i + 2 < records.size()) {
            file.oldPath = records[i + 1];
            file.path = records[i + 2];
            i += 3;
        } else if (i + 1 < records.size()) {
            file.path = records[i + 1];
            i += 2;
        } else {
            break;
        }
        files->push_back(std::move(file));
    }

    fileListCache_.put(cacheKey, files, estimateBytes(*files));
    return ChangedFilesPtr(files);
}

GitResult<DiffService::ParsedDiffPtr> DiffService::commitDiff(const ObjectId& commit,
                                                              const DiffOptions& options,
                                                              CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    const std::string cacheKey = commit.hex() + ":diff:" + std::to_string(options.hash());
    if (auto cached = diffCache_.get(cacheKey)) {
        return ParsedDiffPtr(cached);
    }

    // --root: see the note in changedFiles(); the initial commit must show a diff.
    std::vector<std::string> args{"diff-tree", "-p", "-r", "--no-commit-id", "--root"};
    for (auto& flag : diffFlags(options)) {
        args.push_back(std::move(flag));
    }
    if (options.firstParentOnly) {
        args.emplace_back("--diff-merges=first-parent");
    }
    args.push_back(commit.hex());

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(180);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    UnifiedDiffParser parser;
    auto parsed = std::make_shared<ParsedDiff>(parser.parse(result->out));
    diffCache_.put(cacheKey, parsed, estimateBytes(*parsed));
    return ParsedDiffPtr(parsed);
}

GitResult<DiffService::ParsedDiffPtr> DiffService::commitFileDiff(const ObjectId& commit,
                                                                  const std::string& path,
                                                                  const DiffOptions& options,
                                                                  CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    const std::string cacheKey =
        commit.hex() + ":file:" + path + ":" + std::to_string(options.hash());
    if (auto cached = diffCache_.get(cacheKey)) {
        return ParsedDiffPtr(cached);
    }

    // --root: see the note in changedFiles(); the initial commit must show a diff.
    std::vector<std::string> args{"diff-tree", "-p", "-r", "--no-commit-id", "--root"};
    for (auto& flag : diffFlags(options)) {
        args.push_back(std::move(flag));
    }
    if (options.firstParentOnly) {
        args.emplace_back("--diff-merges=first-parent");
    }
    args.push_back(commit.hex());
    args.emplace_back("--");
    args.push_back(path);

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    UnifiedDiffParser parser;
    auto parsed = std::make_shared<ParsedDiff>(parser.parse(result->out));
    diffCache_.put(cacheKey, parsed, estimateBytes(*parsed));
    return ParsedDiffPtr(parsed);
}

GitResult<DiffService::ParsedDiffPtr> DiffService::workingTreeDiff(
    bool staged,
    const std::vector<std::string>& paths,
    const DiffOptions& options,
    CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    // Deliberately uncached: the work tree changes under us, and the only honest
    // cache key would have to include every file's mtime and size.
    std::vector<std::string> args{"diff"};
    if (staged) {
        args.emplace_back("--cached");
    }
    for (auto& flag : diffFlags(options)) {
        args.push_back(std::move(flag));
    }
    if (!paths.empty()) {
        args.emplace_back("--");
        for (const std::string& path : paths) {
            args.push_back(path);
        }
    }

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(180);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    UnifiedDiffParser parser;
    return ParsedDiffPtr(std::make_shared<ParsedDiff>(parser.parse(result->out)));
}

GitResult<DiffService::ParsedDiffPtr> DiffService::commitVsWorkingTree(const ObjectId& commit,
                                                                       const DiffOptions& options,
                                                                       CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    // Deliberately uncached, like workingTreeDiff above: the work tree changes
    // under us, and any cache entry keyed just on the commit would go wrong
    // the moment the user edits a file.
    std::vector<std::string> args{"diff"};
    for (auto& flag : diffFlags(options)) {
        args.push_back(std::move(flag));
    }
    args.push_back(commit.hex());

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(180);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    UnifiedDiffParser parser;
    return ParsedDiffPtr(std::make_shared<ParsedDiff>(parser.parse(result->out)));
}

GitResult<DiffService::ParsedDiffPtr> DiffService::stashDiff(int stashIndex,
                                                             bool includeUntracked,
                                                             const DiffOptions& options,
                                                             CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    std::vector<std::string> args{"stash", "show", "-p"};
    for (auto& flag : diffFlags(options)) {
        args.push_back(std::move(flag));
    }
    if (includeUntracked) {
        args.emplace_back("--include-untracked");
    }
    args.push_back("stash@{" + std::to_string(stashIndex) + "}");

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(180);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    UnifiedDiffParser parser;
    return ParsedDiffPtr(std::make_shared<ParsedDiff>(parser.parse(result->out)));
}

void DiffService::clearCaches() {
    diffCache_.clear();
    fileListCache_.clear();
}

}  // namespace gbm
