#include "core/git/WorkingCopyStatus.h"

#include "core/base/FsUtil.h"
#include "core/base/ThreadCheck.h"
#include "core/git/TextTraits.h"

#include <charconv>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <system_error>
#include <unordered_map>
#include <unordered_set>
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

/// A stage hash of all zeros means that stage does not exist for this path
/// (e.g. no common ancestor for a both-added conflict). Reported as empty
/// rather than as the all-zero hash, which is not a real object.
std::string blobOrEmpty(std::string_view hash) {
    if (hash.find_first_not_of('0') == std::string_view::npos) {
        return {};
    }
    return std::string(hash);
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

/// Joins one `git diff --numstat -z` pass onto `entries`, keyed by path.
///
/// Two passes rather than one command because git's diff output-format field is
/// a single slot: `--numstat` cannot be combined with the `--porcelain=v2`
/// status read that produced `entries`, and the two sides (work tree vs index,
/// index vs HEAD) are two different diffs regardless. `DiffService.cpp`'s
/// attachLineCounts() works around the same constraint for a commit's file
/// list, and the record shapes parsed below match its parser deliberately.
///
/// `-M` is passed explicitly rather than left to `diff.renames`, so the rename
/// detection here cannot drift away from what `git status --porcelain=v2`
/// already did. If the two ever disagree, a renamed file's counts silently
/// describe the wrong comparison -- so the flag is not decoration.
///
/// `staged` selects which pair of fields the counts land in, which is why a
/// file that is on both sides at once (partly staged) ends up with four
/// independent numbers rather than one pair.
GitResult<void> attachNumstat(IProcessRunner& runner,
                              const RepoPaths& paths,
                              bool staged,
                              std::vector<WorkingCopyEntry>& entries,
                              CancellationToken token) {
    if (entries.empty()) {
        return {};
    }

    // The unstaged pass compares the work tree against the index, so it needs
    // GitCommand::worktreeReadFlags() -- see that function for the measured
    // regression it prevents. The staged pass is index-vs-HEAD, never looks at
    // the work tree, and measured 0 of 12 failures without the flags, so it
    // does not pay for them.
    std::vector<std::string> args;
    if (!staged) {
        args = GitCommand::worktreeReadFlags();
    }
    args.insert(args.end(), {"diff", "--numstat", "-z", "-M"});
    if (staged) {
        args.emplace_back("--cached");
    }
    GitCommand command(paths.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(120);

    std::vector<std::string> records;
    const LineSink sink = [&records](std::string_view record) {
        records.emplace_back(record);
        return true;
    };
    auto result =
        runner.streamSeparated(command, IProcessRunner::Separator::Nul, sink, nullptr, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    // Keyed on `path` -- the new path for a rename or copy, the single path for
    // everything else -- because that is the field every entry has. `oldPath`
    // is empty except for renames and copies, so it cannot serve as the key.
    std::unordered_map<std::string_view, WorkingCopyEntry*> byPath;
    byPath.reserve(entries.size());
    for (WorkingCopyEntry& entry : entries) {
        byPath.emplace(entry.path, &entry);
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
            // Rename or copy: under -z the path field is empty and the next two
            // records are the old and the new path. Only the new one is needed
            // -- it is what byPath is keyed on -- but *both* must be consumed,
            // or the loop reads the old path as the next entry's counts and
            // every count after this point is wrong. Silently wrong: a
            // plausible number, not an error.
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
        if (staged) {
            found->second->stagedAdded = added;
            found->second->stagedRemoved = removed;
        } else {
            found->second->unstagedAdded = added;
            found->second->unstagedRemoved = removed;
        }
    }
    return {};
}

/// Counts the lines of every untracked entry by reading the file.
///
/// `git diff` cannot see an untracked path -- it is in neither the index nor
/// HEAD -- so neither numstat pass reports one, and without this an entire
/// newly-added file would render with no size at all, which is the commonest
/// case in the unstaged column.
///
/// Three ways a file gets no count rather than a wrong one, all landing as 0:
/// it is binary (detectTextTraits()'s NUL-byte test, the same one the conflict
/// surfaces use), it is over [kUntrackedLineCountByteCap], or it could not be
/// read at all (deleted between the status read and here, or unreadable).
///
/// [cache] turns the second and every later refresh of an unedited file into
/// the stat this loop already performs; see [UntrackedLineCountCache] for what
/// its key is and why nothing invalidates it from outside.
void countUntrackedLines(const RepoPaths& paths,
                         std::vector<WorkingCopyEntry>& entries,
                         UntrackedLineCountCache& cache) {
    if (paths.isBare()) {
        return;
    }

    // Read once, before the first file is stat()ed, so that every file this
    // pass caches is compared against a moment that is already in the past by
    // the time the comparison happens. Reading it per file would let a file
    // edited *during* the pass still look strictly older than its own check.
    const std::filesystem::file_time_type passStartedAt =
        std::filesystem::file_time_type::clock::now();

    std::unordered_set<std::string> live;

    for (WorkingCopyEntry& entry : entries) {
        if (!entry.untracked) {
            continue;
        }
        live.insert(entry.path);

        const std::filesystem::path file = paths.workDir() / fsutil::pathFromUtf8(entry.path);

        std::error_code ec;
        const std::uintmax_t size = std::filesystem::file_size(file, ec);
        if (ec || size > kUntrackedLineCountByteCap) {
            continue;
        }
        const auto modified = std::filesystem::last_write_time(file, ec);
        if (ec) {
            continue;
        }

        const UntrackedLineCountCache::Stat stat{size, modified};
        if (const std::optional<std::uint32_t> remembered = cache.lookup(entry.path, stat)) {
            entry.unstagedAdded = *remembered;
            entry.unstagedRemoved = 0;
            continue;
        }

        std::ifstream in(file, std::ios::binary);
        if (!in) {
            continue;
        }
        std::string contents((std::istreambuf_iterator<char>(in)),
                             std::istreambuf_iterator<char>());
        // Cached as 0 rather than skipped: a binary file that stays binary
        // would otherwise be read in full on every single refresh, which is
        // the one case where the read is guaranteed to be wasted.
        std::uint32_t lines = 0;
        if (detectTextTraits(contents).encoding != EncodingKind::Binary) {
            for (const char c : contents) {
                if (c == '\n') {
                    ++lines;
                }
            }
            // A final line with no trailing newline still counts, the same way
            // `git diff --numstat` counts it once the file is tracked.
            if (!contents.empty() && contents.back() != '\n') {
                ++lines;
            }
        }

        cache.store(entry.path, stat, lines, passStartedAt);
        entry.unstagedAdded = lines;
        entry.unstagedRemoved = 0;
    }

    cache.retainOnly(live);
}

}  // namespace

std::optional<std::uint32_t> UntrackedLineCountCache::lookup(const std::string& path,
                                                             const Stat& stat) {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto found = entries_.find(path);
    if (found == entries_.end() || !(found->second.stat == stat)) {
        ++misses_;
        return std::nullopt;
    }
    ++hits_;
    return found->second.lines;
}

void UntrackedLineCountCache::store(const std::string& path,
                                    const Stat& stat,
                                    std::uint32_t lines,
                                    std::filesystem::file_time_type passStartedAt) {
    // git's "racily clean" rule. A file whose mtime is not strictly older than
    // the start of this pass may have been written again after this pass read
    // it, and the two writes are indistinguishable through a timestamp of that
    // resolution. Declining to remember it costs one more read next refresh;
    // remembering it would pin a wrong number until the file is edited again.
    if (!(stat.modified < passStartedAt)) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    entries_[path] = Entry{stat, lines};
}

void UntrackedLineCountCache::retainOnly(const std::unordered_set<std::string>& live) {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto it = entries_.begin(); it != entries_.end();) {
        it = live.count(it->first) == 0 ? entries_.erase(it) : std::next(it);
    }
}

std::size_t UntrackedLineCountCache::hits() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return hits_;
}

