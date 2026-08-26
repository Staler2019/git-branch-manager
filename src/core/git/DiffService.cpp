#include "core/git/DiffService.h"

#include "core/base/ThreadCheck.h"

#include <charconv>
#include <unordered_map>
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

namespace {

/// The `--raw` rename flag, for whichever git command is about to be run.
///
/// Always explicit, never omitted. `diff-tree` is plumbing and does no rename
/// detection unless asked, but `git log` is porcelain and honours
/// `diff.renames` -- which has defaulted to *true* since git 2.9 and can be
/// set per repository. Leaving the flag off would make the two commands
/// disagree about what a rename is, which on screen is the Changed files
/// column saying 2 next to a panel listing 1.
std::string rawRenameFlag(const DiffOptions& options) {
    return options.detectRenames ? "--find-renames" : "--no-renames";
}

/// Parses one commit's worth of `--raw -z` fields into changed files.
///
/// Shared by changedFiles() and commitFileCounts() rather than written twice:
/// the count the History column shows has to be the length of the list the
/// panel shows, and one parser is the only way to guarantee that without a
/// test for every record shape.
///
/// `--raw -z` emits NUL-separated fields, and rename and copy entries span
/// three records (metadata, old path, new path) rather than two. Using -z
/// rather than parsing quoted paths is what keeps non-ASCII filenames
/// correct.
std::vector<ChangedFile> parseRawRecords(const std::vector<std::string>& records,
                                         std::size_t begin,
                                         std::size_t end) {
    std::vector<ChangedFile> files;
    for (std::size_t i = begin; i < end;) {
        std::string_view meta = records[i];
        // git log writes its commit header and the raw block separated by a
        // newline, so the first metadata record of each commit arrives with a
        // leading one. diff-tree's records never do.
        while (!meta.empty() && (meta.front() == '\n' || meta.front() == '\r')) {
            meta.remove_prefix(1);
        }
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
        if (hasTwoPaths && i + 2 < end) {
            file.oldPath = records[i + 1];
            file.path = records[i + 2];
            i += 3;
        } else if (i + 1 < end) {
            file.path = records[i + 1];
            i += 2;
        } else {
            break;
        }
        files.push_back(std::move(file));
    }
    return files;
}

/// Collects a command's NUL-separated output into fields.
LineSink collectFields(std::vector<std::string>& records) {
    return [&records](std::string_view field) {
        records.emplace_back(field);
        return true;
    };
}

/// Joins `diff-tree --numstat` line counts onto an already-parsed `--raw`
/// list, keyed by path.
///
/// Two invocations rather than one because git's diff-options output-format
/// field is a single slot: `--raw` and `--numstat` cannot both take effect in
/// the same command. `CompareOps.cpp`'s readFiles() works around the same
/// constraint for the Compare tab, and the record shapes below match its
/// parser deliberately.
///
/// Every flag the raw call passes is repeated here. They are not decorative:
/// without `--root` a parentless commit numstats to nothing, without
/// `--diff-merges=first-parent` a *merge* numstats to nothing, and with a
/// different rename flag the two outputs disagree about which paths exist --
/// each of which shows up as a file listed with no badge rather than as an
/// error.
GitResult<void> attachLineCounts(IProcessRunner& runner,
                                 const RepoPaths& paths,
                                 const ObjectId& commit,
                                 const DiffOptions& options,
                                 std::vector<ChangedFile>& files,
                                 CancellationToken token) {
    if (files.empty()) {
        return {};
    }

    std::vector<std::string> args{"diff-tree", "-r", "--numstat", "-z", "--no-commit-id", "--root"};
    args.emplace_back(rawRenameFlag(options));
    if (options.firstParentOnly) {
        args.emplace_back("--diff-merges=first-parent");
    }
    args.push_back(commit.hex());

    GitCommand command(paths.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);

    std::vector<std::string> records;
    auto result = runner.streamSeparated(
        command, IProcessRunner::Separator::Nul, collectFields(records), nullptr, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    // Keyed on `path` because it is the one field parseRawRecords() fills for
    // every change kind: the new path for a rename or copy, and the single
    // path for everything else including a delete. (`oldPath` is empty unless
    // the kind has two paths, so it cannot serve as the key.) numstat prints
    // that same path in each case, which is what makes the join total.
    std::unordered_map<std::string_view, ChangedFile*> byPath;
    byPath.reserve(files.size());
    for (ChangedFile& file : files) {
        byPath.emplace(file.path, &file);
    }

    for (std::size_t i = 0; i < records.size();) {
        const std::string_view record = records[i++];
        const std::size_t firstTab = record.find('\t');
        if (firstTab == std::string_view::npos) {
            continue;
        }
        const std::size_t secondTab = record.find('\t', firstTab + 1);
        if (secondTab == std::string_view::npos) {
            continue;
        }
        const std::string_view addedField = record.substr(0, firstTab);
        const std::string_view removedField = record.substr(firstTab + 1, secondTab - firstTab - 1);
        std::string_view pathField = record.substr(secondTab + 1);

        if (pathField.empty()) {
            // Rename or copy: under -z the path field is empty and the next
            // two records are the old and the new path. Only the new one is
            // needed -- it is what byPath is keyed on -- but both must be
            // consumed or the loop reads the old path as the next entry's
            // counts and every count after this point is wrong.
            if (i < records.size()) {
                ++i;  // old path, unused
            }
            if (i >= records.size()) {
                break;
            }
            pathField = records[i++];
        }

        const auto found = byPath.find(pathField);
        if (found == byPath.end()) {
            continue;
        }
        // "-" for either field means a binary blob. Left at 0 rather than
        // parsed: std::from_chars would leave the value untouched anyway, but
        // saying so here is what stops a later reader treating 0 as measured.
        if (addedField == "-" || removedField == "-") {
            continue;
        }
        std::uint32_t added = 0;
        std::uint32_t removed = 0;
        std::from_chars(addedField.data(), addedField.data() + addedField.size(), added);
        std::from_chars(removedField.data(), removedField.data() + removedField.size(), removed);
        found->second->addedLines = added;
        found->second->removedLines = removed;
    }

    return {};
}

}  // namespace

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
    args.emplace_back(rawRenameFlag(options));
    if (options.firstParentOnly) {
        args.emplace_back("--diff-merges=first-parent");
    }
    args.push_back(commit.hex());

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);

    std::vector<std::string> records;
    auto result = runner_.streamSeparated(
        command, IProcessRunner::Separator::Nul, collectFields(records), nullptr, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    auto files =
        std::make_shared<std::vector<ChangedFile>>(parseRawRecords(records, 0, records.size()));

    // Before the cache write, so a cached list is never one that is missing
    // its badges. A numstat failure fails the whole call rather than
    // returning a half-filled list -- the panel would otherwise render every
    // row as "0 lines changed" with nothing anywhere saying why.
    if (auto counts = attachLineCounts(runner_, paths_, commit, options, *files, token); !counts) {
        return fail(std::move(counts).error());
    }

    fileListCache_.put(cacheKey, files, estimateBytes(*files));
    return ChangedFilesPtr(files);
}

GitResult<std::vector<CommitFileCount>> DiffService::commitFileCounts(
    const std::vector<ObjectId>& commits, const DiffOptions& options, CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    std::vector<CommitFileCount> counts;
    if (commits.empty()) {
        return counts;
    }

    // `git log --no-walk`, not `diff-tree --stdin`: --stdin combined with a
    // merge-diff flag echoes the input commit lines back and produces output
    // for only the last one, dropping the rest silently.
    //
    // --no-walk keeps this to exactly the commits named -- without it git
    // would walk their whole ancestry. A root commit needs no `--root` here;
    // `log` prints its diff already, which is the equivalent of the flag
    // changedFiles() has to pass diff-tree.
    std::vector<std::string> args{
        "log", "--no-walk", "--format=%x00COMMIT %H", "-r", "--raw", "-z", rawRenameFlag(options)};
    if (options.firstParentOnly) {
        args.emplace_back("--diff-merges=first-parent");
    }
    for (const ObjectId& commit : commits) {
        args.push_back(commit.hex());
    }

    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);

    std::vector<std::string> records;
    auto result = runner_.streamSeparated(
        command, IProcessRunner::Separator::Nul, collectFields(records), nullptr, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    // The `%x00` in the format is what makes each commit header its own field,
    // so the stream reads as: "COMMIT <hex>", that commit's raw records,
    // "COMMIT <hex>", and so on. Slice on the headers and hand each slice to
    // the same parser changedFiles() uses.
    static constexpr std::string_view kHeader = "COMMIT ";
    std::vector<std::pair<std::string, std::size_t>> headers;
    for (std::size_t i = 0; i < records.size(); ++i) {
        std::string_view field = records[i];
        if (field.rfind(kHeader, 0) != 0) {
            continue;
        }
        headers.emplace_back(std::string(field.substr(kHeader.size())), i);
    }

    counts.reserve(headers.size());
    for (std::size_t h = 0; h < headers.size(); ++h) {
        const std::size_t begin = headers[h].second + 1;
        const std::size_t end = (h + 1 < headers.size()) ? headers[h + 1].second : records.size();
        CommitFileCount entry;
        entry.commit = ObjectId::fromHex(headers[h].first);
        entry.fileCount = static_cast<std::uint32_t>(parseRawRecords(records, begin, end).size());
        counts.push_back(std::move(entry));
    }
    return counts;
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
    // Same shape as WorkingCopyStatus.cpp's unstaged --numstat pass, and it
    // runs on the same background pool: when `staged` is false this compares
    // the work tree against the index, so it carries the same flags for the
    // same measured reason (GitCommand::worktreeReadFlags()).
    std::vector<std::string> args;
    if (!staged) {
        args = GitCommand::worktreeReadFlags();
    }
    args.emplace_back("diff");
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