std::size_t UntrackedLineCountCache::misses() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return misses_;
}

std::size_t UntrackedLineCountCache::size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return entries_.size();
}

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

/// Parses `git status --porcelain=v2 -z` records into entries.
///
/// Extracted from `WorkingCopyStatusReader::read()` so the per-worktree
/// pending-change count can reuse it instead of writing a second parser
/// ([CULT-single-source-of-truth]). The subtlety worth reusing is that a
/// rename ('2') spends **two** NUL records where every other kind spends one,
/// so anything that counts records rather than parsing them is silently wrong
/// from the first rename onwards.
std::vector<WorkingCopyEntry> parsePorcelainV2Records(const std::vector<std::string>& records) {
    std::vector<WorkingCopyEntry> entries;
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
            entries.push_back(std::move(entry));
            ++i;
            continue;
        }

        // Unmerged (conflicted) entry: u XY sub m1 m2 m3 mW h1 h2 h3 path
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
            entry.ancestorBlob = blobOrEmpty(fields[7]);
            entry.oursBlob = blobOrEmpty(fields[8]);
            entry.theirsBlob = blobOrEmpty(fields[9]);
            entries.push_back(std::move(entry));
            ++i;
            continue;
        }

        // Untracked path.
        if (type == '?') {
            WorkingCopyEntry entry;
            entry.path = record.size() > 2 ? std::string(record.substr(2)) : std::string();
            entry.untracked = true;
            entries.push_back(std::move(entry));
            ++i;
            continue;
        }

        // '!' (ignored, only present with --ignored, which we never pass) and
        // anything else unrecognised: skip rather than guess.
        ++i;
    }

    return entries;
}

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
    status->entries = parsePorcelainV2Records(records);

    // The line counts spec page 03's badges need. Both numstat passes run even
    // when one side is empty -- deciding from the status flags which pass to
    // skip would make the counts depend on a second reading of the same data,
    // and the cost of a diff over an unchanged side is a git process that
    // prints nothing.
    //
    // A numstat failure fails the whole read rather than silently returning
    // entries with no counts: a file list with no badges is indistinguishable
    // from a repository where nothing changed size, so a swallowed error here
    // would surface as a UI that is quietly wrong rather than one that says so.
    if (auto counts = attachNumstat(runner_, paths_, /*staged=*/false, status->entries, token);
        !counts) {
        return fail(std::move(counts).error());
    }
    if (auto counts = attachNumstat(runner_, paths_, /*staged=*/true, status->entries, token);
        !counts) {
        return fail(std::move(counts).error());
    }
    countUntrackedLines(paths_, status->entries, untrackedLineCounts_);

    return WorkingCopyStatusPtr(status);
}

}  // namespace gbm
